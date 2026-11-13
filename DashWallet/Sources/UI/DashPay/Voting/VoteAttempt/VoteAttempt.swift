//
//  VoteAttempt.swift
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

// MARK: - VoteAttempt

/// One run of the vote gates, from a tap to a send or a stop
/// (`docs/adr/0035-run-every-vote-through-a-pure-vote-attempt-state-machine.md`).
///
/// The gates come in a fixed order and only the first that stops the vote is
/// reported: the contest has ended → voting is not set up → the vote history
/// cannot be read → no ticked masternode has a vote left → "One vote left" →
/// the lock-is-final confirmation for a block → send (AC-16b). The
/// confirmations of one attempt come one after another: ``confirm()`` accepts
/// the current one and ``step`` moves to the next.
///
/// Pure: no SwiftUI, no SDK, `now` injected.
struct VoteAttempt {
    /// What the tap asked for.
    enum Intent: Hashable {
        /// Cast this choice from the ticked masternodes that do not hold it yet.
        case vote(VoteChoice)
        /// Take this choice back: abstain from the ticked masternodes that hold it (AC-17).
        case cancel(VoteChoice)
    }

    /// The one thing the attempt does next.
    enum Step: Equatable {
        /// The contest's voting end has passed (AC-03).
        case votingEnded
        /// Voting is not set up, or no masternode is ticked: "Add your voting keys" (AC-12).
        case needsKeys
        /// The vote history could not be read, so the vote limit is unknown.
        case historyUnavailable
        /// No masternode that would send has a vote left (AC-15).
        case noVotesLeft
        /// The sending masternode with the fewest votes left is on its last (AC-15).
        case confirmLastVote
        /// A block is final once the contest ends with block winning (AC-16).
        case confirmBlock
        /// A vote every ticked masternode already holds, or a cancel no ticked
        /// masternode holds. Set up, a held pill is filled and its tap starts
        /// `.cancel`; a vote still gets here when it was tapped before setup and
        /// the keys flow just set voting up, when the history read at the tap is
        /// newer than the pill, or on Try again.
        case nothingToSend
        /// Send `choice` from these masternodes (AC-14b).
        case send(VoteChoice, Set<Data>)
    }

    let intent: Intent
    let votingEndsAt: Date?
    let isVotingSetUp: Bool
    let tickedNodes: Set<Data>
    let history: VoteLimit
    let now: Date

    private var confirmedLastVote = false
    private var confirmedBlock = false

    init(
        intent: Intent,
        votingEndsAt: Date?,
        isVotingSetUp: Bool,
        tickedNodes: Set<Data>,
        history: VoteLimit,
        now: Date
    ) {
        self.intent = intent
        self.votingEndsAt = votingEndsAt
        self.isVotingSetUp = isVotingSetUp
        self.tickedNodes = tickedNodes
        self.history = history
        self.now = now
    }

    /// The choice that is sent: abstain when cancelling.
    var sentChoice: VoteChoice {
        switch intent {
        case .vote(let choice): return choice
        case .cancel: return .abstain
        }
    }

    var step: Step {
        // An unknown voting end does not stop the vote (AC-03b).
        if let votingEndsAt, votingEndsAt <= now { return .votingEnded }
        guard isVotingSetUp, !tickedNodes.isEmpty else { return .needsKeys }
        guard let candidates = candidates else { return .historyUnavailable }
        guard !candidates.isEmpty else { return .nothingToSend }
        guard let senders = history.nodesWithVotesLeft(among: candidates), !senders.isEmpty else {
            return .noVotesLeft
        }
        if !confirmedLastVote, history.fewestVotesLeft(among: senders) == 1 { return .confirmLastVote }
        if !confirmedBlock, sentChoice == .lock { return .confirmBlock }
        return .send(sentChoice, senders)
    }

    /// The vote ``step`` would send is the last one some of its nodes have
    /// here: after it, those nodes cannot take it back.
    var isLastVote: Bool {
        guard let candidates, let senders = history.nodesWithVotesLeft(among: candidates) else { return false }
        return history.fewestVotesLeft(among: senders) == 1
    }

    /// The masternodes this intent concerns that have no vote left: ``step``
    /// sends without them, and the outcome says so (AC-15).
    var skippedForNoVotesLeft: Set<Data> {
        guard let candidates, let senders = history.nodesWithVotesLeft(among: candidates) else { return [] }
        return candidates.subtracting(senders)
    }

    /// Accept the confirmation ``step`` is asking for; any other step is left as it is.
    mutating func confirm() {
        switch step {
        case .confirmLastVote: confirmedLastVote = true
        case .confirmBlock: confirmedBlock = true
        default: break
        }
    }

    /// The ticked masternodes this intent concerns, before the vote limit;
    /// `nil` when the history is unknown.
    private var candidates: Set<Data>? {
        switch intent {
        case .vote(let choice):
            guard let holders = history.nodes(holding: choice, among: tickedNodes) else { return nil }
            return tickedNodes.subtracting(holders)
        case .cancel(let held):
            return history.nodes(holding: held, among: tickedNodes)
        }
    }
}
