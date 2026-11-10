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
        /// When the intent was done with: the user disconnected the app, a
        /// later approval on the same connection replaced it, or an approval
        /// placed its supersession fence, after which every open intent of the
        /// identity that reads Never landed is closed.
        var closedAt: Date?
        /// The contract groups among the auth keys' bounds that had
        /// administrators besides their owner when the sheet was shown
        /// (`GrantPlan.administeredGroupIds`). Absent on an intent from a
        /// build that did not note it.
        var administeredGroupIds: [Data]? = nil
        /// Platform's permanent refusal of the identity update, when the
        /// wallet has learned of one.
        var refusal: ConsensusRefusal?
        /// When Remove hid this intent's row. Absent on a row written before
        /// the field existed.
        var removedAt: Date?
        /// When the user's Disconnect last closed this intent, or left it
        /// open as the app's newest because a key's bound was unknown, or
        /// left it live while a stopped run sent one of its keys in an update
        /// reported done or of unknown outcome, or while a run that was not
        /// stopped left its fence on. Any other intent left live is not
        /// marked, nor is one that read Never landed before the disconnect
        /// ran because a key other than the wallet's own fence, on or off,
        /// held one of its ids. Absent on an intent written before the field
        /// existed.
        var disconnectedAt: Date?

        var authKeys: [IntendedKey] { keys.filter(\.isAuthentication) }

        /// Whether the sheet said `bound`'s group has other administrators;
        /// `false` when it is not a group or the intent did not note it.
        func isAdministered(_ bound: StoredBound) -> Bool {
            guard case .contractGroup(let id) = bound else { return false }
            return administeredGroupIds?.contains(id) == true
        }
    }

    /// The data model's «Refusal» (ADR 0012): the consensus error code with
    /// which Platform refused an identity update for good, and when the wallet
    /// learned of it. Platform's message text is not stored.
    struct ConsensusRefusal: Codable, Equatable {
        let code: UInt32
        let at: Date
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
        /// Platform refused the update for good (the intent carries the
        /// reason) and none of its keys is on the identity.
        case refused
        /// Every auth key is off, or the user closed the intent and the
        /// update that was still to land is fenced.
        case disconnected
        /// Another key holds one of its ids and none of its auth keys is
        /// enabled: the update never landed and never will. An intent a
        /// disconnect ran on is `disconnected` instead; a closed one the
        /// disconnect did not mark still reads as never landed.
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
        // A recorded refusal with none of the intent's keys on the identity.
        if intent.refusal != nil, intent.keys.allSatisfy({ presence(of: $0, in: snapshot) == .missing }) {
            return .refused
        }
        // One key of the update held by another, encryption keys included,
        // and the rest of it never lands. An expired key that is still
        // enabled can be revived by an authorized limits update, so it is
        // access the app has.
        if hasConflict(intent, in: snapshot) {
            if auth.contains(where: { $0.1 == .expired }) { return .expired }
            return intent.disconnectedAt != nil ? .disconnected : .neverLanded
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
        /// The intents of the group the card follows (`followedGroup`), newest
        /// first; empty when only unrecorded keys show the app.
        var followedIntents: [ConnectionIntent] = []

        var id: Data { appId }
    }

    struct Projection: Equatable {
        let connections: [ProjectedConnection]
        /// Live keys bound to the DashPay profile that no intent names, by
        /// identity. They are not any one app's and form no connection.
        let unrecordedProfileKeyIds: [Data: [UInt32]]
        /// Live App Connect keys no intent names whose bound the wallet's
        /// key store does not hold yet, by identity.
        var unplacedKeyIds: [Data: [UInt32]] = [:]
        /// The apps with a connection in any status but Refused: a kept
        /// intent whose status is not Refused, or a live key no intent names.
        var appsWithConnectionOtherThanRefused: Set<Data> = []
        /// The app installs (connection ids) of each app that have an intent
        /// in Active, Not delivered, Confirming or Expired: the ones a new
        /// request from the same install replaces.
        var supersedableInstalls: [Data: Set<Data>] = [:]

        /// Whether the wallet has a connection of `appId` in any status other
        /// than Refused, judged per intent: a Refused attempt next to an
        /// earlier Disconnected one does not hide that one.
        func hasConnectionOtherThanRefused(appId: Data) -> Bool {
            appsWithConnectionOtherThanRefused.contains(appId)
        }

        /// Whether a request of `appId` from the install `connectionId`
        /// replaces an existing connection: that install has an intent in
        /// Active, Not delivered, Confirming or Expired. A Disconnected or
        /// Refused one is replaced by nothing, another install of the same
        /// app is never touched (AC-21), and a request without a connection
        /// id names no connection.
        func supersedes(appId: Data, connectionId: Data?) -> Bool {
            guard let connectionId else { return false }
            return supersedableInstalls[appId]?.contains(connectionId) == true
        }
    }

    /// Which of two statuses of intents created at the same moment the card
    /// shows: the one the user can act on first. Live keys come first, then
    /// an update that may still land, an expired one, a refused one, and a
    /// disconnected one.
    private static func rank(_ status: IntentStatus) -> Int {
        switch status {
        case .active: return 0
        case .confirming: return 1
        case .expired: return 2
        case .refused: return 3
        case .disconnected: return 4
        case .neverLanded: return 5
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
    /// key no intent names.
    static func project(_ snapshots: [IdentitySnapshot], intents: [ConnectionIntent]) -> Projection {
        let byIdentity = newestSnapshots(snapshots)
        // An id an intent names is that intent's only while the key under
        // it is the one the intent submits: one held by another key is that
        // key's.
        let named = Set(intents.flatMap { intent in
            intent.keys.filter { key in
                byIdentity[intent.identityId].map { presence(of: key, in: $0) != .conflicting } ?? true
            }.map { IdentityKey(intent.identityId, $0.id) }
        })

        // The contracts each app's intents on each identity bind keys to.
        var contractsOfApp: [Data: [Data: Set<Data>]] = [:]
        for intent in intents {
            contractsOfApp[intent.identityId, default: [:]][intent.appId, default: [intent.appId]]
                .formUnion(intent.authKeys.compactMap(\.bound).filter { !isProfileBound($0) }.map(contractId(of:)))
        }

        var unrecorded: [Data: [Data: [UInt32]]] = [:]
        var profile: [Data: [UInt32]] = [:]
        var unplaced: [Data: [UInt32]] = [:]
        for snapshot in snapshots {
            for key in snapshot.keys where isAppConnectAuthKey(key)
                && !named.contains(IdentityKey(snapshot.identityId, key.id)) {
                guard let bound = key.bound else {
                    // The store does not hold the key's bound yet: whose it
                    // is cannot be told, and it is reported as such.
                    if !key.boundKnown { unplaced[snapshot.identityId, default: []].append(key.id) }
                    continue
                }
                if isProfileBound(bound) {
                    // No app can be told to hold it: it gets no row, and any
                    // app's disconnect turns it off.
                    profile[snapshot.identityId, default: []].append(key.id)
                    continue
                }
                // A key bound to a system contract is no app's. One bound to
                // a contract the intents of several apps bind (on this
                // identity first) cannot be told to be any one of theirs:
                // each of them shows it, and a disconnect of any of them
                // turns it off.
                let contract = contractId(of: bound)
                guard !systemContractIds.contains(contract.toBase58String()) else { continue }
                func binding(_ contracts: [Data: Set<Data>]) -> [Data] { contracts.filter { $0.value.contains(contract) }.map(\.key) }
                var apps = binding(contractsOfApp[snapshot.identityId] ?? [:])
                if apps.isEmpty { apps = Array(Set(contractsOfApp.values.flatMap(binding))) }
                for app in apps.isEmpty ? [contract] : apps {
                    unrecorded[app, default: [:]][snapshot.identityId, default: []].append(key.id)
                }
            }
        }

        // An intent Remove hid yields no row; its keys still count as named
        // above, so a key of it that is live is not reported as unrecorded.
        let kept = intents.filter { $0.removedAt == nil }
        // Profile keys no intent names are turned off by any app's
        // disconnect. On an identity with no connection to disconnect, that
        // would be never: there they stand as a DashPay row of their own.
        if let dashPay = Data.identifier(fromBase58: dashPayContractId) {
            for (identity, ids) in profile {
                let disconnectable = unrecorded.values.contains { $0[identity] != nil }
                    || kept.contains { intent in
                        guard intent.identityId == identity, let snapshot = byIdentity[identity] else { return false }
                        switch status(of: intent, in: snapshot) {
                        case .active, .confirming, .expired: return true
                        case .refused, .disconnected, .neverLanded: return false
                        }
                    }
                if !disconnectable { unrecorded[dashPay, default: [:]][identity] = ids }
            }
        }
        let apps = Set(kept.map(\.appId)).union(unrecorded.keys)
        var hasOtherThanRefused = Set(unrecorded.keys)
        var supersedable: [Data: Set<Data>] = [:]
        let connections: [ProjectedConnection] = apps.compactMap { app in
            let own = kept.filter { $0.appId == app }.sorted { $0.createdAt > $1.createdAt }
            let ownStatuses = own.compactMap { intent in byIdentity[intent.identityId].map { (intent, status(of: intent, in: $0)) } }
            if ownStatuses.contains(where: { $0.1 != .refused }) { hasOtherThanRefused.insert(app) }
            for (intent, status) in ownStatuses {
                guard let install = intent.connectionId else { continue }
                switch status {
                case .active, .confirming, .expired: supersedable[app, default: []].insert(install)
                case .refused, .disconnected, .neverLanded: break
                }
            }
            let others = unrecorded[app] ?? [:]
            let (followed, followedStatus) = followedGroup(of: ownStatuses)
            // Live keys no intent names count as the app's oldest connection:
            // they show when no intent of the app has a status here, or the
            // followed one has no access left (Disconnected, Never landed).
            // They are Active while one of them is live at Platform's time,
            // else Expired: enabled, so still turned off by a disconnect.
            var latest = followedStatus
            if !others.isEmpty, latest == nil || [.disconnected, .neverLanded].contains(latest) {
                let anyLive = others.contains { identity, ids in
                    guard let snapshot = byIdentity[identity] else { return false }
                    return snapshot.keys.contains { ids.contains($0.id) && isLive($0, at: snapshot.platformTime) }
                }
                latest = anyLive ? .active(expiresAt: nil) : .expired
            }
            // An app this read says nothing about (its intents are on
            // identities not read) has no connection here.
            guard let latest else { return nil }
            // Whether the card is waiting on a response is read off the
            // Active intents of the group it follows.
            let delivering = followed.compactMap { intent, status -> ConnectionIntent? in
                guard case .active = status else { return nil }
                return intent
            }
            let isUndelivered = others.isEmpty && !delivering.isEmpty && delivering.allSatisfy { $0.responseDocumentId == nil }
            return ProjectedConnection(
                appId: app, status: latest, intents: own, unrecordedKeyIds: others, isUndelivered: isUndelivered,
                followedIntents: followed.map(\.0))
        }
        return Projection(
            connections: connections.sorted { $0.appId.lexicographicallyPrecedes($1.appId) },
            unrecordedProfileKeyIds: profile,
            unplacedKeyIds: unplaced,
            appsWithConnectionOtherThanRefused: hasOtherThanRefused,
            supersedableInstalls: supersedable)
    }

    /// The card follows the app's latest intent (AC-13), skipping
    /// intents that Never landed (they hold no access, so they do not
    /// hide an older connection) unless every intent of the app Never
    /// landed; intents created together give it to the status the
    /// user can act on first. When that latest group is Disconnected,
    /// the newest older group with an Active, Confirming or Expired
    /// status is followed instead. The group is empty, and its status
    /// nil, when no intent of the app has a status here.
    private static func followedGroup(of ownStatuses: [(ConnectionIntent, IntentStatus)])
        -> (group: [(ConnectionIntent, IntentStatus)], status: IntentStatus?) {
        func newestGroup(_ list: [(ConnectionIntent, IntentStatus)]) -> [(ConnectionIntent, IntentStatus)] {
            let newest = list.first?.0.createdAt
            return list.filter { $0.0.createdAt == newest }
        }
        func decided(_ group: [(ConnectionIntent, IntentStatus)]) -> IntentStatus? {
            group.map(\.1).min { rank($0) < rank($1) }
        }
        let landed = ownStatuses.filter { $0.1 != .neverLanded }
        var followed = newestGroup(landed.isEmpty ? ownStatuses : landed)
        var latest = decided(followed)
        if latest == .disconnected {
            let holding = landed.filter { intent, status in
                guard intent.createdAt < followed[0].0.createdAt else { return false }
                switch status {
                case .active, .confirming, .expired: return true
                case .refused, .disconnected, .neverLanded: return false
                }
            }
            if !holding.isEmpty {
                followed = newestGroup(holding)
                latest = decided(followed)
            }
        }
        return (followed, latest)
    }

    // MARK: Refusal and Remove

    /// `intents` with `refusal` written on the intent `intentId`; the rest
    /// are unchanged, and so is the list when no intent has that id.
    static func recordRefusal(
        _ refusal: ConsensusRefusal,
        on intentId: UUID,
        in intents: [ConnectionIntent]
    ) -> [ConnectionIntent] {
        var recorded = intents
        guard let index = recorded.firstIndex(where: { $0.id == intentId }) else { return intents }
        recorded[index].refusal = refusal
        return recorded
    }

    /// `intents` with `removedAt` set on each intent of `appId` that shows
    /// Refused, which hides the app's Refused row; nil when the projection
    /// does not show the app Refused, so Remove writes nothing for a
    /// connection that holds, or may still get, access.
    static func removing(
        appId: Data,
        intents: [ConnectionIntent],
        snapshots: [IdentitySnapshot],
        at removedAt: Date
    ) -> [ConnectionIntent]? {
        let connection = project(snapshots, intents: intents).connections.first { $0.appId == appId }
        guard connection?.status == .refused else { return nil }
        let byIdentity = newestSnapshots(snapshots)
        var removed = intents
        for index in removed.indices where removed[index].appId == appId && removed[index].removedAt == nil {
            guard let snapshot = byIdentity[removed[index].identityId],
                  status(of: removed[index], in: snapshot) == .refused else { continue }
            removed[index].removedAt = removedAt
        }
        return removed
    }

    /// The newest read of each identity among `snapshots`.
    private static func newestSnapshots(_ snapshots: [IdentitySnapshot]) -> [Data: IdentitySnapshot] {
        Dictionary(snapshots.map { ($0.identityId, $0) }, uniquingKeysWith: { a, b in
            b.revision >= a.revision ? b : a
        })
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

    /// One identity update of a disconnect: the fence keys it adds and the
    /// keys it turns off.
    struct DisconnectUpdate: Equatable {
        /// Ids a fence key of the wallet's own is added under (at most
        /// `maxKeysAddedPerUpdate`).
        var fence: [UInt32] = []
        /// Ids of keys to turn off (at most `maxKeysDisabledPerUpdate`).
        var disable: [UInt32] = []
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

        /// The identity updates that carry the plan, in order: fences and
        /// disables are cut into batches of the sizes Platform takes and
        /// paired index by index.
        var updates: [DisconnectUpdate] {
            func batches(_ ids: [UInt32], _ size: Int) -> [[UInt32]] {
                stride(from: 0, to: ids.count, by: size).map { Array(ids[$0 ..< min($0 + size, ids.count)]) }
            }
            let fences = batches(fence, AppConnect.maxKeysAddedPerUpdate)
            let disables = batches(disable, AppConnect.maxKeysDisabledPerUpdate)
            return (0 ..< max(fences.count, disables.count)).map { index in
                DisconnectUpdate(
                    fence: index < fences.count ? fences[index] : [],
                    disable: index < disables.count ? disables[index] : [])
            }
        }
    }

    /// What `submit` got done.
    struct DisconnectProgress: Equatable {
        /// A send failed: the updates after it were not sent.
        var stopped = false
        /// Keys of the plan whose update was sent.
        var turnedOff: [UInt32] = []
        /// Keys of the plan whose update was not sent.
        var stillLive: [UInt32] = []
        /// Fence key ids of the updates that failed or were not sent: the key
        /// may or may not be on the identity, so the sign-in it fences can
        /// still land.
        var unplacedFences: [UInt32] = []
    }

    /// Sends the plan's updates one by one through `send` and stops at the
    /// first one that fails; it does not throw, the progress says what was
    /// not turned off.
    static func submit(
        _ plan: DisconnectPlan,
        send: (DisconnectUpdate) async throws -> Void
    ) async -> DisconnectProgress {
        var progress = DisconnectProgress()
        for update in plan.updates {
            if progress.stopped {
                progress.stillLive += update.disable
                progress.unplacedFences += update.fence
                continue
            }
            do {
                try await send(update)
                progress.turnedOff += update.disable
            } catch {
                progress.stopped = true
                progress.stillLive += update.disable
                progress.unplacedFences += update.fence
            }
        }
        return progress
    }

    /// What a disconnect of `appId` submits for the intents `intents` alone:
    /// their keys and the fences of those that may still land (not the
    /// refused ones).
    static func recordedDisconnectPlan(
        appId: Data, snapshot: IdentitySnapshot, intents: [ConnectionIntent]
    ) -> DisconnectPlan {
        var plan = DisconnectPlan()
        let own = intents.filter { $0.appId == appId && $0.identityId == snapshot.identityId }
        for intent in own {
            let auth = intent.authKeys.map { ($0, presence(of: $0, in: snapshot)) }
            plan.disable += auth.filter { [.live, .expired].contains($0.1) }.map(\.0.id)
            // A refused update can never land: it needs no fence.
            if intent.refusal == nil, !hasConflict(intent, in: snapshot), let missing = auth.first(where: { $0.1 == .missing })?.0.id {
                plan.fence.append(missing)
            }
            if !intent.responseRemoved { plan.deleteResponses.append(intent.id) }
        }
        plan.disable = Array(Set(plan.disable)).sorted()
        plan.fence = Array(Set(plan.fence)).sorted()
        return plan
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

    /// What a disconnect of `appId` submits on one identity: the keys its
    /// intents name, the live keys bound to its contracts that no intent
    /// names, and every DashPay profile key no intent names. Keys whose
    /// bound the key store does not hold are left (`Projection.unplacedKeyIds`).
    static func disconnectPlan(
        appId: Data, snapshot: IdentitySnapshot, intents: [ConnectionIntent]
    ) -> DisconnectPlan {
        var plan = recordedDisconnectPlan(appId: appId, snapshot: snapshot, intents: intents)
        let projection = project([snapshot], intents: intents)
        let others = projection.connections.first { $0.appId == appId }?.unrecordedKeyIds[snapshot.identityId] ?? []
        let profile = projection.unrecordedProfileKeyIds[snapshot.identityId] ?? []
        plan.disable = disableOrder(appKeyIds: plan.disable + others, otherKeyIds: profile)
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
