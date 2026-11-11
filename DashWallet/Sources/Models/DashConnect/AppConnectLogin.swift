import CryptoKit
import Foundation
import os
import SwiftDashSDK

/// App Connect (DashConnect from protocol version 14): the wallet registers
/// the keys a request asks for on the identity, then publishes them,
/// encrypted, to the App Connect system contract. There is no `dash-st:`
/// step.
///
/// `AppConnect` holds the rules and is pure; `PlatformDashConnectDataSource`
/// owns the Platform calls and their order. The intent store is at the end
/// of the file; the v2 rules are in `AppConnectV2Login.swift` and the
/// projection in `AppConnectProjection.swift`.
enum AppConnect {
    /// The protocol version that registers the App Connect system contract.
    /// Below it the contract does not exist and no login can work.
    static let minimumProtocolVersion: UInt32 = 14

    /// Same id on every network (`docs/protocol/app-connect.md` in
    /// dashpay/platform).
    static let contractId = "H8F9mP1BM55TE1ShsxPZHzhyinaMdY9bMmP85mkDhcJJ"
    static let documentType = PlatformDashConnectDataSource.loginKeyExchangeDocumentType

    static func isAvailable(protocolVersion: UInt32) -> Bool {
        protocolVersion >= minimumProtocolVersion
    }

    /// Which login an approval would run, as far as the wallet could tell
    /// when it built the approval sheet.
    enum Login: Equatable {
        /// The network did not say which login it takes, so what approving
        /// would give the app is unknown and there is nothing to approve.
        case unresolved
        /// An App Connect request v2: registers the keys of this plan.
        case appConnect(GrantPlan)
        /// An App Connect request v2 the wallet will not answer; there is
        /// nothing to approve.
        case refused(Refusal)

        var grantPlan: GrantPlan? {
            if case .appConnect(let plan) = self { return plan }
            return nil
        }

        /// Whether the sheet has something to approve.
        var isApprovable: Bool {
            switch self {
            case .appConnect: return true
            case .unresolved, .refused: return false
            }
        }
    }

    /// The answer to a `dash-key:` v1 request: only a v2 request says what
    /// it asks for, and the wallet answers no other.
    static var v1Refusal: Refusal { Refusal(.unsupported, NSLocalizedString(
        "This app uses an older sign-in that this wallet no longer supports. Ask the app for a new code.",
        comment: "DashConnect App Connect v1")) }

    /// What the wallet's store of identity keys says about one key: its
    /// payload, whether it is disabled there, and the contract it is bound to
    /// when the bound is a whole single contract. The fetched key list
    /// carries no bounds, so this is where a key's bound is read from.
    struct KeyBinding: Equatable {
        let keyId: UInt32
        let data: Data
        let singleContractId: Data?
        var isDisabled = false
        /// The store has a bound for the key that this build cannot read, so
        /// the key's app is unknown rather than "another one".
        var hasUnreadableBound = false
        /// The key's bound as the store holds it; nil for a key with no
        /// bound, or one this build cannot read (`hasUnreadableBound`).
        var bound: StoredBound? = nil
    }

    /// A key's contract bound, as the wallet's store records it.
    enum StoredBound: Codable, Equatable {
        case singleContract(Data)
        case documentType(contractId: Data, name: String)
        case contractGroup(Data)
    }

    /// The bound of a stored key: the store's discriminant (`boundsKind`,
    /// see `singleContractId(boundsKind:boundIds:)`), its ids and, for a
    /// document type, its name. Nil for no bound and for one that cannot be
    /// read.
    static func storedBound(boundsKind: Int, boundIds: [Data]?, documentTypeName: String?) -> StoredBound? {
        guard let id = boundIds?.first, id.count == 32 else { return nil }
        switch boundsKind {
        case 1: return .singleContract(id)
        case 2: return documentTypeName.map { .documentType(contractId: id, name: $0) }
        case 3: return .contractGroup(id)
        default: return nil
        }
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

}

/// Lets one DashConnect operation at a time run for a wallet, across every
/// data source in the process. A screen that is opened again gets a new data
/// source over the same stores while an approval started on the old one is
/// still running; without this a disconnect could pick the keys to disable
/// before that approval registers one more.
///
/// Callers wait their turn in the order they arrived.
actor DashConnectOperationGate {
    static let shared = DashConnectOperationGate()

    private var held: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// `onWait` is called when the operation has to wait for its turn.
    func run<T>(
        for key: String,
        onWait: () -> Void = {},
        _ operation: () async throws -> T
    ) async rethrows -> T {
        if held.contains(key) { onWait() }
        await enter(key)
        do {
            let result = try await operation()
            leave(key)
            return result
        } catch {
            leave(key)
            throw error
        }
    }

    private func enter(_ key: String) async {
        guard held.contains(key) else {
            held.insert(key)
            return
        }
        // The turn is handed over by `leave`, which keeps `key` held.
        await withCheckedContinuation { waiting[key, default: []].append($0) }
    }

    private func leave(_ key: String) {
        guard var queue = waiting[key], !queue.isEmpty else {
            waiting[key] = nil
            held.remove(key)
            return
        }
        let next = queue.removeFirst()
        waiting[key] = queue
        next.resume()
    }
}

protocol AppConnectIntentStore {
    /// Whether `save` keeps anything. An approval must not submit keys the
    /// store cannot record: nothing would then name them.
    var canPersist: Bool { get }
    /// Whether the store holds a row `load` leaves out because it cannot be
    /// read, and that may be an intent of `identityId`: one naming another
    /// identity is not. Such a row may name key ids that are still to land.
    func hasUnreadableRows(identityId: Data) -> Bool
    func load() -> [AppConnect.ConnectionIntent]
    func save(_ intents: [AppConnect.ConnectionIntent])
    /// This store fixed to one wallet, and to the network scope it has now,
    /// like `DashConnectStore.pinned(toWalletIdHex:)`.
    func pinned(toWalletIdHex walletIdHex: String) -> any AppConnectIntentStore
}

extension AppConnectIntentStore {
    var canPersist: Bool { true }
    func hasUnreadableRows(identityId: Data) -> Bool { false }
}

/// Wallet- and network-scoped, like `UserDefaultsDashConnectStore`, whose
/// scope it borrows. Nothing stored is secret: the public keys and the
/// response, which is sealed to the app's ephemeral key, are what goes on
/// chain.
///
/// It replaces the grant records (`app-connect-responses.v1`) that internal
/// TestFlight builds of the DashConnect release branch wrote; no App Store
/// build wrote them, and they are not read. Keys those builds gave show as
/// keys no intent names, and can be turned off from Connections.
final class UserDefaultsAppConnectIntentStore: AppConnectIntentStore {
    private let defaults: UserDefaults
    private let scope: Scope
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "dashconnect.app-connect-store")

    /// Where the scope comes from.
    enum Scope {
        /// Borrowed from a connection store, so both keep one wallet's data.
        case connections(UserDefaultsDashConnectStore)
        /// Handed in as it is; it names no wallet.
        case key(() -> String?)
    }

    convenience init(
        defaults: UserDefaults = .standard,
        network: DashConnectNetwork,
        scopeKeyProvider: (() -> String?)? = nil
    ) {
        self.init(
            defaults: defaults,
            scope: scopeKeyProvider.map(Scope.key)
                ?? .connections(UserDefaultsDashConnectStore(defaults: defaults, network: network)))
    }

    init(defaults: UserDefaults, scope: Scope) {
        self.defaults = defaults
        self.scope = scope

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    private var storageKey: String? {
        let scopeKey: String?
        switch scope {
        case .connections(let connections): scopeKey = connections.storageKey
        case .key(let provider): scopeKey = provider()
        }
        return scopeKey.map { "\($0).app-connect-intents.v1" }
    }

    func pinned(toWalletIdHex walletIdHex: String) -> any AppConnectIntentStore {
        switch scope {
        case .connections(let connections):
            return UserDefaultsAppConnectIntentStore(
                defaults: defaults, scope: .connections(connections.pinnedStore(toWalletIdHex: walletIdHex)))
        case .key(let provider):
            // A handed-in scope names no wallet to replace: it is fixed to
            // the value it has now.
            let scopeKey = provider()
            return UserDefaultsAppConnectIntentStore(defaults: defaults, scope: .key { scopeKey })
        }
    }

    /// False as well while the stored value is not a list of rows: `save`
    /// leaves such a value alone, so nothing new would be kept.
    var canPersist: Bool { storageKey != nil && !readRows().isNotRowList }

    func hasUnreadableRows(identityId: Data) -> Bool {
        let rows = readRows()
        return rows.isNotRowList || rows.unreadable.contains {
            guard let named = ($0 as? [String: Any])?["identityId"] as? String else { return true }
            return named == identityId.base64EncodedString()
        }
    }

    func load() -> [AppConnect.ConnectionIntent] {
        readRows().intents
    }

    func save(_ intents: [AppConnect.ConnectionIntent]) {
        guard let storageKey else { return }
        let stored = readRows()
        // A value that is not a list of rows is not this build's to replace:
        // nothing is written until it is gone.
        guard !stored.isNotRowList else {
            Self.logger.error("AppConnectIntentStore: stored value is not a JSON array; intents not saved")
            return
        }
        // Rows this build cannot read are written back untouched: each may
        // name keys that are still to land.
        let unreadable = stored.unreadable
        guard !intents.isEmpty || !unreadable.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        do {
            let encoded = try intents.map { try JSONSerialization.jsonObject(with: encoder.encode($0)) }
            defaults.set(
                try JSONSerialization.data(withJSONObject: encoded + unreadable),
                forKey: storageKey)
        } catch {
            Self.logger.error(
                "AppConnectIntentStore: failed to encode intents: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Decodes row by row, like `UserDefaultsDashConnectStore`, so one
    /// unreadable row costs one record instead of all of them.
    private func readRows() -> (intents: [AppConnect.ConnectionIntent], unreadable: [Any], isNotRowList: Bool) {
        guard let storageKey, let stored = defaults.object(forKey: storageKey) else { return ([], [], false) }
        guard let data = stored as? Data,
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            Self.logger.error("AppConnectIntentStore: stored value is not a JSON array; left in place")
            return ([], [], true)
        }
        var intents: [AppConnect.ConnectionIntent] = []
        var unreadable: [Any] = []
        for row in rows {
            if JSONSerialization.isValidJSONObject(row),
               let rowData = try? JSONSerialization.data(withJSONObject: row),
               let intent = try? decoder.decode(AppConnect.ConnectionIntent.self, from: rowData) {
                intents.append(intent)
            } else {
                unreadable.append(row)
            }
        }
        if !unreadable.isEmpty {
            Self.logger.warning(
                "AppConnectIntentStore: \(unreadable.count, privacy: .public) stored intent(s) could not be read; kept as stored")
        }
        return (intents, unreadable, false)
    }
}
