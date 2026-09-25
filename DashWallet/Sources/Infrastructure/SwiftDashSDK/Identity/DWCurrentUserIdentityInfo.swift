//
//  DWCurrentUserIdentityInfo.swift
//  DashWallet
//
//  App-scoped lookup helper for the current user's SwiftDashSDK-side
//  DashPay identity: DPNS username, DashPay profile (display name,
//  public message, avatar URL), and identity ID.
//
//  Row #17 stage A added the home-screen avatar visibility gate and
//  the read-only `SDKIdentityProfileSheet`. Row #17 proper migrates
//  the ~85 other DashSync-side reads (`DSBlockchainIdentity.currentDashpayUsername`,
//  `.avatarPath`, `.displayName`, `.publicMessage`) to source data from
//  the SDK instead. Centralising the SDK plumbing here keeps the 22
//  modified call-sites free of repeated SwiftData/FFI boilerplate.
//
//  Read model:
//    - Sync, main-thread reads of a cached snapshot (matches the
//      DashSync usage shape the call-sites already assume).
//    - `currentRevision` is bumped whenever
//      `DWDashPayRegistrationStatusUpdatedNotification` or
//      `DWIdentityRegistrationBridge.stateChangedNotification` fires.
//      On the next property read, the snapshot is lazily rebuilt from
//      SwiftData + `ManagedIdentity` lookups. Profile writes through
//      `DWProfileUpdateCoordinator` (Commit 6) call `refreshFromSDK()`
//      to force an immediate invalidation without waiting for the
//      notification round-trip.
//
//  Concurrency: `@MainActor`-isolated singleton; readers must be on
//  the main thread. Every existing read site is either UIKit (main-
//  thread by construction) or a notification handler dispatched on
//  main.
//
//  Scope (Row #17 proper):
//    - Reads from SwiftDashSDK only. No dual-source fallback to a
//      DashSync `DSBlockchainIdentity` — pre-existing DashSync
//      identities are accepted to break in this branch and are
//      retired entirely in Row #25.
//    - Confirmed identity-scoped persistence covers cold name caches. A legacy
//      mirror is recovered only after a live ownership check. Empty caches
//      remain unknown until a scoped network refresh succeeds.
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@objc(DWCurrentUserIdentityInfo)
@MainActor
@objcMembers
public final class DWCurrentUserIdentityInfo: NSObject {

    @objc public static let shared = DWCurrentUserIdentityInfo()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.identity-info")

    /// v1 pins identityIndex to 0 across the coordinator + bridge +
    /// this helper (dashwallet has exactly one DashPay identity per
    /// wallet). Keep aligned with
    /// `DWIdentityRegistrationCoordinator.pinnedIdentityIndex`.
    private static let pinnedIdentityIndex: UInt32 = 0

    // MARK: - Main identity (per-wallet pick)

    /// The SDK deliberately leaves primary-identity selection to the app
    /// layer (`InMemoryWalletSummary.primaryIdentityId` is always nil
    /// Rust-side), so the pick lives here: one UserDefaults slot per
    /// wallet, holding the chosen identity's 32-byte id as hex. `nil` =
    /// no explicit pick; the snapshot then falls back to identity index
    /// 0, then the lowest registered index.
    private static func mainIdentityDefaultsKey(walletId: Data) -> String {
        "DWMainIdentityId." + walletId.map { String(format: "%02x", $0) }.joined()
    }

    /// The stored main-identity pick for `walletId`, or nil.
    static func mainIdentityId(walletId: Data) -> Data? {
        guard let hex = UserDefaults.standard.string(forKey: mainIdentityDefaultsKey(walletId: walletId)),
              hex.count == 64 else { return nil }
        var bytes = Data(capacity: 32)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// Store (or clear, with nil) the main-identity pick for `walletId`.
    /// Storage only — callers drive the refresh/notification cascade so
    /// DashPay surfaces re-key (see `IdentitiesViewModel.setMainIdentity`).
    static func setMainIdentityId(_ identityId: Data?, walletId: Data) {
        let key = mainIdentityDefaultsKey(walletId: walletId)
        if let identityId {
            UserDefaults.standard.set(
                identityId.map { String(format: "%02x", $0) }.joined(),
                forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Displayed username (per-identity pick)

    /// The user's pick in Identities → detail → Usernames. The SDK column
    /// `PersistentIdentity.mainDpnsName` cannot hold it on its own: on every
    /// launch `syncDpnsNames` persists the owned names one at a time, and the
    /// SDK persister resets a pick missing from that partial list to the first
    /// name (fixed SDK-side in dashpay/platform#4978; this copy also covers
    /// picks lost under an SDK without it). So the app keeps its own copy —
    /// one UserDefaults slot per identity, like the main-identity pick above
    /// — and every reader prefers it. Callers still apply their ownership /
    /// pending filters.
    private nonisolated static let mainDpnsNameKeyPrefix = "DWMainDpnsName."

    private static func mainDpnsNameDefaultsKey(identityId: Data) -> String {
        mainDpnsNameKeyPrefix + identityId.map { String(format: "%02x", $0) }.joined()
    }

    /// Store (or clear, with nil) the displayed-username pick for `identityId`.
    static func setMainDpnsName(_ name: String?, identityId: Data) {
        let key = mainDpnsNameDefaultsKey(identityId: identityId)
        if let name = nilIfEmpty(name) {
            UserDefaults.standard.set(name, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The displayed-username pick for `identity`: the app's stored copy,
    /// else the SDK column (picks made before the app kept its own copy),
    /// captured into the copy on first read while it is still owned.
    static func mainDpnsName(for identity: PersistentIdentity) -> String? {
        nilIfEmpty(UserDefaults.standard.string(forKey: mainDpnsNameDefaultsKey(identityId: identity.identityId)))
            ?? captureLegacyMainDpnsName(identity)
            ?? nilIfEmpty(identity.mainDpnsName)
    }

    /// Copy every pick that lives only in the SDK column into the app's
    /// copy. Called when the store opens, before the SDK's first DPNS sync
    /// can rewrite the column, so a pick made before this copy existed
    /// survives the upgrade launch. A column the SDK already rewrote on an
    /// earlier launch cannot be told apart from a real pick; the user
    /// re-picks once.
    static func captureLegacyMainDpnsNames(in container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { $0.mainDpnsName != nil })
        guard let identities = try? context.fetch(descriptor) else { return }
        for identity in identities {
            captureLegacyMainDpnsName(identity)
        }
    }

    /// Capture `identity`'s SDK-column pick into the app's copy when the
    /// copy is empty and the name is not known to have left the identity
    /// (no label rows yet, or an owned row for it). Returns the captured
    /// name.
    @discardableResult
    private static func captureLegacyMainDpnsName(_ identity: PersistentIdentity) -> String? {
        let key = mainDpnsNameDefaultsKey(identityId: identity.identityId)
        guard UserDefaults.standard.string(forKey: key) == nil,
              let legacy = nilIfEmpty(identity.mainDpnsName) else { return nil }
        let rows = identity.dpnsNames
        guard rows.isEmpty || rows.contains(where: {
            $0.isOwned && DWContestedNameStatusService.labelsMatch($0.label, legacy)
        }) else { return nil }
        UserDefaults.standard.set(legacy, forKey: key)
        return legacy
    }

    // MARK: - Snapshot

    /// Cached read of the SDK's current identity info. Rebuilt lazily
    /// on the next property access after `currentRevision` advances.
    struct Snapshot {
        var isLoading = false
        var namesAreLoaded = false
        var balanceCredits: UInt64? = nil
        var pendingContestedName: String? = nil
        var pendingVotingEndTime: Date? = nil
        let identityId: Data?
        let identityIdHex: String?
        let username: String?
        let usernames: [String]
        let displayName: String?
        let avatarURL: String?
        let publicMessage: String?

        var hasIdentity: Bool { identityId != nil }
        var hasKnownZeroBalance: Bool { balanceCredits == 0 }
        var needsUsername: Bool {
            !isLoading && namesAreLoaded && hasIdentity && username == nil && usernames.isEmpty && pendingContestedName == nil
        }

        var registrationRecovery: UsernameRegistrationRecovery {
            guard needsUsername, let identityId else { return .none }
            return .identityNeedsUsername(identityId)
        }

        static let empty = Snapshot(
            identityId: nil,
            identityIdHex: nil,
            username: nil,
            usernames: [],
            displayName: nil,
            avatarURL: nil,
            publicMessage: nil)
    }

    /// One refreshed value for profile content and action eligibility.
    @nonobjc func refreshedSnapshot() -> Snapshot {
        invalidate()
        return snapshot
    }

    static func cachedBalanceCredits(_ credits: UInt64?) -> UInt64? {
        guard let credits, credits > 0 else { return nil }
        return credits
    }

    private let nameReadiness = IdentityNameReadiness()
    private var nameRefreshTasks: [UsernameRegistrationDraftStore.Scope: Task<Void, Never>] = [:]

    private var cachedSnapshot: Snapshot = .empty
    private var cachedRevision: Int = -1
    private var currentRevision: Int = 0
    private var cachedNetwork: Network?

    private override init() {
        super.init()
        let center = NotificationCenter.default
        // `DWDashPayRegistrationStatusUpdatedNotification` is the
        // canonical app-wide registration notification posted by
        // `DWDashPayModel` after the bridge state-change observer
        // rebuilds its registrationStatus. Subscribing here picks up:
        //   - terminal `.completed` (new DPNS name landed)
        //   - terminal `.failed` (reset error message)
        //   - profile edits (Commit 6 posts the same notification to
        //     piggy-back on the existing observer infra)
        center.addObserver(
            self,
            selector: #selector(handleInvalidationNotification(_:)),
            name: Notification.Name("DWDashPayRegistrationStatusUpdatedNotification"),
            object: nil)
        // Bridge-internal notification fires on every phase / asset-
        // lock transition. Useful for picking up the username the
        // moment IdentityCreate writes `PersistentIdentity` to
        // SwiftData, without waiting for the canonical post.
        center.addObserver(
            self,
            selector: #selector(handleInvalidationNotification(_:)),
            name: DWIdentityRegistrationBridge.stateChangedNotification,
            object: nil)
        // A runtime wallet switch rebinds the host to a different wallet whose
        // identity/username is entirely different (or absent). Invalidate so
        // the next read rebuilds the snapshot from the new wallet's
        // `PersistentIdentity` rows instead of serving the old wallet's cache.
        center.addObserver(
            self,
            selector: #selector(handleInvalidationNotification(_:)),
            name: SwiftDashSDKWalletState.activeWalletDidChangeNotification,
            object: nil)
        // A network switch rebinds the host to the destination network's
        // container, whose identity set is entirely different (or empty) —
        // the walletId can be identical across networks (same seed), so the
        // active-wallet notification alone doesn't cover it. Without this
        // the testnet identity kept rendering on mainnet.
        center.addObserver(
            self,
            selector: #selector(handleInvalidationNotification(_:)),
            name: NSNotification.Name.DWCurrentNetworkDidChange,
            object: nil)
    }

    // MARK: - Obj-C / Swift read API

    /// `YES` when the SDK has a `PersistentIdentity` row for the
    /// current wallet at `pinnedIdentityIndex`. Mirrors the
    /// `DWDashPayProtocol.hasIdentity` semantics from Row #17 stage A.
    @objc public var hasIdentity: Bool {
        snapshot.identityId != nil
    }

    /// True only after the SDK host has rebound to the network currently
    /// selected by the app. During a network switch the persisted selection
    /// changes before the old host is stopped, so destination UI must not
    /// consume that old host's identity.
    @objc public var isCurrentNetworkContextReady: Bool {
        guard let selectedNetwork = WalletEnvironment.network else {
            return false
        }
        let host = SwiftDashSDKHost.shared
        return host.runningNetwork == selectedNetwork
            && host.wallet != nil
            && host.modelContainer != nil
    }

    /// First confirmed DPNS label associated with the selected identity.
    /// A locally entered registration draft is not proof of ownership.
    @objc public var username: String? {
        snapshot.username
    }

    /// All DPNS labels the identity owns — `ManagedIdentity.getDpnsNames()`,
    /// or the persisted SwiftData name sources when that cache yields
    /// nothing — with the pending-contested labels filtered out same as
    /// `username`. Unlike `username` this never falls back to
    /// `DWGlobalOptions.dashpayUsername`, so it stays empty while a
    /// registration is still in flight. Empty when no identity is
    /// registered or no source carries a confirmed name yet.
    @objc public var usernames: [String] {
        snapshot.usernames
    }

    /// `dashpay.profile.displayName`. Nil when the profile document
    /// doesn't exist or the field is empty.
    @objc public var displayName: String? {
        snapshot.displayName
    }

    /// `dashpay.profile.avatarUrl`. Nil when the profile document
    /// doesn't exist or the URL is empty. Use
    /// `UIImageView+DWDPAvatar` for the actual image load — the URL
    /// shape (DIP-15 + percent-encoded query) is unchanged from the
    /// DashSync path; only the source flips.
    @objc public var avatarURL: String? {
        snapshot.avatarURL
    }

    /// `dashpay.profile.publicMessage` (biography / about-me).
    @objc public var publicMessage: String? {
        snapshot.publicMessage
    }

    /// 32-byte identity ID rendered as lowercase hex (64 chars), or
    /// nil when no identity is registered. Mirrors the format used
    /// by `SDKIdentityProfileSheet` and the coordinator logs.
    @objc public var identityIdHex: String? {
        snapshot.identityIdHex
    }

    /// Raw 32-byte identity ID, or nil when no identity is registered.
    /// Swift-only (SDK APIs take `Identifier` = `Data`); Obj-C callers
    /// use `identityIdHex`. Added for the contacts service (Row #18),
    /// which passes it as `ownerIdentityId` into the SwiftData
    /// predicates and `ManagedPlatformWallet` contact calls.
    public var identityId: Data? {
        snapshot.identityId
    }

    /// Display title preferring `displayName`, falling back to
    /// `username`. Nil only when no identity exists at all.
    @objc public var displayTitle: String? {
        snapshot.displayName ?? snapshot.username
    }

    /// Force a snapshot rebuild before the next property read. Use
    /// after writes (e.g. `DWProfileUpdateCoordinator`) where you
    /// know the cache is stale and don't want to wait for the
    /// notification to round-trip through `DWDashPayModel`.
    @objc public func refreshFromSDK() {
        invalidate()
    }

    /// Fetch Platform credits and let the SDK persist them before invalidating UI.
    /// Capturing the wallet instance prevents a late response being applied to a
    /// newly selected wallet/network, even if the wallet IDs happen to match.
    @nonobjc
    func refreshBalanceFromNetwork(
        identityId: Data, wallet: ManagedPlatformWallet, network: Network
    ) async {
        await IdentityBalanceRefresh.run(
            isCurrent: {
                let host = SwiftDashSDKHost.shared
                return host.wallet === wallet
                    && host.runningNetwork == network
                    && WalletEnvironment.network == network
            },
            previousBalance: { try? wallet.managedIdentity(identityId: identityId).getBalance() },
            refresh: { try await wallet.refreshIdentityBalance(identityId: identityId) },
            publish: { balance in
                self.invalidate()
                Self.logger.info("🪪 IDENT-INFO :: refreshed identity balance: \(balance, privacy: .public) credits")
                NotificationCenter.default.post(
                    name: Notification.Name("DWDashPayRegistrationStatusUpdatedNotification"),
                    object: nil)
            },
            onFailure: { error in
                if let walletError = error as? PlatformWalletError {
                    switch walletError {
                    case .persisterStoreTransient, .persisterStoreFatal, .persisterStoreConstraint:
                        Self.logger.error("🪪 IDENT-INFO :: identity balance persistence failed: \(String(describing: error), privacy: .public)")
                        return
                    default: break
                    }
                }
                Self.logger.warning("🪪 IDENT-INFO :: identity balance refresh failed: \(String(describing: error), privacy: .public)")
            })
    }

    @nonobjc
    func refreshCurrentBalanceFromNetwork() async {
        guard isCurrentNetworkContextReady,
              let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              let identityId = snapshot.identityId else { return }
        await refreshBalanceFromNetwork(identityId: identityId, wallet: wallet, network: network)
    }

    /// Adopt an identity that arrived through seed recovery/discovery into the
    /// app-level DashPay state and notify every live UI consumer immediately.
    ///
    /// Identity discovery is an SDK operation, so it can populate SwiftData
    /// without passing through `DWIdentityRegistrationBridge`. Posting that
    /// bridge's internal notification is insufficient: the bridge has no
    /// registration username in a recovery session and `DWDashPayModel`
    /// deliberately ignores the event. Reconcile the mirror from SDK truth,
    /// then post the canonical notification directly.
    @discardableResult
    @nonobjc
    func reconcileRecoveredIdentity() -> Bool {
        invalidate()

        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer,
              let recoveredIdentityId = snapshot.identityId
        else {
            return false
        }

        let walletId = wallet.walletId
        if Self.mainIdentityId(walletId: walletId) == nil {
            Self.setMainIdentityId(recoveredIdentityId, walletId: walletId)
        }

        // Prefer the managed-wallet DPNS cache. The scalar SwiftData fields
        // are a short hydration fallback for the explicit Identities screen,
        // whose legacy refresh path writes them directly.
        var recoveredUsername = snapshot.usernames.first
        if recoveredUsername == nil {
            var walletDescriptor = FetchDescriptor<PersistentWallet>(
                predicate: #Predicate { $0.walletId == walletId }
            )
            walletDescriptor.fetchLimit = 1
            if let persistedWallet = try? container.mainContext.fetch(walletDescriptor).first,
               let persistedIdentity = persistedWallet.identities.first(where: {
                   $0.identityId == recoveredIdentityId
               }) {
                recoveredUsername = [Self.mainDpnsName(for: persistedIdentity), persistedIdentity.dpnsName]
                    .compactMap { Self.nilIfEmpty($0) }
                    .first(where: { candidate in
                        guard let network = SwiftDashSDKHost.shared.runningNetwork else { return false }
                        let service = DWContestedNameStatusService.shared
                        let pending = service.pendingLabels(for: network, identityId: recoveredIdentityId, walletId: walletId)
                            + service.unattributedLabels(for: network, walletId: walletId)
                        let departed = persistedIdentity.dpnsNames.filter { !$0.isOwned }.map(\.label)
                        return !(pending + departed).contains { DWContestedNameStatusService.labelsMatch(candidate, $0) }
                    })
            }
        }

        if let recoveredUsername {
            let options = DWGlobalOptions.sharedInstance()
            options.dashpayUsername = recoveredUsername
            options.dashpayRegistrationCompleted = true
            Self.logger.info(
                "🪪 IDENT-INFO :: adopted recovered identity with SDK username \(recoveredUsername, privacy: .public)")
        } else {
            // The recovered identity is authoritative for this wallet. Do not
            // retain a username mirror from a previously-active wallet/network
            // or from a contested label that is still being voted on.
            let options = DWGlobalOptions.sharedInstance()
            options.dashpayUsername = nil
            options.dashpayRegistrationCompleted = false
            Self.logger.info(
                "🪪 IDENT-INFO :: adopted recovered identity without an owned DPNS name")
        }

        invalidate()
        SwiftDashSDKContactsService.shared.refresh()
        NotificationCenter.default.post(
            name: Notification.Name("DWDashPayRegistrationStatusUpdatedNotification"),
            object: nil)
        return true
    }

    /// Install an authoritative empty snapshot at the wallet-removal boundary.
    /// Unlike a regular invalidation this does not depend on the SDK host being
    /// available, because the host has already stopped by the time the wipe
    /// lifecycle invokes it.
    @nonobjc
    func resetForWalletRemoval() {
        nameReadiness.retry()
        currentRevision &+= 1
        cachedSnapshot = .empty
        cachedRevision = currentRevision
        cachedNetwork = nil
        Self.logger.info(
            "🪪 IDENT-INFO :: wallet-context reset; revision → \(self.currentRevision, privacy: .public)")
    }

    /// Fire-and-forget blockchain refresh of the local DPNS-names
    /// cache via `wallet.syncDpnsNames(identityId:)`. The local
    /// cache (`ManagedIdentity.dpns_names`) only contains names
    /// that were either written by `registerDpnsName` in this
    /// session or pulled by a prior sync — wallet reinstalls,
    /// network switches, or contested-sync rewrites can leave it
    /// missing legitimately-owned names. Wired from
    /// `HomeViewController.viewDidAppear` so the helper picks up
    /// blockchain-side names automatically.
    @objc public func syncFromNetwork() {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              let container = SwiftDashSDKHost.shared.modelContainer,
              let id = refreshedSnapshot().identityId else { return }
        scheduleNameRefresh(wallet: wallet, network: network, container: container, identityId: id, refresh: true)
    }

    @nonobjc func retryNameRefresh() {
        for task in nameRefreshTasks.values { task.cancel() }
        nameRefreshTasks.removeAll()
        nameReadiness.retry()
        invalidate()
    }

    private func scheduleNameRefresh(
        wallet: ManagedPlatformWallet, network: Network, container: ModelContainer, identityId: Data,
        refresh: Bool = false
    ) {
        let scope = UsernameRegistrationDraftStore.Scope(
            network: network.persistenceScope, walletId: wallet.walletId, identityId: identityId)
        if refresh, nameRefreshTasks[scope] == nil { nameReadiness.retry(scope) }
        guard let generation = nameReadiness.begin(scope, refresh: refresh) else { return }
        nameRefreshTasks[scope] = Task { @MainActor in
            do {
                try await self.refreshNames(wallet: wallet, network: network, container: container, identityId: identityId)
                let hasUnknownContests = !DWContestedNameStatusService.shared
                    .unattributedLabels(for: network, walletId: wallet.walletId).isEmpty
                self.nameReadiness.finish(scope, generation: generation, succeeded: !hasUnknownContests)
            } catch {
                self.nameReadiness.finish(scope, generation: generation, succeeded: false)
                Self.logger.warning("Name refresh remains unknown: \(error.localizedDescription)")
            }
            guard self.nameReadiness.isCurrent(scope, generation: generation) else { return }
            self.nameRefreshTasks.removeValue(forKey: scope)
            self.invalidate()
            NotificationCenter.default.post(name: .DWDashPayRegistrationStatusUpdated, object: nil)
        }
    }

    /// Shared by startup and the retryable UI read. All writes retain the captured scope.
    @nonobjc func refreshNames(
        wallet: ManagedPlatformWallet, network: Network, container: ModelContainer, identityId: Data
    ) async throws {
        let options = DWGlobalOptions.sharedInstance()
        let legacyName = WalletEnvironment.network == network
            && (WalletEnvironment.activeWalletIdHex as String?) == wallet.walletId.hexEncodedString()
            && options.dashpayRegistrationCompleted ? options.dashpayUsername : nil
        var syncError: Error?
        do { _ = try await wallet.syncDpnsNames(identityId: identityId) }
        catch { syncError = error }
        try Task.checkCancellation()
        let names = try wallet.managedIdentity(identityId: identityId).getDpnsNames()
        if let legacyName, !legacyName.isEmpty, names.isEmpty || syncError != nil {
            do {
                if try await DWIdentityRegistrationCoordinator.shared.registrationNameState(
                    legacyName, identityId: identityId, wallet: wallet) == .owned {
                    try Task.checkCancellation()
                    Self.persistConfirmedUsername(legacyName, identityId: identityId, walletId: wallet.walletId, container: container)
                    syncError = nil
                }
            } catch DWIdentityRegistrationCoordinator.CoordinatorError.usernameUnavailable {
                // A wallet-global mirror can belong to another selected identity.
                // It must not turn a successful empty name read into an error.
            }
        }
        if let syncError { throw syncError }
        _ = try await wallet.syncContestedDpnsNames(identityId: identityId)
        try Task.checkCancellation()
        let unattributed = DWContestedNameStatusService.shared.unattributedLabels(for: network, walletId: wallet.walletId)
        for label in try wallet.managedIdentity(identityId: identityId).getContestedDpnsNames() {
            // Upgrade entries require a unique owner across every wallet identity.
            guard !unattributed.contains(where: { DWContestedNameStatusService.labelsMatch($0, label) }) else { continue }
            DWContestedNameStatusService.shared.recordSubmission(
                label: label, network: network, identityId: identityId, walletId: wallet.walletId)
        }
        try await rehydrateLegacyContests(wallet: wallet, network: network, container: container)
    }

    @nonobjc func rehydrateLegacyContests(
        wallet: ManagedPlatformWallet, network: Network, container: ModelContainer
    ) async throws {
        let walletId = wallet.walletId
        let descriptor = FetchDescriptor<PersistentWallet>(predicate: #Predicate { $0.walletId == walletId })
        let identities = try container.mainContext.fetch(descriptor).first?.identities.map(\.identityId) ?? []
        guard !identities.isEmpty else { return }
        let service = DWContestedNameStatusService.shared
        try await service.rehydrateUnattributed(network: network, walletId: walletId, owners: { label in
            var candidates: [Data] = []
            for id in identities {
                if let vote = try await wallet.fetchContestVoteState(identityId: id, label: label),
                   vote.contenders.contains(where: { $0.identityId == id }) {
                    candidates.append(id)
                }
            }
            if candidates.isEmpty, let owner = try await wallet.resolveDpnsName(label), identities.contains(owner) {
                candidates.append(owner)
            }
            return candidates
        }, resolved: { label in
            guard let end = service.pendingVotingEndTime(label: label, for: network, walletId: walletId),
                  Date() >= end else { return false }
            // No wallet identity is still contending; retain the old deadline
            // and the same canonical-owner resolution policy as attributed entries.
            _ = try await wallet.resolveDpnsName(label)
            return true
        })
    }

    // MARK: - Internals

    @objc private func handleInvalidationNotification(_ notification: Notification) {
        if notification.name == .DWCurrentNetworkDidChange
            || notification.name == SwiftDashSDKWalletState.activeWalletDidChangeNotification {
            retryNameRefresh()
        }
        invalidate()
    }

    private func invalidate() {
        currentRevision &+= 1
        Self.logger.debug("🪪 IDENT-INFO :: revision → \(self.currentRevision, privacy: .public)")
    }

    private var snapshot: Snapshot {
        // Never serve or recompute the previous network's snapshot while the
        // selected network and the still-running SDK host disagree. That
        // transition window previously leaked a Testnet identity into Mainnet
        // and repopulated the cleared global username mirror.
        guard isCurrentNetworkContextReady,
              let selectedNetwork = WalletEnvironment.network
        else {
            var loading = Snapshot.empty
            loading.isLoading = true
            return loading
        }

        if cachedNetwork != selectedNetwork || cachedRevision != currentRevision {
            if let computed = computeSnapshot() {
                cachedSnapshot = computed
                cachedRevision = currentRevision
                cachedNetwork = selectedNetwork
            }
            else {
                var loading = Snapshot.empty
                loading.isLoading = true
                cachedSnapshot = loading
                cachedRevision = currentRevision
                cachedNetwork = selectedNetwork
            }
            // Hydration retries are explicit and bounded in the UI. Repeated
            // accessors within one revision reuse even the loading snapshot.
        }
        return cachedSnapshot
    }

    /// Resolve the current identity from SwiftData + `ManagedIdentity`
    /// reads. Returns nil when the host hasn't hydrated wallet +
    /// container yet (cold-launch race) — the caller uses nil to
    /// mean "don't cache, retry on next read." A non-nil return is
    /// the authoritative snapshot, including `.empty` for "host is
    /// ready but no identity registered." Inner reads still bail
    /// gracefully (returning nil fields) rather than throwing so
    /// the 22 read-site call patterns stay simple.
    private func computeSnapshot() -> Snapshot? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              let container = SwiftDashSDKHost.shared.modelContainer
        else {
            return nil
        }

        let context = container.mainContext
        let walletId = wallet.walletId
        let pinnedIndex = Self.pinnedIdentityIndex
        // Query from the wallet side rather than via the
        // `identity.wallet?.walletId` relationship predicate. The
        // `#Predicate` macro compiles relationship traversals to SQL
        // that requires the inverse-edge graph to be hydrated at
        // query time. On cold launch the `PersistentIdentity` rows
        // exist on disk but SwiftData hasn't walked the inverse yet,
        // so the relationship predicate silently misses — the row
        // shows up later (the coordinator's identical lookup
        // succeeds because by the time it runs, other code paths
        // have already touched the relationship). `walletId` is a
        // direct attribute on `PersistentWallet`, so filtering there
        // requires no traversal; accessing `.identities` in Swift
        // hydrates the inverse on demand.
        var walletDescriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId }
        )
        walletDescriptor.fetchLimit = 1
        guard let persistedWallet = try? context.fetch(walletDescriptor).first else {
            return nil
        }
        // Resolution order: the user's stored main-identity pick (when it
        // still names one of this wallet's identities), then the pinned
        // registration slot (index 0), then the lowest registered index —
        // so a wallet whose only identity was discovered at a higher slot
        // still resolves instead of reading as unregistered.
        let identities = persistedWallet.identities
        let mainPick = Self.mainIdentityId(walletId: walletId)
        guard let persisted = identities.first(where: { mainPick != nil && $0.identityId == mainPick })
            ?? identities.first(where: { $0.identityIndex == pinnedIndex })
            ?? identities.min(by: { $0.identityIndex < $1.identityIndex })
        else {
            return .empty
        }

        let identityId = persisted.identityId
        let hex = identityId.map { String(format: "%02x", $0) }.joined()

        var username: String? = nil
        var usernames: [String] = []
        var displayName: String? = nil
        var avatarURL: String? = nil
        var publicMessage: String? = nil

        // Row #18: filter the pending-contested label out of every
        // candidate username source. `registerDpnsName` creates the
        // DPNS domain document immediately for both contested and
        // uncontested submissions — voting only decides who keeps
        // it. Without this filter, the contested-but-not-yet-owned
        // label leaks into Edit Profile, the SDK profile sheet,
        // invitation links, and the payment-side username memo. The
        // service-side bookmark in `DWContestedNameStatusService`
        // is single-writer/single-reader and cleared on resolution.
        // EVERY in-flight contested label filters out — the marketplace
        // allows several simultaneous requests, each its own vote poll.
        let pendingContested = DWContestedNameStatusService.shared.pendingLabels(
            for: network, identityId: identityId, walletId: walletId)
        let unattributed = DWContestedNameStatusService.shared.unattributedLabels(for: network, walletId: walletId)
        let isPending: (String) -> Bool = { name in
            (pendingContested + unattributed).contains { DWContestedNameStatusService.labelsMatch(name, $0) }
        }

        if let managed = try? wallet.managedIdentity(identityId: identityId) {
            if let names = try? managed.getDpnsNames() {
                usernames = names.filter { !isPending($0) }
                username = usernames.first
            }
            if let profile = try? managed.getDashPayProfile() {
                displayName = Self.nilIfEmpty(profile.displayName)
                publicMessage = Self.nilIfEmpty(profile.publicMessage)
                avatarURL = Self.nilIfEmpty(profile.avatarUrl)
            }
        }

        // A main name the create-username flow picked but could not store
        // yet (see `promoteToMainName`) stands in for the stored pick as
        // soon as the label is owned, so the display does not wait for the
        // SDK persister. Once the persister holds the label, the pick is
        // written for real — deferred, because this runs inside a
        // property read.
        var selectedMainName = Self.mainDpnsName(for: persisted)
        if let promoted = Self.pendingMainName(identityId: identityId), !isPending(promoted) {
            let persistedAsOwned = persisted.dpnsNames.contains {
                $0.isOwned && DWContestedNameStatusService.labelsMatch($0.label, promoted)
            }
            if persistedAsOwned || usernames.contains(where: { DWContestedNameStatusService.labelsMatch($0, promoted) }) {
                selectedMainName = promoted
            }
            if persistedAsOwned {
                Task { @MainActor [weak self] in
                    if Self.applyPendingMainName(identityId: identityId, walletId: walletId, container: container) {
                        self?.invalidate()
                    }
                }
            }
        }

        // The user's picked display label (Identities → detail →
        // Usernames card, read through `mainDpnsName(for:)`).
        // Promote it to the front so `username` / `usernames.first` —
        // and every mirror written from them — render the pick instead
        // of DPNS-cache order. Only an owned label qualifies: it must
        // appear in the managed cache or the SwiftData label cache, so
        // a stale pick (name transferred away) can't resurface.
        if let mainName = Self.nilIfEmpty(selectedMainName), !isPending(mainName) {
            if let index = usernames.firstIndex(where: {
                DWContestedNameStatusService.labelsMatch($0, mainName)
            }) {
                usernames.insert(usernames.remove(at: index), at: 0)
            } else if persisted.dpnsNames.contains(where: {
                // `isOwned == false` rows are sold/transferred-away labels
                // retained for trade history — without this check a stale
                // pick of a SOLD name resurfaces through the label cache.
                $0.isOwned && DWContestedNameStatusService.labelsMatch($0.label, mainName)
            }) {
                usernames.insert(mainName, at: 0)
            }
            username = usernames.first ?? username
        }

        // Persisted fallback: the managed-wallet DPNS cache is session-
        // scoped — it holds only names written by `registerDpnsName` in
        // this session or pulled by a `syncDpnsNames` round — so on a
        // fresh runtime start it is legitimately empty until the next
        // sync round, while the SwiftData side already carries the
        // confirmed name: `IdentitiesViewModel.refreshFromNetwork`
        // resolves names through a live `sdk.dpnsGetUsername` query and
        // writes the `PersistentIdentity.dpnsName` scalar, and the SDK
        // persister maintains the owned `PersistentDPNSName` rows. Read
        // those sources when the cache yields nothing so the confirmed
        // name reaches `usernames` — and through it the mirror self-heal
        // below. (Only that cache-not-yet-synced window: a wallet with no
        // persisted identity row never reaches this fallback — the
        // `guard let persisted` above returns `.empty` first.) Owned
        // label rows first (ownership-tracked), then the scalars in
        // `reconcileRecoveredIdentity`'s order; the pending-contested
        // filter applies the same as above.
        if usernames.isEmpty {
            var persistedCandidates = persisted.dpnsNames
                .filter { $0.isOwned }
                .map { $0.label }
            // The scalars can outlive a sale of the name: skip a label whose
            // row is known to have left (the same guard as the row model).
            let departed = persisted.dpnsNames.filter { !$0.isOwned }.map(\.label)
            persistedCandidates.append(contentsOf: [Self.mainDpnsName(for: persisted), persisted.dpnsName]
                .compactMap { Self.nilIfEmpty($0) }
                .filter { candidate in
                    !departed.contains { DWContestedNameStatusService.labelsMatch($0, candidate) }
                })
            for candidate in persistedCandidates where !isPending(candidate) {
                if !usernames.contains(where: {
                    DWContestedNameStatusService.labelsMatch($0, candidate)
                }) {
                    usernames.append(candidate)
                }
            }
            username = usernames.first
        }

        // Only names associated with this selected identity are authoritative.
        // The legacy global mirror also holds attempted labels (before DPNS)
        // and can belong to a different selected identity in the same wallet.

        // Self-heal the DWGlobalOptions mirror. Registration completion
        // and Find-identities adoption are the only writers, so an
        // identity that arrived any other way (synced in after a
        // reinstall, registered under an older build) leaves the mirror
        // empty forever — and every mirror reader (the menu's Join
        // DashPay banner, DWDashPayModel's registration status) then
        // disagrees with the SDK truth rendered everywhere else. Only a
        // confirmed name qualifies (`usernames` — fed by the SDK DPNS
        // cache or the persisted SwiftData sources), and the
        // pending-contested filter has already run, so a deferred
        // contested registration can't sneak in. The
        // canonical notification is posted async: this runs lazily inside a
        // property read, and re-entering registration-status observers
        // mid-read is the kind of surprise we don't need. Recovered
        // identities do not have an active registration bridge username, so
        // its internal notification would be ignored by DWDashPayModel.
        if let sdkUsername = usernames.first,
           DWGlobalOptions.sharedInstance().dashpayUsername?.isEmpty != false {
            let options = DWGlobalOptions.sharedInstance()
            options.dashpayUsername = sdkUsername
            options.dashpayRegistrationCompleted = true
            Self.logger.info(
                "🪪 IDENT-INFO :: backfilled username mirror from SDK: \(sdkUsername, privacy: .public)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("DWDashPayRegistrationStatusUpdatedNotification"),
                    object: nil)
            }
        }

        Self.logger.debug(
            "🪪 IDENT-INFO :: snapshot username=\(username ?? "nil", privacy: .public) hasProfile=\(displayName != nil || avatarURL != nil, privacy: .public) id=\(hex.prefix(8), privacy: .public)…")

        let scope = UsernameRegistrationDraftStore.Scope(
            network: network.persistenceScope, walletId: walletId, identityId: identityId)
        let namesAreLoaded = !usernames.isEmpty || !pendingContested.isEmpty
            || (nameReadiness.isLoaded(scope) && unattributed.isEmpty)
        if !namesAreLoaded {
            scheduleNameRefresh(wallet: wallet, network: network, container: container, identityId: identityId)
        }
        return Snapshot(
            isLoading: !namesAreLoaded,
            namesAreLoaded: namesAreLoaded,
            // SDK and persisted balances are cached: a successful local zero
            // does not prove Platform was read. Let submission validate credits.
            balanceCredits: Self.cachedBalanceCredits(
                (try? wallet.managedIdentity(identityId: identityId).getBalance())
                    ?? (persisted.balance > 0 ? UInt64(persisted.balance) : nil)),
            pendingContestedName: pendingContested.first,
            pendingVotingEndTime: pendingContested.first.flatMap {
                guard let network = SwiftDashSDKHost.shared.runningNetwork else { return nil }
                return DWContestedNameStatusService.shared.pendingVotingEndTime(label: $0, for: network, walletId: walletId)
            },
            identityId: identityId,
            identityIdHex: hex,
            username: username,
            usernames: usernames,
            displayName: displayName,
            avatarURL: avatarURL,
            publicMessage: publicMessage)
    }

    /// Persist only a label whose ownership was proven by registration or resolution.
    static func persistConfirmedUsername(
        _ name: String, identityId: Data, walletId: Data, container: ModelContainer?
    ) {
        guard let context = container?.mainContext else { return }
        let descriptor = FetchDescriptor<PersistentWallet>(predicate: #Predicate { $0.walletId == walletId })
        guard let wallet = try? context.fetch(descriptor).first,
              let identity = wallet.identities.first(where: { $0.identityId == identityId }) else { return }
        identity.dpnsName = name
        do { try context.save() }
        catch { Self.logger.warning("Could not persist confirmed DPNS name: \(error.localizedDescription)") }
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Main-name promotion

    /// Make `label` the identity's main DPNS name: first in `usernames`,
    /// in the `DWGlobalOptions` mirror and in Identities → Usernames. The
    /// create-username flow calls this for the name it registers, because
    /// that is the name the user asked to be known by. Names acquired in
    /// the username marketplace never come through here, so they do not
    /// displace it; the user can still pick another main name manually.
    ///
    /// The pick is held as an intent until the SDK persister stores an
    /// owned row for the label, and only then written to
    /// `PersistentIdentity.mainDpnsName`. Writing it earlier does not
    /// stick: every identity flush resets a main name that is not among
    /// the labels it carries, and a flush queued before the name landed
    /// can still be applied after our write. Flushes are applied in order,
    /// so once the owned row exists, no later flush predates the name.
    /// The snapshot honours the intent meanwhile (see `computeSnapshot`).
    ///
    /// The caller has already checked that the identity belongs to the
    /// active wallet and network; the mirror is written only when it is
    /// also the selected identity.
    @nonobjc
    func promoteToMainName(_ label: String, identityId: Data, walletId: Data, network: Network) {
        Self.setPendingMainName(label, identityId: identityId)
        let container = SwiftDashSDKHost.shared.modelContainer
        let stored = Self.applyPendingMainName(identityId: identityId, walletId: walletId, container: container)
        invalidate()
        let current = snapshot
        if SwiftDashSDKHost.shared.wallet?.walletId == walletId,
           SwiftDashSDKHost.shared.runningNetwork == network,
           current.identityId == identityId {
            let options = DWGlobalOptions.sharedInstance()
            // The snapshot carries the label as Platform spells it.
            options.dashpayUsername = current.usernames.first {
                DWContestedNameStatusService.labelsMatch($0, label)
            } ?? label
            options.dashpayRegistrationCompleted = true
        }
        Self.logger.info(
            "🪪 IDENT-INFO :: main name → \(label, privacy: .public) stored=\(stored, privacy: .public)")
    }

    /// Drop a pending promotion, e.g. when the user picks a main name by
    /// hand: their choice must not be overridden once the promoted label
    /// reaches the persister.
    static func discardPendingMainName(identityId: Data) {
        setPendingMainName(nil, identityId: identityId)
    }

    /// Identity ids are unique across networks and wallets, so the id alone
    /// scopes the intent to the identity that registered the name.
    private nonisolated static let pendingMainNameKeyPrefix = "DWPendingMainDpnsName."

    private static func pendingMainNameKey(identityId: Data) -> String {
        pendingMainNameKeyPrefix + identityId.map { String(format: "%02x", $0) }.joined()
    }

    private static func pendingMainName(identityId: Data) -> String? {
        nilIfEmpty(UserDefaults.standard.string(forKey: pendingMainNameKey(identityId: identityId)))
    }

    private static func setPendingMainName(_ label: String?, identityId: Data) {
        let key = pendingMainNameKey(identityId: identityId)
        if let label {
            UserDefaults.standard.set(label, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Store the pending pick once the persister owns the label; true when
    /// it was stored (the intent is then consumed).
    @discardableResult
    private static func applyPendingMainName(identityId: Data, walletId: Data, container: ModelContainer?) -> Bool {
        guard let label = pendingMainName(identityId: identityId),
              let context = container?.mainContext else { return false }
        let descriptor = FetchDescriptor<PersistentWallet>(predicate: #Predicate { $0.walletId == walletId })
        guard let wallet = try? context.fetch(descriptor).first,
              let identity = wallet.identities.first(where: { $0.identityId == identityId }),
              let owned = identity.dpnsNames.first(where: {
                  $0.isOwned && DWContestedNameStatusService.labelsMatch($0.label, label)
              })
        else { return false }
        setMainDpnsName(owned.label, identityId: identityId)
        PersistentIdentity.updateMainDpnsName(in: context, identityId: identityId, mainDpnsName: owned.label)
        do {
            try context.save()
        } catch {
            Self.logger.warning("Could not store the main DPNS name: \(error.localizedDescription)")
            return false
        }
        setPendingMainName(nil, identityId: identityId)
        return true
    }

    /// Wallet wipe: no promotion or stored pick may outlive the identities
    /// it names.
    nonisolated static func resetPendingMainNamesForWipe() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(pendingMainNameKeyPrefix) || key.hasPrefix(mainDpnsNameKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Same-seed identity recovery

/// Small dependency-injected core for the startup recovery flow. Keeping the
/// sequencing independent from SwiftData/FFI makes the cold-install behavior
/// regression-testable: discover only when the local store is empty, refresh
/// names after discovery persistence, then reconcile app state.
@MainActor
enum SameSeedIdentityRecoveryPipeline {
    private static let logger = Logger(subsystem: "org.dash.wallet", category: "IdentityRecovery")
    struct Outcome: Equatable {
        let discoveredCount: Int
        let identityCount: Int
        let adopted: Bool
        /// Whether EVERY identity this run acted on was found in the local
        /// store after the name refresh. `false` means at least one id came
        /// from a discovery result or from the readiness verdict and the
        /// persister has not landed it (yet) — the caller must not treat the
        /// identity as settled, whatever other rows the wallet already has.
        let identitiesPersisted: Bool
    }

    /// `knownIdentityIds`: identities the readiness pass already discovered
    /// and persisted in this start. They stand in for an empty local read —
    /// the persister normally lands the rows before the readiness call
    /// returns, but a lagging store must not trigger a second discovery scan.
    /// `allowDiscovery: false` adopts and refreshes whatever identity rows
    /// exist locally without ever scanning — for a readiness verdict that
    /// says a scan cannot succeed (`.discoveryFailed`).
    static func run(
        knownIdentityIds: [Data] = [],
        allowDiscovery: Bool = true,
        localIdentityIds: () -> [Data],
        discover: () async throws -> [Data],
        refreshNames: ([Data]) async throws -> Void,
        adopt: () -> Bool
    ) async throws -> Outcome {
        var identityIds = localIdentityIds()
        var discoveredIds: [Data] = []

        if identityIds.isEmpty, !knownIdentityIds.isEmpty {
            identityIds = knownIdentityIds
        }

        if identityIds.isEmpty, allowDiscovery {
            discoveredIds = try await discover()
            identityIds = localIdentityIds()
            // The SDK persister normally makes the rows visible before the
            // discovery call returns. Keep the authoritative discovery result
            // as a hydration fallback instead of losing the same launch.
            if identityIds.isEmpty {
                identityIds = discoveredIds
            }
        }

        guard !identityIds.isEmpty else {
            return Outcome(
                discoveredCount: discoveredIds.count, identityCount: 0, adopted: false, identitiesPersisted: false)
        }

        do { try await refreshNames(identityIds) }
        catch is CancellationError { throw CancellationError() }
        catch { logger.warning("Identity recovered; name refresh remains pending: \(error.localizedDescription)") }
        try Task.checkCancellation()
        // Re-read rather than trust the ids we acted on: `knownIdentityIds`
        // came from a different call, and even a discovery result can
        // outrun its own persistence. Intersected with the acted-on ids so
        // a row the wallet already had cannot vouch for a new one.
        let persistedIds = Set(localIdentityIds())
        let identitiesPersisted = identityIds.allSatisfy { persistedIds.contains($0) }
        return Outcome(
            discoveredCount: discoveredIds.count,
            identityCount: identityIds.count,
            adopted: adopt(),
            identitiesPersisted: identitiesPersisted)
    }
}

/// Decides what the BLAST-side same-seed recovery backstop still has to do
/// after the pre-SPV readiness pass (`DashPayContactAddressReadiness` →
/// `startWalletSubsystems`) already ran for the same runtime start. Pure so
/// the rules stay regression-testable.
enum StartupIdentityRecoveryPolicy {
    /// Budget handed to the SDK's startup sequence for a wallet whose
    /// mnemonic was generated on this device and that has no local identity.
    /// It caps the WHOLE sequence, so it is only ever a first probe: a proof
    /// of absence settles on the first discovery pass, an unreachable
    /// Platform costs this much instead of the SDK default, and a probe cut
    /// short after finding an identity is re-run with the default budget
    /// (`probeNeedsFullRerun`). A probe that is cut off before it finds
    /// anything reports `.partialNoIdentity`, which `decision` sends to the
    /// backstop — so a generated wallet whose seed owns an identity
    /// registered elsewhere is still discovered in the same runtime start.
    static let generatedWalletStartupBudget: TimeInterval = 5

    /// What the backstop does with the readiness verdict of this start.
    enum Decision: Equatable {
        /// Run the full pipeline (discover if needed → refresh names → adopt),
        /// subject to the per-process settled memo. Also the answer for an
        /// identity readiness re-confirmed on file: the pipeline's DPNS name
        /// refresh is the only code path that rebuilds contested-label
        /// bookmarks and keeps the name cache `reconcileRecoveredIdentity`
        /// reads, so adoption is never taken without it — once per process
        /// per wallet, as before this policy existed.
        case runPipeline
        /// Readiness discovered and persisted the identity in THIS start: a
        /// second install's first sight of it. The pipeline runs regardless
        /// of the settled memo (the memo may hold a `.noIdentity` from
        /// earlier in the process) — its discovery finds the rows already
        /// there, and its name refresh rebuilds the bookmarks.
        case refreshNamesAndAdopt
        /// Platform confirmed the seed owns no identity; settled for the
        /// process.
        case skipSettled
        /// Platform answered the network side and a scan would add nothing
        /// — either it proved absence while the local store may still hold
        /// rows, or the SDK reports a local fault a rescan cannot clear
        /// (`.discoveryFailed`). No scan, but the pipeline still refreshes
        /// and adopts whatever identity rows exist locally, under the memo.
        /// A run that finds none settles nothing; the next runtime start
        /// asks the SDK again.
        case runPipelineWithoutDiscovery
    }

    /// `nil` status = no readiness pass ran in this start (a Platform-sync
    /// re-arm, the storage explorer's direct BLAST start, a thrown or elided
    /// pass): the pipeline runs as before. A known identity runs the
    /// pipeline too (past the memo when it was discovered in this start).
    /// Without an identity the SDK's own verdict properties decide:
    /// `.noIdentity` settles; a status that is `discoveryWorthRetrying`
    /// (`.partialNoIdentity` — Platform or the Keychain scan key not
    /// reachable, also what the SDK decodes an unrecognised FFI status into
    /// — and `.identityScanIncomplete`) or otherwise `identityIsSettled`
    /// runs the pipeline unless the wallet was already settled in this
    /// process; a status that is neither (`.discoveryFailed`) runs the
    /// pipeline without its scan. Every runtime start asks the SDK again.
    /// `readinessDiscoveredThisStart` means the wallet had NO local
    /// identity before the readiness pass and has one after it — measured
    /// by the caller from the store, not from `discoveryAttempts`, which
    /// the SDK also increments when it rescans an identity already on file.
    /// `hasLocalIdentity` is the same store reading the startup budget uses,
    /// `nil` when the lookup was inconclusive. A proof of absence only
    /// settles a wallet the store agrees has no identity: the two can
    /// disagree (a SwiftData mirror outliving a Rust-side store reset, a
    /// watch-only wallet Rust answers for without a signer), and rows on
    /// disk still deserve adoption — without a scan, since Platform already
    /// answered the network side.
    static func decision(
        readinessStatus: WalletStartupStatus?,
        readinessIdentityId: Data?,
        readinessDiscoveredThisStart: Bool,
        hasLocalIdentity: Bool?
    ) -> Decision {
        guard let readinessStatus else { return .runPipeline }
        if readinessIdentityId != nil {
            return readinessDiscoveredThisStart ? .refreshNamesAndAdopt : .runPipeline
        }
        if readinessStatus == .noIdentity {
            return hasLocalIdentity == false ? .skipSettled : .runPipelineWithoutDiscovery
        }
        if readinessStatus.discoveryWorthRetrying || readinessStatus.identityIsSettled {
            return .runPipeline
        }
        return .runPipelineWithoutDiscovery
    }

    /// Whether a short-budget probe found an identity and the BUDGET — not
    /// a Platform error — cut the sequence short before the contact-request
    /// pass and the contact-account drain completed, the two steps the
    /// readiness pass exists to guarantee before the first SPV filter set is
    /// built. `budgetExhausted` is the caller's reading of `elapsed` against
    /// the budget it passed: the SDK clears `dashPaySyncRan` for a degraded
    /// or failed contact pass too, and a re-run cannot fix those. Never when
    /// the drain was skipped for `seedBindingUnverified` (the SDK fails that
    /// closed on every budget), and never when the probe's own scan was cut
    /// off (`identityScanIncomplete`): the SDK then rescans on the next
    /// start instead of reusing the identity, so a re-run would pay a fresh
    /// full discovery on the switch path. Those cases leave the contact
    /// steps to the DIP-15 rescan.
    static func probeNeedsFullRerun(
        identityFound: Bool,
        budgetExhausted: Bool,
        dashPaySyncRan: Bool,
        contactAccountsPending: UInt32,
        seedBindingUnverified: Bool,
        identityScanIncomplete: Bool
    ) -> Bool {
        identityFound
            && budgetExhausted
            && !seedBindingUnverified
            && !identityScanIncomplete
            && (!dashPaySyncRan || contactAccountsPending > 0)
    }

    /// Attempts the backstop makes on an identity the store keeps failing
    /// to confirm before it settles the context for the process anyway.
    /// Bounds a SwiftData mirror that never lands the row: without a cap
    /// every re-arm in the process would pay the unbudgeted scan.
    static let maxUnpersistedAttempts = 2

    /// `nil` = the SDK default budget. `hasLocalIdentity == nil` means the
    /// lookup was inconclusive (fetch failed, no wallet row): the probe is
    /// only ever applied to a wallet KNOWN to have no local identity, so the
    /// unknown case keeps the default budget.
    static func startupBudget(isGeneratedOnDevice: Bool, hasLocalIdentity: Bool?) -> TimeInterval? {
        guard isGeneratedOnDevice, hasLocalIdentity == false else { return nil }
        return generatedWalletStartupBudget
    }
}

/// Best-effort startup recovery for an identity created by the same seed on a
/// different device/install. A network-scoped wallet is settled once per
/// process — by a completed pipeline run, by a readiness pass that proved
/// the seed owns no identity, or by adopting the identity a readiness pass
/// found — until `forgetWallet` (wallet deletion) drops it, so a phrase
/// removed and re-imported in the same session gets its attempt back.
/// Failures remain retryable on the next runtime start. A readiness verdict
/// with a known identity always adopts, settled or not.
@MainActor
final class DWSameSeedIdentityRecoveryCoordinator {
    static let shared = DWSameSeedIdentityRecoveryCoordinator()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.identity-recovery")

    private var completedContexts: Set<String> = []
    private var activeContexts: Set<String> = []
    /// Readiness verdicts recorded by `DashPayContactAddressReadiness` for
    /// the current runtime start. `recoverIfNeeded` removes the verdict for
    /// its context on entry, before any early return, so one verdict is
    /// consulted at most once.
    private var startupVerdicts: [String: (status: WalletStartupStatus, identityId: Data?, discovered: Bool)] = [:]
    /// Pipeline runs per context that acted on an identity the store did
    /// not confirm (see `maxUnpersistedAttempts`).
    private var unpersistedAttempts: [String: Int] = [:]

    private init() {}

    /// Hand over the pre-SPV readiness verdict for `walletId` on `network`
    /// so the backstop below can tell a fresh discovery from a repeat.
    func recordStartupDiscovery(
        status: WalletStartupStatus,
        identityId: Data?,
        discoveredThisStart: Bool,
        walletId: Data,
        network: Network
    ) {
        startupVerdicts[Self.contextKey(walletId: walletId, network: network)] =
            (status, identityId, discoveredThisStart)
    }

    /// Runtime teardown (`SwiftDashSDKWalletRuntime.fullReset`) calls this
    /// so a readiness verdict never outlives the start that produced it.
    /// The settled contexts deliberately survive: they are the per-process
    /// memo that keeps the unbudgeted scan from running on every switch.
    func clearStartupVerdicts() {
        startupVerdicts.removeAll()
    }

    /// Drop everything remembered about `walletId` on every network. Called
    /// on wallet deletion: walletIds are deterministic per mnemonic+network,
    /// so a phrase removed and re-imported must not inherit a settled
    /// context.
    func forgetWallet(walletId: Data) {
        let suffix = ":" + walletId.hexEncodedString()
        completedContexts = completedContexts.filter { !$0.hasSuffix(suffix) }
        startupVerdicts = startupVerdicts.filter { !$0.key.hasSuffix(suffix) }
        unpersistedAttempts = unpersistedAttempts.filter { !$0.key.hasSuffix(suffix) }
    }

    /// Startup budget for the SDK's pre-SPV sequence, or `nil` for the SDK
    /// default — see `StartupIdentityRecoveryPolicy.startupBudget`. Takes
    /// the store reading rather than repeating it: the caller needs the
    /// same value to tell a first sight from a re-confirmation, and this
    /// runs on the pre-SPV main-thread path.
    func startupBudget(walletId: Data, hasLocalIdentity: Bool?) -> TimeInterval? {
        StartupIdentityRecoveryPolicy.startupBudget(
            isGeneratedOnDevice: GeneratedWalletIdentityMarker.isMarked(walletId: walletId),
            hasLocalIdentity: hasLocalIdentity)
    }

    func recoverIfNeeded(
        wallet: ManagedPlatformWallet,
        modelContainer: ModelContainer,
        network: Network
    ) async {
        let walletId = wallet.walletId
        let contextKey = Self.contextKey(walletId: walletId, network: network)
        let walletHex = walletId.hexEncodedString()

        // An in-flight run for this context keeps its verdict untouched: the
        // call that started it settles or returns it.
        guard !activeContexts.contains(contextKey) else { return }

        // Consumed here. A branch that settles the context keeps it
        // consumed; every branch that returns without settling — the memo
        // early return, a thrown pipeline — puts it back, so a later call in
        // the same start decides on the same verdict instead of a
        // verdict-less one. The one exception is a pipeline run whose
        // identity the store never confirmed: there the verdict stays
        // consumed so the retry rediscovers.
        let verdict = startupVerdicts.removeValue(forKey: contextKey)
        // Restores only into an empty slot, so a verdict RECORDED while this
        // call was suspended wins over the one this call took. It does not
        // distinguish "cleared by `fullReset`" from "never recorded" — both
        // leave the slot nil. That case is handled by ordering instead:
        // every non-elided refresh runs `fullReset` before the readiness
        // pass that records the next verdict.
        func restoreVerdict() {
            if let verdict, startupVerdicts[contextKey] == nil { startupVerdicts[contextKey] = verdict }
        }

        let allowDiscovery: Bool
        switch StartupIdentityRecoveryPolicy.decision(
            readinessStatus: verdict?.status,
            readinessIdentityId: verdict?.identityId,
            readinessDiscoveredThisStart: verdict?.discovered ?? false,
            hasLocalIdentity: Self.hasLocalIdentity(walletId: walletId, modelContainer: modelContainer)) {
        case .skipSettled:
            completedContexts.insert(contextKey)
            Self.logger.info(
                "🪪 IDENT-RECOVERY :: skipped — startup readiness proved this seed owns no identity")
            return
        case .refreshNamesAndAdopt:
            // First sight of this identity on this install: run the pipeline
            // past the settled memo (its discovery finds the rows readiness
            // persisted; the name refresh rebuilds the contested bookmarks).
            allowDiscovery = true
        case .runPipeline:
            allowDiscovery = true
            guard !completedContexts.contains(contextKey) else {
                restoreVerdict()
                return
            }
        case .runPipelineWithoutDiscovery:
            // A local fault blocked the SDK's scan and a rescan cannot clear
            // it: adopt and refresh whatever identity rows exist locally,
            // never scan.
            allowDiscovery = false
            guard !completedContexts.contains(contextKey) else {
                restoreVerdict()
                return
            }
        }

        activeContexts.insert(contextKey)
        defer { activeContexts.remove(contextKey) }

        do {
            let outcome = try await SameSeedIdentityRecoveryPipeline.run(
                knownIdentityIds: verdict?.identityId.map { [$0] } ?? [],
                allowDiscovery: allowDiscovery,
                localIdentityIds: {
                    Self.localIdentityIds(walletId: walletId, modelContainer: modelContainer)
                },
                discover: {
                    Self.logger.info(
                        "🪪 IDENT-RECOVERY :: wallet=\(walletHex.prefix(8), privacy: .public) no local identities; scanning seed from index 0")
                    return try await wallet.discoverIdentities(startIndex: 0)
                },
                refreshNames: { identityIds in
                    for identityId in identityIds {
                        try await DWCurrentUserIdentityInfo.shared.refreshNames(
                            wallet: wallet, network: network, container: modelContainer, identityId: identityId)
                    }
                },
                adopt: {
                    DWCurrentUserIdentityInfo.shared.reconcileRecoveredIdentity()
                })

            if outcome.identityCount > 0 {
                // The seed owns an identity after all; the next start must
                // run the full pre-SPV bring-up, not the generated-wallet
                // probe.
                GeneratedWalletIdentityMarker.clear(walletId: walletId)
            }
            if outcome.identityCount == 0, !allowDiscovery {
                // Nothing was established: this run was forbidden from
                // scanning (a local fault the SDK says a rescan cannot
                // clear) and found no local rows to adopt. Settling here
                // would retire the backstop for the process on a transient
                // fault, so leave the context open and hand the verdict back
                // for a later start whose readiness has improved.
                restoreVerdict()
                Self.logger.warning(
                    "🪪 IDENT-RECOVERY :: no local identity to adopt and scanning was not allowed; leaving the context open")
            } else if outcome.identityCount == 0 || outcome.identitiesPersisted {
                completedContexts.insert(contextKey)
                unpersistedAttempts[contextKey] = nil
            } else {
                // Acted on ids the store has not confirmed: leave the context
                // open (and the verdict consumed) so the next attempt runs
                // the discovery that repopulates the store — a bounded
                // number of times, then settle for the process anyway so a
                // mirror that never lands the row cannot buy an unbudgeted
                // scan on every re-arm.
                let attempts = (unpersistedAttempts[contextKey] ?? 0) + 1
                unpersistedAttempts[contextKey] = attempts
                if attempts >= StartupIdentityRecoveryPolicy.maxUnpersistedAttempts {
                    completedContexts.insert(contextKey)
                    Self.logger.error(
                        "🪪 IDENT-RECOVERY :: identity still not persisted after \(attempts, privacy: .public) attempt(s); settling for this process")
                } else {
                    Self.logger.warning(
                        "🪪 IDENT-RECOVERY :: identity acted on but not yet persisted locally; leaving the context open")
                }
            }
            Self.logger.info(
                """
                🪪 IDENT-RECOVERY :: wallet=\(walletHex.prefix(8), privacy: .public) complete \
                discovered=\(outcome.discoveredCount, privacy: .public) \
                identities=\(outcome.identityCount, privacy: .public) \
                persisted=\(outcome.identitiesPersisted, privacy: .public) \
                adopted=\(outcome.adopted, privacy: .public)
                """)
        } catch {
            restoreVerdict()
            Self.logger.warning(
                """
                🪪 IDENT-RECOVERY :: failed; will retry after next runtime start: \
                \(String(describing: error), privacy: .public)
                """)
        }
    }

    private static func contextKey(walletId: Data, network: Network) -> String {
        "\(network.rawValue):" + walletId.hexEncodedString()
    }

    /// Existence check for the startup-budget decision. Queried from the
    /// wallet side, like `computeSnapshot`: a `#Predicate` over
    /// `identity.wallet?.walletId` compiles to a relationship traversal that
    /// silently misses rows on cold launch until the inverse edge is
    /// hydrated, and this runs BEFORE `startWalletSubsystems` — a miss would
    /// hand a wallet that does own a local identity the short probe budget.
    /// `walletId` is a direct attribute on `PersistentWallet`, and reading
    /// `.identities` hydrates the inverse on demand; `isEmpty` faults the
    /// relationship but skips the sort and the `[Data]` copy
    /// `localIdentityIds` builds for callers that need the ids.
    /// `nil` when the answer is unknown — the fetch threw or there is no
    /// wallet row to ask — so the caller can fail towards the default budget.
    static func hasLocalIdentity(walletId: Data, modelContainer: ModelContainer) -> Bool? {
        var descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId }
        )
        descriptor.fetchLimit = 1
        guard let persistedWallet = try? modelContainer.mainContext.fetch(descriptor).first else {
            return nil
        }
        return !persistedWallet.identities.isEmpty
    }

    private static func localIdentityIds(
        walletId: Data,
        modelContainer: ModelContainer
    ) -> [Data] {
        var descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContainer.mainContext.fetch(descriptor).first)?
            .identities ?? [])
            .sorted { $0.identityIndex < $1.identityIndex }
            .map(\.identityId)
    }
}
