//
//  VoteLimitTests.swift
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

/// The per-masternode vote history and the five-vote limit, as pure values.
final class VoteLimitTests: XCTestCase {

    private let nodeA = Data([0xA1])
    private let nodeB = Data([0xB2])
    private let nodeC = Data([0xC3])
    private let approve = VoteChoice.towards(identityId: "contender-1")
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(_ node: Data, _ choice: VoteChoice, casts: Int, at offset: TimeInterval = 0) -> CastVoteRecord {
        CastVoteRecord(
            proTxHash: node, normalizedLabel: "johndoe", choice: choice,
            castAt: epoch.addingTimeInterval(offset), castCount: casts)
    }

    func testCeilingIsFive() {
        XCTAssertEqual(VoteLimit.maxCastsPerNode, 5)
    }

    func testVotesLeftByCastCount() {
        let table: [(casts: Int, left: Int)] = [(1, 4), (3, 2), (4, 1), (5, 0)]
        for row in table {
            let limit = VoteLimit([record(nodeA, .lock, casts: row.casts)])
            XCTAssertEqual(limit.votesLeft(nodeA), row.left, "casts \(row.casts)")
            XCTAssertEqual(limit.fewestVotesLeft(among: [nodeA]), row.left, "casts \(row.casts)")
        }
    }

    func testAbstainCountsTowardsTheLimit() {
        let limit = VoteLimit([record(nodeA, .abstain, casts: 5)])
        XCTAssertEqual(limit.votesLeft(nodeA), 0)
    }

    func testNodeWithoutRowHasFiveLeftAndNoChoice() {
        let limit = VoteLimit([record(nodeA, .lock, casts: 2)])
        XCTAssertEqual(limit.votesLeft(nodeB), 5)
        XCTAssertEqual(limit.filledChoices(of: [nodeB]), [])
        XCTAssertEqual(limit.nodes(holding: .lock, among: [nodeB]), [])
    }

    func testFewestLeftFollowsTheMostSpentNode() {
        let limit = VoteLimit([record(nodeA, .lock, casts: 4), record(nodeB, .lock, casts: 1)])
        XCTAssertEqual(limit.fewestVotesLeft(among: [nodeA, nodeB]), 1)
        XCTAssertEqual(limit.fewestVotesLeft(among: [nodeB]), 4)
        XCTAssertEqual(limit.fewestVotesLeft(among: [nodeB, nodeC]), 4)
    }

    func testNoVotesLeftOnlyWhenEveryNodeIsSpent() {
        let limit = VoteLimit([record(nodeA, .lock, casts: 5), record(nodeB, .lock, casts: 2)])
        XCTAssertEqual(limit.nodesWithVotesLeft(among: [nodeA, nodeB]), [nodeB])
        XCTAssertEqual(limit.nodesWithVotesLeft(among: [nodeA]), [])
    }

    func testTwoNodesWithDifferentChoicesAreBothReported() {
        let limit = VoteLimit([record(nodeA, .lock, casts: 1), record(nodeB, approve, casts: 1)])
        XCTAssertEqual(limit.filledChoices(of: [nodeA, nodeB]), [.lock, approve])
        XCTAssertEqual(limit.filledChoices(of: [nodeB]), [approve])
        XCTAssertEqual(limit.nodes(holding: approve, among: [nodeA, nodeB]), [nodeB])
        XCTAssertEqual(limit.nodes(holding: .lock, among: [nodeA, nodeB]), [nodeA])
    }

    func testAbstainOnlyIsNotAFilledPillButStillHeld() {
        let limit = VoteLimit([record(nodeA, .abstain, casts: 2)])
        XCTAssertEqual(limit.filledChoices(of: [nodeA]), [])
        XCTAssertEqual(limit.nodes(holding: .abstain, among: [nodeA]), [nodeA])
    }

    func testLatestRecordOfANodeWins() {
        let limit = VoteLimit([record(nodeA, .lock, casts: 2, at: 0), record(nodeA, approve, casts: 3, at: 10)])
        XCTAssertEqual(limit.filledChoices(of: [nodeA]), [approve])
        XCTAssertEqual(limit.votesLeft(nodeA), 2)
    }

    func testRecordCastSpendsOneAndChangesTheChoice() {
        var limit = VoteLimit([record(nodeA, approve, casts: 3)])
        limit.recordCast(of: nodeA, on: "johndoe", choice: .abstain, at: epoch)
        XCTAssertEqual(limit.votesLeft(nodeA), 1)
        XCTAssertEqual(limit.filledChoices(of: [nodeA]), [])
    }

    /// An older cast merged onto a newer row spends one but keeps the newer choice.
    func testRecordCastOlderThanTheLiveChoiceSpendsOneButKeepsTheChoice() {
        var limit = VoteLimit([record(nodeA, approve, casts: 2, at: 10)])
        limit.recordCast(of: nodeA, on: "johndoe", choice: .lock, at: epoch)
        XCTAssertEqual(limit.votesLeft(nodeA), 2)
        XCTAssertEqual(limit.liveChoice(of: nodeA), approve)
    }

    func testUnknownHistoryIsUnknownNotNoVotes() {
        let limit = VoteLimit(nil)
        XCTAssertFalse(limit.isKnown)
        XCTAssertNil(limit.votesLeft(nodeA))
        XCTAssertNil(limit.fewestVotesLeft(among: [nodeA]))
        XCTAssertNil(limit.filledChoices(of: [nodeA]))
        XCTAssertNil(limit.nodes(holding: approve, among: [nodeA]))
        XCTAssertNil(limit.nodesWithVotesLeft(among: [nodeA]))
    }

    func testEmptyKnownHistoryIsKnown() {
        let limit = VoteLimit([])
        XCTAssertTrue(limit.isKnown)
        XCTAssertEqual(limit.votesLeft(nodeA), 5)
    }
}
