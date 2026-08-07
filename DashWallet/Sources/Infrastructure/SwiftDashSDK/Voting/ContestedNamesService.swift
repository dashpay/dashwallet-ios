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

        var errorDescription: String? {
            switch self {
            case .sdkUnavailable:
                return NSLocalizedString(
                    "Dash Platform is not connected yet. Wait for syncing to finish and try again.",
                    comment: "Voting")
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
    /// (`Alice` → `a11ce`). Returns the input lowercased if the SDK is not up,
    /// which is only used for local search filtering.
    func normalizedLabel(for label: String) -> String {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            return SDK.locallyNormalizedLabel(label)
        }
        return sdk.dpnsNormalizeLabel(label)
    }
}
