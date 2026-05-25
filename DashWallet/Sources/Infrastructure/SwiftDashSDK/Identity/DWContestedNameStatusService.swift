//
//  DWContestedNameStatusService.swift
//  DashWallet
//
//  Lightweight bookmark for the in-flight contested DPNS name
//  registration submitted by THIS device. The SDK side already
//  persists active contested labels via `syncContestedDpnsNames`,
//  but a label drops out of `getContestedDpnsNames()` once the
//  contest resolves — won names move to `getDpnsNames()`, lost
//  ones disappear entirely. We add a single UserDefaults slot so
//  the helper (`DWCurrentUserIdentityInfo`) can filter the
//  pending label out of the displayed username until resolution.
//
//  Scope:
//    - `recordSubmission(label:)` — coordinator writes the
//      bookmark right after `registerDpnsName` succeeds for a
//      contested label.
//    - `pendingLabel` — read by `DWCurrentUserIdentityInfo` to
//      suppress the leak into Edit Profile / SDK profile sheet /
//      invitation links / payment-side username memo.
//    - `clearPending()` — manual escape hatch (e.g. debug tool,
//      a future resolution-detection path).
//    - `isContestedLabel(_:)` — static deterministic predicate via
//      the SDK's FFI helper. Shared between the viewmodel (warning
//      badge) and the coordinator (branch on submission).
//
//  Notes:
//    - The blockchain-side status view + per-vote refresh that
//      previously lived here was removed once we hit the upstream
//      SwiftDashSDK `GetDataContractsRequest.version = None` bug
//      that blocks `syncDpnsNames` and `fetchContestVoteState`
//      (same family as the profile-write bug — see
//      `DASHSYNC_MIGRATION.md → Known SDK issues`). Status UI can
//      come back when that bug is fixed upstream.
//    - Single UserDefaults slot — v1 pins to one in-flight
//      contested submission per identity. NOT read by any
//      carveout viewmodel (`JoinDashPayViewModel`, `HomeViewModel`).
//

import Foundation
import OSLog
import SwiftDashSDK

@MainActor
@objc(DWContestedNameStatusService)
@objcMembers
public final class DWContestedNameStatusService: NSObject {

    public static let shared = DWContestedNameStatusService()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.contested-name")

    /// UserDefaults key for the pending-submission bookmark. Name
    /// is dashwallet-private; no other component reads it.
    private static let pendingLabelKey = "DWPendingContestedDPNSLabel"

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Persisted label of the most-recent contested submission, or
    /// `nil` if no submission is in flight. Single-writer (this
    /// service); single-reader (`DWCurrentUserIdentityInfo`
    /// snapshot filter).
    public var pendingLabel: String? {
        UserDefaults.standard.string(forKey: Self.pendingLabelKey)
    }

    /// Coordinator calls this immediately after `registerDpnsName`
    /// returns success for a contested label, before the
    /// `.completed` controller transition fan-outs through the
    /// bridge. The bookmark prevents the contested-but-not-yet-
    /// owned label from leaking into Edit Profile + the SDK
    /// profile sheet via `DWCurrentUserIdentityInfo`'s filter.
    public func recordSubmission(label: String) {
        UserDefaults.standard.set(label, forKey: Self.pendingLabelKey)
        Self.logger.info("🪪 CONTEST-SVC :: recordSubmission label=\(label, privacy: .public)")
    }

    /// Clear the pending bookmark. No internal callers in v1 — the
    /// resolution-detection path that previously consumed this was
    /// removed alongside the status view. Kept as an escape hatch
    /// for future surfaces (debug tool, manual resolution check).
    public func clearPending() {
        UserDefaults.standard.removeObject(forKey: Self.pendingLabelKey)
        Self.logger.info("🪪 CONTEST-SVC :: clearPending")
    }

    /// Client-side contested-eligibility predicate. Deterministic
    /// per the DPNS contract spec — `≤19 chars + only [a-zA-Z0-9-]`.
    /// Reused by:
    ///   - `CreateUsernameViewModel.validateUsername` for the
    ///     warning badge,
    ///   - `DWIdentityRegistrationCoordinator.handlePhaseChange`
    ///     for deciding whether to skip the global-mirror writes.
    /// `nonisolated` so non-MainActor callers (currently none, but
    /// future-proofs) don't need a hop.
    public nonisolated static func isContestedLabel(_ label: String) -> Bool {
        label.withCString { namePtr in
            dash_sdk_dpns_is_contested_username(namePtr) == 1
        }
    }
}
