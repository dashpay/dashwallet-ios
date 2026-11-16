//
//  QuickVotePlanTests.swift
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

/// Which names Quick voting votes on, towards which request, from which
/// masternodes, and which it skips (AC-18, AC-19, AC-20).
final class QuickVotePlanTests: XCTestCase {
    private let a = Data([1]), b = Data([2]), untickedNode = Data([3])
    private let end = Date(timeIntervalSince1970: 1_800_000_000)
    /// 9:00 on a day, the first request of most names.
    private let nine = Date(timeIntervalSince1970: 1_762_765_200)

    private func contest(_ label: String, dates: [Date?], endKnown: Bool = true) -> DPNSContest {
        DPNSContest(
            normalizedLabel: label, endTime: endKnown ? end : nil, hasWinner: false, abstainVotes: 0, lockVotes: 0,
            contenders: dates.enumerated().map {
                DPNSContender(identityId: "\(label)-\($0.offset + 1)", voteTally: 0, createdAt: $0.element)
            })
    }

    private func record(_ node: Data, on label: String, _ choice: VoteChoice, casts: Int = 1) -> CastVoteRecord {
        CastVoteRecord(proTxHash: node, normalizedLabel: label, choice: choice, castAt: nine, castCount: casts)
    }

    private func plan(
        _ contests: [DPNSContest], ticked: Set<Data>? = nil, records: [CastVoteRecord] = [],
        unknownHistory: Set<String> = [], closed: Set<String> = [], cut: Set<String> = [], now: Date? = nil
    ) -> QuickVotePlan {
        QuickVotePlan(
            contests: contests,
            tickedNodes: ticked ?? [a, b],
            closedLabels: closed,
            requestsMayBeCut: cut,
            now: now ?? nine,
            history: { label in
                unknownHistory.contains(label)
                    ? VoteLimit(nil) : VoteLimit(records.filter { $0.normalizedLabel == label })
            })
    }

    /// A name whose requests may not all have been read is skipped: the
    /// first request may be among those not read (dashpay/platform#5876).
    func testANameWhoseRequestsMayBeCutIsSkipped() {
        let result = plan([contest("big", dates: [nine]), contest("small", dates: [nine])], cut: ["big"])

        XCTAssertEqual(skipReason(result, "big"), .requestsMayBeCut)
        XCTAssertEqual(result.votes.map(\.normalizedLabel), ["small"])
    }

    private func skipReason(_ plan: QuickVotePlan, _ label: String) -> QuickVotePlan.SkipReason? {
        plan.skipped.first { $0.normalizedLabel == label }?.reason
    }

    // MARK: Voting ended (AC-03)

    func testANameClosedByPlatformIsSkippedAsEnded() {
        let result = plan([contest("alice", dates: [nine]), contest("bob", dates: [nine])], closed: ["alice"])

        XCTAssertEqual(result.votes.map(\.normalizedLabel), ["bob"])
        XCTAssertEqual(skipReason(result, "alice"), .votingEnded)
    }

    func testANameKeptPastItsVotingEndIsSkippedAsEnded() {
        let result = plan([contest("alice", dates: [nine])], now: end)

        XCTAssertTrue(result.votes.isEmpty, "no vote once the voting end is reached")
        XCTAssertEqual(skipReason(result, "alice"), .votingEnded)
    }

    // MARK: Target request (AC-18, AC-20)

    func testEveryTickedNodeApprovesTheEarliestShownRequest() {
        let dates = [nine.addingTimeInterval(60), nine, nine.addingTimeInterval(120)]
        let result = plan([contest("johndoe", dates: dates)])

        XCTAssertEqual(result.votes.map(\.identityId), ["johndoe-2"])
        XCTAssertEqual(result.votes.first?.nodes, [a, b])
        XCTAssertTrue(result.skipped.isEmpty)
    }

    func testTheSameDayAtDifferentTimesIsNotATie() {
        let result = plan([contest("johndoe", dates: [nine.addingTimeInterval(6 * 3600), nine])])

        XCTAssertEqual(result.votes.map(\.identityId), ["johndoe-2"], "the 9:00 request is first")
    }

    func testTwoEarliestRequestsAtTheSameMillisecondAreATie() {
        let result = plan([
            contest("exact", dates: [nine, nine, nine.addingTimeInterval(3600)]),
            contest("submillisecond", dates: [nine, nine.addingTimeInterval(0.0004)]),
            contest("onemillisecond", dates: [nine.addingTimeInterval(0.001), nine]),
        ])

        XCTAssertEqual(skipReason(result, "exact"), .tiedFirstRequests)
        XCTAssertEqual(skipReason(result, "submillisecond"), .tiedFirstRequests, "compared to the millisecond")
        XCTAssertEqual(result.votes.map(\.identityId), ["onemillisecond-2"])
    }

    func testANameWithAnUndatedShownRequestIsSkipped() {
        let result = plan([contest("johndoe", dates: [nine, nil])])

        XCTAssertEqual(skipReason(result, "johndoe"), .undatedRequest, "the undated one may be first")
        XCTAssertTrue(result.votes.isEmpty)
    }

    func testANameWithAnUnknownVotingEndIsSkipped() {
        let result = plan([contest("johndoe", dates: [nine], endKnown: false)])

        XCTAssertEqual(skipReason(result, "johndoe"), .unknownVotingEnd)
    }

    // MARK: Per masternode (AC-19)

    func testANameAnyWalletNodeBlockedIsSkippedForAllEvenAnUntickedOne() {
        let result = plan([contest("johndoe", dates: [nine])], records: [record(untickedNode, on: "johndoe", .lock)])

        XCTAssertEqual(skipReason(result, "johndoe"), .blocked)
        XCTAssertTrue(result.votes.isEmpty)
    }

    /// A block by a node of this wallet that cannot vote any more (banned,
    /// or its key removed) still keeps the name out.
    func testABlockByANodeNoLongerVotableIsSkippedForAll() {
        let gone = Data([9])
        let result = plan([contest("johndoe", dates: [nine])], records: [record(gone, on: "johndoe", .lock)])

        XCTAssertEqual(skipReason(result, "johndoe"), .blocked)
        XCTAssertTrue(result.votes.isEmpty)
    }

    func testANodeThatApprovesAnyRequestOfTheNameSendsNothingThere() {
        let result = plan(
            [contest("johndoe", dates: [nine, nine.addingTimeInterval(60)])],
            records: [record(a, on: "johndoe", .towards(identityId: "johndoe-2"))])

        XCTAssertEqual(result.votes.first?.identityId, "johndoe-1", "towards the earliest, not the one a approves")
        XCTAssertEqual(result.votes.first?.nodes, [b], "an approve is never replaced")
    }

    func testANodeThatAlreadyApprovesTheEarliestRequestSendsNothing() {
        let result = plan(
            [contest("johndoe", dates: [nine])],
            records: [record(a, on: "johndoe", .towards(identityId: "johndoe-1"))])

        XCTAssertEqual(result.votes.first?.nodes, [b])
    }

    func testANodeHoldingOnlyAnAbstainStillVotes() {
        let result = plan([contest("johndoe", dates: [nine])], records: [record(a, on: "johndoe", .abstain)])

        XCTAssertEqual(result.votes.first?.nodes, [a, b])
    }

    func testANodeWithNoVotesLeftIsSkippedAndAnotherStillSends() {
        let result = plan(
            [contest("johndoe", dates: [nine])],
            records: [record(a, on: "johndoe", .abstain, casts: VoteLimit.maxCastsPerNode)])

        XCTAssertEqual(result.votes.first?.nodes, [b], "no node goes over the vote limit")
    }

    func testANameNoTickedNodeCanSendOnIsSkipped() {
        let result = plan(
            [contest("johndoe", dates: [nine])], ticked: [a],
            records: [record(a, on: "johndoe", .abstain, casts: VoteLimit.maxCastsPerNode)])

        XCTAssertEqual(skipReason(result, "johndoe"), .nothingToSend)
        XCTAssertTrue(result.votes.isEmpty)
    }

    func testANameWhoseHistoryIsUnknownIsSkipped() {
        let result = plan([contest("johndoe", dates: [nine])], unknownHistory: ["johndoe"])

        XCTAssertEqual(skipReason(result, "johndoe"), .historyUnknown, "the vote limit cannot be checked")
    }

    // MARK: Counts and the last vote (AC-18)

    func testCountsAndTheNamesGettingTheirLastVote() {
        let result = plan(
            [
                contest("last", dates: [nine]),
                contest("plenty", dates: [nine]),
                contest("tied", dates: [nine, nine]),
            ],
            records: [record(b, on: "last", .abstain, casts: VoteLimit.maxCastsPerNode - 1)])

        XCTAssertEqual(result.votes.map(\.normalizedLabel), ["last", "plenty"], "in the shown order")
        XCTAssertEqual(result.skipped.map(\.normalizedLabel), ["tied"])
        XCTAssertEqual(result.lastVoteLabels, ["last"], "b's fifth vote on «last»")
        XCTAssertEqual(result.votes.first?.isLastVote, true)
        XCTAssertEqual(result.votes.last?.isLastVote, false)
    }
}
