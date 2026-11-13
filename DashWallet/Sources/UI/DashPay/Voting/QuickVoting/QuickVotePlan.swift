//
//  QuickVotePlan.swift
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

// MARK: - QuickVotePlan

/// What Quick voting does with the names on screen: per name,
/// the request it approves and the ticked masternodes that send, or why the
/// name is skipped (AC-18, AC-19, AC-20).
///
/// Pure: it reads the contests as shown (only their shown requests), the
/// ticked and wallet masternodes, which names are closed, the time and each
/// contest's vote history, and calls nothing.
///
/// Its own gate chain rather than ``VoteAttempt``'s: a deviation recorded in
/// ADR-0035. It checks what the vote gates check, in their order — voting
/// ended, history known, votes left — over many names at once.
struct QuickVotePlan: Equatable {
    /// One name's approve.
    struct Vote: Equatable {
        let normalizedLabel: String
        /// The request submitted first among the shown ones.
        let identityId: String
        /// The ticked masternodes that send: each has a vote left and approves
        /// no request of the name yet.
        let nodes: Set<Data>
        /// The vote is the last one for at least one of ``nodes``.
        let isLastVote: Bool
    }

    /// Why a name gets no vote.
    enum SkipReason: Equatable {
        /// Platform closed it, or its voting end has passed (AC-03).
        case votingEnded
        /// A masternode of this wallet, ticked or not, blocked it.
        case blocked
        /// Its voting end is unknown.
        case unknownVotingEnd
        /// A shown request has no request date, so the first one cannot be told.
        case undatedRequest
        /// The two earliest requests have the same date to the millisecond.
        case tiedFirstRequests
        /// The last read of its requests may have stopped at Platform's page
        /// size, so the first request may not be among them.
        case requestsMayBeCut
        /// The vote history could not be read, so the vote limit cannot be checked.
        case historyUnknown
        /// No ticked masternode has a vote left without replacing an approve.
        case nothingToSend
    }

    struct Skip: Equatable {
        let normalizedLabel: String
        let reason: SkipReason
    }

    /// In the order the names were shown.
    let votes: [Vote]
    let skipped: [Skip]

    /// The names where this vote is the last one for a sending masternode,
    /// for "One vote left" before the run.
    var lastVoteLabels: [String] {
        votes.filter(\.isLastVote).map(\.normalizedLabel)
    }

    /// - Parameters:
    ///   - contests: the names on screen, each with only its shown requests.
    ///   - tickedNodes: the masternodes that vote.
    ///   - closedLabels: names Platform was seen to close.
    ///   - requestsMayBeCut: names whose requests may not all have been read.
    ///   - now: names whose voting end is not after it have ended.
    ///   - history: each contest's vote history.
    init(
        contests: [DPNSContest],
        tickedNodes: Set<Data>,
        closedLabels: Set<String>,
        requestsMayBeCut: Set<String> = [],
        now: Date,
        history: (_ normalizedLabel: String) -> VoteLimit
    ) {
        var votes: [Vote] = []
        var skipped: [Skip] = []
        for contest in contests {
            if closedLabels.contains(contest.normalizedLabel) || contest.endTime.map({ $0 <= now }) == true {
                skipped.append(Skip(normalizedLabel: contest.normalizedLabel, reason: .votingEnded))
                continue
            }
            if requestsMayBeCut.contains(contest.normalizedLabel) {
                skipped.append(Skip(normalizedLabel: contest.normalizedLabel, reason: .requestsMayBeCut))
                continue
            }
            switch Self.plan(contest, tickedNodes: tickedNodes,
                             history: history(contest.normalizedLabel)) {
            case .success(let vote): votes.append(vote)
            case .failure(let skip): skipped.append(Skip(normalizedLabel: contest.normalizedLabel, reason: skip.reason))
            }
        }
        self.votes = votes
        self.skipped = skipped
    }

    private struct SkipError: Error {
        let reason: SkipReason
    }

    private static func plan(
        _ contest: DPNSContest, tickedNodes: Set<Data>, history: VoteLimit
    ) -> Result<Vote, SkipError> {
        guard contest.endTime != nil else { return .failure(SkipError(reason: .unknownVotingEnd)) }
        guard history.isKnown else { return .failure(SkipError(reason: .historyUnknown)) }
        // A block by any masternode of this wallet keeps the name out, ticked
        // or not, votable today or not (a banned node, a removed key): this
        // device's history holds only this wallet's votes (a wipe clears it).
        if history.anyNode(holding: .lock) == true {
            return .failure(SkipError(reason: .blocked))
        }
        let first: DPNSContender
        switch firstRequest(of: contest) {
        case .success(let request): first = request
        case .failure(let skip): return .failure(skip)
        }

        let senders = tickedNodes.filter { node in
            guard (history.votesLeft(node) ?? 0) > 0 else { return false }
            if case .towards = history.liveChoice(of: node) { return false }
            return true
        }
        guard !senders.isEmpty else { return .failure(SkipError(reason: .nothingToSend)) }
        return .success(Vote(
            normalizedLabel: contest.normalizedLabel,
            identityId: first.identityId,
            nodes: senders,
            isLastVote: history.fewestVotesLeft(among: senders) == 1))
    }

    /// The request with the earliest date, compared to the millisecond as
    /// Android does; none when a request has no date or two share the earliest.
    private static func firstRequest(of contest: DPNSContest) -> Result<DPNSContender, SkipError> {
        var dated: [(request: DPNSContender, millisecond: Int64)] = []
        for request in contest.contenders {
            guard let date = request.createdAt else { return .failure(SkipError(reason: .undatedRequest)) }
            dated.append((request, Int64((date.timeIntervalSince1970 * 1000).rounded())))
        }
        let ordered = dated.sorted { $0.millisecond < $1.millisecond }
        guard let first = ordered.first else { return .failure(SkipError(reason: .nothingToSend)) }
        if ordered.count > 1, ordered[1].millisecond == first.millisecond {
            return .failure(SkipError(reason: .tiedFirstRequests))
        }
        return .success(first.request)
    }
}
