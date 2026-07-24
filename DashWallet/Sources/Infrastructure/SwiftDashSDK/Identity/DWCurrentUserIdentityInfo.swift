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
        let pendingContested = DWContestedNameStatusService.shared.pendingLabel
        let isPending: (String) -> Bool = { name in
            guard let pending = pendingContested else { return false }
            return name == pending || name == "\(pending).dash"
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
        // bridge notification is posted async: this runs lazily inside a
        // property read, and DWDashPayModel re-posting the canonical
        // status update reentrantly mid-read is the kind of surprise we
        // don't need.
        if let sdkUsername = usernames.first,
           DWGlobalOptions.sharedInstance().dashpayUsername?.isEmpty != false {
            let options = DWGlobalOptions.sharedInstance()
            options.dashpayUsername = sdkUsername
            options.dashpayRegistrationCompleted = true
            Self.logger.info(
                "🪪 IDENT-INFO :: backfilled username mirror from SDK: \(sdkUsername, privacy: .public)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: DWIdentityRegistrationBridge.stateChangedNotification,
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
