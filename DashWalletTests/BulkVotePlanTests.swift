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
import SQLite
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

/// The five-cast ceiling counts casts, and the table keeps one row per node
/// and contest: the count lives in `castCount`, added by its own migration and
/// incremented by the upsert. Run against a private in-memory database built
/// from the app's own migration files.
final class VoteHistoryPersistenceTests: XCTestCase {
    private let label = "a11ce"
    private let network = "testnet"
    private let node = Data(repeating: 7, count: 32)

    private func migrationSQL(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            DatabaseConnection.migrationsBundle().url(forResource: name, withExtension: "sql"),
            "missing migration \(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func castCounts(_ db: Connection) throws -> [Int64] {
        try db.prepare("SELECT castCount FROM masternode_vote_history").compactMap { $0[0] as? Int64 }
    }

    func testUpgradeCountsAnExistingVoteOnceAndReplacementsAccumulate() async throws {
        let db = try Connection(.inMemory)
        try db.execute(migrationSQL("20260808030000_add_masternode_vote_history"))

        // A vote recorded before the column existed.
        try db.run(
            """
            INSERT INTO masternode_vote_history
                (proTxHash, normalizedLabel, network, choice, contenderIdentityId, castAt)
            VALUES (?, ?, ?, 'abstain', NULL, 1)
            """,
            [Blob(bytes: [UInt8](node)), label, network] as [Binding?])

        try db.execute(migrationSQL("20260922120000_vote_history_cast_count"))
        XCTAssertEqual(try castCounts(db), [1], "an existing row is at least one cast")

        // Four changes of mind through the persistence boundary.
        let dao = VoteHistoryDAOImpl(connection: db)
        let choices: [VoteChoice] = [.lock, .abstain, .towards(identityId: "contender"), .lock]
        for (index, choice) in choices.enumerated() {
            await dao.record(
                CastVoteRecord(
                    proTxHash: node, normalizedLabel: label, choice: choice,
                    castAt: Date(timeIntervalSince1970: Double(10 + index))),
                network: network)
        }

        XCTAssertEqual(try castCounts(db), [5], "one row, five casts")
        let stored = await dao.votes(forContest: label, network: network)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.castCount, 5)
        XCTAssertEqual(stored.first?.choice, .lock, "the row holds the latest vote")
    }

    func testAFreshStoreStartsEachNodeAtOneCast() async throws {
        let db = try Connection(.inMemory)
        try db.execute(migrationSQL("20260808030000_add_masternode_vote_history"))
        try db.execute(migrationSQL("20260922120000_vote_history_cast_count"))

        let dao = VoteHistoryDAOImpl(connection: db)
        await dao.record(
            CastVoteRecord(proTxHash: node, normalizedLabel: label, choice: .abstain, castAt: Date()),
            network: network)

        let stored = await dao.votes(forContest: label, network: network)
        XCTAssertEqual(stored.map(\.castCount), [1])
        let counts = await dao.voteCountsByContest(network: network)
        XCTAssertEqual(counts, [label: 1])
    }
}
