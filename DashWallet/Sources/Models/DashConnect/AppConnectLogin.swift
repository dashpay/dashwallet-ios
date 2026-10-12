import CryptoKit
import Foundation
import os
import SwiftDashSDK

/// The one-QR login (DashConnect v2): the wallet derives a session key for
/// the request, registers it on the identity, and only then publishes the
/// encrypted key to the App Connect system contract. There is no `dash-st:`
/// step.
///
/// `AppConnect` holds the rules and is pure; `PlatformDashConnectDataSource`
/// owns the Platform calls and their order. The grant records and their
/// `UserDefaults` store are at the end of the file.
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

    /// What the wallet's store of identity keys says about one key: its
    /// payload, whether it is disabled there, and the contract it is bound to
    /// when the bound is a whole single contract. The fetched key list
    /// carries no bounds, so for a key without a grant record this is where
    /// its app is read from.
    struct KeyBinding: Equatable {
        let keyId: UInt32
        let data: Data
        let singleContractId: Data?
        var isDisabled = false
        /// The stored key has the type, purpose, level and limits of a key
        /// this login registers.
        var isSessionKeyShaped = false
        /// The store has a bound for the key that this build cannot read, so
        /// the key's app is unknown rather than "another one".
        var hasUnreadableBound = false
    }

    /// The most keys one identity update may disable (Platform consensus).
    static let maxKeysDisabledPerUpdate = 10

    /// Whether the store's bound for a key says which contract, if any, the
    /// key is bound to: no bound (0), a 32-byte single contract (1), a
    /// document type (2) or a contract group (3).
    static func isReadableBound(boundsKind: Int, boundIds: [Data]?) -> Bool {
        switch boundsKind {
        case 0, 2, 3: return true
        case 1: return boundIds?.first?.count == 32
        default: return false
        }
    }

    /// The contract a stored key is bound to as a whole. `boundsKind` is the
    /// store's discriminant: 1 is a single contract; a document-type bound
    /// (2), a contract group (3) and no bound (0) give nil.
    static func singleContractId(boundsKind: Int, boundIds: [Data]?) -> Data? {
        guard boundsKind == 1, let id = boundIds?.first, id.count == 32 else { return nil }
        return id
    }

    private static func isLiveSessionKey(_ key: ManagedIdentity.IdentityPublicKeyInfo) -> Bool {
        key.keyType == .ecdsaHash160
            && key.purpose == .authentication
            && key.securityLevel == .high
            && key.disabledAt == nil
    }

    /// The keys a disconnect has to disable: the live ones behind `grants`,
    /// plus every live key of the same kind that `bindings` shows bound to
    /// `appContractId` and that carries a budget and an expiry, as every key
    /// this login registers does. That covers the keys a reinstalled wallet
    /// has no grant record for. A key that is gone, already disabled, or of
    /// another shape is left alone, including one another wallet gave the
    /// app with a document-type bound, a single limit or another key type.
    static func sessionKeyIdsToDisable(
        for grants: [AppConnectGrant],
        appContractId: Data,
        bindings: [KeyBinding],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [UInt32] {
        let granted = Set(grants.map(\.sessionKeyId))
        return currentIdentityPublicKeys
            .filter { key in
                guard isLiveSessionKey(key) else { return false }
                let keyId = UInt32(bitPattern: key.keyId)
                if granted.contains(keyId) { return true }
                guard key.totalBudget != nil, key.expiresAt != nil else { return false }
                return bindings.contains {
                    $0.keyId == keyId && $0.data == key.data && $0.singleContractId == appContractId
                }
            }
            .map { UInt32(bitPattern: $0.keyId) }
            .sorted()
    }

    /// Live session keys whose bound contract is unknown: not behind
    /// `grants`, and either absent from `bindings` or stored with a bound
    /// that cannot be read. Any of them could belong to the app being
    /// disconnected, so a disconnect must stop on these instead of reporting
    /// every key as turned off.
    static func sessionKeyIdsWithUnknownBinding(
        for grants: [AppConnectGrant],
        bindings: [KeyBinding],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [UInt32] {
        let granted = Set(grants.map(\.sessionKeyId))
        return currentIdentityPublicKeys
            .filter { key in
                guard isLiveSessionKey(key) else { return false }
                let keyId = UInt32(bitPattern: key.keyId)
                return !granted.contains(keyId) && !bindings.contains {
                    $0.keyId == keyId && $0.data == key.data && !$0.hasUnreadableBound
                }
            }
            .map { UInt32(bitPattern: $0.keyId) }
            .sorted()
    }

    /// Keys the store holds as live and bound to `appContractId` that the
    /// given view of the identity does not contain. As with a missing granted
    /// key, the view is out of date and a disconnect must stop.
    static func boundKeyIdsMissing(
        from currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        appContractId: Data,
        bindings: [KeyBinding]
    ) -> [UInt32] {
        let known = Set(currentIdentityPublicKeys.map { UInt32(bitPattern: $0.keyId) })
        return bindings
            .filter { $0.singleContractId == appContractId && !$0.isDisabled && !known.contains($0.keyId) }
            .map(\.keyId)
            .sorted()
    }

    /// Granted session keys the given view of the identity does not contain.
    /// Platform never removes a key, it only disables it, so a missing id
    /// means the view is out of date — not that the key is gone. A disconnect
    /// must stop on these instead of treating them as dealt with.
    static func sessionKeyIdsMissing(
        from currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        for grants: [AppConnectGrant]
    ) -> [UInt32] {
        let known = Set(currentIdentityPublicKeys.map { UInt32(bitPattern: $0.keyId) })
        return Set(grants.map(\.sessionKeyId)).subtracting(known).sorted()
    }

    /// The query for one identity's response to one request, in the order of
    /// the contract's only index. A byte-array value travels as base64.
    static func responseLookupWhereClause(appEphemeralPubKeyHash: Data, ownerIdentityId: Data) -> String {
        """
        [["appEphemeralPubKeyHash","==","\(appEphemeralPubKeyHash.base64EncodedString())"],\
        ["$ownerId","==","\(ownerIdentityId.toBase58String())"]]
        """
    }

    /// The values of a response read back from Platform, or `nil` when the
    /// document is not the response to `appEphemeralPubKeyHash` or cannot be
    /// read. A delete has to carry the values that are on Platform, and those
    /// are this wallet's own only when it recorded them before publishing.
    ///
    /// The SDK returns a byte field as base64 text. An array of numbers and
    /// hex text are read as well, so a change of that encoding does not turn
    /// every lookup into a failure.
    static func responseValues(
        fromDocument document: [String: Any],
        appEphemeralPubKeyHash: Data
    ) -> ResponseValues? {
        func field(_ name: String) -> Any? {
            document[name] ?? (document["properties"] as? [String: Any])?[name]
        }
        func bytes(_ value: Any?, _ decode: (String) -> Data?) -> Data? {
            if let text = value as? String { return decode(text) }
            guard let numbers = value as? [Int], numbers.allSatisfy({ (0 ... 255).contains($0) }) else { return nil }
            return Data(numbers.map(UInt8.init))
        }
        let decoders: [(String) -> Data?] = [{ Data(base64Encoded: $0) }, { data(fromHex: $0) }]
        for decode in decoders {
            guard bytes(field("appEphemeralPubKeyHash"), decode) == appEphemeralPubKeyHash,
                  let walletEphemeralPubKey = bytes(field("walletEphemeralPubKey"), decode),
                  walletEphemeralPubKey.count == 33,
                  let encryptedPayload = bytes(field("encryptedPayload"), decode),
                  (60 ... 572).contains(encryptedPayload.count) else { continue }
            return ResponseValues(
                appEphemeralPubKeyHash: appEphemeralPubKeyHash.toHexString(),
                walletEphemeralPubKey: walletEphemeralPubKey.toHexString(),
                encryptedPayload: encryptedPayload.toHexString())
        }
        return nil
    }

    static func data(fromHex hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
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
/// back to the entry. It also names the key; without it a disconnect finds
/// the key by its contract bound, and the entry not at all.
struct AppConnectGrant: Codable, Equatable {
    /// Base58 ids.
    let identityId: String
    let appContractId: String
    /// `nil` until Platform confirmed the response: the grant is recorded
    /// before publishing, so a publish whose outcome is unknown still leaves
    /// a key that can be disabled.
    var documentId: String?
    /// Replaced only by values read back from Platform.
    var values: AppConnect.ResponseValues
    let sessionKeyId: UInt32
    /// The limits the key was registered with; `nil` for one without.
    let totalBudget: UInt64?
    let expiresAt: UInt64?
    let publishedAt: Date
    /// Set once the response is known to be gone from Platform while the key
    /// stays live: deleted by a later login to the same app, or never there
    /// after a publish that did not land. Absent means not known to be gone.
    var responseDeleted: Bool?
    /// Set once a disconnect disabled the key while its response could not
    /// be deleted, or could not be shown to be absent; the record then only
    /// waits for that.
    var keyDisabled: Bool?

    /// What makes two records the same grant: one session key given for one
    /// request. Records are matched on this, never on whole-value equality —
    /// `publishedAt` does not survive the store's millisecond round trip bit
    /// for bit.
    var key: String {
        [identityId, appContractId, String(sessionKeyId), values.appEphemeralPubKeyHash].joined(separator: "|")
    }

    /// Whether there is a response on Platform this record can still delete.
    var hasDeletableResponse: Bool {
        documentId != nil && responseDeleted != true
    }

    /// A publish was started and never confirmed: the response may be on
    /// Platform or not.
    var hasUnconfirmedResponse: Bool {
        documentId == nil && responseDeleted != true
    }
}

protocol AppConnectResponseStore {
    /// Whether `save` keeps anything. A login must not register a key the
    /// store cannot record: its response could not be found again.
    var canPersist: Bool { get }
    func load() -> [AppConnectGrant]
    func save(_ grants: [AppConnectGrant])
}

extension AppConnectResponseStore {
    var canPersist: Bool { true }
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

    var canPersist: Bool { storageKey != nil }

    func load() -> [AppConnectGrant] {
        readRows().grants
    }

    func save(_ grants: [AppConnectGrant]) {
        guard let storageKey else { return }
        // Rows this build cannot read are written back untouched: each one is
        // the only record of a response on Platform, and dropping it would
        // leave that response impossible to find.
        let unreadable = readRows().unreadable
        guard !grants.isEmpty || !unreadable.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        do {
            let encoded = try grants.map { try JSONSerialization.jsonObject(with: encoder.encode($0)) }
            defaults.set(
                try JSONSerialization.data(withJSONObject: encoded + unreadable),
                forKey: storageKey)
        } catch {
            Self.logger.error(
                "AppConnectResponseStore: failed to encode grants: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Decodes row by row, like `UserDefaultsDashConnectStore`, so one
    /// unreadable row costs one record instead of all of them.
    private func readRows() -> (grants: [AppConnectGrant], unreadable: [Any]) {
        guard let storageKey, let data = defaults.data(forKey: storageKey) else { return ([], []) }
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            Self.logger.error("AppConnectResponseStore: stored value is not a JSON array; left in place")
            return ([], [])
        }
        var grants: [AppConnectGrant] = []
        var unreadable: [Any] = []
        for row in rows {
            if JSONSerialization.isValidJSONObject(row),
               let rowData = try? JSONSerialization.data(withJSONObject: row),
               let grant = try? decoder.decode(AppConnectGrant.self, from: rowData) {
                grants.append(grant)
            } else {
                unreadable.append(row)
            }
        }
        if !unreadable.isEmpty {
            Self.logger.warning(
                "AppConnectResponseStore: \(unreadable.count, privacy: .public) stored grant(s) could not be read; kept as stored")
        }
        return (grants, unreadable)
    }
}
