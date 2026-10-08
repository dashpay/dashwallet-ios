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
    static let documentType = "loginKeyResponse"

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

    /// The three values of a `loginKeyResponse`, as hex.
    struct ResponseValues: Codable, Equatable {
        let appEphemeralPubKeyHash: String
        let walletEphemeralPubKey: String
        let encryptedPayload: String

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

    /// Encrypts the session private key to the app. `walletEphemeralPrivateKey`
    /// is wiped before returning.
    static func responseValues(
        sessionPrivateKey: Data,
        appEphemeralPubKey: Data,
        walletEphemeralPrivateKey: inout Data,
        encrypt: (Data, Data, Data) throws -> Data = { key, walletPriv, appPub in
            try KeyExchangeCrypto.encryptLoginKey(
                key,
                walletEphemeralPriv: walletPriv,
                appEphemeralPub: appPub
            )
        }
    ) throws -> ResponseValues {
        defer { PlatformDashConnectDataSource.zero(&walletEphemeralPrivateKey) }

        let appEphemeralPubKeyHash = try KeyExchangeCrypto.hash160(appEphemeralPubKey)
        guard appEphemeralPubKeyHash.count == 20 else {
            throw DashConnectPlatformError.invalidHash160
        }
        let walletEphemeralPublicKey = try Secp256k1.compressedPublicKey(privateKey: walletEphemeralPrivateKey)
        let encryptedPayload = try encrypt(sessionPrivateKey, walletEphemeralPrivateKey, appEphemeralPubKey)

        return ResponseValues(
            appEphemeralPubKeyHash: appEphemeralPubKeyHash.toHexString(),
            walletEphemeralPubKey: walletEphemeralPublicKey.toHexString(),
            encryptedPayload: encryptedPayload.toHexString()
        )
    }
}

/// A response this wallet published and has not deleted yet, with the key it
/// granted. The type is index-only on Platform: there is no lookup by app and
/// a delete has to carry the original values, so this record is the only way
/// back to the entry.
struct AppConnectPublishedResponse: Codable, Equatable {
    /// Base58 ids.
    let identityId: String
    let appContractId: String
    let documentId: String
    let values: AppConnect.ResponseValues
    let sessionKeyId: UInt32
    /// `nil` when the key was found already registered and its limits were
    /// not read back.
    let totalBudget: UInt64?
    let expiresAt: UInt64?
    let publishedAt: Date
}

protocol AppConnectResponseStore {
    func load() -> [AppConnectPublishedResponse]
    func save(_ responses: [AppConnectPublishedResponse])
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

    func load() -> [AppConnectPublishedResponse] {
        guard let storageKey, let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            return try decoder.decode([AppConnectPublishedResponse].self, from: data)
        } catch {
            // Losing the records is survivable: the next login still creates a
            // fresh response, and the old entries stay until deleted by value.
            Self.logger.warning(
                "AppConnectResponseStore: stored responses could not be decoded: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ responses: [AppConnectPublishedResponse]) {
        guard let storageKey else { return }
        guard !responses.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        do {
            defaults.set(try encoder.encode(responses), forKey: storageKey)
        } catch {
            Self.logger.error(
                "AppConnectResponseStore: failed to encode responses: \(error.localizedDescription, privacy: .public)")
        }
    }
}
