//
//  VoteAttemptCoordinator.swift
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

// MARK: - VoteAttemptHosting

/// What a vote attempt reads and does outside itself.
@MainActor
protocol VoteAttemptHosting: AnyObject {
    /// Whether this wallet can vote at all; `false` sends the attempt to the keys.
    var isVotingSetUp: Bool { get }
    /// The masternodes the user votes with.
    var tickedNodeIDs: Set<Data> { get }
    /// An attempt starts at the tap, before any gate or dialog.
    func attemptWillStart(on contest: DPNSContest)
    /// Platform said this contest is closed, whatever its end time says.
    func isClosed(normalizedLabel: String) -> Bool
    /// The contest's vote history, read now; `VoteLimit(nil)` when it cannot be read.
    func voteHistory(for normalizedLabel: String) async -> VoteLimit
    /// Cast `choice` from these masternodes; the outcome is the host's to show.
    /// `skipped` are the ticked masternodes the vote concerns that have no vote
    /// left: nothing is sent from them, and the outcome names them.
    /// `pill` is the pill the tap was on, which shows progress while it sends.
    func send(
        _ choice: VoteChoice, on contest: DPNSContest, from nodeIDs: Set<Data>, skipped: Set<Data>, pill: VoteChoice
    ) async
    /// Tell the user that voting on this contest has ended (AC-03).
    func reportVotingEnded(on contest: DPNSContest)
    /// Tell the user the vote stopped because the vote history could not be read.
    func reportHistoryUnavailable()
    /// Tell the user every ticked masternode already holds this vote, so
    /// nothing was sent.
    func reportAlreadyVoted(on contest: DPNSContest)
}

// MARK: - VoteAttemptCoordinator

/// Runs one ``VoteAttempt`` at a time: presents its step through
/// ``presentation``, advances on ``confirm(_:)``, stops on ``dismiss()``,
/// and sends when every gate has passed
/// (`docs/adr/0035-run-every-vote-through-a-pure-vote-attempt-state-machine.md`).
///
/// The dialogs replace each other in place. The keys flow is a sheet, so the
/// attempt waits for it to be gone (``presentationDismissed()``) before the
/// gates run again from the top.
@MainActor
final class VoteAttemptCoordinator: ObservableObject {
    /// The one thing on screen for the running attempt.
    enum Presentation: Hashable, Identifiable {
        /// SCR-07: the last vote on this name.
        case oneVoteLeft
        /// SCR-08: no ticked masternode has a vote left.
        case noVotesLeft
        /// SCR-09: a block is final once block wins.
        case confirmBlock(username: String, isLastVote: Bool)
        /// "Add your voting keys"; its button repeats this choice.
        case addKeys(VoteChoice)

        var id: Self { self }
    }

    @Published private(set) var presentation: Presentation?

    /// An attempt has started and has not ended yet.
    var isRunning: Bool { running != nil }

    private let host: VoteAttemptHosting
    private let now: () -> Date
    /// Set at the tap, before any await, and cleared when the attempt ends; a
    /// gate run that resumes under another token belongs to an ended attempt.
    private var running: UUID?
    private var attempt: VoteAttempt?
    private var contest: DPNSContest?
    /// Set when the keys flow ended with its vote button: restart once the sheet is gone.
    private var restartAfterKeys = false

    init(host: VoteAttemptHosting, now: @escaping () -> Date = Date.init) {
        self.host = host
        self.now = now
    }

    /// Start a vote from a tap. Ignored while another attempt runs.
    func start(_ intent: VoteAttempt.Intent, on contest: DPNSContest) async {
        guard running == nil else { return }
        let token = UUID()
        running = token
        host.attemptWillStart(on: contest)
        self.contest = contest
        await runGates(intent, token: token)
    }

    /// The positive button of "One vote left" or the lock-is-final dialog.
    /// `expected` is the dialog the button belongs to: a tap that lands after
    /// its dialog was replaced does not confirm the next one.
    func confirm(_ expected: Presentation) async {
        guard var attempt, presentation == expected,
              presentation == .oneVoteLeft || isConfirmBlock(presentation)
        else { return }
        attempt.confirm()
        self.attempt = attempt
        await advance()
    }

    /// Cancel, OK, or a dialog dismissed: the attempt ends and nothing is sent.
    func dismiss() {
        end()
    }

    /// The keys flow is closing. With `continueToVote` its Block or Approve
    /// button was the next try, and the gates run again from the top once the
    /// sheet is gone (AC-12, AC-16b).
    func finishKeys(continueToVote: Bool) {
        guard case .addKeys = presentation else { return }
        restartAfterKeys = continueToVote
        presentation = nil
    }

    /// Call from the keys sheet's `onDismiss`.
    func presentationDismissed() async {
        guard let running, let attempt else { return }
        guard restartAfterKeys else {
            // Swiped away, or closed with back: the attempt ends.
            if presentation == nil { end() }
            return
        }
        restartAfterKeys = false
        await runGates(attempt.intent, token: running)
    }

    // MARK: Steps

    private func runGates(_ intent: VoteAttempt.Intent, token: UUID) async {
        guard let contest else { return }
        let label = contest.normalizedLabel
        let history = await host.voteHistory(for: label)
        // Dismissed while the history was being read: that attempt is over.
        guard running == token else { return }
        attempt = VoteAttempt(
            intent: intent,
            votingEndsAt: host.isClosed(normalizedLabel: label) ? now() : contest.endTime,
            isVotingSetUp: host.isVotingSetUp,
            tickedNodes: host.tickedNodeIDs,
            history: history,
            now: now())
        await advance()
    }

    private func advance() async {
        guard let attempt, let contest else { return }
        switch attempt.step {
        case .votingEnded:
            host.reportVotingEnded(on: contest)
            end()
        case .needsKeys:
            presentation = .addKeys(tappedChoice(for: attempt.intent))
        case .historyUnavailable:
            host.reportHistoryUnavailable()
            end()
        case .nothingToSend:
            // A vote every ticked masternode already holds is told; a cancel
            // with no holder left has nothing to take back and stays silent.
            if case .vote = attempt.intent { host.reportAlreadyVoted(on: contest) }
            end()
        case .noVotesLeft:
            presentation = .noVotesLeft
        case .confirmLastVote:
            presentation = .oneVoteLeft
        case .confirmBlock:
            presentation = .confirmBlock(username: contest.displayTitle, isLastVote: attempt.isLastVote)
        case .send(let choice, let nodes):
            presentation = nil
            end()
            await host.send(
                choice, on: contest, from: nodes, skipped: attempt.skippedForNoVotesLeft,
                pill: tappedChoice(for: attempt.intent))
        }
    }

    /// The pill the tap was on: the choice tapped, or the one being taken back.
    /// The keys flow's button repeats it.
    private func tappedChoice(for intent: VoteAttempt.Intent) -> VoteChoice {
        switch intent {
        case let .vote(choice), let .cancel(choice): return choice
        }
    }

    private func isConfirmBlock(_ presentation: Presentation?) -> Bool {
        if case .confirmBlock = presentation { return true }
        return false
    }

    private func end() {
        presentation = nil
        running = nil
        attempt = nil
        contest = nil
        restartAfterKeys = false
    }
}
