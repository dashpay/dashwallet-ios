//
//  VoteAttemptCoordinatorTests.swift
//  DashWalletTests
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

@testable import dashpay
import SwiftDashSDK
import XCTest

// MARK: - FakeVoteAttemptHost

@MainActor
private final class FakeVoteAttemptHost: VoteAttemptHosting {
    var isVotingSetUp = true
    var tickedNodeIDs: Set<Data> = []
    var closedLabels: Set<String> = []
    var history = VoteLimit([])
    private(set) var historyReads = 0
    struct Sent {
        let choice: VoteChoice
        let nodes: Set<Data>
        var label = ""
        var pill: VoteChoice?
        var skipped: Set<Data> = []
    }

    /// Holds every history read until ``releaseHistory()``, as a read queued
    /// behind a running list refresh does.
    var holdsHistory = false
    private var heldReads: [CheckedContinuation<Void, Never>] = []

    func releaseHistory() {
        holdsHistory = false
        heldReads.forEach { $0.resume() }
        heldReads = []
    }

    private(set) var sends: [Sent] = []
    private(set) var endedReports: [String] = []
    /// What the host saw, in order: "start" for an attempt starting, "history" for a gate read.
    private(set) var events: [String] = []

    func attemptWillStart(on contest: DPNSContest) {
        events.append("start")
    }

    func isClosed(normalizedLabel: String) -> Bool { closedLabels.contains(normalizedLabel) }

    func voteHistory(for normalizedLabel: String) async -> VoteLimit {
        historyReads += 1
        events.append("history")
        if holdsHistory {
            await withCheckedContinuation { heldReads.append($0) }
        }
        return history
    }

    func send(
        _ choice: VoteChoice, on contest: DPNSContest, from nodeIDs: Set<Data>, skipped: Set<Data>, pill: VoteChoice
    ) async {
        sends.append(Sent(choice: choice, nodes: nodeIDs, label: contest.normalizedLabel, pill: pill, skipped: skipped))
    }

    func reportVotingEnded(on contest: DPNSContest) {
        endedReports.append(contest.normalizedLabel)
    }

    private(set) var historyUnavailableReports = 0
    private(set) var alreadyVotedReports: [String] = []

    func reportAlreadyVoted(on contest: DPNSContest) {
        alreadyVotedReports.append(contest.normalizedLabel)
    }

    func reportHistoryUnavailable() {
        historyUnavailableReports += 1
    }
}

// MARK: - VoteAttemptCoordinatorTests

/// The vote attempt as the screens run it: one dialog at a time, nothing sent
/// on Cancel or OK, and the gates restarted from the top after the key flow.
@MainActor
final class VoteAttemptCoordinatorTests: XCTestCase {
    private let nodeA = Data([0xA1])
    private let nodeB = Data([0xB2])
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var host: FakeVoteAttemptHost!
    private var coordinator: VoteAttemptCoordinator!

    override func setUp() async throws {
        host = FakeVoteAttemptHost()
        host.tickedNodeIDs = [nodeA, nodeB]
        let now = now
        coordinator = VoteAttemptCoordinator(host: host, now: { now })
    }

    private func contest(endsAt end: Date? = nil) -> DPNSContest {
        DPNSContest(normalizedLabel: "johndoe", endTime: end, hasWinner: false,
                    abstainVotes: 0, lockVotes: 0, contenders: [])
    }

    private func lastVoteHistory() -> VoteLimit {
        VoteLimit([nodeA, nodeB].map {
            CastVoteRecord(proTxHash: $0, normalizedLabel: "johndoe", choice: .abstain,
                           castAt: now.addingTimeInterval(-60), castCount: 4)
        })
    }

    // MARK: Dialog sequence (AC-15, AC-16, AC-16b)

    func testBlockOnTheLastVoteShowsOneVoteLeftThenLockIsFinalThenSends() async {
        host.history = lastVoteHistory()

        await coordinator.start(.vote(.lock), on: contest())
        XCTAssertEqual(coordinator.presentation, .oneVoteLeft)

        await coordinator.confirm(.oneVoteLeft)
        XCTAssertEqual(coordinator.presentation, .confirmBlock(username: "johndoe", isLastVote: true))
        XCTAssertTrue(host.sends.isEmpty)

        await coordinator.confirm(.confirmBlock(username: "johndoe", isLastVote: true))
        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(host.sends.count, 1)
        XCTAssertEqual(host.sends.first?.choice, .lock)
        XCTAssertEqual(host.sends.first?.nodes, [nodeA, nodeB])
        XCTAssertFalse(coordinator.isRunning)
    }

    /// The host hears of the attempt at the tap, before the gates read
    /// anything or show a dialog, so the last vote toast goes then (AC-06).
    func testStartTellsTheHostBeforeTheGates() async {
        host.history = lastVoteHistory()

        await coordinator.start(.vote(.lock), on: contest())

        XCTAssertEqual(host.events, ["start", "history"])
        XCTAssertEqual(coordinator.presentation, .oneVoteLeft)
    }

    /// A tap while an attempt runs is ignored, and tells the host nothing.
    func testStartWhileRunningTellsTheHostNothing() async {
        host.history = lastVoteHistory()
        await coordinator.start(.vote(.lock), on: contest())

        await coordinator.start(.vote(.lock), on: contest())

        XCTAssertEqual(host.events.filter { $0 == "start" }.count, 1)
    }

    /// AC-16b: the attempt runs from the tap. A second tap while the first
    /// still waits for its history read is ignored, and the first sends on
    /// its own contest.
    func testASecondTapWhileTheFirstReadsHistoryIsIgnored() async {
        host.holdsHistory = true
        let first = Task { await coordinator.start(.vote(.towards(identityId: "c1")), on: contest()) }
        while host.historyReads == 0 { await Task.yield() }

        XCTAssertTrue(coordinator.isRunning)
        let other = DPNSContest(normalizedLabel: "janedoe", endTime: nil, hasWinner: false,
                                abstainVotes: 0, lockVotes: 0, contenders: [])
        let second = Task { await coordinator.start(.vote(.abstain), on: other) }
        await Task.yield()
        host.releaseHistory()
        await first.value
        await second.value

        XCTAssertEqual(host.events.filter { $0 == "start" }.count, 1)
        XCTAssertEqual(host.sends.map(\.label), ["johndoe"])
        XCTAssertEqual(host.sends.first?.choice, .towards(identityId: "c1"))
        XCTAssertFalse(coordinator.isRunning)
    }

    /// A dismiss while the history is still being read ends the attempt: the
    /// read that comes back later shows nothing and sends nothing.
    func testDismissWhileReadingHistoryEndsTheAttempt() async {
        host.holdsHistory = true
        host.history = lastVoteHistory()
        let first = Task { await coordinator.start(.vote(.lock), on: contest()) }
        while host.historyReads == 0 { await Task.yield() }

        coordinator.dismiss()
        host.releaseHistory()
        await first.value

        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    /// AC-15: with the vote limit unknown nothing is sent, and the user is told why.
    func testUnreadableHistoryIsReportedAndNothingIsSent() async {
        host.history = VoteLimit(nil)

        await coordinator.start(.vote(.lock), on: contest())

        XCTAssertEqual(host.historyUnavailableReports, 1)
        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testApproveWithVotesToSpareSendsWithoutADialog() async {
        await coordinator.start(.vote(.towards(identityId: "contender-1")), on: contest())

        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(host.sends.count, 1)
    }

    /// AC-15: the ticked masternode with no vote left is handed to the host
    /// with the send, so the outcome can name it.
    func testTheSendNamesTheMasternodeSkippedForNoVotesLeft() async {
        host.history = VoteLimit([
            CastVoteRecord(proTxHash: nodeA, normalizedLabel: "johndoe", choice: .abstain,
                           castAt: now.addingTimeInterval(-60), castCount: 5),
        ])

        await coordinator.start(.vote(.towards(identityId: "contender-1")), on: contest())

        XCTAssertEqual(host.sends.first?.nodes, [nodeB])
        XCTAssertEqual(host.sends.first?.skipped, [nodeA])
    }

    func testCancelOnOneVoteLeftSendsNothing() async {
        host.history = lastVoteHistory()
        await coordinator.start(.vote(.lock), on: contest())

        coordinator.dismiss()

        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testCancelOnLockIsFinalSendsNothing() async {
        await coordinator.start(.vote(.lock), on: contest())
        XCTAssertEqual(coordinator.presentation, .confirmBlock(username: "johndoe", isLastVote: false))

        coordinator.dismiss()

        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testOKOnNoVotesLeftSendsNothing() async {
        host.history = VoteLimit([nodeA, nodeB].map {
            CastVoteRecord(proTxHash: $0, normalizedLabel: "johndoe", choice: .lock, castAt: now, castCount: 5)
        })
        await coordinator.start(.vote(.towards(identityId: "contender-1")), on: contest())
        XCTAssertEqual(coordinator.presentation, .noVotesLeft)

        coordinator.dismiss()

        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testConfirmWithoutADialogDoesNothing() async {
        await coordinator.confirm(.oneVoteLeft)
        XCTAssertTrue(host.sends.isEmpty)
    }

    /// A second tap on "One vote left"'s button lands after the lock-is-final
    /// dialog replaced it: it must not confirm that dialog unseen.
    func testAConfirmMeantForAnEarlierDialogChangesNothing() async {
        host.history = lastVoteHistory()
        await coordinator.start(.vote(.lock), on: contest())
        await coordinator.confirm(.oneVoteLeft)
        XCTAssertEqual(coordinator.presentation, .confirmBlock(username: "johndoe", isLastVote: true))

        await coordinator.confirm(.oneVoteLeft)

        XCTAssertEqual(coordinator.presentation, .confirmBlock(username: "johndoe", isLastVote: true))
        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertTrue(coordinator.isRunning)
    }

    // MARK: Voting ended (AC-03)

    func testAnEndedContestIsReportedAndNothingIsSent() async {
        await coordinator.start(.vote(.lock), on: contest(endsAt: now.addingTimeInterval(-1)))

        XCTAssertEqual(host.endedReports, ["johndoe"])
        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(host.sends.isEmpty)
    }

    func testAContestPlatformClosedCountsAsEnded() async {
        host.closedLabels = ["johndoe"]

        await coordinator.start(.vote(.lock), on: contest())

        XCTAssertEqual(host.endedReports, ["johndoe"])
        XCTAssertTrue(host.sends.isEmpty)
    }

    // MARK: Keys (AC-12, AC-16b)

    func testNotSetUpAsksForKeysWithTheTappedChoice() async {
        host.isVotingSetUp = false

        await coordinator.start(.vote(.lock), on: contest())

        XCTAssertEqual(coordinator.presentation, .addKeys(.lock))
        XCTAssertTrue(host.sends.isEmpty)
    }

    func testRetryAfterKeysRestartsTheGatesFromTheTop() async {
        host.isVotingSetUp = false
        await coordinator.start(.vote(.lock), on: contest())

        // Keys added; the masternodes turn out to be on their last vote.
        host.isVotingSetUp = true
        host.history = lastVoteHistory()
        coordinator.finishKeys(continueToVote: true)
        XCTAssertNil(coordinator.presentation, "the keys sheet goes before the next dialog")
        await coordinator.presentationDismissed()

        XCTAssertEqual(coordinator.presentation, .oneVoteLeft)
        XCTAssertGreaterThanOrEqual(host.historyReads, 2, "the history is read again after the keys")
    }

    func testRetryAfterKeysMayStopAtNoVotesLeft() async {
        host.isVotingSetUp = false
        await coordinator.start(.vote(.towards(identityId: "contender-1")), on: contest())

        host.isVotingSetUp = true
        host.history = VoteLimit([nodeA, nodeB].map {
            CastVoteRecord(proTxHash: $0, normalizedLabel: "johndoe", choice: .lock, castAt: now, castCount: 5)
        })
        coordinator.finishKeys(continueToVote: true)
        await coordinator.presentationDismissed()

        XCTAssertEqual(coordinator.presentation, .noVotesLeft)
        XCTAssertTrue(host.sends.isEmpty)
    }

    /// AC-12, AC-14b: before setup no pill is filled, so a tap may ask for a
    /// vote the ticked masternodes already hold. After the keys nothing is
    /// sent, and the user is told so instead of the sheet just closing.
    func testAVoteTheTicksAlreadyHoldIsToldAfterTheKeys() async {
        host.isVotingSetUp = false
        await coordinator.start(.vote(.lock), on: contest())
        XCTAssertEqual(coordinator.presentation, .addKeys(.lock))

        host.isVotingSetUp = true
        host.history = VoteLimit([nodeA, nodeB].map {
            CastVoteRecord(proTxHash: $0, normalizedLabel: "johndoe", choice: .lock, castAt: now, castCount: 1)
        })
        coordinator.finishKeys(continueToVote: true)
        await coordinator.presentationDismissed()

        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertEqual(host.alreadyVotedReports, ["johndoe"])
        XCTAssertFalse(coordinator.isRunning)
    }

    /// A cancel with no holder left has nothing to take back and stays silent.
    func testACancelWithNoHolderSendsNothingAndSaysNothing() async {
        host.history = VoteLimit([])

        await coordinator.start(.cancel(.lock), on: contest())

        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertTrue(host.alreadyVotedReports.isEmpty)
    }

    func testKeyFlowClosedWithoutVotingEndsTheAttempt() async {
        host.isVotingSetUp = false
        await coordinator.start(.vote(.lock), on: contest())

        coordinator.finishKeys(continueToVote: false)
        await coordinator.presentationDismissed()

        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(host.sends.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    // MARK: Cancel (AC-17)

    func testCancelSendsAbstainFromTheHoldersWithoutLockIsFinal() async {
        host.history = VoteLimit([
            CastVoteRecord(proTxHash: nodeA, normalizedLabel: "johndoe", choice: .lock, castAt: now, castCount: 1),
        ])

        await coordinator.start(.cancel(.lock), on: contest())

        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(host.sends.first?.choice, .abstain)
        XCTAssertEqual(host.sends.first?.nodes, [nodeA])
        XCTAssertEqual(host.sends.first?.pill, .lock, "the filled pill tapped shows the send, not abstain")
    }

    /// AC-05: a vote sends from the pill it was tapped on.
    func testAVoteSendsFromThePillTapped() async {
        await coordinator.start(.vote(.towards(identityId: "contender-1")), on: contest())

        XCTAssertEqual(host.sends.first?.pill, .towards(identityId: "contender-1"))
    }

    // MARK: One attempt at a time

    func testASecondStartWhileADialogIsUpIsIgnored() async {
        await coordinator.start(.vote(.lock), on: contest())
        XCTAssertEqual(coordinator.presentation, .confirmBlock(username: "johndoe", isLastVote: false))

        await coordinator.start(.vote(.towards(identityId: "contender-1")), on: contest())

        XCTAssertEqual(coordinator.presentation, .confirmBlock(username: "johndoe", isLastVote: false))
        XCTAssertTrue(host.sends.isEmpty)
    }
}
