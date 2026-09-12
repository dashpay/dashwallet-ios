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
//      pin, 2026-05-27.)
//    - MANY submissions can be in flight at once (each label is its own
//      network vote poll; the marketplace lets the user request several).
//      The store is one UserDefaults dictionary per (network, wallet):
//      canonical label → {submittedAt, votingEnd}. The single-value
//      `pendingLabel` / `pendingVotingEndTime` remain as OLDEST-entry
//      conveniences for the setup-flow surfaces, which only ever deal
//      with the first username.
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

    /// UserDefaults key prefixes. A suffix is added for the active
    /// Platform network: contested submissions and their deadlines must
    /// never leak across a Testnet/Mainnet round-trip.
    /// `entriesKeyPrefix` is the multi-label store (canonical label →
    /// {submitted, end}); the label/endTime prefixes are the two retired
    /// single-slot layouts, kept only for one-time migration.
    private static let entriesKeyPrefix = "DWPendingContestedDPNSEntries"
    private static let pendingLabelKeyPrefix = "DWPendingContestedDPNSLabel"
    private static let pendingVotingEndTimeKeyPrefix = "DWPendingContestedDPNSVotingEndTime"

    /// Dictionary-value field names in the entries store.
    private static let submittedField = "submitted"
    private static let endField = "end"

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

    /// OLDEST in-flight contested label, or `nil` when none. The setup
    /// flow's compatibility view of the store: those surfaces only deal
    /// with the user's FIRST username, which is by construction the
    /// oldest entry. Multi-label consumers use `pendingLabels`.
    public var pendingLabel: String? {
        guard let network = WalletEnvironment.network else { return nil }
        return pendingLabels(for: network).first
    }

    /// Every in-flight contested label for the active network, oldest
    /// submission first.
    public var pendingLabels: [String] {
        guard let network = WalletEnvironment.network else { return [] }
        return pendingLabels(for: network)
    }

    /// Best-known voting deadline of the OLDEST entry (see `pendingLabel`).
    /// Submission writes a conservative fallback immediately;
    /// `ContestVoteState.endTime` replaces it once Platform indexes the
    /// contest.
    public var pendingVotingEndTime: Date? {
        guard let network = WalletEnvironment.network,
              let label = pendingLabels(for: network).first else { return nil }
        return pendingVotingEndTime(label: label, for: network)
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
    /// Upserts — an existing entry for the label keeps its original
    /// submission time (re-recording from recovery must not reorder).
    @nonobjc
    func recordSubmission(
        label: String,
        network: Network,
        submittedAt: Date = Date()
    ) {
        guard let key = Self.entriesKey(for: network) else {
            // A submission is always made by an active wallet, so this cannot
            // happen — but recording it under no wallet would write a bookmark
            // nothing can ever own or clear.
            Self.logger.error(
                "🪪 CONTEST-SVC :: cannot record submission with no active wallet")
            return
        }
        let fallbackEnd = Self.fallbackVotingEndTime(
            submittedAt: submittedAt,
            network: network)
        var entries = Self.entries(for: network)
        let canonical = Self.canonicalLabel(label)
        if var existing = entries[canonical] {
            existing[Self.endField] = existing[Self.endField] ?? fallbackEnd.timeIntervalSince1970
            entries[canonical] = existing
        } else {
            entries[canonical] = [
                Self.submittedField: submittedAt.timeIntervalSince1970,
                Self.endField: fallbackEnd.timeIntervalSince1970,
            ]
        }
        UserDefaults.standard.set(entries, forKey: key)
        Self.logger.info(
            "🪪 CONTEST-SVC :: recordSubmission label=\(canonical, privacy: .public) network=\(network.rawValue, privacy: .public) inFlight=\(entries.count, privacy: .public)")
    }

    /// Cache the real contest deadline for one label once Platform exposes
    /// its vote state. It replaces the conservative submission-time
    /// estimate. No-op for a label with no bookmark.
    @nonobjc
    func recordVotingEndTime(_ endTime: Date, label: String, network: Network) {
        guard let key = Self.entriesKey(for: network) else { return }
        var entries = Self.entries(for: network)
        let canonical = Self.canonicalLabel(label)
        guard var entry = entries[canonical] else { return }
        entry[Self.endField] = endTime.timeIntervalSince1970
        entries[canonical] = entry
        UserDefaults.standard.set(entries, forKey: key)
        Self.logger.info(
            "🪪 CONTEST-SVC :: authoritative voting end label=\(canonical, privacy: .public) network=\(network.rawValue, privacy: .public) end=\(endTime.timeIntervalSince1970, privacy: .public)")
    }

    /// Clear ONE label's bookmark — the LOST/pruned branches of
    /// `DWIdentityRegistrationCoordinator.checkPendingContestResolution()`
    /// (and `finalizeWon` on the WON branch). Other in-flight contests
    /// keep their bookmarks.
    @nonobjc
    func clearPending(label: String, for network: Network) {
        guard let key = Self.entriesKey(for: network) else { return }
        var entries = Self.entries(for: network)
        entries.removeValue(forKey: Self.canonicalLabel(label))
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(entries, forKey: key)
        }
        Self.logger.info("🪪 CONTEST-SVC :: clearPending label=\(Self.canonicalLabel(label), privacy: .public) network=\(network.rawValue, privacy: .public) remaining=\(entries.count, privacy: .public)")
    }

    /// Drop EVERY bookmark for the network (all in-flight labels, plus any
    /// retired-layout leftovers).
    public func clearPending() {
        guard let network = WalletEnvironment.network else { return }
        clearPending(for: network)
    }

    @nonobjc
    func clearPending(for network: Network) {
        let defaults = UserDefaults.standard
        if let key = Self.entriesKey(for: network) {
            defaults.removeObject(forKey: key)
        }
        if let labelKey = Self.pendingLabelKey(for: network) {
            defaults.removeObject(forKey: labelKey)
        }
        if let endTimeKey = Self.pendingVotingEndTimeKey(for: network) {
            defaults.removeObject(forKey: endTimeKey)
        }
        // Also drop any legacy bookmark, so clearing a resolved contest cannot
        // leave a pre-scoping value behind for the next read to adopt.
        defaults.removeObject(forKey: Self.legacyPendingLabelKey(for: network))
        defaults.removeObject(forKey: Self.legacyPendingVotingEndTimeKey(for: network))
        Self.logger.info("🪪 CONTEST-SVC :: clearPending ALL network=\(network.rawValue, privacy: .public)")
    }

    /// Compare DPNS labels in their canonical form. The registration form
    /// preserves the user's capitalization while Platform can return the
    /// normalized lowercase label, and some reads append `.dash`.
    public nonisolated static func labelsMatch(_ lhs: String, _ rhs: String) -> Bool {
        canonicalLabel(lhs) == canonicalLabel(rhs)
    }

    /// Objective-C-friendly check used by the legacy DashPay state bridge.
    /// True when ANY in-flight contested submission matches `label`.
    public func isPendingLabel(_ label: String) -> Bool {
        pendingLabels.contains { Self.labelsMatch(label, $0) }
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
        // Backfill the global username mirror only when it's empty (the
        // setup-flow first-username case). A contested win on a SECOND
        // name — requested from the username marketplace — must not
        // displace the username the user already shows everywhere.
        let options = DWGlobalOptions.sharedInstance()
        if options.dashpayUsername?.isEmpty != false {
            options.dashpayUsername = username
        }
        options.dashpayRegistrationCompleted = true
        // Only the WON label's bookmark clears — other contests stay in flight.
        clearPending(label: username, for: network)
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

    /// All in-flight labels for `network`, oldest submission first.
    @nonobjc
    func pendingLabels(for network: Network) -> [String] {
        Self.entries(for: network)
            .sorted {
                ($0.value[Self.submittedField] ?? 0) < ($1.value[Self.submittedField] ?? 0)
            }
            .map(\.key)
    }

    /// Compatibility single-label read: the OLDEST in-flight label.
    @nonobjc
    func pendingLabel(for network: Network) -> String? {
        pendingLabels(for: network).first
    }

    /// Best-known voting deadline for one label's contest, or nil when the
    /// label has no bookmark.
    @nonobjc
    func pendingVotingEndTime(label: String, for network: Network) -> Date? {
        guard let timestamp = Self.entries(for: network)[Self.canonicalLabel(label)]?[Self.endField],
              timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Compatibility read: the OLDEST entry's deadline (see `pendingLabel`).
    @nonobjc
    func pendingVotingEndTime(for network: Network) -> Date? {
        guard let label = pendingLabels(for: network).first else { return nil }
        return pendingVotingEndTime(label: label, for: network)
    }

    /// The entries dictionary, after migrating any retired single-slot
    /// bookmark into it (one-time: the old keys are deleted on adoption).
    private nonisolated static func entries(for network: Network) -> [String: [String: Double]] {
        discardLegacyBookmark(for: network)
        guard let key = entriesKey(for: network) else { return [:] }
        let defaults = UserDefaults.standard
        var entries = (defaults.dictionary(forKey: key) as? [String: [String: Double]]) ?? [:]
        // Adopt the retired wallet-scoped single-slot layout: same wallet
        // scope, so attribution is unambiguous (unlike the legacy unscoped
        // bookmark, which is discarded).
        if let labelKey = pendingLabelKey(for: network),
           let oldLabel = defaults.string(forKey: labelKey) {
            let canonical = canonicalLabel(oldLabel)
            if entries[canonical] == nil {
                let oldEnd = pendingVotingEndTimeKey(for: network)
                    .map { defaults.double(forKey: $0) } ?? 0
                let end = oldEnd > 0
                    ? oldEnd
                    : fallbackVotingEndTime(submittedAt: Date(), network: network).timeIntervalSince1970
                // Approximate the original submission time from the deadline
                // so ordering against newer entries stays sane.
                let duration = network == .mainnet ? mainnetFallbackDuration : testnetFallbackDuration
                entries[canonical] = [
                    submittedField: end - duration - fallbackResolutionGrace,
                    endField: end,
                ]
                defaults.set(entries, forKey: key)
                logger.info("🪪 CONTEST-SVC :: migrated single-slot bookmark label=\(canonical, privacy: .public)")
            }
            defaults.removeObject(forKey: labelKey)
            if let endKey = pendingVotingEndTimeKey(for: network) {
                defaults.removeObject(forKey: endKey)
            }
        }
        return entries
    }

    private nonisolated static func entriesKey(for network: Network) -> String? {
        scope().map { "\(entriesKeyPrefix).\(networkKey(network)).\($0)" }
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

    /// A contested submission belongs to the WALLET that made it, not to the
    /// device. Scoping only by network let a bookmark outlive the wallet that
    /// created it: reset the wallet mid-vote, create a new one, and the new
    /// wallet still reported the old wallet's name as "in voting".
    ///
    /// Returns nil while no wallet is active (onboarding, post-wipe) — with no
    /// wallet there is no submission to report, and answering nil is what keeps
    /// a wiped device from resurrecting the previous wallet's vote.
    private nonisolated static func scope() -> String? {
        guard let hex = WalletEnvironment.activeWalletIdHex as String?, !hex.isEmpty else {
            return nil
        }
        return hex
    }

    private nonisolated static func pendingLabelKey(for network: Network) -> String? {
        scope().map { "\(pendingLabelKeyPrefix).\(networkKey(network)).\($0)" }
    }

    private nonisolated static func pendingVotingEndTimeKey(for network: Network) -> String? {
        scope().map { "\(pendingVotingEndTimeKeyPrefix).\(networkKey(network)).\($0)" }
    }

    /// Pre-wallet-scoping key layout, kept only so an install that is mid-vote
    /// when it updates does not lose its bookmark: the first scoped read for a
    /// wallet adopts the legacy value and deletes it.
    private nonisolated static func legacyPendingLabelKey(for network: Network) -> String {
        "\(pendingLabelKeyPrefix).\(networkKey(network))"
    }

    private nonisolated static func legacyPendingVotingEndTimeKey(for network: Network) -> String {
        "\(pendingVotingEndTimeKeyPrefix).\(networkKey(network))"
    }

    /// Delete any pre-scoping bookmark, without adopting it.
    ///
    /// Adopting looked like the kind thing to do for an install that updates
    /// mid-vote, but a wallet-agnostic value cannot be attributed to a wallet:
    /// it handed the previous wallet's vote to whichever wallet read first,
    /// which is the leak the scoping exists to close — reset the wallet, create
    /// a new one, and the old contest reappeared on it.
    ///
    /// Nothing is lost by dropping it. A wallet that really has a contest in
    /// flight rebuilds the bookmark from Platform on the next runtime start:
    /// the same-seed recovery pipeline refreshes contested names for every
    /// identity it finds and calls `recordSubmission` for the one it owns.
    private nonisolated static func discardLegacyBookmark(for network: Network) {
        let defaults = UserDefaults.standard
        let legacyLabelKey = legacyPendingLabelKey(for: network)
        guard defaults.object(forKey: legacyLabelKey) != nil else { return }
        defaults.removeObject(forKey: legacyLabelKey)
        defaults.removeObject(forKey: legacyPendingVotingEndTimeKey(for: network))
        logger.info(
            "🪪 CONTEST-SVC :: discarded unattributable legacy bookmark for \(networkKey(network), privacy: .public)")
    }

    /// Drop every contested bookmark this device holds — both wallet-scoped and
    /// legacy, across networks. Called from the wallet wiper alongside the other
    /// UserDefaults-backed stores.
    nonisolated static func resetForWipe() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(entriesKeyPrefix)
            || key.hasPrefix(pendingLabelKeyPrefix)
            || key.hasPrefix(pendingVotingEndTimeKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        logger.info("🪪 CONTEST-SVC :: cleared all contested bookmarks for wipe")
    }

    private nonisolated static func networkKey(_ network: Network) -> String {
        // Same "mainnet"/"testnet" strings as before; devnet gets its own
        // key instead of colliding with testnet's bookmarks.
        network.networkName
    }
}
