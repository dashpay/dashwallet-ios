import CryptoKit
import Foundation
import SwiftDashSDK

/// App Connect as one projection. The wallet stores only what Platform cannot
/// tell it: the intents, which name the keys an approval submits. Every
/// connection, its status and its expiry are computed from one read of the
/// identity and those intents; nothing computed is stored.
///
/// Platform takes an identity update whole or not at all, and refuses one
/// that adds a key id the identity already holds. So an intent's keys either
/// all appear as submitted, or one of their ids is held by another key and the
/// update can never land. Nothing else settles an intent: a key that is absent
/// may still arrive, whatever the revision or the time.
extension AppConnect {
    // MARK: Stored

    /// One key an intent submits, exactly as it is submitted.
    struct IntendedKey: Codable, Equatable {
        let id: UInt32
        let purpose: KeyPurpose
        let securityLevel: SecurityLevel
        let keyType: KeyType
        let data: Data
        let readOnly: Bool
        let bound: StoredBound?
        let totalBudget: UInt64?
        /// Block time in milliseconds.
        let expiresAt: UInt64?

        var isAuthentication: Bool { purpose == .authentication }
    }

    /// What the wallet writes before it submits an identity update for an
    /// app, and the only App Connect state it keeps. It is never removed
    /// automatically: an intent whose keys are all off, or whose update can
    /// never land, stays as the connection's history. Its rows are decoded
    /// one by one and a row a build cannot read blocks approvals on its
    /// identity, so a field added later has to be optional.
    struct ConnectionIntent: Codable, Equatable, Identifiable {
        let id: UUID
        let identityId: Data
        let appId: Data
        /// The app's name and website as the approval sheet showed them.
        let appLabel: String
        let appUrl: String
        /// `hash160(appEphPub)` of the request.
        let requestHash: Data
        let connectionId: Data?
        /// The keys the update adds, auth and encryption.
        let keys: [IntendedKey]
        /// The identity's encryption keys the response carries without adding
        /// them, in slot order.
        let sentEncryptionKeyIds: [UInt32]
        /// The ids of earlier auth keys the same update turns off.
        let disables: [UInt32]
        /// The response, sealed before the submit, so a retry publishes the
        /// same values and a disconnect deletes them by those values.
        let response: ResponseValues
        /// Set once the response is known to be on Platform.
        var responseDocumentId: Data?
        /// Set once the response is known to be gone from Platform, or never
        /// to have got there.
        var responseRemoved: Bool
        let createdAt: Date
        /// When the intent was done with: the user disconnected the app, or a
        /// later approval on the same connection replaced it.
        var closedAt: Date?

        var authKeys: [IntendedKey] { keys.filter(\.isAuthentication) }
    }

    // MARK: Read

    /// One key of the identity as Platform shows it. Bounds come from the
    /// wallet's key store, which may not know a key yet: `bound` is nil then,
    /// and `boundKnown` false.
    struct PlatformKey: Equatable {
        let id: UInt32
        let purpose: KeyPurpose
        let securityLevel: SecurityLevel
        let keyType: KeyType
        let data: Data
        let readOnly: Bool
        let bound: StoredBound?
        let boundKnown: Bool
        let totalBudget: UInt64?
        /// Block time in milliseconds.
        let expiresAt: UInt64?
        let disabledAt: UInt64?
    }

    /// A key as the SDK fetched it, with its bound from the wallet's key
    /// store (`binding`, nil when the store does not hold the key).
    static func platformKey(_ key: ManagedIdentity.IdentityPublicKeyInfo, binding: KeyBinding?) -> PlatformKey {
        let known = binding.map { $0.data == key.data && !$0.hasUnreadableBound } ?? false
        return PlatformKey(
            id: UInt32(bitPattern: key.keyId), purpose: key.purpose, securityLevel: key.securityLevel,
            keyType: key.keyType, data: key.data, readOnly: key.readOnly,
            bound: known ? binding?.bound : nil, boundKnown: known,
            // Protocol timestamps are unsigned; the SDK hands them over in an
            // Int64 bit for bit.
            totalBudget: key.totalBudget, expiresAt: key.expiresAt.map { UInt64(bitPattern: $0) },
            disabledAt: key.disabledAt.map { UInt64(bitPattern: $0) })
    }

    /// One read of an identity.
    struct IdentitySnapshot: Equatable {
        let identityId: Data
        let revision: UInt64
        let keys: [PlatformKey]
        /// Platform's block time in milliseconds, proved with the read; nil
        /// when the read carries none. Without it no key is judged expired.
        let platformTime: UInt64?

        /// Whether this read may replace `newest`. A revision only grows, so
        /// a read below one already seen comes from a node that is behind.
        func mayReplace(_ newest: IdentitySnapshot?) -> Bool {
            guard let newest, newest.identityId == identityId else { return true }
            return revision >= newest.revision
        }
    }

    // MARK: One key against the identity

    enum KeyPresence: Equatable {
        /// No key under the id: the update may still land.
        case missing
        /// Another key holds the id: the update can never land.
        case conflicting
        case live
        case expired
        case disabled
    }

    /// The same key: id, type, purpose, level, payload and access. Limits
    /// are left out, since an authorized limits update changes them, and so
    /// is a bound the store does not know yet.
    static func isSameKey(_ actual: PlatformKey, as intended: IntendedKey) -> Bool {
        actual.id == intended.id && actual.keyType == intended.keyType && actual.purpose == intended.purpose
            && actual.securityLevel == intended.securityLevel && actual.data == intended.data
            && actual.readOnly == intended.readOnly
            && (!actual.boundKnown || actual.bound == intended.bound)
    }

    static func isLive(_ key: PlatformKey, at platformTime: UInt64?) -> Bool {
        guard key.disabledAt == nil else { return false }
        guard let expiresAt = key.expiresAt, let platformTime else { return true }
        return expiresAt > platformTime
    }

    static func presence(of intended: IntendedKey, in snapshot: IdentitySnapshot) -> KeyPresence {
        guard let actual = snapshot.keys.first(where: { $0.id == intended.id }) else { return .missing }
        guard isSameKey(actual, as: intended) else { return .conflicting }
        if actual.disabledAt != nil { return .disabled }
        return isLive(actual, at: snapshot.platformTime) ? .live : .expired
    }

    // MARK: One intent

    enum IntentStatus: Equatable {
        /// An auth key is live; `expiresAt` is the earliest expiry among them.
        case active(expiresAt: UInt64?)
        /// No auth key is there yet and none is taken: the update may land.
        case confirming
        /// Every auth key is there and none is live; some expired.
        case expired
        /// Every auth key is off.
        case disconnected
        /// Another key holds one of its ids: the update never landed and
        /// never will.
        case neverLanded
    }

    static func status(of intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> IntentStatus {
        // One key of the update held by another, encryption keys included,
        // and the whole update never lands.
        if intent.keys.contains(where: { presence(of: $0, in: snapshot) == .conflicting }) { return .neverLanded }
        let auth = intent.authKeys.map { ($0, presence(of: $0, in: snapshot)) }
        let live = auth.filter { $0.1 == .live }
        if !live.isEmpty {
            let expiries = live.compactMap { key, _ in
                snapshot.keys.first { $0.id == key.id }?.expiresAt
            }
            return .active(expiresAt: expiries.min())
        }
        if auth.contains(where: { $0.1 == .missing }) { return .confirming }
        if auth.contains(where: { $0.1 == .expired }) { return .expired }
        return .disconnected
    }

    // MARK: The connections

    struct ProjectedConnection: Equatable, Identifiable {
        let appId: Data
        let status: IntentStatus
        /// The app's intents, newest first.
        let intents: [ConnectionIntent]
        /// Live auth keys bound to one of the app's contracts that no intent
        /// names: granted on another device, or before a restore. Keyed by
        /// identity.
        let unrecordedKeyIds: [Data: [UInt32]]

        var id: Data { appId }
    }

    struct Projection: Equatable {
        let connections: [ProjectedConnection]
        /// Live keys bound to the DashPay profile that no intent names, by
        /// identity. They are not any one app's.
        let unrecordedProfileKeyIds: [Data: [UInt32]]
        /// Live App Connect keys no intent names whose bound the wallet's
        /// key store does not hold yet, by identity.
        var unplacedKeyIds: [Data: [UInt32]] = [:]
    }

    /// One app's status from those of its intents: the one the user can act
    /// on first. Live keys come first, then an update that may still land.
    private static func rank(_ status: IntentStatus) -> Int {
        switch status {
        case .active: return 0
        case .confirming: return 1
        case .expired: return 2
        case .disconnected: return 3
        case .neverLanded: return 4
        }
    }

    /// The contract a bound is on.
    static func contractId(of bound: StoredBound) -> Data {
        switch bound {
        case .singleContract(let id), .contractGroup(let id): return id
        case .documentType(let contractId, _): return contractId
        }
    }

    /// A live key in a shape App Connect registers for an app: HASH160
    /// authentication at HIGH or CRITICAL, with an expiry (every key an
    /// approval gives has one). Anything else on the identity (the wallet's
    /// own keys, keys of other tools) is never counted as an app's.
    static func isAppConnectAuthKey(_ key: PlatformKey) -> Bool {
        key.purpose == .authentication && key.keyType == .ecdsaHash160
            && (key.securityLevel == .high || key.securityLevel == .critical)
            && key.expiresAt != nil && key.disabledAt == nil
    }

    static func isProfileBound(_ bound: StoredBound) -> Bool {
        guard case .documentType(let contractId, let name) = bound else { return false }
        return contractId.toBase58String() == dashPayContractId && name == "profile"
    }

    /// Every connection the wallet can show for these identities. An app
    /// with no intent appears when one of its contracts carries a live auth
    /// key no intent names. Keys whose payload is in `protected` are never
    /// counted as unrecorded: the two-QR login derives its keys again every
    /// time, and Platform never re-adds one that was turned off.
    static func project(
        _ snapshots: [IdentitySnapshot], intents: [ConnectionIntent], protected: Set<Data> = []
    ) -> Projection {
        let byIdentity = Dictionary(snapshots.map { ($0.identityId, $0) }, uniquingKeysWith: { a, b in
            b.revision >= a.revision ? b : a
        })
        // An id an intent names is that intent's only while the key under
        // it is the one the intent submits: one held by another key is that
        // key's.
        let named = Set(intents.flatMap { intent in
            intent.keys.filter { key in
                byIdentity[intent.identityId].map { presence(of: key, in: $0) != .conflicting } ?? true
            }.map { IdentityKey(intent.identityId, $0.id) }
        })

        // The contracts each app's intents bind keys to.
        var contractsOfApp: [Data: Set<Data>] = [:]
        for intent in intents {
            contractsOfApp[intent.appId, default: [intent.appId]]
                .formUnion(intent.authKeys.compactMap(\.bound).filter { !isProfileBound($0) }.map(contractId(of:)))
        }

        var unrecorded: [Data: [Data: [UInt32]]] = [:]
        var profile: [Data: [UInt32]] = [:]
        var unplaced: [Data: [UInt32]] = [:]
        for snapshot in snapshots {
            for key in snapshot.keys where isAppConnectAuthKey(key)
                && !named.contains(IdentityKey(snapshot.identityId, key.id)) && !protected.contains(key.data) {
                guard let bound = key.bound else {
                    // The store does not hold the key's bound yet: whose it
                    // is cannot be told, and it is reported as such.
                    if !key.boundKnown { unplaced[snapshot.identityId, default: []].append(key.id) }
                    continue
                }
                if isProfileBound(bound) {
                    profile[snapshot.identityId, default: []].append(key.id)
                    continue
                }
                // A key bound to a system contract is no app's; one bound to
                // a contract the intents of several apps bind cannot be
                // told to be any one of theirs. Neither is shown or offered.
                let contract = contractId(of: bound)
                guard !systemContractIds.contains(contract.toBase58String()) else { continue }
                let apps = contractsOfApp.filter { $0.value.contains(contract) }.map(\.key)
                guard apps.count <= 1 else { continue }
                let app = apps.first ?? contract
                unrecorded[app, default: [:]][snapshot.identityId, default: []].append(key.id)
            }
        }

        let apps = Set(intents.map(\.appId)).union(unrecorded.keys)
        let connections: [ProjectedConnection] = apps.compactMap { app in
            let own = intents.filter { $0.appId == app }.sorted { $0.createdAt > $1.createdAt }
            var statuses = own.compactMap { intent in byIdentity[intent.identityId].map { status(of: intent, in: $0) } }
            let others = unrecorded[app] ?? [:]
            if !others.isEmpty { statuses.append(.active(expiresAt: nil)) }
            // An app this read says nothing about (its intents are on
            // identities not read) has no connection here.
            guard let best = statuses.min(by: { rank($0) < rank($1) }) else { return nil }
            return ProjectedConnection(appId: app, status: best, intents: own, unrecordedKeyIds: others)
        }
        return Projection(
            connections: connections.sorted { $0.appId.lexicographicallyPrecedes($1.appId) },
            unrecordedProfileKeyIds: profile,
            unplacedKeyIds: unplaced)
    }

    private struct IdentityKey: Hashable {
        let identityId: Data
        let keyId: UInt32
        init(_ identityId: Data, _ keyId: UInt32) {
            self.identityId = identityId
            self.keyId = keyId
        }
    }

    // MARK: Plans

    /// The ids for `count` new keys that no key on the identity and no
    /// intent on it holds, so a key that may still land is never given to
    /// another: above the highest while they fit, then the lowest free ones
    /// (a `dash-st:` registration picks its own ids). Nil when the ids run
    /// out.
    static func newKeyIds(count: Int, snapshot: IdentitySnapshot, intents: [ConnectionIntent]) -> [UInt32]? {
        let taken = Set(snapshot.keys.map(\.id)
            + intents.filter { $0.identityId == snapshot.identityId }.flatMap { $0.keys.map(\.id) })
        let first = taken.max().map { UInt64($0) + 1 } ?? 0
        if first + UInt64(count) <= UInt64(UInt32.max) + 1 {
            return (0 ..< count).map { UInt32(first + UInt64($0)) }
        }
        var ids: [UInt32] = []
        var id: UInt32 = 0
        // The identity holds far fewer keys than there are ids.
        while ids.count < count {
            if !taken.contains(id) { ids.append(id) }
            guard ids.count < count else { break }
            guard id < .max else { return nil }
            id += 1
        }
        return ids
    }

    /// Whether a retry of a request may carry on with its intent: its keys
    /// are live or may still land, and the user has not disconnected it.
    static func mayResume(_ intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> Bool {
        guard intent.closedAt == nil else { return false }
        switch status(of: intent, in: snapshot) {
        case .active, .confirming: return true
        case .expired, .disconnected, .neverLanded: return false
        }
    }

    /// Whether the app's intents gave it a DashPay profile key. Only then are
    /// the profile keys no intent names offered with its disconnect.
    static func usesProfileAccess(_ intents: [ConnectionIntent], appId: Data) -> Bool {
        intents.contains { $0.appId == appId && $0.authKeys.contains { $0.bound.map(isProfileBound) ?? false } }
    }

    /// What a disconnect of one app submits on one identity.
    struct DisconnectPlan: Equatable {
        /// The app's auth keys still enabled: live or expired. Platform still
        /// lets an authorized limits update revive an expired one.
        var disable: [UInt32] = []
        /// One missing auth key id per intent whose update may still land. A
        /// key of the wallet's own under that id means the update never can.
        var fence: [UInt32] = []
        /// Intents whose response may be on Platform.
        var deleteResponses: [UUID] = []

        var isEmpty: Bool { disable.isEmpty && fence.isEmpty && deleteResponses.isEmpty }
    }

    /// `includeUnrecorded`: also turn off the app's live keys no intent
    /// names; the user confirms that separately.
    static func disconnectPlan(
        appId: Data, snapshot: IdentitySnapshot, intents: [ConnectionIntent], includeUnrecorded: Bool,
        protected: Set<Data> = []
    ) -> DisconnectPlan {
        var plan = DisconnectPlan()
        let own = intents.filter { $0.appId == appId && $0.identityId == snapshot.identityId }
        for intent in own {
            let auth = intent.authKeys.map { ($0, presence(of: $0, in: snapshot)) }
            plan.disable += auth.filter { [.live, .expired].contains($0.1) }.map(\.0.id)
            if status(of: intent, in: snapshot) != .neverLanded,
               let missing = auth.first(where: { $0.1 == .missing })?.0.id {
                plan.fence.append(missing)
            }
            if !intent.responseRemoved { plan.deleteResponses.append(intent.id) }
        }
        if includeUnrecorded {
            let projection = project([snapshot], intents: intents, protected: protected)
            let others = projection.connections.first { $0.appId == appId }?.unrecordedKeyIds[snapshot.identityId] ?? []
            plan.disable += others
        }
        plan.disable = Array(Set(plan.disable)).sorted()
        plan.fence = Array(Set(plan.fence)).sorted()
        return plan
    }

    // MARK: Submitting

    /// The most keys one identity update may add (Platform consensus).
    static let maxKeysAddedPerUpdate = 6

    /// The key `intended` is submitted as.
    static func identityPubkey(of intended: IntendedKey) -> ManagedPlatformWallet.IdentityPubkey {
        ManagedPlatformWallet.IdentityPubkey(
            keyId: intended.id,
            keyType: intended.keyType,
            purpose: intended.purpose,
            securityLevel: intended.securityLevel,
            pubkeyBytes: intended.data,
            readOnly: intended.readOnly,
            contractBounds: intended.bound.map(contractBounds(of:)),
            totalBudget: intended.totalBudget,
            expiresAt: intended.expiresAt)
    }

    static func contractBounds(of bound: StoredBound) -> ManagedPlatformWallet.ContractBounds {
        switch bound {
        case .singleContract(let id): return .singleContract(id: id)
        case .documentType(let id, let name): return .singleContractDocumentType(id: id, documentTypeName: name)
        case .contractGroup(let id): return .contractGroup(id: id)
        }
    }

    /// Whether a retry of a request may submit `intent` again under what
    /// the user approved now: the same keys, each with the level, bound and
    /// budget the plan grants, and an expiry no later than the plan's.
    static func isWithinPlan(_ intent: ConnectionIntent, _ plan: GrantPlan) -> Bool {
        let auth = intent.authKeys
        guard intent.appId == plan.appId, auth.count == plan.auth.count else { return false }
        return zip(auth, plan.auth).allSatisfy { key, grant in
            key.securityLevel == grant.securityLevel && key.bound == grant.storedBound
                && key.totalBudget == grant.totalBudget
                && (key.expiresAt ?? .max) <= grant.expiresAt
        }
    }

    // MARK: Fence

    /// The leaf a fence key is derived at: one per identity and key id, so
    /// the same fence is built on every try.
    static func fenceKeyLeaf(identityId: Data, keyId: UInt32) -> Data {
        var input = Data("dashconnect-fence".utf8) + identityId
        withUnsafeBytes(of: keyId.bigEndian) { input.append(contentsOf: $0) }
        return Data(SHA256.hash(data: Data(SHA256.hash(data: input))))
    }

    /// A key of the wallet's own under `keyId`, which an intent may still
    /// land on. Platform refuses an update that adds an id the identity
    /// holds, so once this key is there that intent's update never lands.
    /// It can spend one credit and has no expiry: an expiry would have to be
    /// ahead of Platform's block time, which the wallet does not read.
    static func fenceKey(keyId: UInt32, publicKeyHash160: Data) -> ManagedPlatformWallet.IdentityPubkey {
        ManagedPlatformWallet.IdentityPubkey(
            keyId: keyId,
            keyType: .ecdsaHash160,
            purpose: .authentication,
            securityLevel: .high,
            pubkeyBytes: publicKeyHash160,
            readOnly: false,
            contractBounds: nil,
            totalBudget: 1,
            expiresAt: nil)
    }
}
