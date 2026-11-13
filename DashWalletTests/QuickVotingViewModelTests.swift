//
//  QuickVotingViewModelTests.swift
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

/// «Vote for all»: keys first, then the sheet with its counts, then "One
/// vote left" for the names getting their last vote, then the run (AC-18).
@MainActor
final class QuickVotingViewModelTests: XCTestCase {
    private final class Host: QuickVotingHosting {
        var isVotingSetUp = true
        var tickedNodeIDs: Set<Data> = [Data([1])]
        var shownContests: [DPNSContest] = []
        var history: [String: [CastVoteRecord]] = [:]
        private(set) var historyReloads = 0
        /// What the reload answers: `false` is a store that could not be read.
        var historyReadable = true
        var nodeListMayMissNodes = false
        var showsOnlyRequestsWithLinks = false
        private(set) var nodeListReports = 0
        private(set) var attemptsStarted = 0
        private(set) var planned: [[String]] = []
        private(set) var started: [QuickVotePlan] = []

        func reloadVoteHistory() async -> Bool {
            historyReloads += 1
            return historyReadable
        }

        func quickVotingWillStart() { attemptsStarted += 1 }

        func reportNodeListMayMissNodes() { nodeListReports += 1 }

        func quickVotePlan(for shown: [DPNSContest]) -> QuickVotePlan {
            planned.append(shown.map(\.normalizedLabel))
            return QuickVotePlan(
                contests: shown, tickedNodes: tickedNodeIDs,
                closedLabels: [], now: Date(timeIntervalSince1970: 1_762_765_200),
                history: { [history] in VoteLimit(history[$0] ?? []) })
        }

        func username(of normalizedLabel: String) -> String { normalizedLabel.uppercased() }

        func startQuickVoting(_ plan: QuickVotePlan) { started.append(plan) }
    }

    private let nine = Date(timeIntervalSince1970: 1_762_765_200)

    private func contest(_ label: String, dates: [Date?]) -> DPNSContest {
        DPNSContest(
            normalizedLabel: label, endTime: Date(timeIntervalSince1970: 1_800_000_000), hasWinner: false,
            abstainVotes: 0, lockVotes: 0,
            contenders: dates.enumerated().map {
                DPNSContender(identityId: "\(label)-\($0.offset + 1)", voteTally: 0, createdAt: $0.element)
            })
    }

    private func fourCasts(on label: String) -> [CastVoteRecord] {
        [CastVoteRecord(proTxHash: Data([1]), normalizedLabel: label, choice: .abstain, castAt: nine,
                        castCount: VoteLimit.maxCastsPerNode - 1)]
    }

    func testVotingNotSetUpAsksForTheKeysBeforeTheSheet() async {
        let host = Host()
        host.isVotingSetUp = false
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertEqual(quick.step, .addKeys)
        XCTAssertTrue(host.planned.isEmpty, "no plan before voting is set up")
    }

    func testTheTapClearsTheLastVotesToastBeforeAnythingElse() async {
        let host = Host()
        host.isVotingSetUp = false
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertEqual(host.attemptsStarted, 1, "the last toast goes at the tap, even before the keys")
        await quick.start()
        XCTAssertEqual(host.attemptsStarted, 1, "a tap while a step is up starts nothing")
    }

    func testNoTickedNodeAsksForTheKeysToo() async {
        let host = Host()
        host.tickedNodeIDs = []
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertEqual(quick.step, .addKeys)
    }

    func testTheKeysVoteButtonOpensTheSheetAndClosingThemEndsIt() async {
        let host = Host()
        host.isVotingSetUp = false
        host.shownContests = [contest("alice", dates: [nine])]
        let quick = QuickVotingViewModel(host: host)
        await quick.start()

        host.isVotingSetUp = true
        await quick.finishKeys(continueToVote: true)
        XCTAssertEqual(quick.step, .confirm)

        quick.cancel()
        host.isVotingSetUp = false
        await quick.start()
        await quick.finishKeys(continueToVote: false)
        XCTAssertNil(quick.step)
        XCTAssertTrue(host.started.isEmpty)
    }

    func testTheSheetCountsTheNamesOnScreenWithoutTheSkippedOnes() async {
        let host = Host()
        host.shownContests = [
            contest("alice", dates: [nine]), contest("bob", dates: [nine]), contest("tied", dates: [nine, nine]),
        ]
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertEqual(host.historyReloads, 1, "the plan reads today's vote history")
        XCTAssertEqual(host.planned, [["alice", "bob", "tied"]], "exactly the rows on screen")
        XCTAssertEqual(quick.step, .confirm)
        XCTAssertEqual(quick.votedCount, 2)
        XCTAssertEqual(quick.skippedCount, 1)
        XCTAssertTrue(quick.canVote)
    }

    func testAHistoryThatCannotBeReadOpensNoSheet() async {
        let host = Host()
        host.historyReadable = false
        host.shownContests = [contest("alice", dates: [nine])]
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertNil(quick.step, "voting is paused: no sheet to confirm")
        XCTAssertTrue(host.planned.isEmpty, "no plan on a stale history")
        quick.voteForAll()
        XCTAssertTrue(host.started.isEmpty)
    }

    /// AC-18: with "Only requests with links" on, the sheet says the linked
    /// request gets the approve.
    func testTheSheetSaysTheLinkedRequestWhenOnlyLinksAreShown() async {
        let host = Host()
        host.showsOnlyRequestsWithLinks = true
        host.shownContests = [contest("alice", dates: [nine])]
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertEqual(quick.step, .confirm)
        XCTAssertTrue(quick.approvesLinkedRequests)
        XCTAssertEqual(
            QuickVotingSheet.description(votedCount: 2, skippedCount: 0, approvesLinkedRequests: true),
            "By tapping Vote for all, you approve the linked request submitted first for 2 usernames.")
    }

    /// AC-20: the wallet's sync is not done, or the list may be incomplete,
    /// at the tap: no sheet, and the user is told why.
    func testANodeListThatMayMissNodesOpensNoSheetAndSaysWhy() async {
        let host = Host()
        host.nodeListMayMissNodes = true
        host.shownContests = [contest("alice", dates: [nine])]
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertNil(quick.step)
        XCTAssertTrue(host.planned.isEmpty)
        XCTAssertEqual(host.nodeListReports, 1)
    }

    func testNothingToVoteOffersCloseOnly() async {
        let host = Host()
        host.shownContests = [contest("tied", dates: [nine, nine])]
        let quick = QuickVotingViewModel(host: host)

        await quick.start()

        XCTAssertEqual(quick.step, .confirm)
        XCTAssertFalse(quick.canVote)
        quick.voteForAll()
        XCTAssertTrue(host.started.isEmpty)
    }

    func testVoteForAllStartsTheRunWhenNoNameGetsItsLastVote() async {
        let host = Host()
        host.shownContests = [contest("alice", dates: [nine])]
        let quick = QuickVotingViewModel(host: host)
        await quick.start()

        quick.voteForAll()

        XCTAssertEqual(host.started.map { $0.votes.map(\.normalizedLabel) }, [["alice"]])
        XCTAssertNil(quick.step)
    }

    func testNamesGettingTheirLastVoteAreAskedFirst() async {
        let host = Host()
        host.shownContests = [contest("alice", dates: [nine]), contest("bob", dates: [nine])]
        host.history = ["bob": fourCasts(on: "bob")]
        let quick = QuickVotingViewModel(host: host)
        await quick.start()

        quick.voteForAll()

        XCTAssertEqual(quick.step, .lastVotes(usernames: ["BOB"]))
        XCTAssertTrue(host.started.isEmpty)
        quick.confirmLastVotes()
        XCTAssertEqual(host.started.count, 1)
        XCTAssertNil(quick.step)
    }

    func testCancelOnOneVoteLeftStopsTheWholeRun() async {
        let host = Host()
        host.shownContests = [contest("alice", dates: [nine]), contest("bob", dates: [nine])]
        host.history = ["bob": fourCasts(on: "bob")]
        let quick = QuickVotingViewModel(host: host)
        await quick.start()
        quick.voteForAll()

        quick.cancel()

        XCTAssertNil(quick.step)
        XCTAssertTrue(host.started.isEmpty, "nothing is sent")
        quick.confirmLastVotes()
        XCTAssertTrue(host.started.isEmpty)
    }
}
