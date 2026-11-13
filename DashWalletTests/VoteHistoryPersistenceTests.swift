//
//  VoteHistoryPersistenceTests.swift
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
        XCTAssertEqual(stored?.count, 1)
        XCTAssertEqual(stored?.first?.castCount, 5)
        XCTAssertEqual(stored?.first?.choice, .lock, "the row holds the latest vote")
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
        XCTAssertEqual(stored?.map(\.castCount), [1])
        // The list reads every contest's history in one query; it sees the same row.
        let listed = await dao.votes(forContests: [label, "other"], network: network)
        XCTAssertEqual(listed?.map(\.normalizedLabel), [label])
        XCTAssertEqual(listed?.map(\.castCount), [1])
        let unlisted = await dao.votes(forContests: ["other"], network: network)
        XCTAssertEqual(unlisted?.isEmpty, true)
    }
}
