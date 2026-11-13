//
//  VoteAttemptTests.swift
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
import XCTest

/// The gate order of one vote attempt (AC-03, AC-12, AC-15, AC-16, AC-16b, AC-17),
/// one row per gate combination.
final class VoteAttemptTests: XCTestCase {
    private let nodeA = Data([0xA1])
    private let nodeB = Data([0xB2])
    private let approve = VoteChoice.towards(identityId: "contender-1")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var future: Date { now.addingTimeInterval(3600) }
    private var past: Date { now.addingTimeInterval(-1) }

    /// One node's record: `casts` spent here, `choice` its live vote (abstain when not given).
    private func cast(_ node: Data, _ choice: VoteChoice = .abstain, casts: Int) -> CastVoteRecord {
        CastVoteRecord(
            proTxHash: node, normalizedLabel: "johndoe", choice: choice,
            castAt: now.addingTimeInterval(-60), castCount: casts)
    }

    private func history(_ records: CastVoteRecord...) -> VoteLimit {
        VoteLimit(records)
    }

    private func attempt(
        _ intent: VoteAttempt.Intent,
        endsAt: Date? = nil,
        setUp: Bool = true,
        ticked: Set<Data>? = nil,
        history: VoteLimit = VoteLimit([])
    ) -> VoteAttempt {
        VoteAttempt(
            intent: intent,
            votingEndsAt: endsAt,
            isVotingSetUp: setUp,
            tickedNodes: ticked ?? [nodeA, nodeB],
            history: history,
            now: now)
    }

    /// Accepts every confirmation in turn and returns the steps seen, ending at the first non-confirmation.
    private func run(_ attempt: VoteAttempt) -> [VoteAttempt.Step] {
        var attempt = attempt
        var steps = [attempt.step]
        while attempt.step == .confirmLastVote || attempt.step == .confirmBlock {
            attempt.confirm()
            steps.append(attempt.step)
        }
        return steps
    }

    // MARK: First stopper wins (AC-16b)

    func testEndedContestStopsBeforeEverythingElse() {
        let attempt = attempt(.vote(.lock), endsAt: past, setUp: false, history: VoteLimit(nil))
        XCTAssertEqual(attempt.step, .votingEnded)
    }

    func testVotingEndingExactlyNowCountsAsEnded() {
        XCTAssertEqual(attempt(.vote(approve), endsAt: now).step, .votingEnded)
    }

    func testUnknownVotingEndStillAllowsTheVote() {
        XCTAssertEqual(attempt(.vote(approve), endsAt: nil).step, .send(approve, [nodeA, nodeB]))
    }

    func testNotSetUpAsksForKeysEvenWhenNoVotesAreLeft() {
        let spent = history(cast(nodeA, .lock, casts: 5), cast(nodeB, .lock, casts: 5))
        XCTAssertEqual(attempt(.vote(approve), setUp: false, history: spent).step, .needsKeys)
    }

    func testNoTickedMasternodeAsksForKeys() {
        XCTAssertEqual(attempt(.vote(approve), ticked: []).step, .needsKeys)
    }

    func testUnreadableHistoryStopsTheVote() {
        XCTAssertEqual(attempt(.vote(approve), history: VoteLimit(nil)).step, .historyUnavailable)
    }

    func testNoTickedMasternodeWithAVoteLeftIsNoVotesLeft() {
        let spent = history(cast(nodeA, .lock, casts: 5), cast(nodeB, .lock, casts: 5))
        XCTAssertEqual(attempt(.vote(approve), history: spent).step, .noVotesLeft)
    }

    // MARK: Confirmations, one after another (AC-15, AC-16, AC-16b)

    func testBlockAsksLockIsFinalThenSends() {
        XCTAssertEqual(run(attempt(.vote(.lock))), [.confirmBlock, .send(.lock, [nodeA, nodeB])])
    }

    func testApproveWithVotesToSpareSendsAtOnce() {
        XCTAssertEqual(run(attempt(.vote(approve))), [.send(approve, [nodeA, nodeB])])
    }

    func testLastVoteAsksOneVoteLeftThenSends() {
        let fourEach = history(cast(nodeA, casts: 4), cast(nodeB, casts: 4))
        XCTAssertEqual(
            run(attempt(.vote(approve), history: fourEach)),
            [.confirmLastVote, .send(approve, [nodeA, nodeB])])
    }

    func testBlockOnTheLastVoteAsksOneVoteLeftThenLockIsFinalThenSends() {
        let fourEach = history(cast(nodeA, casts: 4), cast(nodeB, casts: 4))
        XCTAssertEqual(
            run(attempt(.vote(.lock), history: fourEach)),
            [.confirmLastVote, .confirmBlock, .send(.lock, [nodeA, nodeB])])
    }

    /// The block dialog knows a last vote, so it does not offer to take it back.
    func testABlockOnTheLastVoteIsALastVote() {
        XCTAssertTrue(attempt(.vote(.lock), history: history(cast(nodeA, casts: 4), cast(nodeB, casts: 1))).isLastVote)
        XCTAssertFalse(attempt(.vote(.lock), history: history(cast(nodeA, casts: 3), cast(nodeB, casts: 1))).isLastVote)
    }

    func testOneVoteLeftFollowsTheMasternodeWithTheFewestVotesLeft() {
        let mixed = history(cast(nodeA, casts: 4), cast(nodeB, casts: 1))
        XCTAssertEqual(attempt(.vote(approve), history: mixed).step, .confirmLastVote)
    }

    func testAnExhaustedMasternodeIsSkippedWhileTheOtherVotes() {
        let mixed = history(cast(nodeA, casts: 5), cast(nodeB, casts: 3))
        XCTAssertEqual(run(attempt(.vote(approve), history: mixed)), [.send(approve, [nodeB])])
    }

    /// AC-15: the masternode skipped for having no vote left is named, so
    /// the outcome can say it did not vote.
    func testAnExhaustedMasternodeIsNamedAsSkipped() {
        let mixed = history(cast(nodeA, casts: 5), cast(nodeB, casts: 3))
        XCTAssertEqual(attempt(.vote(approve), history: mixed).skippedForNoVotesLeft, [nodeA])
        XCTAssertEqual(attempt(.vote(approve)).skippedForNoVotesLeft, [])
    }

    /// AC-17 with AC-15: both ticked masternodes approve, one has no vote
    /// left. Only the other abstains, and the spent one is named as skipped.
    func testMixedLimitCancelNamesTheHolderWithNoVoteLeft() {
        let bothApprove = history(cast(nodeA, approve, casts: 5), cast(nodeB, approve, casts: 1))
        let cancel = attempt(.cancel(approve), history: bothApprove)
        XCTAssertEqual(cancel.step, .send(.abstain, [nodeB]))
        XCTAssertEqual(cancel.skippedForNoVotesLeft, [nodeA])
    }

    func testTheSkippedMasternodeDoesNotTriggerOneVoteLeft() {
        // nodeA has none left and is skipped; nodeB, the one sending, has 2.
        let mixed = history(cast(nodeA, casts: 5), cast(nodeB, casts: 3))
        XCTAssertNotEqual(attempt(.vote(approve), history: mixed).step, .confirmLastVote)
    }

    func testConfirmOutsideAConfirmationChangesNothing() {
        var attempt = attempt(.vote(approve))
        attempt.confirm()
        XCTAssertEqual(attempt.step, .send(approve, [nodeA, nodeB]))
    }

    // MARK: Who sends (AC-14b)

    func testAMasternodeAlreadyHoldingTheChoiceIsLeftOut() {
        let oneHolds = history(cast(nodeA, approve, casts: 1))
        XCTAssertEqual(attempt(.vote(approve), history: oneHolds).step, .send(approve, [nodeB]))
    }

    func testAMasternodeHoldingAnotherChoiceChangesItsVote() {
        let blocked = history(cast(nodeA, .lock, casts: 1))
        XCTAssertEqual(attempt(.vote(approve), history: blocked).step, .send(approve, [nodeA, nodeB]))
    }

    func testEveryTickedMasternodeHoldingTheChoiceHasNothingToSend() {
        let allHold = history(cast(nodeA, approve, casts: 1), cast(nodeB, approve, casts: 2))
        XCTAssertEqual(attempt(.vote(approve), history: allHold).step, .nothingToSend)
    }

    // MARK: Cancel = abstain from the holders (AC-17)

    func testCancelSendsAbstainFromTheHoldersOnly() {
        let oneHolds = history(cast(nodeA, .lock, casts: 1), cast(nodeB, approve, casts: 1))
        XCTAssertEqual(run(attempt(.cancel(.lock), history: oneHolds)), [.send(.abstain, [nodeA])])
    }

    func testCancellingABlockHasNoLockIsFinal() {
        let bothBlock = history(cast(nodeA, .lock, casts: 1), cast(nodeB, .lock, casts: 1))
        XCTAssertEqual(attempt(.cancel(.lock), history: bothBlock).step, .send(.abstain, [nodeA, nodeB]))
    }

    func testCancelOnTheLastVoteAsksOneVoteLeftThenSends() {
        let lastVote = history(cast(nodeA, approve, casts: 4))
        XCTAssertEqual(
            run(attempt(.cancel(approve), history: lastVote)),
            [.confirmLastVote, .send(.abstain, [nodeA])])
    }

    func testCancelByAHolderWithNoVotesLeftIsNoVotesLeft() {
        let spent = history(cast(nodeA, approve, casts: 5))
        XCTAssertEqual(attempt(.cancel(approve), history: spent).step, .noVotesLeft)
    }

    func testCancelWithNoTickedHolderHasNothingToSend() {
        let otherHolds = history(cast(nodeA, .lock, casts: 1))
        XCTAssertEqual(attempt(.cancel(approve), history: otherHolds).step, .nothingToSend)
    }

    func testCancelPassesTheVotingEndedGate() {
        let holds = history(cast(nodeA, approve, casts: 1))
        XCTAssertEqual(attempt(.cancel(approve), endsAt: past, history: holds).step, .votingEnded)
    }
}
