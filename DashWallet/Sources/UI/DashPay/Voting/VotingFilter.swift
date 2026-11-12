//
//  VotingFilter.swift
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
import SwiftDashSDK

// MARK: - ContestSort

/// The order of contests inside each "Voting ends …" day of the voting list.
///
/// A contest's date is its first request's: voting ends a fixed period after
/// it, so the date orders follow `endTime`.
enum ContestSort: String, CaseIterable, Identifiable {
    case dateNewToOld
    case dateOldToNew
    case votesHighToLow
    case votesLowToHigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateNewToOld: return NSLocalizedString("Date: New to old", comment: "Voting")
        case .dateOldToNew: return NSLocalizedString("Date: Old to new", comment: "Voting")
        case .votesHighToLow: return NSLocalizedString("Votes: High to low", comment: "Voting")
        case .votesLowToHigh: return NSLocalizedString("Votes: Low to high", comment: "Voting")
        }
    }
}

// MARK: - VotingTypeFilter

/// Which names the list keeps, by this wallet's own vote or by the tallies.
enum VotingTypeFilter: String, CaseIterable, Identifiable {
    case all
    /// This wallet's last vote on the name is towards one of its contenders.
    case approved
    /// This wallet has no vote on the name.
    case notVoted
    /// Anyone has voted to block the name.
    case hasBlockedVotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return NSLocalizedString("All", comment: "Voting")
        case .approved: return NSLocalizedString("I have approved", comment: "Voting")
        case .notVoted: return NSLocalizedString("I have not voted", comment: "Voting")
        case .hasBlockedVotes: return NSLocalizedString("Has blocked votes", comment: "Voting")
        }
    }

    /// Whether the type depends on this wallet's own votes.
    var readsMyVotes: Bool {
        switch self {
        case .approved, .notVoted: return true
        case .all, .hasBlockedVotes: return false
        }
    }

    /// Whether `contest` passes, given the choices this wallet holds on it;
    /// `nil` when those are not known, which the types by my vote leave out.
    func includes(_ contest: DPNSContest, myChoices: Set<VoteChoice>?) -> Bool {
        switch self {
        case .all:
            return true
        case .approved:
            return myChoices?.contains { choice in
                if case .towards = choice { return true }
                return false
            } ?? false
        case .notVoted:
            // No record, or abstain only: neither blocks nor approves.
            return myChoices?.allSatisfy { $0 == .abstain } ?? false
        case .hasBlockedVotes:
            return contest.lockVotes > 0
        }
    }
}

// MARK: - VotingFilter

/// What the voting list shows and in which order.
struct VotingFilter: Equatable {
    var sort: ContestSort
    var type: VotingTypeFilter
    /// Only names requested by more than one identity.
    var onlyDuplicates: Bool

    /// The header's name for what the list holds: the type, and the
    /// duplicates switch when it is on (the bottom bar names the order).
    var title: String {
        guard onlyDuplicates else { return type.title }
        return String(format: NSLocalizedString("%@ · only duplicates", comment: "Voting: filter type, then the duplicates switch"), type.title)
    }

    /// Everything, oldest request first.
    static let `default` = VotingFilter(sort: .dateOldToNew, type: .all, onlyDuplicates: false)

    /// `contests` narrowed by type and duplicates, then ordered. `myChoices`
    /// gives this wallet's choices on a contest, `nil` when they are unknown.
    ///
    /// Every order is stable: names that tie keep the order `contests` came
    /// in. A contest whose end is unknown goes last in both date orders.
    func apply(to contests: [DPNSContest], myChoices: (String) -> Set<VoteChoice>?) -> [DPNSContest] {
        let kept = contests.filter { contest in
            (!onlyDuplicates || contest.contenders.count > 1)
                && type.includes(contest, myChoices: type.readsMyVotes ? myChoices(contest.normalizedLabel) : nil)
        }
        switch sort {
        case .dateOldToNew:
            return Self.stableSorted(kept) { Self.ends($0, before: $1) }
        case .dateNewToOld:
            return Self.stableSorted(kept) { Self.ends($1, before: $0, unknownLast: false) }
        case .votesHighToLow:
            return Self.stableSorted(kept) { $0.totalVotes > $1.totalVotes }
        case .votesLowToHigh:
            return Self.stableSorted(kept) { $0.totalVotes < $1.totalVotes }
        }
    }

    /// Whether `lhs` ends before `rhs`. An unknown end counts as the latest
    /// when `unknownLast`, as the earliest otherwise, so a reversed comparison
    /// still puts it last.
    private static func ends(_ lhs: DPNSContest, before rhs: DPNSContest, unknownLast: Bool = true) -> Bool {
        switch (lhs.endTime, rhs.endTime) {
        case let (lhs?, rhs?): return lhs < rhs
        case (_?, nil): return unknownLast
        case (nil, _?): return !unknownLast
        case (nil, nil): return false
        }
    }

    private static func stableSorted(
        _ contests: [DPNSContest],
        by areInIncreasingOrder: (DPNSContest, DPNSContest) -> Bool
    ) -> [DPNSContest] {
        contests.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
