//
//  VotingStoreTests.swift
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

// MARK: - Fakes

private final class FakeContests: VotingContestReading {
    var result: Result<[DPNSContest], Error> = .success([])
    /// When set, `activeContests()` suspends until `release()` is called.
    var gate: CheckedContinuation<Void, Never>?
    var holdNextLoad = false
    private(set) var started = false
    private(set) var loads = 0
    /// What `voteState(normalizedLabel:)` answers: a state, `nil` (Platform
    /// holds no contenders), or a failure.
    var voteStateResult: Result<DPNSContestVoteState?, Error> = .success(nil)

    func activeContests() async throws -> [DPNSContest] {
        started = true
        loads += 1
        if holdNextLoad {
            await withCheckedContinuation { gate = $0 }
        }
        return try result.get()
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    /// When set, the next `voteState(normalizedLabel:)` suspends until
    /// `releaseVoteState()` — a contest refresh that holds the load queue.
    var holdNextVoteState = false
    private var voteStateGate: CheckedContinuation<Void, Never>?
    private(set) var voteStateHeld = false

    func voteState(normalizedLabel: String) async throws -> DPNSContestVoteState? {
        if holdNextVoteState {
            holdNextVoteState = false
            voteStateHeld = true
            await withCheckedContinuation { voteStateGate = $0 }
        }
        return try voteStateResult.get()
    }

    func releaseVoteState() {
        voteStateGate?.resume()
        voteStateGate = nil
    }
}

/// A clock the test moves by hand.
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private final class FakeNodes: VotableMasternodeResolving {
    var resolution = MasternodeVoterRegistry.Resolution(nodes: [], mayBeIncomplete: false)
    var isNodeListSynced = true
    func votableNodes() -> MasternodeVoterRegistry.Resolution { resolution }
}

private struct FakeCaster: VoteCasting {
    struct Unused: Error {}
    func cast(choice: VoteChoice, onNormalizedLabel normalizedLabel: String, with nodes: [VoterNode]) async throws
        -> VoteCastReport {
        throw Unused()
    }
}

/// A caster the test scripts: it answers with a report, throws, or holds the
/// call until `release()`. A landed, recorded outcome is written to the fake
/// history the way the real caster writes it.
private final class ScriptedCaster: VoteCasting {
    enum Script {
        case outcomes([VoteOutcome])
        case throwing(Error)
    }

    var script: Script = .outcomes([])
    var holdNextCall = false
    var history: FakeHistory?
    private(set) var calls: [(choice: VoteChoice, label: String, nodes: [VoterNode])] = []
    private var gate: CheckedContinuation<Void, Never>?

    var started: Bool { !calls.isEmpty }

    func cast(choice: VoteChoice, onNormalizedLabel normalizedLabel: String, with nodes: [VoterNode]) async throws
        -> VoteCastReport {
        calls.append((choice, normalizedLabel, nodes))
        if holdNextCall {
            holdNextCall = false
            await withCheckedContinuation { gate = $0 }
        }
        switch script {
        case .throwing(let error):
            throw error
        case .outcomes(let outcomes):
            for outcome in outcomes where outcome.succeeded && outcome.historyRecorded {
                let previous = history?.records?.first {
                    $0.proTxHash == outcome.node.proTxHash && $0.normalizedLabel == normalizedLabel
                }
                history?.records?.removeAll {
                    $0.proTxHash == outcome.node.proTxHash && $0.normalizedLabel == normalizedLabel
                }
                history?.records?.append(CastVoteRecord(
                    proTxHash: outcome.node.proTxHash, normalizedLabel: normalizedLabel, choice: choice,
                    castAt: Date(), castCount: (previous?.castCount ?? 0) + 1))
            }
            return VoteCastReport(normalizedLabel: normalizedLabel, choice: choice, outcomes: outcomes)
        }
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

private final class FakeHistory: VoteHistoryDAO {
    /// `nil` makes the whole-list read fail, as an unreadable store does.
    var records: [CastVoteRecord]? = []
    private(set) var listReads = 0
    private(set) var singleReads = 0

    func record(_ record: CastVoteRecord, network: String) async throws {}
    /// When set, the next one-contest read suspends until `releaseSingleRead()`.
    var holdNextSingleRead = false
    private var singleGate: CheckedContinuation<Void, Never>?
    private(set) var singleReadHeld = false

    func votes(forContest normalizedLabel: String, network: String) async -> [CastVoteRecord]? {
        singleReads += 1
        if holdNextSingleRead {
            holdNextSingleRead = false
            singleReadHeld = true
            await withCheckedContinuation { singleGate = $0 }
        }
        return records?.filter { $0.normalizedLabel == normalizedLabel }
    }

    func releaseSingleRead() {
        singleGate?.resume()
        singleGate = nil
    }
    /// When set, the next whole-list read takes its rows, then suspends until
    /// `releaseListRead()` — a read that finished before a later write landed.
    var holdNextListRead = false
    private var listGate: CheckedContinuation<Void, Never>?
    private(set) var listReadHeld = false

    func votes(forContests normalizedLabels: Set<String>, network: String) async -> [CastVoteRecord]? {
        listReads += 1
        let snapshot = records
        if holdNextListRead {
            holdNextListRead = false
            listReadHeld = true
            await withCheckedContinuation { listGate = $0 }
        }
        return snapshot?.filter { normalizedLabels.contains($0.normalizedLabel) }
    }

    func releaseListRead() {
        listGate?.resume()
        listGate = nil
    }
    func deleteAll() {}
}

private final class FakePrefs: VotingSelectionStoring {
    var votingNodeSelection: Set<Data> = []
    /// A wallet that set voting up, unless a test says otherwise.
    var isVotingSetUp = true
}

// MARK: - Tests

/// The shared voting store: one history read per list load, the load and
/// banner states, and the pills filled from the ticked masternodes only.
@MainActor
final class VotingStoreTests: XCTestCase {

    private let approve = VoteChoice.towards(identityId: "contender-1")
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private var contests: FakeContests!
    private var nodes: FakeNodes!
    private var history: FakeHistory!
    private var prefs: FakePrefs!

    override func setUp() {
        super.setUp()
        contests = FakeContests()
        nodes = FakeNodes()
        history = FakeHistory()
        prefs = FakePrefs()
    }

    private func makeStore(caster: VoteCasting? = nil) -> VotingStore {
        VotingStore(contests: contests, nodes: nodes, caster: caster ?? FakeCaster(), history: history, prefs: prefs)
    }

    private func node(_ byte: UInt8) -> VoterNode {
        VoterNode(proTxHash: Data([byte]), isEvonode: false, typeIndex: UInt32(byte),
                  serviceAddress: nil, keySource: .walletIndex(0))
    }

    private func contest(_ label: String, endsAt end: Date? = nil) -> DPNSContest {
        DPNSContest(normalizedLabel: label, endTime: end, hasWinner: false,
                    abstainVotes: 0, lockVotes: 0, contenders: [])
    }

    private func vote(_ node: VoterNode, on label: String, _ choice: VoteChoice) -> CastVoteRecord {
        CastVoteRecord(proTxHash: node.proTxHash, normalizedLabel: label, choice: choice, castAt: epoch)
    }

    // MARK: One history read per load (NFR)

    func testListLoadIssuesExactlyOneHistoryRead() async {
        contests.result = .success((1...12).map { contest("name\($0)") })
        let store = makeStore()

        await store.refresh()

        XCTAssertEqual(history.listReads, 1, "one read for the whole list, not one per row")
        XCTAssertEqual(history.singleReads, 0)
        XCTAssertEqual(store.contests.count, 12)
    }

    // MARK: Load states

    func testLoadingThenEmptyWhenNoOpenContests() async {
        contests.result = .success([])
        contests.holdNextLoad = true
        let store = makeStore()
        XCTAssertFalse(store.hasLoadedOnce)

        let load = Task { await store.refresh() }
        while !contests.started { await Task.yield() }
        XCTAssertTrue(store.isLoading)
        XCTAssertFalse(store.hasLoadedOnce, "the empty state must not show while the first fetch is in flight")

        contests.release()
        await load.value

        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.hasLoadedOnce)
        XCTAssertTrue(store.contests.isEmpty)
    }

    func testNodeListIncompleteFlagFollowsTheRegistry() async {
        nodes.resolution = .init(nodes: [node(1)], mayBeIncomplete: true)
        let store = makeStore()

        await store.refresh()

        XCTAssertTrue(store.nodeListMayBeIncomplete)
        XCTAssertEqual(store.votableNodes.map(\.proTxHash), [Data([1])])
    }

    func testNodeListCompleteByDefault() async {
        nodes.resolution = .init(nodes: [node(1)], mayBeIncomplete: false)
        let store = makeStore()
        await store.refresh()
        XCTAssertFalse(store.nodeListMayBeIncomplete)
    }

    func testFailedContestLoadKeepsLastGoodListAndSetsError() async {
        contests.result = .success([contest("kept")])
        let store = makeStore()
        await store.refresh()

        struct Boom: Error {}
        contests.result = .failure(Boom())
        await store.refresh()

        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["kept"])
        XCTAssertTrue(store.loadFailed)
    }

    // MARK: History unavailable (flow 4)

    func testUnreadableHistorySetsFlagAndFillsNoPill() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest("johndoe")])
        history.records = nil
        let store = makeStore()

        await store.refresh()

        XCTAssertTrue(store.historyUnavailable)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [], "counts only, none filled")
        XCTAssertFalse(store.hasLoadedVoteHistory(for: "johndoe"), "unknown, not 'nobody voted'")
    }

    func testReadableHistoryClearsTheFlag() async {
        contests.result = .success([contest("johndoe")])
        history.records = nil
        let store = makeStore()
        await store.refresh()
        XCTAssertTrue(store.historyUnavailable)

        history.records = []
        await store.refresh()

        XCTAssertFalse(store.historyUnavailable)
        XCTAssertTrue(store.hasLoadedVoteHistory(for: "johndoe"))
    }

    // MARK: Pill fill from ticked masternodes only (AC-04)

    func testPillFillsFromTickedMasternodesOnly() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest("johndoe")])
        history.records = [vote(a, on: "johndoe", approve), vote(b, on: "johndoe", .lock)]
        let store = makeStore()

        await store.refresh()

        XCTAssertEqual(store.myChoices(on: "johndoe"), [approve], "b voted lock but is not ticked")
    }

    func testUntickedNodesVoteFillsNothing() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest("johndoe")])
        history.records = [vote(b, on: "johndoe", approve)]
        let store = makeStore()

        await store.refresh()

        XCTAssertEqual(store.myChoices(on: "johndoe"), [])
    }

    /// Flow 4: a read that fails after a good one leaves no pill filled from
    /// the last good read, as the history is unknown now.
    func testAFailedHistoryReadAfterAGoodOneFillsNoPill() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest("johndoe")])
        history.records = [vote(a, on: "johndoe", .lock)]
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.myChoices(on: "johndoe"), [.lock])

        history.records = nil
        await store.refresh()

        XCTAssertTrue(store.historyUnavailable)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [], "counts only, none filled")
    }

    // MARK: No masternode chosen yet

    /// AC-12: before voting is set up, the default tick is not a choice — it
    /// is neither persisted nor reported as ticked.
    func testDefaultTickBeforeSetupIsNeitherPersistedNorTicked() async {
        let first = node(1)
        nodes.resolution = .init(nodes: [first, node(2)], mayBeIncomplete: false)
        prefs.votingNodeSelection = []
        prefs.isVotingSetUp = false
        let store = makeStore()

        await store.refresh()

        XCTAssertEqual(prefs.votingNodeSelection, [])
        XCTAssertNil(store.tickedNodeIDs)
        XCTAssertFalse(store.isVotingSetUp)
    }

    /// AC-12: voting is set up only by confirming «Add your voting keys» once
    /// on this install. A selection an earlier build stored, with votes
    /// recorded for it, is not that: the first tap opens SCR-04, with the
    /// stored ticks ticked.
    func testAStoredSelectionWithVotesIsNotSetUpButStaysTicked() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [b.proTxHash]
        prefs.isVotingSetUp = false
        contests.result = .success([contest("johndoe")])
        history.records = [vote(b, on: "johndoe", .lock)]
        let store = makeStore()

        await store.refresh()

        XCTAssertFalse(store.isVotingSetUp)
        XCTAssertFalse(prefs.isVotingSetUp)
        XCTAssertEqual(store.tickedNodeIDs, [b.proTxHash])
        XCTAssertEqual(VotingKeysViewModel(mode: .vote(.lock), source: store).ticked, [b.proTxHash])
    }

    /// AC-12: a voting key the user added does not set voting up by itself.
    func testAnAddedVotingKeyIsNotSetUp() async {
        let derived = node(1)
        let added = VoterNode(proTxHash: Data([9]), isEvonode: false, typeIndex: 9,
                              serviceAddress: nil, keySource: .trackedVault)
        nodes.resolution = .init(nodes: [derived, added], mayBeIncomplete: false)
        prefs.votingNodeSelection = []
        prefs.isVotingSetUp = false
        contests.result = .success([contest("johndoe")])
        history.records = [vote(added, on: "johndoe", .lock)]
        let store = makeStore()

        await store.refresh()

        XCTAssertFalse(store.isVotingSetUp)
        XCTAssertNil(store.tickedNodeIDs)
    }

    /// Ticks kept in manage mode before setup do not set voting up at a later
    /// refresh; only «Add your voting keys» does.
    func testManageModeTicksBeforeSetupDoNotSetVotingUpOnALaterRefresh() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = []
        prefs.isVotingSetUp = false
        contests.result = .success([contest("johndoe")])
        let store = makeStore()
        await store.refresh()

        store.setTick(a.proTxHash, true)
        store.setTick(b.proTxHash, true)
        await store.refresh()

        XCTAssertFalse(store.isVotingSetUp)
        XCTAssertEqual(store.tickedNodeIDs, [a.proTxHash, b.proTxHash])
    }

    /// A stored selection none of whose nodes can vote any more is not a choice.
    func testAStaleStoredSelectionIsNotSetUp() async {
        nodes.resolution = .init(nodes: [node(1)], mayBeIncomplete: false)
        prefs.votingNodeSelection = [node(7).proTxHash]
        prefs.isVotingSetUp = false
        let store = makeStore()

        await store.refresh()

        XCTAssertFalse(store.isVotingSetUp)
        XCTAssertNil(store.tickedNodeIDs)
    }

    /// A wiped wallet forgets voting set up and the masternode choice, so the
    /// next wallet is not set up by what the last one chose.
    func testForgettingVotingSetupClearsTheFlagAndTheSelection() {
        let prefs = VotingPrefs.shared
        let saved = (prefs.isVotingSetUp, prefs.votingNodeSelection)
        defer { (prefs.isVotingSetUp, prefs.votingNodeSelection) = saved }
        prefs.isVotingSetUp = true
        prefs.votingNodeSelection = [Data([1])]

        prefs.forgetVotingSetup()

        XCTAssertFalse(prefs.isVotingSetUp)
        XCTAssertEqual(prefs.votingNodeSelection, [])
    }

    /// AC-12, AC-14: the vote button of "Add your voting keys" keeps the ticks and sets voting up.
    func testConfirmingTheTicksSetsVotingUp() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.isVotingSetUp = false
        let store = makeStore()
        await store.refresh()

        store.confirmVotingSetup(ticked: [a.proTxHash, b.proTxHash])

        XCTAssertTrue(prefs.isVotingSetUp)
        XCTAssertTrue(store.isVotingSetUp)
        XCTAssertEqual(prefs.votingNodeSelection, [a.proTxHash, b.proTxHash])
        XCTAssertEqual(store.tickedNodeIDs, [a.proTxHash, b.proTxHash])
    }

    /// A complete node list proves a ticked node that is not votable gone:
    /// confirming does not keep it.
    func testConfirmingWithACompleteListKeepsOnlyVotableTicks() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        let store = makeStore()
        await store.refresh()

        store.confirmVotingSetup(ticked: [a.proTxHash, node(2).proTxHash])

        XCTAssertEqual(prefs.votingNodeSelection, [a.proTxHash])
    }

    /// Managing keys keeps the ticks but does not set voting up.
    func testSavingTicksDoesNotSetVotingUp() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.isVotingSetUp = false
        let store = makeStore()
        await store.refresh()

        store.setTick(a.proTxHash, true)

        XCTAssertEqual(prefs.votingNodeSelection, [a.proTxHash])
        XCTAssertFalse(prefs.isVotingSetUp)
    }

    /// Without a node to vote with, voting is not set up whatever the flag says.
    func testNoVotableNodeIsNotSetUp() async {
        nodes.resolution = .init(nodes: [], mayBeIncomplete: false)
        let store = makeStore()
        await store.refresh()

        XCTAssertFalse(store.isVotingSetUp)
    }

    /// Nothing stored and no nodes yet (SDK not ready): no selection is
    /// persisted, and the store says "none chosen yet" rather than an empty set.
    func testEmptySelectionWithoutNodesIsNoneChosenYetAndPersistsNothing() async {
        nodes.resolution = .init(nodes: [], mayBeIncomplete: false)
        prefs.votingNodeSelection = []
        let store = makeStore()

        XCTAssertNil(store.tickedNodeIDs)
        await store.refresh()

        XCTAssertNil(store.tickedNodeIDs)
        XCTAssertEqual(prefs.votingNodeSelection, [])
    }

    /// AC-14, AC-16b: once set up, unticking every masternode is a choice of
    /// none. The next attempt opens Add your voting keys, and no node the user
    /// did not tick is saved in its place.
    func testUntickingEveryMasternodeAfterSetupOpensAddYourVotingKeys() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let johndoe = contest("johndoe", endsAt: Date().addingTimeInterval(30 * day))
        contests.result = .success([johndoe])
        let store = makeStore()
        await store.refresh()

        store.setTick(a.proTxHash, false)
        await store.refresh()

        XCTAssertEqual(store.tickedNodeIDs, [])
        XCTAssertEqual(prefs.votingNodeSelection, [], "no fallback saved")
        let voting = VotingViewModel(store: store)
        let attempt = VoteAttemptCoordinator(host: voting)
        await attempt.start(.vote(.lock), on: johndoe)
        XCTAssertEqual(attempt.presentation, .addKeys(.lock))
    }

    /// Ticks kept in manage mode before voting was set up are shown there again.
    func testManageModeBeforeSetupShowsTheStoredTicks() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.isVotingSetUp = false
        let store = makeStore()
        await store.refresh()

        store.setTick(b.proTxHash, true)

        XCTAssertFalse(store.isVotingSetUp)
        XCTAssertEqual(store.tickedNodeIDs, [b.proTxHash])
        XCTAssertEqual(VotingKeysViewModel(mode: .manage, source: store).ticked, [b.proTxHash])
    }

    func testTickedNodesAreTheStoredChoiceThatIsStillVotable() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a, node(2)], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, Data([9])]
        let store = makeStore()

        await store.refresh()

        XCTAssertEqual(store.tickedNodeIDs, [a.proTxHash], "a remembered node that is no longer votable is dropped")
    }

    /// A partial resolution does not prove a missing node gone: the choice
    /// stays as the user made it, the vote uses the nodes that resolved, and
    /// the missing node votes again once it resolves.
    func testAPartialNodeListKeepsTheRememberedChoice() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        let store = makeStore()
        await store.refresh()

        nodes.resolution = .init(nodes: [a], mayBeIncomplete: true)
        store.refreshVotableNodes()
        XCTAssertEqual(store.nodeResolution, .partial)
        XCTAssertEqual(prefs.votingNodeSelection, [a.proTxHash, b.proTxHash])
        XCTAssertEqual(store.tickedNodeIDs, [a.proTxHash])

        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        store.refreshVotableNodes()
        XCTAssertEqual(store.tickedNodeIDs, [a.proTxHash, b.proTxHash])
    }

    /// Before the wallet's sync is done the registry may already return the
    /// imported nodes and not yet this wallet's own: that is a partial list,
    /// and the remembered choice stays as the user made it.
    func testANodeListReadBeforeTheWalletsSyncIsDoneKeepsTheRememberedChoice() async {
        let a = node(1), b = node(2)
        nodes.isNodeListSynced = false
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        let store = makeStore()
        await store.refresh()

        XCTAssertEqual(store.nodeResolution, .partial)
        XCTAssertEqual(prefs.votingNodeSelection, [a.proTxHash, b.proTxHash])

        nodes.isNodeListSynced = true
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        store.refreshVotableNodes()
        XCTAssertEqual(store.nodeResolution, .complete)
        XCTAssertEqual(store.tickedNodeIDs, [a.proTxHash, b.proTxHash])
    }

    /// The vote button of "Add your voting keys" keeps the ticks shown; a
    /// remembered node a partial list did not show stays remembered.
    func testConfirmingFromAPartialNodeListKeepsTheUnseenChoice() async {
        let a = node(1), b = node(2), c = node(3)
        nodes.resolution = .init(nodes: [a, c], mayBeIncomplete: true)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        let store = makeStore()
        await store.refresh()

        store.confirmVotingSetup(ticked: [c.proTxHash])

        XCTAssertEqual(prefs.votingNodeSelection, [b.proTxHash, c.proTxHash])
    }

    /// A removed voting key leaves the remembered choice even while the node
    /// list is partial, so the node does not come back ticked.
    func testARemovedKeyLeavesTheChoice() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: true)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        let store = makeStore()
        await store.refresh()

        store.forgetNode(b.proTxHash)

        XCTAssertEqual(prefs.votingNodeSelection, [a.proTxHash])
    }

    // MARK: Sections on the list view model (AC-01, AC-03b)

    func testListSectionsSoonestFirstAndUnknownEndLast() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!
        let day: TimeInterval = 86_400
        contests.result = .success([
            contest("unknown"),
            contest("ten", endsAt: now.addingTimeInterval(10 * day)),
            contest("today", endsAt: now.addingTimeInterval(3600)),
            contest("three", endsAt: now.addingTimeInterval(3 * day)),
        ])
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() }, now: { now },
                                       calendar: { calendar })

        await store.refresh()

        XCTAssertEqual(list.sections.map(\.daysLeft), [0, 3, 10, nil])
        XCTAssertEqual(list.sections.last?.contests.map(\.normalizedLabel), ["unknown"])
        XCTAssertEqual(list.sections.last?.title, "Voting end unknown")
    }

    func testSearchNarrowsRowsButNotTheOpenCount() async {
        contests.result = .success([contest("alice"), contest("bob")])
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })
        await store.refresh()

        list.searchQuery = "bob"

        XCTAssertEqual(list.visibleContests.map(\.normalizedLabel), ["bob"])
        XCTAssertEqual(list.filterMatchCount, 2, "the header's count ignores the search")
    }

    // MARK: Keep a contest until its voting end, newer data wins (AC-03, AC-03c)

    private let day: TimeInterval = 86_400

    /// The store reads its clock from here; the list view model reads the same one.
    private func makeClockedStore(_ clock: TestClock) -> VotingStore {
        VotingStore(contests: contests, nodes: nodes, caster: FakeCaster(), history: history, prefs: prefs,
                    now: { clock.now })
    }

    private func contest(_ label: String, endsAt end: Date?, lock: UInt32) -> DPNSContest {
        DPNSContest(normalizedLabel: label, endTime: end, hasWinner: false,
                    abstainVotes: 0, lockVotes: lock, contenders: [])
    }

    private func ongoing(_ label: String, lock: UInt32) -> DPNSContestVoteState {
        DPNSContestVoteState(normalizedLabel: label, contenders: [], abstainVotes: 0, lockVotes: lock,
                             outcome: .ongoing, resolvedAt: nil)
    }

    /// Loads apply in the order they were asked for: a full refresh asked
    /// for before a vote's per-contest refresh cannot land after it and put
    /// the pre-vote counts back.
    func testLoadsApplyInTheOrderTheyWereAskedFor() async {
        let end = epoch.addingTimeInterval(10 * day)
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: end, lock: 1)])
        let store = makeClockedStore(clock)
        await store.refresh()

        contests.result = .success([contest("johndoe", endsAt: end, lock: 1)])  // the pre-vote counts
        contests.holdNextLoad = true
        let full = Task { await store.refresh() }
        while contests.loads < 2 { await Task.yield() }
        contests.holdNextLoad = false

        contests.voteStateResult = .success(ongoing("johndoe", lock: 5))  // the vote's counts
        let single = Task { await store.refreshContest(normalizedLabel: "johndoe") }
        await Task.yield()
        contests.release()
        await full.value
        await single.value

        XCTAssertEqual(store.contests.first?.lockVotes, 5, "the later counts must survive the earlier response")
    }

    /// A per-contest refresh that finds no contenders, before the voting end,
    /// keeps the contest with its last known votes.
    func testEmptyContestRefreshKeepsTheContestWithItsLastKnownVotes() async {
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: epoch.addingTimeInterval(3 * day), lock: 3)])
        let store = makeClockedStore(clock)
        await store.refresh()

        contests.voteStateResult = .success(nil)
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["johndoe"])
        XCTAssertEqual(store.contests.first?.lockVotes, 3)
        XCTAssertFalse(store.isClosed(normalizedLabel: "johndoe"))
    }

    /// Same, without the injected clock: the end is far in the future of the real clock.
    func testEmptyContestRefreshKeepsTheContestOnTheRealClock() async {
        contests.result = .success([contest("johndoe", endsAt: Date().addingTimeInterval(30 * day), lock: 3)])
        let store = makeStore()
        await store.refresh()

        contests.voteStateResult = .success(nil)
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["johndoe"])
    }

    /// A failed per-contest refresh keeps the row as it was (already the case).
    func testFailedContestRefreshKeepsTheContestWithItsLastKnownVotes() async {
        struct Boom: Error {}
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: epoch.addingTimeInterval(3 * day), lock: 3)])
        let store = makeClockedStore(clock)
        await store.refresh()

        contests.voteStateResult = .failure(Boom())
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertEqual(store.contests.first?.lockVotes, 3)
    }

    /// Once the voting end has passed, the next refresh of the contest drops it.
    func testEmptyContestRefreshAfterTheVotingEndDropsTheContest() async {
        let end = epoch.addingTimeInterval(3 * day)
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: end, lock: 3)])
        let store = makeClockedStore(clock)
        await store.refresh()

        clock.now = end.addingTimeInterval(1)
        contests.voteStateResult = .success(nil)
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertTrue(store.contests.isEmpty)
    }

    /// The voting end passing on screen changes nothing by itself (no timer);
    /// the next refresh drops the row.
    func testRowStaysWhenTheVotingEndPassesUntilTheNextRefresh() async {
        let end = epoch.addingTimeInterval(3600)
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: end, lock: 3)])
        let store = makeClockedStore(clock)
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() }, now: { clock.now })
        await store.refresh()
        let before = list.visibleContests

        clock.now = end.addingTimeInterval(60)
        await Task.yield()
        XCTAssertEqual(list.visibleContests, before, "no timer removes or changes the row")
        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["johndoe"])

        contests.result = .success([])
        await store.refresh()
        XCTAssertTrue(list.visibleContests.isEmpty, "the next refresh drops it")
    }

    private func resolved(_ label: String, lock: UInt32) -> DPNSContestVoteState {
        DPNSContestVoteState(normalizedLabel: label, contenders: [], abstainVotes: 0, lockVotes: lock,
                             outcome: .locked, resolvedAt: epoch)
    }

    /// sad §4 choice 6: a contest Platform closed early stays on the list
    /// until its voting end; no vote can start on it.
    func testContestClosedEarlyStaysUntilItsVotingEnd() async {
        let end = epoch.addingTimeInterval(3 * day)
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: end, lock: 3)])
        let store = makeClockedStore(clock)
        await store.refresh()

        contests.voteStateResult = .success(resolved("johndoe", lock: 9))
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["johndoe"])
        XCTAssertTrue(store.isClosed(normalizedLabel: "johndoe"))

        contests.result = .success([])
        await store.refresh()
        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["johndoe"], "still before its voting end")

        clock.now = end.addingTimeInterval(1)
        await store.refresh()
        XCTAssertTrue(store.contests.isEmpty, "gone once its voting end passed")
    }

    /// A resolved contest whose voting end has passed goes at once.
    func testContestResolvedAfterItsVotingEndGoes() async {
        let end = epoch.addingTimeInterval(3600)
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: end, lock: 3)])
        let store = makeClockedStore(clock)
        await store.refresh()

        clock.now = end.addingTimeInterval(1)
        contests.voteStateResult = .success(resolved("johndoe", lock: 9))
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertTrue(store.contests.isEmpty)
        XCTAssertTrue(store.isClosed(normalizedLabel: "johndoe"))
    }

    /// A full refresh that leaves out a contest it listed before (a cut list,
    /// a transient omission) keeps it, with its last known votes, until its
    /// voting end.
    func testFullRefreshKeepsALeftOutContestUntilItsVotingEnd() async {
        let end = epoch.addingTimeInterval(3 * day)
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: end, lock: 3), contest("alice", endsAt: end, lock: 0)])
        let store = makeClockedStore(clock)
        await store.refresh()

        contests.result = .success([contest("alice", endsAt: end, lock: 1)])
        await store.refresh()

        XCTAssertEqual(Set(store.contests.map(\.normalizedLabel)), ["johndoe", "alice"])
        XCTAssertEqual(store.contests.first { $0.normalizedLabel == "johndoe" }?.lockVotes, 3)
        XCTAssertEqual(store.contests.first { $0.normalizedLabel == "alice" }?.lockVotes, 1, "listed ones are fresh")
        XCTAssertFalse(store.isClosed(normalizedLabel: "johndoe"), "left out is not known to be closed")

        clock.now = end.addingTimeInterval(1)
        await store.refresh()
        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["alice"])
    }

    /// Without a known voting end there is no end to keep it until.
    func testFullRefreshDropsALeftOutContestWithAnUnknownEnd() async {
        let clock = TestClock(epoch)
        contests.result = .success([contest("johndoe", endsAt: nil, lock: 3)])
        let store = makeClockedStore(clock)
        await store.refresh()

        contests.result = .success([])
        await store.refresh()

        XCTAssertTrue(store.contests.isEmpty)
    }

    // MARK: Could not load (AC-02)

    func testLoadingBeforeTheFirstLoadFinishes() {
        let list = VotingListViewModel(store: makeStore(), normalizedLabel: { $0.lowercased() })
        XCTAssertEqual(list.loadState, .loading)
    }

    /// Nothing cached and the load fails: the full-screen could-not-load state,
    /// never "No open contests".
    func testFailedFirstLoadIsCouldNotLoadNotNoContests() async {
        struct Boom: Error {}
        contests.result = .failure(Boom())
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })

        await store.refresh()

        XCTAssertEqual(list.loadState, .couldNotLoad)
        XCTAssertNotEqual(list.loadState, .noContests)
    }

    /// Rows on screen and the refresh fails: rows stay, the banner flag is set.
    func testFailedRefreshWithRowsKeepsRowsAndFlagsTheBanner() async {
        struct Boom: Error {}
        contests.result = .success([contest("kept")])
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })
        await store.refresh()
        XCTAssertEqual(list.loadState, .contests(refreshFailed: false))

        contests.result = .failure(Boom())
        await store.refresh()

        XCTAssertEqual(list.loadState, .contests(refreshFailed: true))
        XCTAssertEqual(list.visibleContests.map(\.normalizedLabel), ["kept"])
    }

    /// Try again while a refresh runs shows the loading state and queues no
    /// second refresh, however often it is tapped.
    func testTryAgainWhileARefreshRunsQueuesNoSecondOne() async {
        struct Boom: Error {}
        contests.result = .failure(Boom())
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })
        await store.refresh()
        XCTAssertEqual(list.emptyState, .couldNotLoad)

        contests.holdNextLoad = true
        let first = Task { await store.retry() }
        while contests.loads < 2 { await Task.yield() }
        XCTAssertTrue(store.isRefreshing)
        XCTAssertEqual(list.emptyState, .loading, "the retry shows progress")
        let taps = [Task { await store.retry() }, Task { await store.retry() }]
        for _ in 0..<20 { await Task.yield() }
        contests.holdNextLoad = false
        contests.result = .success([contest("back")])
        contests.release()
        await first.value
        for tap in taps { await tap.value }

        XCTAssertEqual(contests.loads, 2, "one load for the first tap, none for the others")
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["back"])
    }

    /// The screen comes back after a failed first load and its own initial
    /// load runs: that load shows progress too, and Try again queues nothing.
    func testTryAgainWhileTheInitialLoadRunsQueuesNoSecondOne() async {
        struct Boom: Error {}
        contests.result = .failure(Boom())
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })
        await store.refreshIfNeeded()
        XCTAssertEqual(list.emptyState, .couldNotLoad)

        contests.holdNextLoad = true
        let reappeared = Task { await store.refreshIfNeeded() }
        while contests.loads < 2 { await Task.yield() }
        XCTAssertTrue(store.isRefreshing)
        XCTAssertEqual(list.emptyState, .loading, "the initial load shows progress")
        let tap = Task { await store.retry() }
        for _ in 0..<20 { await Task.yield() }
        contests.holdNextLoad = false
        contests.result = .success([contest("back")])
        contests.release()
        await reappeared.value
        await tap.value

        XCTAssertEqual(contests.loads, 2, "Try again added no load")
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["back"])
    }

    /// The list reappears after contests have loaded and a later refresh
    /// failed, while a contest refresh holds the queue: nothing will load, so
    /// the list does not read as refreshing and Try again stays.
    func testReappearingAfterContestsLoadedLeavesTryAgain() async {
        struct Boom: Error {}
        contests.result = .success([contest("a")])
        let store = makeStore()
        await store.refreshIfNeeded()
        contests.result = .failure(Boom())
        await store.refresh()
        XCTAssertTrue(store.loadFailed)

        contests.holdNextVoteState = true
        let busy = Task { await store.refreshContest(normalizedLabel: "a") }
        while !contests.voteStateHeld { await Task.yield() }
        let reappeared = Task { await store.refreshIfNeeded() }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(store.isRefreshing, "Try again stays while the queue is busy")

        contests.releaseVoteState()
        await busy.value
        await reappeared.value
        XCTAssertEqual(contests.loads, 2, "the reappearing list loaded nothing")
        XCTAssertFalse(store.isRefreshing)
    }

    func testNoOpenContestsIsTheEmptyStateOnlyAfterASuccessfulLoad() async {
        contests.result = .success([])
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })

        await store.refresh()

        XCTAssertEqual(list.loadState, .noContests)
    }

    /// Try again after a failed first load succeeds: the error clears.
    func testRetryAfterFailedFirstLoadShowsTheContests() async {
        struct Boom: Error {}
        contests.result = .failure(Boom())
        let store = makeStore()
        let list = VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })
        await store.refresh()

        contests.result = .success([contest("johndoe")])
        await store.refresh()

        XCTAssertEqual(list.loadState, .contests(refreshFailed: false))
    }

    // MARK: Send and the one outcome (AC-05, AC-06, AC-14b)

    private var caster: ScriptedCaster!

    private func landed(_ node: VoterNode, recorded: Bool = true) -> VoteOutcome {
        VoteOutcome(node: node, failure: nil, historyRecorded: recorded)
    }

    private func refused(_ node: VoterNode, _ reason: String = "No votes left") -> VoteOutcome {
        VoteOutcome(node: node, failure: reason)
    }

    /// Two ticked masternodes with an empty, known history on "johndoe".
    private func makeVotingStore(clock: TestClock? = nil) async
        -> (store: VotingStore, a: VoterNode, b: VoterNode, johndoe: DPNSContest) {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        let johndoe = contest("johndoe", endsAt: Date().addingTimeInterval(30 * day), lock: 1)
        contests.result = .success([johndoe])
        contests.voteStateResult = .success(ongoing("johndoe", lock: 7))
        caster = ScriptedCaster()
        caster.history = history
        let store = clock.map { clock in
            VotingStore(contests: contests, nodes: nodes, caster: caster, history: history, prefs: prefs,
                        now: { clock.now })
        } ?? makeStore(caster: caster)
        await store.refresh()
        return (store, a, b, johndoe)
    }

    /// AC-17: an abstain that landed everywhere is told as a cancelled vote, not as a vote.
    func testAllAbstainsLandedGivesVoteCancelledToast() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), landed(b)])

        await store.send(choice: .abstain, on: johndoe, from: [a, b])

        guard case .success(let toast)? = store.outcome else {
            return XCTFail("expected .success, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(toast.message, "Vote cancelled on \(johndoe.displayTitle)")
        XCTAssertEqual(toast.style, .success)
    }

    func testAllLandedGivesSuccessToastAndUpdatesCountsAndMyVote() async throws {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), landed(b)])

        await store.send(choice: approve, on: johndoe, from: [a, b])

        guard case .success(let toast)? = store.outcome else {
            return XCTFail("expected .success, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(toast.message, "Voted \(johndoe.displayTitle) username")
        XCTAssertEqual(toast.style, .success)
        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode - 1)
        XCTAssertEqual(limit.votesLeft(b.proTxHash), VoteLimit.maxCastsPerNode - 1)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [approve])
        XCTAssertEqual(store.votedNodeCount(on: "johndoe"), 2)
        XCTAssertEqual(store.contests.first?.lockVotes, 7, "the contest's tallies are re-read once the votes landed")
        XCTAssertFalse(store.isSending(normalizedLabel: "johndoe"))
        XCTAssertEqual(caster.calls.count, 1)
        XCTAssertEqual(caster.calls.first?.label, "johndoe")
        XCTAssertEqual(caster.calls.first?.nodes.map(\.proTxHash), [a.proTxHash, b.proTxHash])
    }

    /// AC-15, AC-06b: a masternode skipped for having no vote left is in the
    /// report as «No votes left», so a cancel that landed from the other one
    /// is a mixed result, not «Vote cancelled».
    func testAMasternodeSkippedForNoVotesLeftMakesTheOutcomeMixed() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(b)])

        await store.send(choice: .abstain, on: johndoe, from: [b], skipped: [a])

        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.succeeded.map(\.node.proTxHash), [b.proTxHash])
        XCTAssertEqual(report.failed.map(\.node.proTxHash), [a.proTxHash])
        XCTAssertEqual(report.failed.first?.failure, "No votes left")
        XCTAssertEqual(
            caster.calls.first?.nodes.map(\.proTxHash), [b.proTxHash], "nothing is sent from the skipped one")
    }

    /// A full refresh that ran while the vote was in flight already counted
    /// it; when the store cannot be read afterwards, the patch must not count
    /// the same vote again — a fourth vote stays a fourth, with one left.
    func testAVoteAFullRefreshAlreadyCountedIsNotCountedAgainWhenTheReReadFails() async throws {
        let (store, a, _, johndoe) = await makeVotingStore()
        history.records = [CastVoteRecord(
            proTxHash: a.proTxHash, normalizedLabel: "johndoe", choice: approve, castAt: epoch, castCount: 3)]
        await store.refresh()
        caster.history = nil
        caster.script = .outcomes([landed(a)])
        caster.holdNextCall = true

        let send = Task { await store.send(choice: approve, on: johndoe, from: [a]) }
        while !caster.started { await Task.yield() }
        // The caster wrote the fourth cast; a refresh reads it while the cast
        // is still returning.
        history.records = [CastVoteRecord(
            proTxHash: a.proTxHash, normalizedLabel: "johndoe", choice: approve, castAt: Date(), castCount: 4)]
        await store.refresh()
        XCTAssertEqual(store.voteHistoryByContest["johndoe"]?.votesLeft(a.proTxHash), 1)
        history.records = nil
        caster.release()
        await send.value

        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), 1, "the landed vote is counted once")
    }

    /// The twin: no load saw the vote, so when the store cannot be read
    /// afterwards the patch counts it — a fourth vote leaves one, not two.
    func testAVoteNoLoadSawIsCountedWhenTheReReadFails() async throws {
        let (store, a, _, johndoe) = await makeVotingStore()
        history.records = [CastVoteRecord(
            proTxHash: a.proTxHash, normalizedLabel: "johndoe", choice: approve, castAt: epoch, castCount: 3)]
        await store.refresh()
        caster.history = nil
        caster.script = .outcomes([landed(a)])
        caster.holdNextCall = true

        let send = Task { await store.send(choice: approve, on: johndoe, from: [a]) }
        while !caster.started { await Task.yield() }
        history.records = nil
        caster.release()
        await send.value

        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), 1, "the landed vote is counted")
    }

    /// Owner decision: Platform accepted the vote but the history write
    /// failed. The cast is spent all the same.
    func testLandedWithoutHistoryRecordStillSpendsACast() async throws {
        let (store, a, _, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a, recorded: false)])

        await store.send(choice: approve, on: johndoe, from: [a])

        guard case .success? = store.outcome else {
            return XCTFail("expected .success, got \(String(describing: store.outcome))")
        }
        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode - 1)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [approve])
    }

    /// The unrecorded cast stays spent when the contest's history is read
    /// again — opening Request details does that.
    func testUnrecordedCastStaysSpentAfterTheContestHistoryReloads() async throws {
        let (store, a, _, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a, recorded: false)])
        await store.send(choice: approve, on: johndoe, from: [a])

        await store.loadVotedNodes(for: "johndoe")

        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode - 1)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [approve])
        XCTAssertEqual(store.votedNodeCount(on: "johndoe"), 1)
    }

    /// Same across a pull-to-refresh, which re-reads every contest's history.
    func testUnrecordedCastStaysSpentAfterAFullRefresh() async throws {
        let (store, a, _, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a, recorded: false)])
        await store.send(choice: approve, on: johndoe, from: [a])

        await store.refresh()

        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode - 1)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [approve])
    }

    /// A recorded cast is in the store's rows; reading them again does not
    /// count it a second time.
    func testRecordedCastIsCountedOnceAfterAReload() async throws {
        let (store, a, _, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a)])
        await store.send(choice: approve, on: johndoe, from: [a])

        await store.loadVotedNodes(for: "johndoe")
        await store.refresh()

        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode - 1)
    }

    /// A full refresh read the history before the cast was written and applies
    /// what it read after the cast returned: the cast is still there.
    func testFullRefreshThatReadTheHistoryBeforeACastDoesNotEraseIt() async throws {
        let (store, a, _, johndoe) = await makeVotingStore()
        history.holdNextListRead = true
        let full = Task { await store.refresh() }
        while !history.listReadHeld { await Task.yield() }

        caster.script = .outcomes([landed(a)])
        let send = Task { await store.send(choice: approve, on: johndoe, from: [a]) }
        await yield(until: { caster.started })
        for _ in 0..<20 { await Task.yield() }
        history.releaseListRead()
        await full.value
        await send.value

        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode - 1)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [approve])
    }

    func testAllFailedGivesFailureOutcomeAndClearsInFlight() async throws {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([refused(a, "No votes left"), refused(b, "The vote was not cast. Check your connection and try again.")])

        await store.send(choice: approve, on: johndoe, from: [a, b])

        guard case .failure(let message)? = store.outcome else {
            return XCTFail("expected .failure, got \(String(describing: store.outcome))")
        }
        // Rule: the first failed outcome's message (already plain words, mapped by the caster).
        XCTAssertEqual(message, "No votes left")
        XCTAssertFalse(store.isSending(normalizedLabel: "johndoe"), "the pills are tappable again")
        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode)
        XCTAssertEqual(store.myChoices(on: "johndoe"), [])
    }

    /// The caster throws before anything is sent (here: the owner cancelled
    /// authentication): the outcome is the plain message of that error.
    func testThrownErrorGivesFailureWithThePlainMessage() async {
        let (store, a, _, johndoe) = await makeVotingStore()
        caster.script = .throwing(MasternodeVoteCaster.CastError.authenticationCancelled)

        await store.send(choice: approve, on: johndoe, from: [a])

        guard case .failure(let message)? = store.outcome else {
            return XCTFail("expected .failure, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(message, "Authentication cancelled. Your vote was not cast.")
        XCTAssertFalse(store.isSending(normalizedLabel: "johndoe"))
    }

    /// A contest kept after a full refresh left it out, which Platform had in
    /// fact closed: the caster's "closed" refusal closes it in the store, so no
    /// vote can start on it again, and its row stays until its voting end.
    func testClosedRefusalClosesAKeptContest() async {
        let (store, a, _, johndoe) = await makeVotingStore()
        contests.result = .success([])
        await store.refresh()
        XCTAssertFalse(store.isClosed(normalizedLabel: "johndoe"), "left out is not known to be closed")
        caster.script = .throwing(MasternodeVoteCaster.CastError.contestClosed("johndoe"))

        await store.send(choice: approve, on: johndoe, from: [a])

        XCTAssertTrue(store.isClosed(normalizedLabel: "johndoe"))
        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["johndoe"], "the row stays until its voting end")
        guard case .failure? = store.outcome else {
            return XCTFail("expected .failure, got \(String(describing: store.outcome))")
        }
    }

    /// A full refresh asked for before the cast, whose answer still lists the
    /// contest open, lands after the "closed" refusal: the contest stays closed.
    func testClosedRefusalOutlivesARefreshAskedForBeforeIt() async {
        let (store, a, _, johndoe) = await makeVotingStore()
        let loadsBefore = contests.loads
        contests.holdNextLoad = true
        let refresh = Task { await store.refresh() }
        while contests.loads == loadsBefore { await Task.yield() }
        caster.script = .throwing(MasternodeVoteCaster.CastError.contestClosed("johndoe"))

        let send = Task { await store.send(choice: approve, on: johndoe, from: [a]) }
        await yield(until: { caster.started })
        for _ in 0..<20 { await Task.yield() }
        contests.holdNextLoad = false
        contests.release()
        await refresh.value
        await send.value

        XCTAssertEqual(store.contests.map(\.normalizedLabel), ["johndoe"], "the refresh listed it open")
        XCTAssertTrue(store.isClosed(normalizedLabel: "johndoe"))
    }

    /// Any other refusal says nothing about the contest: it stays open.
    func testOtherRefusalLeavesTheContestOpen() async {
        let (store, a, _, johndoe) = await makeVotingStore()
        caster.script = .throwing(MasternodeVoteCaster.CastError.authenticationCancelled)

        await store.send(choice: approve, on: johndoe, from: [a])

        XCTAssertFalse(store.isClosed(normalizedLabel: "johndoe"))
    }

    func testThrownPlatformRefusalNeverShowsPlatformsText() async {
        let (store, a, _, johndoe) = await makeVotingStore()
        let raw = "Masternode with id: abc already voted 5 times and is trying to vote again"
        caster.script = .throwing(SDKError.consensusRejection(PlatformConsensusError(code: 40303, kind: .state), raw))

        await store.send(choice: approve, on: johndoe, from: [a])

        guard case .failure(let message)? = store.outcome else {
            return XCTFail("expected .failure, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(message, "No votes left")
    }

    func testMixedGivesReportAndCountsOnlyTheLandedOnes() async throws {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b)])

        await store.send(choice: approve, on: johndoe, from: [a, b])

        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.succeeded.map(\.node.proTxHash), [a.proTxHash])
        XCTAssertEqual(report.failed.map(\.node.proTxHash), [b.proTxHash])
        let limit = try XCTUnwrap(store.voteHistoryByContest["johndoe"])
        XCTAssertEqual(limit.votesLeft(a.proTxHash), VoteLimit.maxCastsPerNode - 1)
        XCTAssertEqual(limit.votesLeft(b.proTxHash), VoteLimit.maxCastsPerNode)
        XCTAssertEqual(store.votedNodeCount(on: "johndoe"), 1)
        XCTAssertFalse(store.isSending(normalizedLabel: "johndoe"))
    }

    // MARK: Try again after a mixed vote (AC-06b)

    func testTryAgainSendsOnlyTheFailedMasternodes() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])

        caster.script = .outcomes([landed(b)])
        await store.retryFailed()

        XCTAssertEqual(caster.calls.count, 2)
        XCTAssertEqual(caster.calls.last?.nodes.map(\.proTxHash), [b.proTxHash])
        XCTAssertEqual(caster.calls.last?.choice, approve)
    }

    func testTryAgainThatLandsEverywhereIsASuccess() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])

        caster.script = .outcomes([landed(b)])
        await store.retryFailed()

        guard case .success(let toast)? = store.outcome else {
            return XCTFail("expected .success, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(toast.message, "Voted \(johndoe.displayTitle) username")
    }

    func testTryAgainStillMixedKeepsEveryMasternodeInTheReport() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])

        caster.script = .outcomes([refused(b, "Still offline")])
        await store.retryFailed()

        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.succeeded.map(\.node.proTxHash), [a.proTxHash], "a's earlier vote still counts")
        XCTAssertEqual(report.failed.map(\.node.proTxHash), [b.proTxHash])
        XCTAssertEqual(report.failed.first?.failure, "Still offline")
    }

    func testTryAgainSkipsAFailedMasternodeWithNoVoteLeft() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])
        history.records?.append(CastVoteRecord(
            proTxHash: b.proTxHash, normalizedLabel: "johndoe", choice: .lock,
            castAt: epoch, castCount: VoteLimit.maxCastsPerNode))
        await store.loadVotedNodes(for: "johndoe")
        let callsBefore = caster.calls.count

        await store.retryFailed()

        XCTAssertEqual(caster.calls.count, callsBefore, "nothing is sent for a masternode out of votes")
        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.failed.map(\.node.proTxHash), [b.proTxHash])
        XCTAssertEqual(report.failed.first?.failure, "No votes left")
    }

    /// One vote at a time: while Try again reads the history its slot is
    /// held, so a vote on another name started meanwhile sends nothing.
    func testTryAgainHoldsTheVoteSlotWhileItReadsTheHistory() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])
        let callsBefore = caster.calls.count
        history.holdNextSingleRead = true

        let retry = Task { await store.retryFailed() }
        await yield(until: { self.history.singleReadHeld })
        XCTAssertTrue(store.isVoteBusy, "the retry's history read holds the slot")
        caster.script = .outcomes([landed(a)])
        let other = Task { await store.send(choice: .lock, on: self.contest("alice"), from: [a]) }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(caster.calls.count, callsBefore, "no other vote starts during the retry")

        history.releaseSingleRead()
        await retry.value
        await other.value
        XCTAssertFalse(store.isVoteBusy)
    }

    /// A newer attempt that replaced the outcome while Try again ran keeps it:
    /// the retry does not put its old report back.
    func testTryAgainDoesNotOverwriteANewerOutcome() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])
        history.holdNextSingleRead = true

        let retry = Task { await store.retryFailed() }
        await yield(until: { self.history.singleReadHeld })
        store.beginAttempt(on: "alice")
        caster.script = .outcomes([refused(b, "Still offline")])
        history.releaseSingleRead()
        await retry.value

        XCTAssertNil(store.outcome, "the newer attempt's (empty) outcome stays")
    }

    /// The vote gates' history read holds the slot, so the list's pills and
    /// Request details' button are off until the attempt sends or stops.
    func testAVoteGateReadHoldsTheVoteSlot() async {
        let (store, _, _, _) = await makeVotingStore()
        history.holdNextSingleRead = true

        let read = Task { await store.loadVotedNodesForVote(for: "johndoe") }
        await yield(until: { self.history.singleReadHeld })
        XCTAssertTrue(store.isVoteBusy)
        history.releaseSingleRead()
        _ = await read.value
        XCTAssertFalse(store.isVoteBusy)
    }

    /// The menu's host holds the swipe-back from this publisher: it tells the
    /// slot taken and given back, once each.
    func testTheBusyPublisherFollowsTheVoteSlot() async {
        let (store, _, _, _) = await makeVotingStore()
        var seen: [Bool] = []
        let watch = store.isVoteBusyPublisher.sink { seen.append($0) }
        defer { watch.cancel() }
        history.holdNextSingleRead = true

        let read = Task { await store.loadVotedNodesForVote(for: "johndoe") }
        await yield(until: { self.history.singleReadHeld })
        XCTAssertEqual(seen, [false, true])
        history.releaseSingleRead()
        _ = await read.value
        XCTAssertEqual(seen, [false, true, false])
    }

    /// AC-06b through the view model the vote gates use: their history read
    /// holds the vote slot, so no pill starts a second vote while it runs.
    func testAGateReadThroughTheViewModelKeepsThePillsOff() async {
        let (store, _, _, _) = await makeVotingStore()
        let voting = VotingViewModel(store: store)
        history.holdNextSingleRead = true

        let read = Task { await voting.voteHistory(for: "johndoe") }
        await yield(until: { self.history.singleReadHeld })
        XCTAssertFalse(voting.list.canTapPill(approve, on: "johndoe"))
        history.releaseSingleRead()
        _ = await read.value
        XCTAssertTrue(voting.list.canTapPill(approve, on: "johndoe"))
    }

    /// AC-15 through the view model: the masternodes skipped for having no
    /// vote left reach the store, so the outcome is mixed with their rows.
    func testTheViewModelForwardsTheNodesSkippedForNoVotesLeft() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        let voting = VotingViewModel(store: store)
        caster.script = .outcomes([landed(b)])

        await voting.send(approve, on: johndoe, from: [b.proTxHash], skipped: [a.proTxHash], pill: approve)

        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.failed.map(\.node.proTxHash), [a.proTxHash])
        XCTAssertTrue(report.failed.allSatisfy { $0.failure == NSLocalizedString("No votes left", comment: "Voting") })
    }

    /// SCR-10 «retrying»: the report stays on the sheet while Try again runs.
    func testTryAgainKeepsTheReportWhileItRuns() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])

        caster.script = .outcomes([landed(b)])
        caster.holdNextCall = true
        let retry = Task { await store.retryFailed() }
        while caster.calls.count < 2 { await Task.yield() }

        let whileRetrying = store.outcome
        guard case .mixed(let during)? = whileRetrying else {
            caster.release()
            await retry.value
            return XCTFail("expected the report while retrying, got \(String(describing: whileRetrying))")
        }
        XCTAssertEqual(during.failed.map(\.node.proTxHash), [b.proTxHash])
        XCTAssertTrue(store.isSending(normalizedLabel: "johndoe"))

        caster.release()
        await retry.value
        guard case .success? = store.outcome else {
            return XCTFail("expected .success after the retry, got \(String(describing: store.outcome))")
        }
    }

    /// Try again runs the vote gates again: a contest whose voting has ended
    /// gets nothing, and the report says why.
    func testTryAgainAfterVotingEndedSendsNothingAndSaysSo() async {
        let clock = TestClock(Date())
        let (store, a, b, johndoe) = await makeVotingStore(clock: clock)
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])
        let callsBefore = caster.calls.count

        clock.now = clock.now.addingTimeInterval(31 * day)
        await store.retryFailed()

        XCTAssertEqual(caster.calls.count, callsBefore)
        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.failed.map(\.node.proTxHash), [b.proTxHash])
        XCTAssertEqual(report.failed.first?.failure, "Voting has ended")
    }

    /// Platform closed the contest after the first try: Try again sends nothing.
    func testTryAgainOnAContestPlatformClosedSendsNothing() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])
        contests.voteStateResult = .success(resolved("johndoe", lock: 9))
        await store.refreshContest(normalizedLabel: "johndoe")
        XCTAssertTrue(store.isClosed(normalizedLabel: "johndoe"))
        let callsBefore = caster.calls.count

        await store.retryFailed()

        XCTAssertEqual(caster.calls.count, callsBefore)
        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.failed.first?.failure, "Voting has ended")
    }

    /// A history that cannot be read is unknown, not "No votes left".
    func testTryAgainWithAnUnreadableHistorySendsNothingAndSaysSo() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b])
        history.records = nil
        let callsBefore = caster.calls.count

        await store.retryFailed()

        XCTAssertEqual(caster.calls.count, callsBefore)
        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.failed.first?.failure, "Couldn't read your vote history.")
    }

    /// A failed masternode that holds the choice by now has it, also when
    /// every other failed masternode is out of votes.
    func testTryAgainCountsAHolderAsLandedWhenTheOthersHaveNoVoteLeft() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        let c = node(3)
        nodes.resolution = .init(nodes: [a, b, c], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash, c.proTxHash]
        store.refreshVotableNodes()
        caster.script = .outcomes([landed(a), refused(b, "Network error"), refused(c, "Network error")])
        await store.send(choice: approve, on: johndoe, from: [a, b, c])
        history.records?.append(vote(b, on: "johndoe", approve))
        history.records?.append(CastVoteRecord(
            proTxHash: c.proTxHash, normalizedLabel: "johndoe", choice: .lock,
            castAt: epoch, castCount: VoteLimit.maxCastsPerNode))
        let callsBefore = caster.calls.count

        await store.retryFailed()

        XCTAssertEqual(caster.calls.count, callsBefore)
        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(Set(report.succeeded.map(\.node.proTxHash)), [a.proTxHash, b.proTxHash])
        XCTAssertEqual(report.failed.map(\.node.proTxHash), [c.proTxHash])
        XCTAssertEqual(report.failed.first?.failure, "No votes left")
    }

    func testTryAgainWithoutAMixedOutcomeDoesNothing() async {
        let (store, _, _, _) = await makeVotingStore()

        await store.retryFailed()

        XCTAssertTrue(caster.calls.isEmpty)
        XCTAssertNil(store.outcome)
    }

    func testContestIsInFlightWhileTheCasterIsHeldAndASecondSendIsIgnored() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a)])
        caster.holdNextCall = true
        XCTAssertFalse(store.isSending(normalizedLabel: "johndoe"))

        let first = Task { await store.send(choice: approve, on: johndoe, from: [a]) }
        await yield(until: { caster.started })
        XCTAssertTrue(store.isSending(normalizedLabel: "johndoe"))
        XCTAssertFalse(store.isSending(normalizedLabel: "other"), "only the contest being sent is in flight")

        await store.send(choice: .lock, on: johndoe, from: [b])
        XCTAssertEqual(caster.calls.count, 1, "the second send on the same contest is ignored")

        caster.release()
        await first.value
        XCTAssertFalse(store.isSending(normalizedLabel: "johndoe"))
        XCTAssertEqual(caster.calls.count, 1)
    }

    /// One vote at a time, from every entry point: a send on another contest
    /// while one is in flight casts nothing, so the first send's report and
    /// Try again stay its own.
    func testASendOnAnotherContestWhileOneIsInFlightIsIgnored() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        let jane = contest("janedoe", endsAt: Date().addingTimeInterval(30 * day), lock: 1)
        caster.script = .outcomes([landed(a), refused(b, "Network error")])
        caster.holdNextCall = true

        let first = Task { await store.send(choice: approve, on: johndoe, from: [a, b]) }
        await yield(until: { caster.started })
        await store.send(choice: .lock, on: jane, from: [a])
        XCTAssertEqual(caster.calls.count, 1, "the second contest's send is ignored")

        caster.release()
        await first.value
        guard case .mixed(let report)? = store.outcome else {
            return XCTFail("expected johndoe's .mixed, got \(String(describing: store.outcome))")
        }
        XCTAssertEqual(report.normalizedLabel, "johndoe")
    }

    func testBeginAttemptClearsThePreviousOutcome() async {
        let (store, a, _, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a)])
        await store.send(choice: approve, on: johndoe, from: [a])
        XCTAssertNotNil(store.outcome)

        store.beginAttempt(on: "johndoe")

        XCTAssertNil(store.outcome)
    }

    /// A send clears the previous outcome before it casts: no old toast sits
    /// next to a vote in progress.
    func testSendClearsThePreviousOutcomeWhileItIsInFlight() async {
        let (store, a, b, johndoe) = await makeVotingStore()
        caster.script = .outcomes([landed(a)])
        await store.send(choice: approve, on: johndoe, from: [a])
        XCTAssertNotNil(store.outcome)

        caster.holdNextCall = true
        let second = Task { await store.send(choice: .abstain, on: johndoe, from: [b]) }
        while caster.calls.count < 2 { await Task.yield() }
        XCTAssertNil(store.outcome)

        caster.release()
        await second.value
    }

    // MARK: Plain-words error mapping (AC-06)

    private func consensus(_ code: UInt32) -> SDKError {
        .consensusRejection(PlatformConsensusError(code: code, kind: .state), "RAW-PLATFORM-TEXT \(code)")
    }

    func testPlatformTooManyVotesRefusalReadsNoVotesLeft() {
        XCTAssertEqual(VoteErrorMessage.plain(for: consensus(40303)), "No votes left")
    }

    func testNetworkFailuresReadAsAConnectionProblem() {
        let expected = "The vote was not cast. Check your connection and try again."
        XCTAssertEqual(VoteErrorMessage.plain(for: SDKError.networkError("RAW grpc status 14")), expected)
        XCTAssertEqual(VoteErrorMessage.plain(for: SDKError.timeout("RAW deadline")), expected)
        XCTAssertEqual(VoteErrorMessage.plain(for: URLError(.notConnectedToInternet)), expected)
    }

    func testClosedContestReadsAsClosed() {
        let expected = "The vote was not cast. Voting on this name has closed."
        XCTAssertEqual(VoteErrorMessage.plain(for: MasternodeVoteCaster.CastError.contestClosed("johndoe")), expected)
        XCTAssertEqual(VoteErrorMessage.plain(for: consensus(40302)), expected)
    }

    func testKeyNotOfAnActiveMasternodeReadsAsSuch() {
        let expected = "The vote was not cast. This voting key does not belong to an active masternode."
        XCTAssertEqual(VoteErrorMessage.plain(for: consensus(40300)), expected)
        XCTAssertEqual(VoteErrorMessage.plain(for: consensus(40305)), expected)
        XCTAssertEqual(VoteErrorMessage.plain(for: consensus(40306)), expected)
    }

    func testAuthenticationCancelledAndFailedReadAsNothingSent() {
        XCTAssertEqual(VoteErrorMessage.plain(for: MasternodeVoteCaster.CastError.authenticationCancelled),
                       "Authentication cancelled. Your vote was not cast.")
        XCTAssertEqual(VoteErrorMessage.plain(for: MasternodeVoteCaster.CastError.authenticationFailed),
                       "Authentication failed. Your vote was not cast.")
    }

    /// Anything unmapped gets the generic plain message, never Platform's text.
    func testUnknownErrorsNeverCarryRawText() {
        struct Odd: LocalizedError { var errorDescription: String? { "RAW-PLATFORM-TEXT odd" } }
        let generic = "The vote was not cast. Please try again."
        XCTAssertEqual(VoteErrorMessage.plain(for: Odd()), generic)
        XCTAssertEqual(VoteErrorMessage.plain(for: SDKError.internalError("RAW-PLATFORM-TEXT")), generic)
        XCTAssertEqual(VoteErrorMessage.plain(for: consensus(40307)), generic)
        XCTAssertFalse(VoteErrorMessage.plain(for: consensus(40304)).contains("RAW-PLATFORM-TEXT"))
    }
}
