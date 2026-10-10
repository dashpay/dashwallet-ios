import CryptoKit
import Foundation
import os
import SwiftDashSDK

/// The one-QR login (DashConnect v2): the wallet derives a session key for
/// the request, registers it on the identity, and only then publishes the
/// encrypted key to the App Connect system contract. There is no `dash-st:`
/// step.
///
/// Everything here is pure; `PlatformDashConnectDataSource` owns the Platform
/// calls and their order.
enum AppConnect {
    /// The protocol version that registers the App Connect system contract.
    /// Below it the contract does not exist and the two-QR login is the only
    /// one that can work.
    static let minimumProtocolVersion: UInt32 = 14

    /// Same id on every network (`docs/protocol/app-connect.md` in
    /// dashpay/platform).
    static let contractId = "H8F9mP1BM55TE1ShsxPZHzhyinaMdY9bMmP85mkDhcJJ"
    static let documentType = PlatformDashConnectDataSource.loginKeyExchangeDocumentType

    /// Limits put on every session key.
    /// TODO(app-connect-limits): the protocol leaves both values to the
    /// wallet and nothing has fixed them yet; they are not user-selectable.
    static let sessionKeyBudgetCredits: UInt64 = 5_000_000_000 // 0.05 DASH
    static let sessionKeyLifetime: TimeInterval = 90 * 24 * 60 * 60

    static func isAvailable(protocolVersion: UInt32) -> Bool {
        protocolVersion >= minimumProtocolVersion
    }

    /// The DIP-13 leaf of the session key: `hash256` of the app's ephemeral
    /// public key. Not the lookup key of the response, which is `hash160` of
    /// the same bytes.
    static func requestId(appEphemeralPubKey: Data) -> Data {
        Data(SHA256.hash(data: Data(SHA256.hash(data: appEphemeralPubKey))))
    }

    static func expiresAt(from now: Date) -> UInt64 {
        UInt64((now.addingTimeInterval(sessionKeyLifetime).timeIntervalSince1970 * 1000).rounded())
    }

    /// What the identity already holds for a derived session key.
    enum SessionKeyState: Equatable {
        /// Not on the identity: register it.
        case absent
        /// Registered and able to sign: publish without an identity update.
        case usable(keyId: UInt32)
        /// Registered but disabled or expired. Platform never re-adds a key,
        /// so this request cannot be answered; the app has to ask again.
        case unusable
    }

    static func sessionKeyState(
        publicKeyHash160: Data,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        now: Date
    ) -> SessionKeyState {
        guard let key = currentIdentityPublicKeys.first(where: {
            $0.keyType == .ecdsaHash160 && $0.data == publicKeyHash160
        }) else {
            return .absent
        }
        let nowMilliseconds = Int64((now.timeIntervalSince1970 * 1000).rounded())
        guard key.purpose == .authentication,
              key.securityLevel == .high,
              key.disabledAt == nil,
              key.expiresAt.map({ $0 > nowMilliseconds }) ?? true else {
            return .unusable
        }
        return .usable(keyId: UInt32(bitPattern: key.keyId))
    }

    static func nextKeyId(
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> UInt32 {
        (currentIdentityPublicKeys.map { UInt32(bitPattern: $0.keyId) }.max() ?? 0) + 1
    }

    /// The key an app is given: it can only sign for the contract the request
    /// named, spend up to `totalBudget`, and stops working at `expiresAt`.
    static func sessionIdentityPubkey(
        keyId: UInt32,
        publicKeyHash160: Data,
        appContractId: Data,
        totalBudget: UInt64,
        expiresAt: UInt64
    ) -> ManagedPlatformWallet.IdentityPubkey {
        ManagedPlatformWallet.IdentityPubkey(
            keyId: keyId,
            keyType: .ecdsaHash160,
            purpose: .authentication,
            securityLevel: .high,
            pubkeyBytes: publicKeyHash160,
            contractBounds: .singleContract(id: appContractId),
            totalBudget: totalBudget,
            expiresAt: expiresAt
        )
    }

    /// The session keys behind `grants` that can still sign: the ones a
    /// disconnect has to disable. A key that is gone, already disabled, or no
    /// longer the kind of key this login registers is left alone.
    static func sessionKeyIdsToDisable(
        for grants: [AppConnectGrant],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [UInt32] {
        let granted = Set(grants.map(\.sessionKeyId))
        return currentIdentityPublicKeys
            .filter {
                granted.contains(UInt32(bitPattern: $0.keyId))
                    && $0.keyType == .ecdsaHash160
                    && $0.purpose == .authentication
                    && $0.securityLevel == .high
                    && $0.disabledAt == nil
            }
            .map { UInt32(bitPattern: $0.keyId) }
            .sorted()
    }

    /// The three values of a `loginKeyResponse`, as hex.
    struct ResponseValues: Codable, Equatable {
        let appEphemeralPubKeyHash: String
        let walletEphemeralPubKey: String
        let encryptedPayload: String

        init(appEphemeralPubKeyHash: String, walletEphemeralPubKey: String, encryptedPayload: String) {
            self.appEphemeralPubKeyHash = appEphemeralPubKeyHash
            self.walletEphemeralPubKey = walletEphemeralPubKey
            self.encryptedPayload = encryptedPayload
        }

        init(_ sealed: SealedKey) {
            self.init(
                appEphemeralPubKeyHash: sealed.appEphemeralPubKeyHash.toHexString(),
                walletEphemeralPubKey: sealed.walletEphemeralPublicKey.toHexString(),
                encryptedPayload: sealed.encryptedPayload.toHexString()
            )
        }

        /// The document's properties in the form `createDocument` and
        /// delete-by-values take.
        func propertiesJSON() throws -> String {
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "appEphemeralPubKeyHash": appEphemeralPubKeyHash,
                    "walletEphemeralPubKey": walletEphemeralPubKey,
                    "encryptedPayload": encryptedPayload,
                ],
                options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// A 32-byte key encrypted to an app's ephemeral key, with what the app
    /// needs to find and open it. Shared by both logins: the two-QR response
    /// carries the login key, the one-QR response the session private key.
    struct SealedKey: Equatable {
        let appEphemeralPubKeyHash: Data
        let walletEphemeralPublicKey: Data
        let encryptedPayload: Data
    }

    /// Encrypts `key` to the app. `walletEphemeralPrivateKey` is wiped before
    /// returning.
    static func seal(
        _ key: Data,
        appEphemeralPubKey: Data,
        walletEphemeralPrivateKey: inout Data,
        encrypt: (Data, Data, Data) throws -> Data = { key, walletPriv, appPub in
            try KeyExchangeCrypto.encryptLoginKey(
                key,
                walletEphemeralPriv: walletPriv,
                appEphemeralPub: appPub
            )
        }
    ) throws -> SealedKey {
        defer { PlatformDashConnectDataSource.zero(&walletEphemeralPrivateKey) }

        let appEphemeralPubKeyHash = try KeyExchangeCrypto.hash160(appEphemeralPubKey)
        guard appEphemeralPubKeyHash.count == 20 else {
            throw DashConnectPlatformError.invalidHash160
        }
        let walletEphemeralPublicKey = try Secp256k1.compressedPublicKey(privateKey: walletEphemeralPrivateKey)
        let encryptedPayload = try encrypt(key, walletEphemeralPrivateKey, appEphemeralPubKey)

        return SealedKey(
            appEphemeralPubKeyHash: appEphemeralPubKeyHash,
            walletEphemeralPublicKey: walletEphemeralPublicKey,
            encryptedPayload: encryptedPayload
        )
    }
}

/// A session key this wallet registered for an app, and the response that
/// carried it. Kept until the key is disabled and the response is gone.
///
/// The response type is index-only on Platform: there is no lookup by app and
/// a delete has to carry the original values, so this record is the only way
/// back to the entry — and the only place that knows which key on the
/// identity belongs to which app.
struct AppConnectGrant: Codable, Equatable {
    /// Base58 ids.
    let identityId: String
    let appContractId: String
    /// `nil` until Platform confirmed the response: the grant is recorded
    /// before publishing, so a publish whose outcome is unknown still leaves
    /// a key that can be disabled.
    var documentId: String?
    let values: AppConnect.ResponseValues
    let sessionKeyId: UInt32
    /// `nil` when the key was found already registered and its limits were
    /// not read back.
    let totalBudget: UInt64?
    let expiresAt: UInt64?
    let publishedAt: Date
    /// Set once the response was deleted from Platform while the key stays
    /// live (a later login to the same app). Absent means not deleted.
    var responseDeleted: Bool?
    /// Set once a disconnect disabled the key but could not delete the
    /// response; the record then only waits for that delete.
    var keyDisabled: Bool?

    /// Whether there is a response on Platform this record can still delete.
    var hasDeletableResponse: Bool {
        documentId != nil && responseDeleted != true
    }
}

protocol AppConnectResponseStore {
    func load() -> [AppConnectGrant]
    func save(_ grants: [AppConnectGrant])
}

/// Wallet- and network-scoped, like `UserDefaultsDashConnectStore`, whose
/// scope it borrows. Nothing stored is secret: the values are public on
/// chain and the key ids are visible on the identity.
final class UserDefaultsAppConnectResponseStore: AppConnectResponseStore {
    private let defaults: UserDefaults
    private let scopeKeyProvider: () -> String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "dashconnect.app-connect-store")

    init(
        defaults: UserDefaults = .standard,
        network: DashConnectNetwork,
        scopeKeyProvider: (() -> String?)? = nil
    ) {
        self.defaults = defaults
        if let scopeKeyProvider {
            self.scopeKeyProvider = scopeKeyProvider
        } else {
            let connections = UserDefaultsDashConnectStore(defaults: defaults, network: network)
            self.scopeKeyProvider = { connections.storageKey }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    private var storageKey: String? {
        scopeKeyProvider().map { "\($0).app-connect-responses.v1" }
    }

    func load() -> [AppConnectGrant] {
        guard let storageKey, let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            return try decoder.decode([AppConnectGrant].self, from: data)
        } catch {
            // Without the records the keys they named can no longer be told
            // apart on the identity. A one-QR row whose records are gone
            // refuses to disconnect (`grantRecordsMissing`) instead of
            // pretending the key was disabled.
            Self.logger.warning(
                "AppConnectResponseStore: stored responses could not be decoded: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ grants: [AppConnectGrant]) {
        guard let storageKey else { return }
        guard !grants.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        do {
            defaults.set(try encoder.encode(grants), forKey: storageKey)
        } catch {
            Self.logger.error(
                "AppConnectResponseStore: failed to encode responses: \(error.localizedDescription, privacy: .public)")
        }
    }
}
