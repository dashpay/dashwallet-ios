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
///   `castAfterAuthentication(choice:onNormalizedLabel:with:) async -> VoteCastReport`.
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
        await caster.castAfterAuthentication(choice: choice, onNormalizedLabel: label, with: nodes)
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
        XCTAssertTrue(outcome.hasNoVotesLeft)
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

// MARK: - Quick voting runs (AC-14b, AC-18, AC-19; ADR-0037)

private final class RunLog {
    var authentications = 0
    var authOutcome = AuthenticationGate.Outcome.ok
    var sent: [String] = []
    var closed: Set<String> = []
    var cancelAfterSends: Int?
    /// The run is stopped while the PIN prompt is up, and the PIN then passes.
    var cancelDuringAuthentication = false
    var sdkConnected = true
}

extension MasternodeVoteCasterTests {
    private func makeRunCaster(history: FakeVoteHistory, log: RunLog) -> MasternodeVoteCaster {
        MasternodeVoteCaster(
            registry: MasternodeVoterRegistry(),
            contests: ContestedNamesService(),
            history: history,
            votingKey: { _ in Data(repeating: 1, count: 32) },
            send: { node, _, _, label in
                log.sent.append("\(label)/\(node.proTxHash[0])")
                if log.sent.count == log.cancelAfterSends { withUnsafeCurrentTask { $0?.cancel() } }
            },
            authenticate: {
                log.authentications += 1
                if log.cancelDuringAuthentication { withUnsafeCurrentTask { $0?.cancel() } }
                return log.authOutcome
            },
            isContestOpen: { !log.closed.contains($0) },
            isSDKConnected: { log.sdkConnected })
    }

    private func casts(_ labels: [String], nodes: [VoterNode]) -> [QuickVoteCast] {
        labels.map { QuickVoteCast(normalizedLabel: $0, choice: .towards(identityId: "\($0)-1"), nodes: nodes) }
    }

    func testARunAuthenticatesOnceAndSendsEveryVoteInOrder() async throws {
        let log = RunLog()
        let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)
        var progress: [Int] = []

        let planned = casts(["alice", "bob"], nodes: [node(1), node(2)])
        let reports = try await caster.castRun(planned) { progress.append($0) }

        XCTAssertEqual(log.authentications, 1, "one prompt for the whole run")
        XCTAssertEqual(log.sent, ["alice/1", "alice/2", "bob/1", "bob/2"], "one at a time, name by name")
        XCTAssertEqual(reports.map(\.normalizedLabel), ["alice", "bob"])
        XCTAssertTrue(reports.allSatisfy(\.isCompleteSuccess))
        XCTAssertEqual(progress, [0, 1, 2], "0 once the prompt is passed, then after each name")
    }

    func testARunWhoseAuthenticationIsCancelledSendsNothing() async {
        let log = RunLog()
        log.authOutcome = .cancelled
        let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)
        var progress: [Int] = []

        do {
            _ = try await caster.castRun(casts(["alice"], nodes: [node(1)])) { progress.append($0) }
            XCTFail("a refused prompt must not start the run")
        } catch MasternodeVoteCaster.CastError.authenticationCancelled {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(log.sent.isEmpty)
        XCTAssertTrue(progress.isEmpty, "no progress for a run the prompt refused")
    }

    func testARunWhoseAuthenticationFailsOrTimesOutSendsNothing() async {
        for outcome in [AuthenticationGate.Outcome.failed, .timedOut] {
            let log = RunLog()
            log.authOutcome = outcome
            let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)

            do {
                _ = try await caster.castRun(casts(["alice"], nodes: [node(1)])) { _ in }
                XCTFail("\(outcome) must not start the run")
            } catch MasternodeVoteCaster.CastError.authenticationFailed {
            } catch {
                XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(log.sent.isEmpty)
        }
    }

    func testANameWhosePreflightCannotBeReadFailsAndTheRunGoesOn() async throws {
        struct Down: Error {}
        let log = RunLog()
        let caster = MasternodeVoteCaster(
            registry: MasternodeVoterRegistry(), contests: ContestedNamesService(),
            history: FakeVoteHistory(records: []),
            votingKey: { _ in Data(repeating: 1, count: 32) },
            send: { node, _, _, label in log.sent.append("\(label)/\(node.proTxHash[0])") },
            authenticate: { .ok },
            isContestOpen: { label in
                if label == "alice" { throw Down() }
                return true
            },
            isSDKConnected: { true })

        let reports = try await caster.castRun(casts(["alice", "bob"], nodes: [node(1)])) { _ in }

        XCTAssertEqual(log.sent, ["bob/1"])
        XCTAssertEqual(reports.first?.failed.count, 1)
        XCTAssertEqual(reports.first?.contestClosed, false, "an unread pre-flight is not a closed poll")
        XCTAssertEqual(reports.last?.isCompleteSuccess, true)
    }

    func testARunWithoutPlatformAsksForNoAuthentication() async {
        let log = RunLog()
        log.sdkConnected = false
        let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)

        do {
            _ = try await caster.castRun(casts(["alice"], nodes: [node(1)])) { _ in }
            XCTFail("no run without Platform")
        } catch MasternodeVoteCaster.CastError.sdkUnavailable {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(log.authentications, 0, "no PIN for a run that cannot send")
        XCTAssertTrue(log.sent.isEmpty)
    }

    func testARunStoppedBeforeItStartsAsksForNoAuthenticationAndSendsNothing() async throws {
        let log = RunLog()
        let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)
        let planned = casts(["alice", "bob"], nodes: [node(1)])

        // As a Try again stopped while it re-read the history: the task is cancelled before the run.
        var progress: [Int] = []
        let run = Task { () -> [VoteCastReport] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await caster.castRun(planned) { progress.append($0) }
        }
        let reports = try await run.value

        XCTAssertEqual(log.authentications, 0, "no PIN for a run that will send nothing")
        XCTAssertTrue(progress.isEmpty, "no progress for a run that passed no prompt")
        XCTAssertTrue(log.sent.isEmpty)
        XCTAssertEqual(reports.map(\.normalizedLabel), ["alice", "bob"], "every planned name is reported")
        XCTAssertEqual(reports.flatMap(\.failed).count, 2, "as not cast, for Try again")
        XCTAssertFalse(reports.contains(where: \.contestClosed))
    }

    /// The screen is left while the PIN prompt is up and the PIN then
    /// passes: the run sends nothing and tells no progress for it.
    func testARunStoppedDuringAuthenticationTellsNoProgressAndSendsNothing() async throws {
        let log = RunLog()
        log.cancelDuringAuthentication = true
        let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)
        var progress: [Int] = []

        let reports = try await caster.castRun(casts(["alice", "bob"], nodes: [node(1)])) { progress.append($0) }

        XCTAssertEqual(log.authentications, 1)
        XCTAssertTrue(progress.isEmpty, "no progress for a run that stopped at the prompt")
        XCTAssertTrue(log.sent.isEmpty)
        XCTAssertEqual(reports.flatMap(\.failed).count, 2, "every vote is reported as not cast")
    }

    func testARunReChecksTheVoteLimitBeforeEachCast() async throws {
        let log = RunLog()
        let atLimit = CastVoteRecord(
            proTxHash: node(1).proTxHash, normalizedLabel: "bob", choice: .abstain,
            castAt: Date(timeIntervalSince1970: 1_700_000_000), castCount: VoteLimit.maxCastsPerNode)
        let caster = makeRunCaster(history: FakeVoteHistory(records: [atLimit]), log: log)

        let reports = try await caster.castRun(casts(["alice", "bob"], nodes: [node(1), node(2)])) { _ in }

        XCTAssertEqual(log.sent, ["alice/1", "alice/2", "bob/2"], "never a sixth vote")
        XCTAssertEqual(reports.last?.failed.map(\.node.proTxHash), [node(1).proTxHash])
    }

    func testAClosedNameFailsItsVotesAndTheRunGoesOn() async throws {
        let log = RunLog()
        log.closed = ["alice"]
        let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)

        let reports = try await caster.castRun(casts(["alice", "bob"], nodes: [node(1)])) { _ in }

        XCTAssertEqual(log.sent, ["bob/1"])
        XCTAssertEqual(reports.first?.failed.count, 1)
        XCTAssertEqual(reports.first?.contestClosed, true, "the store marks the name closed")
        XCTAssertEqual(reports.last?.isCompleteSuccess, true)
        XCTAssertEqual(reports.last?.contestClosed, false)
    }

    func testAStoppedRunReportsTheVotesNotSentAsNotCast() async throws {
        let log = RunLog()
        log.cancelAfterSends = 1
        let caster = makeRunCaster(history: FakeVoteHistory(records: []), log: log)

        let reports = try await caster.castRun(casts(["alice", "bob"], nodes: [node(1), node(2)])) { _ in }

        XCTAssertEqual(log.sent, ["alice/1"], "nothing more is sent once the run stops")
        XCTAssertEqual(reports.map(\.normalizedLabel), ["alice", "bob"], "every planned name is reported")
        XCTAssertEqual(reports.flatMap(\.succeeded).count, 1)
        XCTAssertEqual(reports.flatMap(\.failed).count, 3)
    }

    /// A run stopped while a vote's count is being read sends that vote
    /// neither: the check comes after the read, right before the broadcast.
    func testARunStoppedDuringTheCountReadSendsNothingMore() async throws {
        let log = RunLog()
        let history = FakeVoteHistory(records: [])
        history.cancelDuringRead = 0
        let caster = makeRunCaster(history: history, log: log)

        let reports = try await caster.castRun(casts(["alice"], nodes: [node(1), node(2)])) { _ in }

        XCTAssertEqual(log.sent, [], "nothing is sent after the run stopped")
        XCTAssertEqual(reports.flatMap(\.failed).count, 2)
        XCTAssertEqual(
            reports.first?.failed.first?.failure, "Quick voting stopped before this vote was sent.")
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
    /// The read (0-based) during which the calling task is stopped, as when
    /// the screen goes away while the read is suspended.
    var cancelDuringRead: Int?
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
        if reads == cancelDuringRead { withUnsafeCurrentTask { $0?.cancel() } }
        return failingReads.contains(reads) ? nil : records.filter { $0.normalizedLabel == normalizedLabel }
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
