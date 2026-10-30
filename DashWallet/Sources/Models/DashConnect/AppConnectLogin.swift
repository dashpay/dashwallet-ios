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

    /// What a one-QR approval gives the app: how many of the identity's
    /// credits its key may spend and for how long the key works. The approval
    /// sheet shows these values and the key is registered with them.
    struct SessionKeyTerms: Equatable {
        let budgetCredits: UInt64
        let lifetime: TimeInterval

        static let current = SessionKeyTerms(
            budgetCredits: sessionKeyBudgetCredits,
            lifetime: sessionKeyLifetime)

        func expiresAt(from now: Date) -> UInt64 {
            UInt64((now.addingTimeInterval(lifetime).timeIntervalSince1970 * 1000).rounded())
        }
    }

    static func isAvailable(protocolVersion: UInt32) -> Bool {
        protocolVersion >= minimumProtocolVersion
    }

    /// Which login an approval would run, as far as the wallet could tell
    /// when it built the approval sheet.
    enum Login: Equatable {
        /// The network did not say which login it takes, so what approving
        /// would give the app is unknown and there is nothing to approve.
        case unresolved
        /// Registers no key at approval.
        case twoQR
        /// Registers a session key with these terms.
        case oneQR(SessionKeyTerms)
        /// An App Connect request v2: registers the keys of this plan.
        case appConnect(GrantPlan)
        /// An App Connect request v2 the wallet will not answer; there is
        /// nothing to approve.
        case refused(Refusal)

        var sessionKeyTerms: SessionKeyTerms? {
            if case .oneQR(let terms) = self { return terms }
            return nil
        }

        var grantPlan: GrantPlan? {
            if case .appConnect(let plan) = self { return plan }
            return nil
        }

        /// Whether the sheet has something to approve.
        var isApprovable: Bool {
            switch self {
            case .twoQR, .oneQR, .appConnect: return true
            case .unresolved, .refused: return false
            }
        }
    }

    /// The login a network at `protocolVersion` gets.
    static func login(protocolVersion: UInt32) -> Login {
        isAvailable(protocolVersion: protocolVersion) ? .oneQR(.current) : .twoQR
    }

    /// The DIP-13 leaf of the session key: `hash256` of the app's ephemeral
    /// public key. Not the lookup key of the response, which is `hash160` of
    /// the same bytes.
    static func requestId(appEphemeralPubKey: Data) -> Data {
        Data(SHA256.hash(data: Data(SHA256.hash(data: appEphemeralPubKey))))
    }

    /// What the identity already holds for a derived session key.
    enum SessionKeyState: Equatable {
        /// Not on the identity: register it.
        case absent
        /// Registered, able to sign, and shown to be this app's key within
        /// the approved terms: publish without an identity update.
        case usable(keyId: UInt32)
        /// Registered but disabled or expired, or not shown to be this app's
        /// key within the approved terms. Platform never re-adds a key, so
        /// this request cannot be answered; the app has to ask again.
        case unusable
    }

    /// How far the device clock may have moved back since a key was
    /// registered before that key's expiry counts as later than the terms
    /// allow. Without it a clock correction between two tries of one request
    /// would turn the wallet's own key away.
    static let clockTolerance: TimeInterval = 60 * 60

    /// The session key is derived from the identity and the request's
    /// ephemeral key, not from the app's contract, so a request that repeats
    /// another app's ephemeral key derives that app's key. A registered key
    /// is therefore reused only when it is bound to `appContractId` and
    /// carries limits no wider than `terms`.
    ///
    /// The fetched key list carries no bounds. The bound is read from
    /// `bindings`; a key the store cannot place counts as this app's only
    /// when `grantedKeyIds` holds it — the keys this wallet recorded giving
    /// this app for this request.
    static func sessionKeyState(
        publicKeyHash160: Data,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        appContractId: Data,
        bindings: [KeyBinding],
        grantedKeyIds: Set<UInt32>,
        terms: SessionKeyTerms,
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
              let totalBudget = key.totalBudget,
              totalBudget <= terms.budgetCredits,
              let expiresAt = key.expiresAt,
              expiresAt > nowMilliseconds,
              UInt64(expiresAt) <= terms.expiresAt(from: now.addingTimeInterval(clockTolerance)) else {
            return .unusable
        }
        let keyId = UInt32(bitPattern: key.keyId)
        let stored = bindings.first { $0.keyId == keyId && $0.data == key.data && !$0.hasUnreadableBound }
        guard stored.map({ $0.singleContractId == appContractId }) ?? grantedKeyIds.contains(keyId) else {
            return .unusable
        }
        return .usable(keyId: keyId)
    }

    /// `count` ids that no key of the identity has, for one update that
    /// adds `count` keys: above the highest id while they fit, then the
    /// lowest gaps. Nil when the identity cannot take that many. `reserved`
    /// ids count as taken: an update that may still land adds keys under
    /// them (`reservedKeyIds`).
    static func freeKeyIds(
        count: Int,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        reserved: Set<UInt32> = []
    ) -> [UInt32]? {
        let taken = Set(currentIdentityPublicKeys.map { UInt32(bitPattern: $0.keyId) }).union(reserved)
        let highest = taken.max()
        var ids: [UInt32] = []
        var next = highest.map { $0 == .max ? nil : $0 + 1 } ?? 0
        while ids.count < count, let id = next {
            ids.append(id)
            next = id == .max ? nil : id + 1
        }
        // The identity holds far fewer keys than there are ids, so this
        // stops within a few steps of the lowest gaps.
        var gap: UInt32 = 0
        while ids.count < count {
            if !taken.contains(gap) && !ids.contains(gap) { ids.append(gap) }
            guard gap < .max else { return nil }
            gap += 1
        }
        return ids
    }

    /// The id for a new key: one above the highest on the identity, disabled
    /// keys included. Platform only refuses an id the identity already has,
    /// so when the highest is the last id a key can have (a key an app
    /// registered can be given it) the lowest id no key has is taken
    /// instead. `nil` only when every id is taken. `reserved` ids count as
    /// taken (`reservedKeyIds`).
    static func nextKeyId(
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        reserved: Set<UInt32> = []
    ) -> UInt32? {
        let taken = Set(currentIdentityPublicKeys.map { UInt32(bitPattern: $0.keyId) }).union(reserved)
        let highest = taken.max() ?? 0
        guard highest == .max else { return highest + 1 }
        // The identity holds far fewer keys than there are ids, so this
        // stops within a few steps of the lowest gap.
        return (0 ... UInt32.max).first { !taken.contains($0) }
    }

    /// The ids the unconfirmed records of `identityId` whose update may
    /// still land add keys under: every key of a v2 record waiting for its
    /// update, and the session key of a one-QR registration that notes its
    /// revision. A new key under one of them would make that update, or
    /// itself, be refused. A caller retrying one of them leaves its own
    /// record out of `grants`.
    static func reservedKeyIds(grants: [AppConnectGrant], identityId: String) -> Set<UInt32> {
        Set(grants.filter { $0.identityId == identityId && $0.isUnconfirmed }.flatMap { grant -> [UInt32] in
            if let pending = grant.pendingUpdate { return pending.addedKeys.map(\.keyId) }
            return grant.submittedRevision == nil ? [] : [grant.sessionKeyId]
        })
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
        /// The stored key has the type, purpose and level of the two-QR
        /// login's authentication key, or of its encryption key.
        var isTwoQRAuthenticationKeyShaped = false
        var isTwoQREncryptionKeyShaped = false
        /// The key's bound as the store holds it; nil for a key with no
        /// bound, or one this build cannot read (`hasUnreadableBound`).
        var bound: StoredBound? = nil
        /// The stored key has the shape of an App Connect v2 auth key:
        /// HASH160 authentication at HIGH or CRITICAL, with an expiry.
        var isV2AuthKeyShaped = false
        /// When the stored key stops working, in milliseconds since 1970;
        /// nil for a key with no expiry.
        var expiresAt: Int64? = nil
    }

    /// A key's contract bound, as the wallet's store records it.
    enum StoredBound: Equatable, Codable {
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

    /// Whether the store shows either key of the two-QR login, not disabled,
    /// in the kind that login registers it. A two-QR login leaves no grant
    /// record, so on an identity that is not the active one this is how its
    /// keys are recognised.
    static func holdsLiveTwoQRLoginKey(
        authenticationPublicKeyHash160: Data,
        encryptionPublicKey: Data,
        bindings: [KeyBinding]
    ) -> Bool {
        bindings.contains {
            !$0.isDisabled
                && (($0.isTwoQRAuthenticationKeyShaped && $0.data == authenticationPublicKeyHash160)
                    || ($0.isTwoQREncryptionKeyShaped && $0.data == encryptionPublicKey))
        }
    }

    /// Whether the store shows a live session key bound to `appContractId`.
    static func holdsLiveSessionKey(appContractId: Data, bindings: [KeyBinding]) -> Bool {
        bindings.contains { $0.singleContractId == appContractId && !$0.isDisabled && $0.isSessionKeyShaped }
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

    /// A live key in a shape App Connect registers for an app: HASH160
    /// authentication at HIGH (a v1 session key, most v2 keys) or CRITICAL
    /// (a v2 contract-group key).
    static func isLiveAppConnectAuthKey(_ key: ManagedIdentity.IdentityPublicKeyInfo) -> Bool {
        key.keyType == .ecdsaHash160 && key.purpose == .authentication
            && (key.securityLevel == .high || key.securityLevel == .critical) && key.disabledAt == nil
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
    /// A key without a grant record whose payload is
    /// `twoQRAuthenticationKeyHash160` is left alone as well: the two-QR
    /// login's authentication key has the same kind and bound, and a
    /// `dash-st:` registration may have put limits on it. The caller passes
    /// it when that key is to stay.
    static func sessionKeyIdsToDisable(
        for grants: [AppConnectGrant],
        appContractId: Data,
        bindings: [KeyBinding],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        twoQRAuthenticationKeyHash160: Data? = nil
    ) -> [UInt32] {
        let granted = Set(grants.flatMap(\.keyIds))
        let grantedByV2 = Set(grants.filter { $0.additionalKeyIds != nil || $0.connectionId != nil }.flatMap(\.keyIds))
        return currentIdentityPublicKeys
            .filter { key in
                let keyId = UInt32(bitPattern: key.keyId)
                // A recorded id is disabled only while the key under it has
                // the shape the grant registered: the id of a registration
                // that never landed may belong to another key since. A v1
                // session key is HIGH; a v2 grant's keys may also be a
                // CRITICAL group key, which the store has to show bound to a
                // group.
                if granted.contains(keyId) {
                    if isLiveSessionKey(key) { return true }
                    guard grantedByV2.contains(keyId), isLiveAppConnectAuthKey(key),
                          key.securityLevel == .critical else { return false }
                    return bindings.contains {
                        guard $0.keyId == keyId, $0.data == key.data, case .contractGroup = $0.bound else { return false }
                        return true
                    }
                }
                guard isLiveSessionKey(key) else { return false }
                guard key.totalBudget != nil, key.expiresAt != nil,
                      key.data != twoQRAuthenticationKeyHash160 else { return false }
                return bindings.contains {
                    $0.keyId == keyId && $0.data == key.data && $0.singleContractId == appContractId
                }
            }
            .map { UInt32(bitPattern: $0.keyId) }
            .sorted()
    }

    /// Live keys in a shape App Connect registers (`isLiveAppConnectAuthKey`)
    /// whose bound is unknown: not behind `grants`, and either absent from
    /// `bindings` or stored with a bound that cannot be read. Any of them
    /// could belong to the app being disconnected, so a disconnect must stop
    /// on these instead of reporting every key as turned off.
    static func sessionKeyIdsWithUnknownBinding(
        for grants: [AppConnectGrant],
        bindings: [KeyBinding],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [UInt32] {
        let granted = Set(grants.flatMap(\.keyIds))
        return currentIdentityPublicKeys
            .filter { key in
                guard isLiveAppConnectAuthKey(key) else { return false }
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

    /// Whether the identity holds, live, the key a record names. For an
    /// unconfirmed record that is the key it was going to register, with
    /// everything that key was given: the data, the kind, the limits, and the
    /// bound to the record's app as the wallet's store reads it. A bound the
    /// store does not show is not taken on trust.
    static func holdsRecordedKey(
        _ grant: AppConnectGrant,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        bindings: [KeyBinding]
    ) -> Bool {
        guard let hash = grant.unconfirmedKeyHash160 else {
            // A confirmed record: any of its keys (a v2 grant has several).
            return currentIdentityPublicKeys.contains {
                grant.keyIds.contains(UInt32(bitPattern: $0.keyId)) && $0.disabledAt == nil
            }
        }
        return currentIdentityPublicKeys.contains { key in
            guard UInt32(bitPattern: key.keyId) == grant.sessionKeyId, key.disabledAt == nil else { return false }
            guard let appContractId = Data.identifier(fromBase58: grant.appContractId) else { return false }
            return key.keyType == .ecdsaHash160 && key.data.toHexString() == hash
                && key.purpose == .authentication && key.securityLevel == .high
                && key.totalBudget == grant.totalBudget
                && key.expiresAt.map({ UInt64(max(0, $0)) }) == grant.expiresAt
                && bindings.contains {
                    $0.keyId == grant.sessionKeyId && $0.data == key.data && !$0.hasUnreadableBound
                        && $0.singleContractId == appContractId
                }
        }
    }

    /// Confirms the unconfirmed one-QR records of `identityId` whose key the
    /// identity now holds, and returns them. A record whose key is not there
    /// stays as it is: the update may still land, and nothing is taken from
    /// a view that may be behind. An App Connect v2 record waiting for its
    /// update is settled by `settlePendingV2Registrations`.
    static func confirmRegistrations(
        in grants: inout [AppConnectGrant],
        identityId: String,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        bindings: [KeyBinding]
    ) -> [AppConnectGrant] {
        var confirmed: [AppConnectGrant] = []
        for index in grants.indices
        where grants[index].identityId == identityId && grants[index].isUnconfirmed
            && !grants[index].isPendingV2
            && holdsRecordedKey(
                grants[index], currentIdentityPublicKeys: currentIdentityPublicKeys, bindings: bindings) {
            grants[index].unconfirmedKeyHash160 = nil
            confirmed.append(grants[index])
        }
        return confirmed
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
        return Set(grants.flatMap(\.keyIds)).subtracting(known).sorted()
    }

    /// What a disconnect leaves of the matching records once their keys are
    /// disabled. A record whose response is known to be gone is done; the
    /// rest stay, marked, until their response is deleted, or found if its
    /// publish never confirmed.
    static func markKeysDisabled(in grants: inout [AppConnectGrant], where matches: (AppConnectGrant) -> Bool) {
        grants.removeAll { matches($0) && $0.responseDeleted == true }
        for index in grants.indices where matches(grants[index]) {
            grants[index].keyDisabled = true
        }
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
    /// App Connect v2: the grant's other auth keys, in request order after
    /// `sessionKeyId` (the primary binding's key). The identity's encryption
    /// key for the app is shared by every device and is not part of a grant.
    var additionalKeyIds: [UInt32]? = nil
    /// App Connect v2: the request's `CONNECTION_ID` (hex). A later login
    /// with the same one replaces this grant's keys.
    var connectionId: String? = nil
    /// App Connect v2: the ids of the identity's encryption keys the
    /// response carries, in slot order. A retry sends the recorded response
    /// only while it would carry the same ones.
    var encryptionKeyIds: [UInt32]? = nil

    /// Every auth key of the grant.
    var keyIds: [UInt32] {
        [sessionKeyId] + (additionalKeyIds ?? [])
    }

    /// The hex hash160 of the session key, set from just before its
    /// registration is submitted until the key is seen on the identity.
    /// While set, the key may be there or not: an update can land without
    /// confirming. Such a record has no row and no response; it is kept so
    /// the key, if it lands, is found and confirmed, until a disconnect
    /// finds that the update can no longer land.
    var unconfirmedKeyHash160: String? = nil
    /// The identity revision the registration's update was submitted with,
    /// set with `unconfirmedKeyHash160`. Platform takes an identity update
    /// only at one above the identity's revision, so once the identity is at
    /// this revision or past it without the key live, the update can never
    /// land.
    /// `nil` on a record from a build that did not note it.
    var submittedRevision: UInt64? = nil
    /// App Connect v2: the update that registers this grant's keys, from
    /// just before it is submitted until its outcome is known
    /// (`AppConnect.pendingV2Outcome`). Set together with
    /// `unconfirmedKeyHash160`, the primary key's hash, so a build that
    /// does not know this field still reads the record as unconfirmed.
    var pendingUpdate: PendingV2Update? = nil
    /// App Connect v2: the update was found to have landed after its
    /// approval stopped waiting, and its response has not been published
    /// since (`publishRecoveredResponses`).
    var awaitsRecoveredPublish: Bool? = nil

    var isUnconfirmed: Bool { unconfirmedKeyHash160 != nil }

    /// An App Connect v2 grant whose update may or may not have landed.
    var isPendingV2: Bool { pendingUpdate != nil }

    /// What an App Connect v2 update was submitted with, kept with the
    /// grant until its outcome is known.
    struct PendingV2Update: Codable, Equatable {
        /// Every key the update adds, as it adds it.
        var addedKeys: [AppConnect.ExpectedKey]
        /// The keys of the connection's earlier grants it disables.
        var disabledKeyIds: [UInt32]
        /// The records of those grants (`key`) that are done once it lands.
        var retiredGrantKeys: [String]
        /// An update of this wallet to the identity that landed after this
        /// one was submitted (`AppConnect.noteOwnUpdate`): this one cannot
        /// land after it.
        var outlivedBy: AppConnect.OwnUpdate? = nil
        /// The app's row was a two-QR `.approved` one before this approval
        /// showed it as confirming: it goes back to that if the update never
        /// lands.
        var replacesApprovedRow: Bool? = nil
    }

    /// What makes two records the same grant: one session key given for one
    /// request. Records are matched on this, never on whole-value equality —
    /// `publishedAt` does not survive the store's millisecond round trip bit
    /// for bit.
    var key: String {
        [identityId, appContractId, String(sessionKeyId), values.appEphemeralPubKeyHash].joined(separator: "|")
    }

    /// Call before a publish is submitted. Until Platform confirms it, the
    /// response may be there or not, whatever the record said before: a
    /// response an earlier login deleted is published again when its request
    /// comes back.
    mutating func markPublishStarted() {
        documentId = nil
        responseDeleted = nil
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

protocol AppConnectResponseStore {
    /// Whether `save` keeps anything. A login must not register a key the
    /// store cannot record: its response could not be found again.
    var canPersist: Bool { get }
    func load() -> [AppConnectGrant]
    func save(_ grants: [AppConnectGrant])
    /// This store fixed to one wallet, and to the network scope it has now,
    /// like `DashConnectStore.pinned(toWalletIdHex:)`.
    func pinned(toWalletIdHex walletIdHex: String) -> any AppConnectResponseStore
}

extension AppConnectResponseStore {
    var canPersist: Bool { true }
}

/// Wallet- and network-scoped, like `UserDefaultsDashConnectStore`, whose
/// scope it borrows. Nothing stored is secret: the values are public on
/// chain and the key ids are visible on the identity.
final class UserDefaultsAppConnectResponseStore: AppConnectResponseStore {
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
        return scopeKey.map { "\($0).app-connect-responses.v1" }
    }

    func pinned(toWalletIdHex walletIdHex: String) -> any AppConnectResponseStore {
        switch scope {
        case .connections(let connections):
            return UserDefaultsAppConnectResponseStore(
                defaults: defaults, scope: .connections(connections.pinnedStore(toWalletIdHex: walletIdHex)))
        case .key(let provider):
            // A handed-in scope names no wallet to replace: it is fixed to
            // the value it has now.
            let scopeKey = provider()
            return UserDefaultsAppConnectResponseStore(defaults: defaults, scope: .key { scopeKey })
        }
    }

    /// False as well while the stored value is not a list of rows: `save`
    /// leaves such a value alone, so nothing new would be kept.
    var canPersist: Bool { storageKey != nil && !readRows().isNotRowList }

    func load() -> [AppConnectGrant] {
        readRows().grants
    }

    func save(_ grants: [AppConnectGrant]) {
        guard let storageKey else { return }
        let stored = readRows()
        // A value that is not a list of rows is not this build's to replace:
        // nothing is written until it is gone.
        guard !stored.isNotRowList else {
            Self.logger.error("AppConnectResponseStore: stored value is not a JSON array; grants not saved")
            return
        }
        // Rows this build cannot read are written back untouched: each one is
        // the only record of a response on Platform, and dropping it would
        // leave that response impossible to find.
        let unreadable = stored.unreadable
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
    private func readRows() -> (grants: [AppConnectGrant], unreadable: [Any], isNotRowList: Bool) {
        guard let storageKey, let stored = defaults.object(forKey: storageKey) else { return ([], [], false) }
        // A value of another kind is as much not this build's to replace as
        // data that is not a list.
        guard let data = stored as? Data,
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            Self.logger.error("AppConnectResponseStore: stored value is not a JSON array; left in place")
            return ([], [], true)
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
        return (grants, unreadable, false)
    }
}
