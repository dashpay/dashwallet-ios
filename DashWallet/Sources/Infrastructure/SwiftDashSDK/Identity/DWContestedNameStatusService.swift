//
//  DWContestedNameStatusService.swift
//  DashWallet
//
//  Lightweight bookmark for the in-flight contested DPNS name
//  registration submitted by THIS device. The SDK side already
//  persists active contested labels via `syncContestedDpnsNames`,
//  but a label drops out of `getContestedDpnsNames()` once the
//  contest resolves — won names move to `getDpnsNames()`, lost
//  ones disappear entirely. We add one network-scoped UserDefaults
//  bookmark so the helper (`DWCurrentUserIdentityInfo`) can filter the
//  pending label out of the displayed username until resolution.
//
//  Scope:
//    - `recordSubmission(label:)` — coordinator writes the
//      bookmark right after `registerDpnsName` succeeds for a
//      contested label.
//    - `pendingLabel` — read by `DWCurrentUserIdentityInfo` to
//      suppress the leak into Edit Profile / SDK profile sheet /
//      invitation links / payment-side username memo.
//    - `clearPending()` — consumed by the LOST branch of
//      `DWIdentityRegistrationCoordinator.checkPendingContestResolution()`.
//    - `finalizeWon(username:)` — the WON branch: performs the
//      DWGlobalOptions mirror writes that `handlePhaseChange`
//      deferred at submission time, then broadcasts the canonical
//      registration notification.
//    - `isContestedLabel(_:)` — static deterministic predicate via
//      the SDK's FFI helper. Shared between the viewmodel (warning
//      badge) and the coordinator (branch on submission).
//
//  Notes:
//    - Resolution detection lives in
//      `DWIdentityRegistrationCoordinator.checkPendingContestResolution()`,
//      triggered from Home appear/foreground. (The upstream
//      `GetDataContractsRequest.version = None` bug that once blocked
//      `syncDpnsNames`/`fetchContestVoteState` was fixed in the v11
//      pin, 2026-05-27.) A user-facing contest-status VIEW remains
//      future work.
//    - One UserDefaults bookmark per Platform network — v1 pins to
//      one in-flight contested submission per identity and network.
//      NOT read by any carveout viewmodel (`JoinDashPayViewModel`,
//      `HomeViewModel`).
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

    /// UserDefaults key prefixes for the pending-submission bookmark.
    /// A suffix is added for the active Platform network: contested
    /// submissions and their deadlines must never leak across a
    /// Testnet/Mainnet round-trip.
    private static let pendingLabelKeyPrefix = "DWPendingContestedDPNSLabel"
    private static let pendingVotingEndTimeKeyPrefix = "DWPendingContestedDPNSVotingEndTime"

    /// Protocol vote-poll durations in the Platform v2 settings. The fallback
    /// starts at OUR submission time, which is at or after the first contender's
    /// timestamp, and adds a grace period, so it cannot resolve earlier than the
    /// real poll. Platform's authoritative `ContestVoteState.endTime` replaces
    /// this estimate as soon as the contest becomes queryable.
    private static let mainnetFallbackDuration: TimeInterval = 14 * 24 * 60 * 60
    private static let testnetFallbackDuration: TimeInterval = 90 * 60
    private static let fallbackResolutionGrace: TimeInterval = 5 * 60

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Persisted label of the most-recent contested submission, or
    /// `nil` if no submission is in flight. Single-writer (this
    /// service); single-reader (`DWCurrentUserIdentityInfo`
    /// snapshot filter).
    public var pendingLabel: String? {
        guard let network = WalletEnvironment.network else { return nil }
        return pendingLabel(for: network)
    }

    /// Best-known voting deadline for the active network. Submission writes a
    /// conservative fallback immediately; `ContestVoteState.endTime` replaces
    /// it once Platform indexes the contest.
    public var pendingVotingEndTime: Date? {
        guard let network = WalletEnvironment.network else { return nil }
        return pendingVotingEndTime(for: network)
    }

    /// Coordinator calls this immediately after `registerDpnsName`
    /// returns success for a contested label, before the
    /// `.completed` controller transition fan-outs through the
    /// bridge. The bookmark prevents the contested-but-not-yet-
    /// owned label from leaking into Edit Profile + the SDK
    /// profile sheet via `DWCurrentUserIdentityInfo`'s filter.
    public func recordSubmission(label: String) {
        guard let network = WalletEnvironment.network else {
            Self.logger.error("🪪 CONTEST-SVC :: cannot record submission without a supported network")
            return
        }
        recordSubmission(label: label, network: network)
    }

    /// Network-explicit variant used by the registration coordinator. It
    /// captures the runtime network before any async FFI work, avoiding a
    /// late completion being written into the newly-selected network.
    @nonobjc
    func recordSubmission(
        label: String,
        network: Network,
        submittedAt: Date = Date()
    ) {
        let fallbackEnd = Self.fallbackVotingEndTime(
            submittedAt: submittedAt,
            network: network)
        UserDefaults.standard.set(label, forKey: Self.pendingLabelKey(for: network))
        UserDefaults.standard.set(
            fallbackEnd.timeIntervalSince1970,
            forKey: Self.pendingVotingEndTimeKey(for: network))
        Self.logger.info(
            "🪪 CONTEST-SVC :: recordSubmission label=\(label, privacy: .public) network=\(network.rawValue, privacy: .public) fallbackEnd=\(fallbackEnd.timeIntervalSince1970, privacy: .public)")
    }

    /// Cache the real contest deadline once Platform exposes its vote state.
    /// It replaces the conservative submission-time estimate.
    public func recordVotingEndTime(_ endTime: Date) {
        guard let network = WalletEnvironment.network else { return }
        recordVotingEndTime(endTime, network: network)
    }

    @nonobjc
    func recordVotingEndTime(_ endTime: Date, network: Network) {
        UserDefaults.standard.set(
            endTime.timeIntervalSince1970,
            forKey: Self.pendingVotingEndTimeKey(for: network))
        Self.logger.info(
            "🪪 CONTEST-SVC :: authoritative voting end network=\(network.rawValue, privacy: .public) end=\(endTime.timeIntervalSince1970, privacy: .public)")
    }

    /// Clear the pending bookmark. Called by the LOST/pruned branches of
    /// `DWIdentityRegistrationCoordinator.checkPendingContestResolution()`
    /// (and by `finalizeWon` on the WON branch).
    public func clearPending() {
        guard let network = WalletEnvironment.network else { return }
        clearPending(for: network)
    }

    @nonobjc
    func clearPending(for network: Network) {
        UserDefaults.standard.removeObject(forKey: Self.pendingLabelKey(for: network))
        UserDefaults.standard.removeObject(forKey: Self.pendingVotingEndTimeKey(for: network))
        Self.logger.info("🪪 CONTEST-SVC :: clearPending network=\(network.rawValue, privacy: .public)")
    }

    /// Compare DPNS labels in their canonical form. The registration form
    /// preserves the user's capitalization while Platform can return the
    /// normalized lowercase label, and some reads append `.dash`.
    public nonisolated static func labelsMatch(_ lhs: String, _ rhs: String) -> Bool {
        canonicalLabel(lhs) == canonicalLabel(rhs)
    }

    /// Objective-C-friendly check used by the legacy DashPay state bridge.
    public func isPendingLabel(_ label: String) -> Bool {
        guard let pendingLabel else { return false }
        return Self.labelsMatch(label, pendingLabel)
    }

    private nonisolated static func canonicalLabel(_ label: String) -> String {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasSuffix(".dash")
            ? String(normalized.dropLast(".dash".count))
            : normalized
    }

    /// Resolution-side counterpart of the DWGlobalOptions mirror writes
    /// that `DWIdentityRegistrationCoordinator.handlePhaseChange` skips
    /// for contested submissions. Called by
    /// `checkPendingContestResolution()` when the vote resolved in our
    /// favor. Mirrors the post-write broadcast pattern in
    /// `DWProfileUpdateCoordinator`: mirror writes → clear the bookmark →
    /// rebuild the identity-info snapshot (no longer filtered) → post the
    /// canonical registration notification so the home avatar / tab
    /// config / join-banner observers re-read state live.
    public func finalizeWon(username: String) {
        guard let network = WalletEnvironment.network else { return }
        finalizeWon(username: username, network: network)
    }

    @nonobjc
    func finalizeWon(username: String, network: Network) {
        DWGlobalOptions.sharedInstance().dashpayUsername = username
        DWGlobalOptions.sharedInstance().dashpayRegistrationCompleted = true
        clearPending(for: network)
        Self.logger.info("🪪 CONTEST-SVC :: finalizeWon label=\(username, privacy: .public)")
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        NotificationCenter.default.post(
            name: Notification.Name("DWDashPayRegistrationStatusUpdatedNotification"),
            object: nil)
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

    // MARK: - Network-scoped storage

    @nonobjc
    func pendingLabel(for network: Network) -> String? {
        UserDefaults.standard.string(forKey: Self.pendingLabelKey(for: network))
    }

    @nonobjc
    func pendingVotingEndTime(for network: Network) -> Date? {
        let timestamp = UserDefaults.standard.double(
            forKey: Self.pendingVotingEndTimeKey(for: network))
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    nonisolated static func fallbackVotingEndTime(
        submittedAt: Date,
        network: Network
    ) -> Date {
        let duration = network == .mainnet
            ? mainnetFallbackDuration
            : testnetFallbackDuration
        return submittedAt.addingTimeInterval(duration + fallbackResolutionGrace)
    }

    private nonisolated static func pendingLabelKey(for network: Network) -> String {
        "\(pendingLabelKeyPrefix).\(networkKey(network))"
    }

    private nonisolated static func pendingVotingEndTimeKey(for network: Network) -> String {
        "\(pendingVotingEndTimeKeyPrefix).\(networkKey(network))"
    }

    private nonisolated static func networkKey(_ network: Network) -> String {
        network == .mainnet ? "mainnet" : "testnet"
    }
}
