//
//  MasternodeVoteCasterTests.swift
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

@testable import dashpay
import SwiftDashSDK
import XCTest

/// The caster's own vote-limit guard (AC-15) and its handling of a failed
/// history write, through an injected `VoteHistoryDAO`.
///
/// Seams the production code must offer (the SDK call and the key derivation
/// cannot run in a unit test):
/// - `MasternodeVoteCaster.init(registry:contests:history:votingKey:send:)`
///   with `votingKey`/`send` defaulting to the registry and the SDK;
/// - `typealias VoteSender = (VoterNode, Data, VoteChoice, String) async throws -> Void`
///   (node, voting key, choice, normalizedLabel);
/// - the per-node loop reachable as an internal
///   `castAuthenticated(choice:onNormalizedLabel:with:) async -> VoteCastReport`.
@MainActor
final class MasternodeVoteCasterTests: XCTestCase {

    private let label = "johndoe"
    private let choice = VoteChoice.towards(identityId: "contender-1")

    private func node(_ byte: UInt8) -> VoterNode {
        VoterNode(proTxHash: Data([byte]), isEvonode: false, typeIndex: UInt32(byte),
                  serviceAddress: nil, keySource: .walletIndex(0))
    }

    private func record(_ node: VoterNode, casts: Int) -> CastVoteRecord {
        CastVoteRecord(proTxHash: node.proTxHash, normalizedLabel: label, choice: choice,
                       castAt: Date(timeIntervalSince1970: 1_700_000_000), castCount: casts)
    }

    private final class SendLog {
        var sentTo: [Data] = []
        var failFor: Set<Data> = []
    }

    private func makeCaster(history: FakeVoteHistory, log: SendLog) -> MasternodeVoteCaster {
        MasternodeVoteCaster(
            registry: MasternodeVoterRegistry(),
            contests: ContestedNamesService(),
            history: history,
            votingKey: { _ in Data(repeating: 1, count: 32) },
            send: { node, _, _, _ in
                if log.failFor.contains(node.proTxHash) { throw FakeSendError.refused }
                log.sentTo.append(node.proTxHash)
            })
    }

    private func run(_ caster: MasternodeVoteCaster, nodes: [VoterNode]) async -> VoteCastReport {
        await caster.castAuthenticated(choice: choice, onNormalizedLabel: label, with: nodes)
    }

    func testNodeAtTheLimitIsNeverCast() async {
        let a = node(0xA1)
        let history = FakeVoteHistory(records: [record(a, casts: VoteLimit.maxCastsPerNode)])
        let log = SendLog()

        let report = await run(makeCaster(history: history, log: log), nodes: [a])

        XCTAssertTrue(log.sentTo.isEmpty, "a node with no votes left must not be sent")
        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertFalse(report.outcomes[0].succeeded)
        XCTAssertTrue(report.outcomes[0].failure?.lowercased().contains("no votes left") ?? false,
                      "reason was \(report.outcomes[0].failure ?? "nil")")
    }

    func testNodeAtTheLimitIsSkippedWhileOthersCast() async {
        let a = node(0xA1), b = node(0xB2)
        let history = FakeVoteHistory(records: [
            record(a, casts: 5), record(b, casts: 4),
        ])
        let log = SendLog()

        let report = await run(makeCaster(history: history, log: log), nodes: [a, b])

        XCTAssertEqual(log.sentTo, [b.proTxHash])
        XCTAssertFalse(report.outcomes[0].succeeded)
        XCTAssertTrue(report.outcomes[1].succeeded)
        XCTAssertTrue(report.outcomes[1].historyRecorded)
    }

    /// The count is re-read before each node's cast; the node whose read
    /// fails is stopped, the others continue.
    func testUnreadableHistoryStopsTheNodeWithoutCasting() async {
        let a = node(0xA1), b = node(0xB2), c = node(0xC3)
        let history = FakeVoteHistory(records: [], failingReads: [1])  // b's read
        let log = SendLog()

        let report = await run(makeCaster(history: history, log: log), nodes: [a, b, c])

        XCTAssertEqual(history.reads, 3, "one read per node")
        XCTAssertFalse(log.sentTo.contains(b.proTxHash), "never cast on an unknown count")
        XCTAssertFalse(report.outcomes[1].succeeded)
        XCTAssertNotNil(report.outcomes[1].failure)
        XCTAssertEqual(log.sentTo, [a.proTxHash, c.proTxHash], "the other nodes continue")
    }

    /// A node's second cast reads the count its first one wrote.
    func testASecondCastReadsTheCountTheFirstWrote() async {
        let a = node(0xA1)
        let history = FakeVoteHistory(records: [record(a, casts: VoteLimit.maxCastsPerNode - 1)])
        let log = SendLog()
        let caster = makeCaster(history: history, log: log)

        _ = await run(caster, nodes: [a])
        let second = await run(caster, nodes: [a])

        XCTAssertEqual(log.sentTo, [a.proTxHash], "the fifth cast went out, the sixth did not")
        XCTAssertFalse(second.outcomes[0].succeeded)
        XCTAssertEqual(history.records.first?.castCount, VoteLimit.maxCastsPerNode)
        XCTAssertEqual(history.records.count, 1, "one row per node and contest")
    }

    func testFailedHistoryWriteKeepsTheVoteLanded() async {
        let a = node(0xA1)
        let history = FakeVoteHistory(records: [], recordThrows: true)
        let log = SendLog()

        let report = await run(makeCaster(history: history, log: log), nodes: [a])

        XCTAssertEqual(log.sentTo, [a.proTxHash])
        XCTAssertTrue(report.outcomes[0].succeeded, "Platform accepted the vote")
        XCTAssertFalse(report.outcomes[0].historyRecorded)
    }

    func testRecordedVoteIsFlaggedRecordedAndWritten() async {
        let a = node(0xA1)
        let history = FakeVoteHistory(records: [])
        let log = SendLog()

        let report = await run(makeCaster(history: history, log: log), nodes: [a])

        XCTAssertTrue(report.outcomes[0].succeeded)
        XCTAssertTrue(report.outcomes[0].historyRecorded)
        XCTAssertEqual(history.recorded.map(\.proTxHash), [a.proTxHash])
    }

    func testFailedCastIsNotRecordedAndOtherNodesStillCast() async {
        let a = node(0xA1), b = node(0xB2)
        let history = FakeVoteHistory(records: [])
        let log = SendLog()
        log.failFor = [a.proTxHash]

        let report = await run(makeCaster(history: history, log: log), nodes: [a, b])

        XCTAssertFalse(report.outcomes[0].succeeded)
        XCTAssertTrue(report.outcomes[1].succeeded)
        XCTAssertEqual(history.recorded.map(\.proTxHash), [b.proTxHash])
    }

    // MARK: Failure reasons are plain words, never Platform's text

    private func castFailing(with error: Error) async -> VoteOutcome {
        let a = node(0xA1)
        let caster = MasternodeVoteCaster(
            registry: MasternodeVoterRegistry(),
            contests: ContestedNamesService(),
            history: FakeVoteHistory(records: []),
            votingKey: { _ in Data(repeating: 1, count: 32) },
            send: { _, _, _, _ in throw error })
        return await run(caster, nodes: [a]).outcomes[0]
    }

    func testPlatformTooManyVotesRefusalIsStoredAsNoVotesLeft() async {
        let refusal = SDKError.consensusRejection(PlatformConsensusError(code: 40303, kind: .state), "RAW-PLATFORM-TEXT")

        let outcome = await castFailing(with: refusal)

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failure, "No votes left")
    }

    func testGenericSendErrorNeverStoresRawText() async {
        struct Odd: LocalizedError { var errorDescription: String? { "RAW-PLATFORM-TEXT odd" } }

        for error in [Odd() as Error, SDKError.internalError("RAW-PLATFORM-TEXT")] {
            let outcome = await castFailing(with: error)

            XCTAssertFalse(outcome.succeeded)
            XCTAssertEqual(outcome.failure, "The vote was not cast. Please try again.")
            XCTAssertFalse(outcome.failure?.contains("RAW-PLATFORM-TEXT") ?? true)
        }
    }
}

private enum FakeSendError: Error { case refused }
private enum FakeRecordError: Error { case disk }

private final class FakeVoteHistory: VoteHistoryDAO, @unchecked Sendable {
    var records: [CastVoteRecord]
    /// Which reads (0-based, in call order) answer `nil`. The read is per
    /// contest and carries no node, so the fake scripts calls, not nodes.
    let failingReads: Set<Int>
    private(set) var reads = 0
    let recordThrows: Bool
    private(set) var recorded: [CastVoteRecord] = []

    init(records: [CastVoteRecord], failingReads: Set<Int> = [], recordThrows: Bool = false) {
        self.records = records
        self.failingReads = failingReads
        self.recordThrows = recordThrows
    }

    func record(_ record: CastVoteRecord, network: String) async throws {
        if recordThrows { throw FakeRecordError.disk }
        recorded.append(record)
        // As the DAO: one row per node and contest, its count raised.
        let sameRow = { (row: CastVoteRecord) in
            row.proTxHash == record.proTxHash && row.normalizedLabel == record.normalizedLabel
        }
        let previous = records.first(where: sameRow)
        records.removeAll(where: sameRow)
        var row = record
        row.castCount = (previous?.castCount ?? 0) + 1
        records.append(row)
    }

    func votes(forContest normalizedLabel: String, network: String) async -> [CastVoteRecord]? {
        defer { reads += 1 }
        return failingReads.contains(reads) ? nil : records
    }

    func votes(forContests normalizedLabels: Set<String>, network: String) async -> [CastVoteRecord]? { records }
    func deleteAll() {}
}

// MARK: - MasternodeVoterRegistry.votingKeys

/// An imported voting key the keychain could not read is not a key that is
/// gone: the node is left out, and the resolution says it may be incomplete,
/// so the remembered choice keeps it.
@MainActor
final class MasternodeVoterRegistryVotingKeysTests: XCTestCase {
    func testAnUnreadableKeyLeavesTheNodeOutAndMarksTheListIncomplete() {
        let a = Data([1]), b = Data([2]), c = Data([3])
        let presence: [Data: TrackedMasternodeKeyPresence] = [a: .present, b: .unknown, c: .absent]

        let keys = MasternodeVoterRegistry.votingKeys(of: [a, b, c]) { presence[$0]! }

        XCTAssertEqual(keys.present, [a])
        XCTAssertTrue(keys.unreadable)
    }

    func testReadableKeysLeaveTheListComplete() {
        let a = Data([1]), c = Data([3])
        let keys = MasternodeVoterRegistry.votingKeys(of: [a, c]) { $0 == a ? .present : .absent }

        XCTAssertEqual(keys.present, [a])
        XCTAssertFalse(keys.unreadable)
    }
}
