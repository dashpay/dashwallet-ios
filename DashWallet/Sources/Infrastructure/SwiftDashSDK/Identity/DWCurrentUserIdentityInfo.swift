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

    // MARK: - Snapshot

    /// Cached read of the SDK's current identity info. Rebuilt lazily
    /// on the next property access after `currentRevision` advances.
    private struct Snapshot {
        let identityId: Data?
        let identityIdHex: String?
        let username: String?
        let displayName: String?
        let avatarURL: String?
        let publicMessage: String?

        static let empty = Snapshot(
            identityId: nil,
            identityIdHex: nil,
            username: nil,
            displayName: nil,
            avatarURL: nil,
            publicMessage: nil)
    }

    private var cachedSnapshot: Snapshot = .empty
    private var cachedRevision: Int = -1
    private var currentRevision: Int = 0

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
    }

    // MARK: - Obj-C / Swift read API

    /// `YES` when the SDK has a `PersistentIdentity` row for the
    /// current wallet at `pinnedIdentityIndex`. Mirrors the
    /// `DWDashPayProtocol.hasIdentity` semantics from Row #17 stage A.
    @objc public var hasIdentity: Bool {
        snapshot.identityId != nil
    }

    /// First DPNS label for the current identity, or
    /// `DWGlobalOptions.dashpayUsername` as a post-register fallback
    /// when the SDK's name cache hasn't been populated yet. Nil if
    /// no identity is registered.
    @objc public var username: String? {
        snapshot.username
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

    // MARK: - Internals

    @objc private func handleInvalidationNotification(_ notification: Notification) {
        invalidate()
    }

    private func invalidate() {
        currentRevision &+= 1
        Self.logger.debug("🪪 IDENT-INFO :: revision → \(self.currentRevision, privacy: .public)")
    }

    private var snapshot: Snapshot {
        if cachedRevision != currentRevision {
            cachedSnapshot = computeSnapshot()
            cachedRevision = currentRevision
        }
        return cachedSnapshot
    }

    /// Resolve the current identity from SwiftData + `ManagedIdentity`
    /// reads. Falls back gracefully when any step fails — the helper
    /// returns nil rather than throwing so the 22 read-site call
    /// patterns stay simple.
    private func computeSnapshot() -> Snapshot {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer
        else {
            return .empty
        }

        let context = container.mainContext
        let walletId = wallet.walletId
        let pinnedIndex = Self.pinnedIdentityIndex
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { identity in
                identity.wallet?.walletId == walletId
                    && identity.identityIndex == pinnedIndex
            }
        )
        descriptor.fetchLimit = 1
        guard let persisted = try? context.fetch(descriptor).first else {
            return .empty
        }

        let identityId = persisted.identityId
        let hex = identityId.map { String(format: "%02x", $0) }.joined()

        var username: String? = nil
        var displayName: String? = nil
        var avatarURL: String? = nil
        var publicMessage: String? = nil

        if let managed = try? wallet.managedIdentity(identityId: identityId) {
            if let names = try? managed.getDpnsNames(), let first = names.first {
                username = first
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
        // `DWGlobalOptions.dashpayUsername` on `.completed`, so the
        // user-visible name is available without a sync round-trip.
        if username == nil {
            username = Self.nilIfEmpty(DWGlobalOptions.sharedInstance().dashpayUsername)
        }

        Self.logger.debug(
            "🪪 IDENT-INFO :: snapshot username=\(username ?? "nil", privacy: .public) hasProfile=\(displayName != nil || avatarURL != nil, privacy: .public) id=\(hex.prefix(8), privacy: .public)…")

        return Snapshot(
            identityId: identityId,
            identityIdHex: hex,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL,
            publicMessage: publicMessage)
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
