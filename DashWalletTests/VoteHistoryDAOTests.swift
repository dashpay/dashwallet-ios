//
//  VoteHistoryDAOTests.swift
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

import SQLite
import XCTest
@testable import dashpay

/// `VoteHistoryDAOImpl` against an in-memory database: the upsert raises
/// `castCount`, and a failed write throws instead of being logged away.
final class VoteHistoryDAOTests: XCTestCase {

    private let network = "testnet"
    private let label = "johndoe"
    private let node = Data([0xA1, 0xB2])
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// The two vote-history migrations, applied in version order from the host
    /// app's own `Migrations.bundle`, so the schema cannot drift from the app's.
    private static let migrationFiles = [
        "20260808030000_add_masternode_vote_history",
        "20260922120000_vote_history_cast_count",
    ]

    private func makeConnection(createTable: Bool = true) throws -> Connection {
        let connection = try Connection(.inMemory)
        guard createTable else { return connection }
        let bundle = DatabaseConnection.migrationsBundle()
        for name in Self.migrationFiles {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "sql"), name)
            try connection.execute(String(contentsOf: url, encoding: .utf8))
        }
        return connection
    }

    private func vote(_ choice: VoteChoice, at offset: TimeInterval = 0) -> CastVoteRecord {
        CastVoteRecord(proTxHash: node, normalizedLabel: label, choice: choice,
                       castAt: epoch.addingTimeInterval(offset))
    }

    func testRepeatedRecordRaisesCastCountAndKeepsOneRow() async throws {
        let dao = VoteHistoryDAOImpl(connection: try makeConnection())

        try await dao.record(vote(.towards(identityId: "c1")), network: network)
        try await dao.record(vote(.lock, at: 10), network: network)
        try await dao.record(vote(.abstain, at: 20), network: network)

        let rows = await dao.votes(forContest: label, network: network)
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(rows?.first?.castCount, 3)
        XCTAssertEqual(rows?.first?.choice, .abstain)
    }

    /// A vote recorded before `castCount` existed counts as one cast after
    /// the upgrade, and later votes on the same contest add to it.
    func testUpgradeCountsAnExistingVoteOnceAndReplacementsAccumulate() async throws {
        let connection = try makeConnection(createTable: false)
        let bundle = DatabaseConnection.migrationsBundle()
        let sql = { (name: String) throws -> String in
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "sql"), name)
            return try String(contentsOf: url, encoding: .utf8)
        }
        try connection.execute(sql(Self.migrationFiles[0]))
        try connection.run(
            """
            INSERT INTO masternode_vote_history
                (proTxHash, normalizedLabel, network, choice, contenderIdentityId, castAt)
            VALUES (?, ?, ?, 'abstain', NULL, 1)
            """,
            [Blob(bytes: [UInt8](node)), label, network] as [Binding?])
        try connection.execute(sql(Self.migrationFiles[1]))

        let dao = VoteHistoryDAOImpl(connection: connection)
        let upgraded = await dao.votes(forContest: label, network: network)
        XCTAssertEqual(upgraded?.map(\.castCount), [1], "an existing row is one cast")

        let choices: [VoteChoice] = [.lock, .abstain, .towards(identityId: "c1"), .lock]
        for (index, choice) in choices.enumerated() {
            try await dao.record(vote(choice, at: TimeInterval(10 + index)), network: network)
        }

        let rows = await dao.votes(forContest: label, network: network)
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(rows?.first?.castCount, 5)
        XCTAssertEqual(rows?.first?.choice, .lock, "the row holds the latest vote")
    }

    /// On a fresh store a node's first vote is one cast, and the whole-list
    /// read the voting screen uses returns it.
    func testAFreshStoreStartsEachNodeAtOneCast() async throws {
        let dao = VoteHistoryDAOImpl(connection: try makeConnection())

        try await dao.record(vote(.abstain), network: network)

        let rows = await dao.votes(forContest: label, network: network)
        XCTAssertEqual(rows?.map(\.castCount), [1])
        let listed = await dao.votes(forContests: [label, "other"], network: network)
        XCTAssertEqual(listed?.map(\.normalizedLabel), [label])
        XCTAssertEqual(listed?.map(\.castCount), [1])
    }

    func testRecordThrowsWhenTheWriteFails() async throws {
        let dao = VoteHistoryDAOImpl(connection: try makeConnection(createTable: false))

        do {
            try await dao.record(vote(.lock), network: network)
            XCTFail("record must throw when the write fails")
        } catch {
            // expected
        }
    }
}
