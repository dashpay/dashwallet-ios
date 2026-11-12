import CryptoKit
import Foundation
import SwiftDashSDK

/// App Connect as one projection. The wallet stores only what Platform cannot
/// tell it: the intents, which name the keys an approval submits. Every
/// connection, its status and its expiry are computed from one read of the
/// identity and those intents; nothing computed is stored.
///
/// Platform takes an identity update whole or not at all, and refuses one
/// that adds a key id the identity already holds. So an intent's update
/// either lands as submitted, or one of its ids is held by another key and it
/// can never land. Keys of the intent can still show next to such a conflict
/// (another device submitted the same keys with a different one): those are
/// access the app has. Nothing else settles an intent: a key that is absent
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
        /// The response, sealed before the submit, so a disconnect deletes it
        /// by its values.
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
        /// It may sit next to an id another key holds.
        case active(expiresAt: UInt64?)
        /// No auth key is there yet and none is taken: the update may land.
        case confirming
        /// No auth key is live, some are expired but still enabled, and none
        /// may still land.
        case expired
        /// Every auth key is off.
        case disconnected
        /// Another key holds one of its ids and none of its auth keys is
        /// enabled: the update never landed and never will.
        case neverLanded
    }

    static func status(of intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> IntentStatus {
        // A live key of the intent is access the app has, whatever else of
        // the update shows.
        let auth = intent.authKeys.map { ($0, presence(of: $0, in: snapshot)) }
        let live = auth.filter { $0.1 == .live }
        if !live.isEmpty {
            let expiries = live.compactMap { key, _ in
                snapshot.keys.first { $0.id == key.id }?.expiresAt
            }
            return .active(expiresAt: expiries.min())
        }
        // One key of the update held by another, encryption keys included,
        // and the rest of it never lands. An expired key that is still
        // enabled can be revived by an authorized limits update, so it is
        // access the app has.
        if hasConflict(intent, in: snapshot) {
            return auth.contains(where: { $0.1 == .expired }) ? .expired : .neverLanded
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
        /// The app's live access comes only from approvals whose response
        /// was never published: it holds keys it never got.
        var isUndelivered = false

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

    private static let dashPayContractIdData = Data.identifier(fromBase58: dashPayContractId)

    static func isProfileBound(_ bound: StoredBound) -> Bool {
        guard case .documentType(let contractId, let name) = bound else { return false }
        return contractId.toBase58String() == dashPayContractId && name == "profile"
    }

    /// Every connection the wallet can show for these identities. An app
    /// with no intent appears when one of its contracts carries a live auth
    /// key no intent names.
    static func project(_ snapshots: [IdentitySnapshot], intents: [ConnectionIntent], owners: [Data: Data] = [:]) -> Projection {
        let byIdentity = Dictionary(snapshots.map { ($0.identityId, $0) }, uniquingKeysWith: { a, b in
            b.revision >= a.revision ? b : a
        })
        let placing = UnrecordedPlacing(snapshots: Array(byIdentity.values), intents: intents)

        var unrecorded: [Data: [Data: [UInt32]]] = [:]
        var profile: [Data: [UInt32]] = [:]
        var unplaced: [Data: [UInt32]] = [:]
        for snapshot in snapshots {
            for key in snapshot.keys {
                switch placing.placement(of: key, on: snapshot.identityId) {
                case nil, .system:
                    continue
                case .unplaced:
                    unplaced[snapshot.identityId, default: []].append(key.id)
                case .profile:
                    profile[snapshot.identityId, default: []].append(key.id)
                    if let dashPay = dashPayContractIdData {
                        unrecorded[dashPay, default: [:]][snapshot.identityId, default: []].append(key.id)
                    }
                case .apps(let apps):
                    for app in apps {
                        unrecorded[app, default: [:]][snapshot.identityId, default: []].append(key.id)
                    }
                case .noApp(let contract):
                    // It joins an app here only when attributed to it by
                    // owner; otherwise it stands on its own contract's row.
                    let apps = placing.apps(on: snapshot.identityId)
                    let attributed = apps.filter { ownerOutcome(of: contract, for: $0, among: apps, owners: owners) == .attributed }
                    let row = (attributed.count == 1 ? attributed.first : nil) ?? contract
                    unrecorded[row, default: [:]][snapshot.identityId, default: []].append(key.id)
                }
            }
        }

        let apps = Set(intents.map(\.appId)).union(unrecorded.keys)
        let connections: [ProjectedConnection] = apps.compactMap { app in
            let own = intents.filter { $0.appId == app }.sorted { $0.createdAt > $1.createdAt }
            let ownStatuses = own.compactMap { intent in byIdentity[intent.identityId].map { (intent, status(of: intent, in: $0)) } }
            var statuses = ownStatuses.map(\.1)
            let others = unrecorded[app] ?? [:]
            if !others.isEmpty { statuses.append(.active(expiresAt: nil)) }
            // An app this read says nothing about (its intents are on
            // identities not read) has no connection here.
            guard let best = statuses.min(by: { rank($0) < rank($1) }) else { return nil }
            let delivering = ownStatuses.compactMap { intent, status -> ConnectionIntent? in
                guard case .active = status else { return nil }
                return intent
            }
            let isUndelivered = others.isEmpty && !delivering.isEmpty && delivering.allSatisfy { $0.responseDocumentId == nil }
            return ProjectedConnection(
                appId: app, status: best, intents: own, unrecordedKeyIds: others, isUndelivered: isUndelivered)
        }
        return Projection(
            connections: connections.sorted { $0.appId.lexicographicallyPrecedes($1.appId) },
            unrecordedProfileKeyIds: profile,
            unplacedKeyIds: unplaced)
    }

    /// The ids whose owner the projection needs for `snapshot`: the contract
    /// of every app with an intent on its identity, and the bound (contract,
    /// or contract group) of every unrecorded key no intent names by
    /// contract. Empty when there is no such key, or no app has an intent on
    /// the identity: then no owner decides anything.
    static func ownerIdsNeeded(snapshot: IdentitySnapshot, intents: [ConnectionIntent]) -> Set<Data> {
        let placing = UnrecordedPlacing(snapshots: [snapshot], intents: intents)
        let apps = placing.apps(on: snapshot.identityId)
        guard !apps.isEmpty else { return [] }
        let bounds = snapshot.keys.compactMap { key -> Data? in
            guard case .noApp(let contract) = placing.placement(of: key, on: snapshot.identityId) else { return nil }
            return contract
        }
        guard !bounds.isEmpty else { return [] }
        return Set(bounds).union(apps)
    }

    /// How an unrecorded key bound to a contract no intent names stands
    /// against one app, by owner.
    enum OwnerOutcome: Equatable {
        /// The bound's known owner is the app's, and no other app here has
        /// that owner or an unknown one.
        case attributed
        /// The bound's known owner is the app's, and another app here has it
        /// too, or the bound is a contract group with admins, who may add
        /// their own contracts to it: whose the key is cannot be told.
        case notAttributable
        /// It may be the app's, but an owner that decides it is unknown.
        case notChecked
        /// It is not the app's: a known other owner, or the system's.
        case notThisApp
    }

    /// The owner rule, the only place it lives. `apps` are the apps with an
    /// intent on the identity, `app` among them; `owners` holds the owners
    /// read, and an id it lacks has an unknown owner, which is never a match
    /// or a mismatch.
    static func ownerOutcome(
        of bound: Data, for app: Data, among apps: Set<Data>, owners: [Data: Data]
    ) -> OwnerOutcome {
        let boundOwner = owners[bound]
        if boundOwner == systemContractOwnerId { return .notThisApp }
        if boundOwner == administeredGroupOwnerId { return .notAttributable }
        guard let boundOwner, let appOwner = owners[app] else { return .notChecked }
        guard boundOwner == appOwner else { return .notThisApp }
        let others = apps.subtracting([app]).map { owners[$0] }
        if others.contains(appOwner) { return .notAttributable }
        return others.contains(nil) ? .notChecked : .attributed
    }

    /// Where an unrecorded key goes, before any owner is asked.
    private enum UnrecordedPlacement: Equatable {
        /// The store does not hold the key's bound yet: whose it is cannot be
        /// told, and it is reported as such.
        case unplaced
        /// Bound to the DashPay profile. No app can be told to hold it. It is
        /// offered with any app's disconnect, and stands as a connection of
        /// its own, so it can be turned off whatever other rows there are.
        case profile
        /// Bound to a system contract: no app's.
        case system
        /// Bound to a contract the intents of these apps bind (on this
        /// identity first). With several, it cannot be told to be any one
        /// of theirs: each of them shows it, and a disconnect of any of them
        /// turns it off with the user's confirm.
        case apps([Data])
        /// Bound to a contract no intent binds; `contract` is the bound's
        /// contract, or contract group.
        case noApp(contract: Data)
    }

    /// Which keys intents name, and the contracts their apps bind, for one
    /// set of reads.
    private struct UnrecordedPlacing {
        private let named: Set<IdentityKey>
        /// The contracts each app's intents on each identity bind keys to.
        private let contractsOfApp: [Data: [Data: Set<Data>]]

        init(snapshots: [IdentitySnapshot], intents: [ConnectionIntent]) {
            let byIdentity = Dictionary(snapshots.map { ($0.identityId, $0) }, uniquingKeysWith: { a, _ in a })
            // An id an intent names is that intent's only while the key
            // under it is the one the intent submits: one held by another
            // key is that key's.
            named = Set(intents.flatMap { intent in
                intent.keys.filter { key in
                    byIdentity[intent.identityId].map { presence(of: key, in: $0) != .conflicting } ?? true
                }.map { IdentityKey(intent.identityId, $0.id) }
            })
            var contractsOfApp: [Data: [Data: Set<Data>]] = [:]
            for intent in intents {
                contractsOfApp[intent.identityId, default: [:]][intent.appId, default: [intent.appId]]
                    .formUnion(intent.authKeys.compactMap(\.bound).filter { !isProfileBound($0) }.map(contractId(of:)))
            }
            self.contractsOfApp = contractsOfApp
        }

        /// The apps with an intent on `identityId`.
        func apps(on identityId: Data) -> Set<Data> { Set(contractsOfApp[identityId].map { Array($0.keys) } ?? []) }

        /// Nil for a key that is not an unrecorded App Connect key.
        func placement(of key: PlatformKey, on identityId: Data) -> UnrecordedPlacement? {
            guard isAppConnectAuthKey(key), !named.contains(IdentityKey(identityId, key.id)) else { return nil }
            guard let bound = key.bound else { return key.boundKnown ? nil : .unplaced }
            if isProfileBound(bound) { return .profile }
            let contract = contractId(of: bound)
            guard !systemContractIds.contains(contract.toBase58String()) else { return .system }
            func binding(_ contracts: [Data: Set<Data>]) -> [Data] { contracts.filter { $0.value.contains(contract) }.map(\.key) }
            var apps = binding(contractsOfApp[identityId] ?? [:])
            if apps.isEmpty { apps = Array(Set(contractsOfApp.values.flatMap(binding))) }
            return apps.isEmpty ? .noApp(contract: contract) : .apps(apps)
        }
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
    /// another: above the highest while they fit, then the lowest free ones.
    /// Nil when the ids run out.
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

    /// The keys `intent` turns off that are still on.
    static func outstandingDisables(of intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> [UInt32] {
        intent.disables.filter { id in snapshot.keys.contains { $0.id == id && $0.disabledAt == nil } }
    }

    /// Whether `snapshot` shows all of `intent`: every key it adds, and every
    /// key it turns off off. Another update may have added the same keys
    /// without turning the earlier ones off (the same request approved on
    /// another device), so the added keys alone do not tell.
    static func hasLanded(_ intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> Bool {
        intent.keys.allSatisfy { key in
            [.live, .expired, .disabled].contains(presence(of: key, in: snapshot))
                // A key whose bound the store does not hold yet may be bound
                // elsewhere: it is not taken as this update's, so its secret
                // is not handed over.
                && snapshot.keys.first { $0.id == key.id }?.boundKnown == true
        } && outstandingDisables(of: intent, in: snapshot).isEmpty
    }

    /// Whether the encryption keys `intent`'s response carries can still be
    /// used: those it re-sends are live, and those it adds are not off.
    static func encryptionKeysUsable(_ intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> Bool {
        intent.sentEncryptionKeyIds.allSatisfy { id in
            snapshot.keys.contains { $0.id == id && isLive($0, at: snapshot.platformTime) }
        } && intent.keys.allSatisfy { $0.isAuthentication || presence(of: $0, in: snapshot) != .disabled }
    }

    /// Whether every auth key `intent`'s response carries can still sign:
    /// none is off or expired. One that is not there yet may still land.
    static func authKeysUsable(_ intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> Bool {
        intent.authKeys.allSatisfy { ![.disabled, .expired].contains(presence(of: $0, in: snapshot)) }
    }

    /// A key Platform must name current for the app for a response to hold.
    struct ExpectedCurrentKey: Equatable {
        let id: UInt32
        let data: Data
        /// A key the intent registers that the read does not show: none may
        /// be current yet, or this one already (the read may be behind).
        let mayBeNone: Bool
    }

    /// What Platform's current encryption key for the app must be, by
    /// purpose, for `intent`'s response to hold: each key it re-sends or
    /// added that `snapshot` shows live, and for a key it registers that
    /// `snapshot` does not show, that key or none.
    static func expectedCurrentEncryptionKeys(of intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> [KeyPurpose: [ExpectedCurrentKey]] {
        var keys: [KeyPurpose: [ExpectedCurrentKey]] = [:]
        for key in intent.keys where !key.isAuthentication {
            switch presence(of: key, in: snapshot) {
            case .live: keys[key.purpose, default: []].append(ExpectedCurrentKey(id: key.id, data: key.data, mayBeNone: false))
            case .missing: keys[key.purpose, default: []].append(ExpectedCurrentKey(id: key.id, data: key.data, mayBeNone: true))
            case .conflicting, .expired, .disabled: continue
            }
        }
        for id in intent.sentEncryptionKeyIds {
            guard let key = snapshot.keys.first(where: { $0.id == id }), isLive(key, at: snapshot.platformTime) else { continue }
            keys[key.purpose, default: []].append(ExpectedCurrentKey(id: id, data: key.data, mayBeNone: false))
        }
        return keys
    }

    /// How Platform's current key, `current`, stands against `expected`.
    enum CurrentKeyCheck: Equatable {
        /// That very key, enabled, or none at all where none may be.
        case matches
        /// None current yet for a key the identity already shows: the
        /// node that answered may be behind.
        case notYet
        /// Another key is current, or this one is off: no later read that
        /// says otherwise can be trusted over it, as that one may be behind.
        case differs
    }

    static func check(_ current: CurrentContractKey?, against expected: ExpectedCurrentKey) -> CurrentKeyCheck {
        guard let current else { return expected.mayBeNone ? .matches : .notYet }
        let isIt = !current.isDisabled && current.keyId == expected.id && current.data == expected.data
        return isIt ? .matches : .differs
    }

    /// Whether another key holds an id one of the intent's keys was to take:
    /// then the intent's update never lands as a whole.
    static func hasConflict(_ intent: ConnectionIntent, in snapshot: IdentitySnapshot) -> Bool {
        intent.keys.contains { presence(of: $0, in: snapshot) == .conflicting }
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
        /// The live keys no intent names on the app's row, or, for an app
        /// with no intent on the identity, every one placed on its contract:
        /// those a disconnect asks the user to turn off with it.
        var offeredUnrecorded: [UInt32] = []
        /// Keys that may be the app's whose owner, or the app's or another
        /// app's owner, is unknown, and keys whose bound the store does not
        /// hold: they stay on, and no access left cannot be claimed.
        var notChecked: [UInt32] = []
        /// Keys of the app's owner that another app here has too: they stay
        /// on, since they may be the other app's.
        var notAttributable: [UInt32] = []
        /// Offered keys the user's question did not list: they stay on for a
        /// later disconnect.
        var leftAfterQuestion: [UInt32] = []

        var isEmpty: Bool { disable.isEmpty && fence.isEmpty && deleteResponses.isEmpty }
    }

    /// The intents on `identityId` that are closed but whose response may
    /// still be on Platform: its delete failed, and with the row gone no
    /// disconnect of the app reaches it again. The next signed operation on
    /// the identity deletes it.
    static func responsesLeft(identityId: Data, intents: [ConnectionIntent]) -> [UUID] {
        intents.filter { $0.identityId == identityId && $0.closedAt != nil && !$0.responseRemoved }.map(\.id)
    }

    /// The order a disconnect disables keys in: the other keys first (the
    /// DashPay profile keys no intent names, a fence left on), then the
    /// app's own keys. Platform takes `maxKeysDisabledPerUpdate` keys per
    /// update, and an update that fails leaves the later ones live. With the
    /// app's keys last, a failure part way never leaves all of them off while
    /// another key is still live, so the app's row stays and its retry
    /// reaches the keys left (ADR-0031).
    static func disableOrder(appKeyIds: [UInt32], otherKeyIds: [UInt32]) -> [UInt32] {
        let app = Set(appKeyIds)
        return Set(otherKeyIds).subtracting(app).sorted() + app.sorted()
    }

    /// `owners`: the owners read, an absent id unknown. `listedUnrecordedKeyIds`:
    /// the unrecorded keys the user's question listed and confirmed, nil
    /// before the question. Of those, only the ones still offered
    /// (`DisconnectPlan.offeredUnrecorded`) are turned off: never a key the
    /// question did not count.
    static func disconnectPlan(
        appId: Data, snapshot: IdentitySnapshot, intents: [ConnectionIntent], owners: [Data: Data],
        listedUnrecordedKeyIds: Set<UInt32>?
    ) -> DisconnectPlan {
        var plan = DisconnectPlan()
        let own = intents.filter { $0.appId == appId && $0.identityId == snapshot.identityId }
        for intent in own {
            let auth = intent.authKeys.map { ($0, presence(of: $0, in: snapshot)) }
            plan.disable += auth.filter { [.live, .expired].contains($0.1) }.map(\.0.id)
            if !hasConflict(intent, in: snapshot), let missing = auth.first(where: { $0.1 == .missing })?.0.id {
                plan.fence.append(missing)
            }
            if !intent.responseRemoved { plan.deleteResponses.append(intent.id) }
        }
        let placing = UnrecordedPlacing(snapshots: [snapshot], intents: intents)
        let apps = placing.apps(on: snapshot.identityId)
        var offered = Set(project([snapshot], intents: intents, owners: owners).connections
            .first { $0.appId == appId }?.unrecordedKeyIds[snapshot.identityId] ?? [])
        if !apps.contains(appId) {
            // A row with no intent here is the contract the user named: its
            // keys stay its own even when an owner read since attributes
            // them to an app here.
            offered.formUnion(snapshot.keys.filter {
                placing.placement(of: $0, on: snapshot.identityId) == .noApp(contract: appId)
            }.map(\.id))
        }
        plan.offeredUnrecorded = offered.sorted()
        if let listed = listedUnrecordedKeyIds {
            plan.disable += offered.intersection(listed)
            plan.leftAfterQuestion = offered.subtracting(listed).sorted()
        }
        // The keys that may be the app's but stay on, by the same owner rule
        // that places them on rows.
        for key in snapshot.keys {
            switch placing.placement(of: key, on: snapshot.identityId) {
            case .unplaced:
                plan.notChecked.append(key.id)
            case .noApp(let contract) where apps.contains(appId):
                switch ownerOutcome(of: contract, for: appId, among: apps, owners: owners) {
                case .notChecked: plan.notChecked.append(key.id)
                case .notAttributable: plan.notAttributable.append(key.id)
                case .attributed, .notThisApp: break
                }
            default:
                break
            }
        }
        plan.notChecked.sort()
        plan.notAttributable.sort()
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

    /// Whether the auth keys of `intent` that are on the identity hold no more
    /// than `plan` grants now: an authorized limits update may have raised
    /// a key's budget or lifetime after it landed. No budget means no cap.
    static func landedKeysWithinPlan(_ intent: ConnectionIntent, _ plan: GrantPlan, in snapshot: IdentitySnapshot) -> Bool {
        intent.authKeys.count == plan.auth.count && zip(intent.authKeys, plan.auth).allSatisfy { intended, grant in
            guard let key = snapshot.keys.first(where: { isSameKey($0, as: intended) }) else { return true }
            let budgetWithin = grant.totalBudget.map { cap in key.totalBudget.map { $0 <= cap } ?? false } ?? true
            return budgetWithin && (key.expiresAt ?? .max) <= grant.expiresAt
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
