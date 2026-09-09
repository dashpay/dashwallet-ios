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
//    - Username lookup falls back to `DWGlobalOptions.dashpayUsername`
//      when the `ManagedIdentity.getDpnsNames()` cache is empty
//      (newly-registered identity that hasn't synced the DPNS cache
//      yet). The coordinator writes `dashpayUsername` on `.completed`
//      so this fallback closes the post-register sync gap without
//      depending on `wallet.syncDpnsNames(identityId:)`.
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

    // MARK: - Snapshot

    /// Cached read of the SDK's current identity info. Rebuilt lazily
    /// on the next property access after `currentRevision` advances.
    private struct Snapshot {
        let identityId: Data?
        let identityIdHex: String?
        let username: String?
        let usernames: [String]
        let displayName: String?
        let avatarURL: String?
        let publicMessage: String?

        static let empty = Snapshot(
            identityId: nil,
            identityIdHex: nil,
            username: nil,
            usernames: [],
            displayName: nil,
            avatarURL: nil,
            publicMessage: nil)
    }

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

    /// First DPNS label for the current identity, or
    /// `DWGlobalOptions.dashpayUsername` as a post-register fallback
    /// when the SDK's name cache hasn't been populated yet. Nil if
    /// no identity is registered.
    @objc public var username: String? {
        snapshot.username
    }

    /// All DPNS labels the identity owns (`ManagedIdentity.getDpnsNames()`),
    /// with the pending-contested label filtered out same as `username`.
    /// Empty when no identity is registered or the cache is unpopulated.
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
                recoveredUsername = [persistedIdentity.mainDpnsName, persistedIdentity.dpnsName]
                    .compactMap { Self.nilIfEmpty($0) }
                    .first(where: { candidate in
                        !DWContestedNameStatusService.shared.isPendingLabel(candidate)
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
        Task { @MainActor in
            Self.logger.info("🪪 IDENT-INFO :: syncFromNetwork called")
            guard let wallet = SwiftDashSDKHost.shared.wallet,
                  let identityId = snapshot.identityId
            else { return }
            do {
                let added = try await wallet.syncDpnsNames(identityId: identityId)
                Self.logger.info("🪪 IDENT-INFO :: syncDpnsNames added=\(added, privacy: .public)")
                self.invalidate()
            } catch {
                Self.logger.warning("🪪 IDENT-INFO :: syncDpnsNames failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Internals

    @objc private func handleInvalidationNotification(_ notification: Notification) {
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
            return .empty
        }

        if cachedNetwork != selectedNetwork || cachedRevision != currentRevision {
            if let computed = computeSnapshot() {
                cachedSnapshot = computed
                cachedRevision = currentRevision
                cachedNetwork = selectedNetwork
            }
            // else: host wasn't ready (wallet/container hydrating).
            // Don't bump cachedRevision so the next read retries
            // instead of caching `.empty` until the next
            // notification fires — at app cold launch there's no
            // such notification, which previously left the helper
            // permanently empty.
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
            return .empty
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
        let pendingContested = DWContestedNameStatusService.shared.pendingLabels
        let isPending: (String) -> Bool = { name in
            pendingContested.contains { DWContestedNameStatusService.labelsMatch(name, $0) }
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

        // The user's picked display label (Identities → detail →
        // Usernames card, stored as `PersistentIdentity.mainDpnsName`).
        // Promote it to the front so `username` / `usernames.first` —
        // and every mirror written from them — render the pick instead
        // of DPNS-cache order. Only an owned label qualifies: it must
        // appear in the managed cache or the SwiftData label cache, so
        // a stale pick (name transferred away) can't resurface.
        if let mainName = Self.nilIfEmpty(persisted.mainDpnsName), !isPending(mainName) {
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

        // Post-register fallback: SwiftDashSDK's DPNS cache is empty
        // immediately after `registerDpnsName` returns until the next
        // `syncDpnsNames` round, but the coordinator writes
        // `DWGlobalOptions.dashpayUsername` on `.completed` for
        // uncontested submissions only — contested submissions defer
        // the write entirely, so the fallback can't match a pending
        // contested label by construction.
        if username == nil {
            username = Self.nilIfEmpty(DWGlobalOptions.sharedInstance().dashpayUsername)
        }

        // Self-heal the DWGlobalOptions mirror. Registration completion
        // and Find-identities adoption are the only writers, so an
        // identity that arrived any other way (synced in after a
        // reinstall, registered under an older build) leaves the mirror
        // empty forever — and every mirror reader (the menu's Join
        // DashPay banner, DWDashPayModel's registration status) then
        // disagrees with the SDK truth rendered everywhere else. Only an
        // SDK-sourced name qualifies (`usernames` — the fallback above
        // IS the mirror), and the pending-contested filter has already
        // run, so a deferred contested registration can't sneak in. The
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

        return Snapshot(
            identityId: identityId,
            identityIdHex: hex,
            username: username,
            usernames: usernames,
            displayName: displayName,
            avatarURL: avatarURL,
            publicMessage: publicMessage)
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Same-seed identity recovery

/// Small dependency-injected core for the startup recovery flow. Keeping the
/// sequencing independent from SwiftData/FFI makes the cold-install behavior
/// regression-testable: discover only when the local store is empty, refresh
/// names after discovery persistence, then reconcile app state.
@MainActor
enum SameSeedIdentityRecoveryPipeline {
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

        try await refreshNames(identityIds)
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
                        "🪪 IDENT-RECOVERY :: no local identities; scanning seed from index 0")
                    return try await wallet.discoverIdentities(startIndex: 0)
                },
                refreshNames: { identityIds in
                    for identityId in identityIds {
                        _ = try await wallet.syncDpnsNames(identityId: identityId)

                        // Contested-name refresh is important for correctly
                        // withholding a still-voting label, but it must not
                        // block restoration of an already-owned identity when
                        // that auxiliary endpoint is temporarily unavailable.
                        do {
                            _ = try await wallet.syncContestedDpnsNames(identityId: identityId)
                            let contested = try wallet
                                .managedIdentity(identityId: identityId)
                                .getContestedDpnsNames()
                            // A second install has no local submission
                            // bookmarks. Reconstruct one per still-voting
                            // label from Platform so the pre-vote DPNS
                            // documents cannot be mistaken for ownership.
                            for recoveredPending in contested
                            where !DWContestedNameStatusService.shared.isPendingLabel(recoveredPending) {
                                DWContestedNameStatusService.shared.recordSubmission(
                                    label: recoveredPending)
                            }
                        } catch {
                            Self.logger.warning(
                                """
                                🪪 IDENT-RECOVERY :: contested-name refresh failed: \
                                \(String(describing: error), privacy: .public)
                                """)
                        }
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
                🪪 IDENT-RECOVERY :: complete \
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
