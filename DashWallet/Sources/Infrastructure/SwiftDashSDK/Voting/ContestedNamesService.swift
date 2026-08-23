//
//  ContestedNamesService.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import OSLog
import SwiftDashSDK

// MARK: - ContestedNamesService

/// The voter's read side of DPNS username contests: every open contest on the
/// network, and the detailed state of one contest.
///
/// Distinct from `DWContestedNameStatusService`, which tracks *this device's*
/// pending contested submission. That one answers "is my name still being
/// voted on"; this one answers "what can I vote on".
///
/// Every call hits Platform — vote tallies, the contender set and resolution
/// all move throughout a contest, so nothing here is cached. Callers that want
/// history persist it themselves.
@MainActor
final class ContestedNamesService {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.voting")

    /// Ceiling on the active-contest listing. The FFI exposes no cursor on
    /// this query, so this is a hard cap rather than a page size. DPNS
    /// typically has tens of open contests; the cap is logged if hit so a
    /// truncated list is never mistaken for a complete one.
    private static let activeContestLimit: UInt32 = 500

    init() {}

    enum ServiceError: LocalizedError {
        case sdkUnavailable
        case labelNotNormalizable(String)

        var errorDescription: String? {
            switch self {
            case .sdkUnavailable:
                return NSLocalizedString(
                    "Dash Platform is not connected yet. Wait for syncing to finish and try again.",
                    comment: "Voting")
            case .labelNotNormalizable(let label):
                return String(format: NSLocalizedString(
                    "“%@” could not be read as a Dash username.",
                    comment: "Voting"), label)
            }
        }
    }

    private func requireSDK() throws -> SDK {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            throw ServiceError.sdkUnavailable
        }
        return sdk
    }

    /// Every open DPNS username contest, with contenders, tallies and end time.
    ///
    /// Ordered by soonest deadline first, so the contests a voter can still
    /// affect — and has least time to act on — lead the list. Contests with no
    /// reported end time sort last.
    func activeContests() async throws -> [DPNSContest] {
        let sdk = try requireSDK()
        let contests = try sdk.dpnsActiveContests(limit: Self.activeContestLimit)

        if contests.count >= Int(Self.activeContestLimit) {
            Self.logger.warning(
                "🗳️ VOTING :: active-contest listing hit the \(Self.activeContestLimit, privacy: .public) cap; the list may be truncated")
        }
        Self.logger.info("🗳️ VOTING :: fetched \(contests.count, privacy: .public) active contests")

        return contests.sorted { lhs, rhs in
            switch (lhs.endTime, rhs.endTime) {
            case let (left?, right?):
                return left == right ? lhs.normalizedLabel < rhs.normalizedLabel : left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return lhs.normalizedLabel < rhs.normalizedLabel
            }
        }
    }

    /// Detailed vote state for one contest, including whether it resolved.
    ///
    /// - Parameter normalizedLabel: A label from ``activeContests()`` (already
    ///   normalized) or the output of ``normalizedLabel(for:)``.
    /// - Returns: `nil` when Platform holds no contenders for the label —
    ///   never contested, or the poll has been pruned since it resolved.
    func voteState(normalizedLabel: String) async throws -> DPNSContestVoteState? {
        let sdk = try requireSDK()
        return try sdk.dpnsContestVoteState(normalizedLabel: normalizedLabel)
    }

    /// Whether a vote cast right now on `normalizedLabel` can still be
    /// accepted. Used as a pre-flight so a closed poll fails immediately
    /// instead of after a long broadcast retry.
    func contestIsOpen(normalizedLabel: String) async throws -> Bool {
        let sdk = try requireSDK()
        return try sdk.dpnsContestIsOpen(normalizedLabel: normalizedLabel)
    }

    /// Homograph-normalize a user-typed label into the form Platform indexes
    /// (`Alice` → `a11ce`).
    ///
    /// Normalization is protocol behavior owned by Rust, so there is no
    /// app-side fallback: a second copy of the mapping would drift from the
    /// canonical one. `nil` means "could not normalize" — the caller decides
    /// what that means for it, rather than getting a plausible-looking
    /// substitute.
    func normalizedLabel(for label: String) -> String? {
        try? requireNormalizedLabel(for: label)
    }

    /// Throwing variant, for callers that show the reason.
    ///
    /// The two failures are genuinely different — Platform not being reachable
    /// is a wait-and-retry, a label Rust refuses to normalize is not — so they
    /// are reported separately instead of collapsing into "not connected".
    func requireNormalizedLabel(for label: String) throws -> String {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            throw ServiceError.sdkUnavailable
        }
        do {
            return try sdk.dpnsNormalizeLabel(label)
        } catch {
            throw ServiceError.labelNotNormalizable(label)
        }
    }
}

// MARK: - Contender display

extension DPNSContender {
    /// Truncated base58 identity, e.g. `5rTJhbA…9Xk2Qd`.
    ///
    /// The identifying fallback for a contender whose `domain` document could
    /// not be decoded, so their own spelling of the label is unknown. Shared by
    /// the contest detail rows and the request-status rows so the two never
    /// drift apart.
    var shortIdentityId: String {
        guard identityId.count > 16 else { return identityId }
        return String(identityId.prefix(8)) + "…" + String(identityId.suffix(6))
    }
}

// MARK: - Contest display

extension DPNSContest {
    /// What to put in front of the user as the contest's name.
    ///
    /// Platform keys contests by the homograph-normalized label (`p1zza`),
    /// which reads as a typo to the people who typed `pizza`. Contenders carry
    /// their own spelling, so show that instead — and when they disagree, show
    /// each one, since the disagreement is the whole point of the contest.
    ///
    /// Falls back to the normalized label when no contender document could be
    /// decoded. Never reverse-engineered from the normalized form: `0`→`o` and
    /// `1`→`i`/`l` are ambiguous, so guessing would invent a name nobody asked
    /// for.
    var displayTitle: String {
        let labels = requestedLabels
        guard !labels.isEmpty else { return normalizedLabel }
        return labels.joined(separator: NSLocalizedString(" or ", comment: "Voting"))
    }

    /// `true` when ``displayTitle`` differs from ``normalizedLabel``, so the
    /// UI knows whether the normalized form still needs showing alongside.
    var displayTitleDiffersFromNormalized: Bool {
        displayTitle != normalizedLabel
    }
}

extension DPNSContender {
    /// The contender's own spelling, or their truncated identity when the
    /// document could not be decoded.
    var displayNameOrIdentity: String {
        displayLabel ?? shortIdentityId
    }
}
