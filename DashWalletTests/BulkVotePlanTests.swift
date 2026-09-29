//
//  BulkVotePlanTests.swift
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

/// The bulk planner must apply the same five-cast ceiling as the single-contest
/// screen: the caster does not re-check it, so an exhausted node that reaches
/// the batch is broadcast and refused by Platform.
@MainActor
final class BulkVotePlanTests: XCTestCase {
    private let label = "a11ce"

    private func node(_ byte: UInt8) -> VoterNode {
        VoterNode(
            proTxHash: Data(repeating: byte, count: 32),
            isEvonode: false,
            typeIndex: UInt32(byte),
            serviceAddress: nil,
            keySource: .walletIndex(UInt32(byte)))
    }

    private func record(_ node: VoterNode, _ choice: VoteChoice, casts: Int) -> CastVoteRecord {
        CastVoteRecord(
            proTxHash: node.proTxHash,
            normalizedLabel: label,
            choice: choice,
            castAt: Date(timeIntervalSince1970: 1_800_000_000),
            castCount: casts)
    }

    func testExhaustedNodeWithDifferentPriorChoiceIsNotCastOrCountedAsReplacement() {
        let exhausted = node(1)
        let history = VotingViewModel.NodeVoteHistory([
            record(exhausted, .abstain, casts: VotingViewModel.maxCastsPerNodePerContest),
        ])

        let split = VotingViewModel.splitForBulk([exhausted], choice: .lock, history: history)

        XCTAssertTrue(split.casting.isEmpty, "An exhausted node must not reach the caster")
        XCTAssertEqual(split.exhausted, 1)
        XCTAssertEqual(split.changed, 0, "A vote that cannot be cast is not a replacement")
        XCTAssertTrue(split.replacedChoices.isEmpty)
        XCTAssertEqual(split.duplicates, 0)
    }

    func testExhaustedNodeAlreadyHoldingTheChoiceIsADuplicateNotExhausted() {
        let settled = node(1)
        let history = VotingViewModel.NodeVoteHistory([
            record(settled, .lock, casts: VotingViewModel.maxCastsPerNodePerContest),
        ])

        let split = VotingViewModel.splitForBulk([settled], choice: .lock, history: history)

        XCTAssertTrue(split.casting.isEmpty)
        XCTAssertEqual(split.duplicates, 1)
        XCTAssertEqual(split.exhausted, 0)
    }

    func testNodesWithCastsLeftAreCastAndChangesAreCounted() {
        let fresh = node(1)
        let changing = node(2)
        let exhausted = node(3)
        let history = VotingViewModel.NodeVoteHistory([
            record(changing, .abstain, casts: VotingViewModel.maxCastsPerNodePerContest - 1),
            record(exhausted, .abstain, casts: VotingViewModel.maxCastsPerNodePerContest),
        ])

        let split = VotingViewModel.splitForBulk(
            [fresh, changing, exhausted], choice: .lock, history: history)

        XCTAssertEqual(split.casting, [fresh, changing])
        XCTAssertEqual(split.changed, 1)
        XCTAssertEqual(split.replacedChoices, [.abstain])
        XCTAssertEqual(split.exhausted, 1)
        XCTAssertEqual(split.duplicates, 0)
    }
}
