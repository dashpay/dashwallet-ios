//
//  VotingListViewModelTests.swift
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
    var state: Result<DPNSContestVoteState?, Error> = .success(nil)
    /// Awaited before a list read answers, to hold a refresh in flight.
    var gate: (() async -> Void)?
    func activeContests() async throws -> [DPNSContest] {
        await gate?()
        return try result.get()
    }
    func voteState(normalizedLabel: String) async throws -> DPNSContestVoteState? { try state.get() }
}

private final class FakeNodes: VotableMasternodeResolving {
    var resolution = MasternodeVoterRegistry.Resolution(nodes: [], mayBeIncomplete: false)
    var isNodeListSynced = true
    func votableNodes() -> MasternodeVoterRegistry.Resolution { resolution }
}

/// Holds every cast until `release()`, so a test can look at a vote in flight.
private final class HeldCaster: VoteCasting {
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var started = false

    func cast(choice: VoteChoice, onNormalizedLabel normalizedLabel: String, with nodes: [VoterNode]) async throws
        -> VoteCastReport {
        started = true
        await withCheckedContinuation { gate = $0 }
        return VoteCastReport(normalizedLabel: normalizedLabel, choice: choice, outcomes: [])
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

private struct FakeCaster: VoteCasting {
    struct Unused: Error {}
    func cast(choice: VoteChoice, onNormalizedLabel normalizedLabel: String, with nodes: [VoterNode]) async throws
        -> VoteCastReport {
        throw Unused()
    }
}

private final class FakeHistory: VoteHistoryDAO {
    var records: [CastVoteRecord]? = []
    func record(_ record: CastVoteRecord, network: String) async throws {}
    func votes(forContest normalizedLabel: String, network: String) async -> [CastVoteRecord]? {
        records?.filter { $0.normalizedLabel == normalizedLabel }
    }
    /// While set, the next contests-wide read waits for ``releaseRead()``.
    var holdsNextRead = false
    private(set) var isHolding = false
    private var held: CheckedContinuation<Void, Never>?
    func releaseRead() {
        held?.resume()
        held = nil
    }
    func votes(forContests normalizedLabels: Set<String>, network: String) async -> [CastVoteRecord]? {
        if holdsNextRead {
            holdsNextRead = false
            isHolding = true
            await withCheckedContinuation { held = $0 }
            isHolding = false
        }
        return records?.filter { normalizedLabels.contains($0.normalizedLabel) }
    }
    func deleteAll() {}
}

private final class FakePrefs: VotingSelectionStoring {
    var votingNodeSelection: Set<Data> = []
    /// A wallet that set voting up, unless a test says otherwise.
    var isVotingSetUp = true
}

// MARK: - Tests

/// The list view model's several-request rows: expand in place, one approve
/// pill per request filled from the ticked nodes' votes, and the spoken labels.
@MainActor
final class VotingListViewModelTests: XCTestCase {

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

    private func makeStore() -> VotingStore {
        VotingStore(contests: contests, nodes: nodes, caster: FakeCaster(), history: history, prefs: prefs)
    }

    private func makeList(_ store: VotingStore) -> VotingListViewModel {
        VotingListViewModel(store: store, normalizedLabel: { $0.lowercased() })
    }

    private func node(_ byte: UInt8) -> VoterNode {
        VoterNode(proTxHash: Data([byte]), isEvonode: false, typeIndex: UInt32(byte),
                  serviceAddress: nil, keySource: .walletIndex(0))
    }

    private func contest(_ label: String, requests: Int) -> DPNSContest {
        let contenders = (1...requests).map {
            DPNSContender(identityId: "\(label)-id\($0)", voteTally: UInt32($0 * 2))
        }
        return DPNSContest(normalizedLabel: label, endTime: nil, hasWinner: false,
                           abstainVotes: 0, lockVotes: 0, contenders: contenders)
    }

    private func vote(_ node: VoterNode, on label: String, _ choice: VoteChoice) -> CastVoteRecord {
        CastVoteRecord(proTxHash: node.proTxHash, normalizedLabel: label, choice: choice, castAt: epoch)
    }

    // MARK: What the list shows instead of rows (AC-02, AC-08, AC-09)

    private struct RawError: LocalizedError {
        var errorDescription: String? { "Network Error: RAW-SDK-TEXT" }
    }

    private func single(_ label: String, lock: UInt32 = 0) -> DPNSContest {
        DPNSContest(normalizedLabel: label, endTime: nil, hasWinner: false, abstainVotes: 0, lockVotes: lock,
                    contenders: [DPNSContender(identityId: "\(label)-id1", voteTally: 1)])
    }

    /// One ticked node with a readable, empty history.
    private func votingWallet() {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
    }

    func testLoadingUntilTheFirstLoadFinishes() {
        XCTAssertEqual(makeList(makeStore()).emptyState, .loading)
    }

    func testFailedFirstLoadIsCouldNotLoad() async {
        contests.result = .failure(RawError())
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertEqual(list.emptyState, .couldNotLoad)
    }

    // MARK: The message above the rows (AC-02, AC-03b, AC-03c, AC-21)

    /// AC-02: a failed refresh over kept rows is a message above them, in
    /// plain words, never the error's own text; a later read that succeeds
    /// takes it away.
    func testRefreshFailedMessageOverKeptRowsGoesOnALaterSuccess() async {
        contests.result = .success([single("kept")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertNil(list.message)

        contests.result = .failure(RawError())
        await store.refresh()

        XCTAssertEqual(list.message, .refreshFailed)
        XCTAssertNil(list.emptyState, "the kept rows show")

        contests.result = .success([single("kept")])
        await store.refresh()

        XCTAssertNil(list.message)
    }

    /// An empty list read once, then a failed refresh: the no-contests state
    /// stays, with the message above it — not the full-screen error.
    func testRefreshFailedOverAnEmptyListKeepsTheEmptyState() async {
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        contests.result = .failure(RawError())
        await store.refresh()

        XCTAssertEqual(list.emptyState, .noContests)
        XCTAssertEqual(list.message, .refreshFailed)
    }

    /// No message while the first load runs, whatever the node list says.
    func testNoMessageDuringTheFirstLoad() {
        nodes.resolution = .init(nodes: [], mayBeIncomplete: true)
        let store = makeStore()
        store.refreshVotableNodes()
        let list = makeList(store)

        XCTAssertEqual(list.emptyState, .loading)
        XCTAssertNil(list.message)
    }

    /// No message with the full-screen error: no list read has succeeded yet.
    func testNoMessageWithTheFullScreenError() async {
        contests.result = .failure(RawError())
        history.records = nil
        nodes.resolution = .init(nodes: [], mayBeIncomplete: true)
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertEqual(list.emptyState, .couldNotLoad)
        XCTAssertNil(list.message)
    }

    /// One message at a time: the history first, then the failed refresh,
    /// then the incomplete node list; when one goes the next shows.
    func testOneMessageAtATimeInPriorityOrder() async {
        contests.result = .success([single("kept")])
        nodes.resolution = .init(nodes: [node(1)], mayBeIncomplete: true)
        history.records = nil
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertEqual(list.message, .historyUnavailable)

        contests.result = .failure(RawError())
        await store.refresh()
        XCTAssertEqual(list.message, .historyUnavailable, "the history outranks the failed refresh")

        history.records = []
        await store.refresh()
        XCTAssertEqual(list.message, .refreshFailed, "the failed refresh outranks the node list")

        contests.result = .success([single("kept")])
        await store.refresh()
        XCTAssertEqual(list.message, .nodeListIncomplete)

        nodes.resolution = .init(nodes: [node(1)], mayBeIncomplete: false)
        await store.refresh()
        XCTAssertNil(list.message)
    }

    /// AC-03c: a failed read of one contest keeps its last votes silently.
    func testFailedOneContestReadRaisesNoMessage() async {
        contests.result = .success([single("johndoe")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        contests.state = .failure(RawError())
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertNil(list.message)
    }

    /// The message stays while a pull to refresh or its own Try again runs,
    /// and its button shows that one is running.
    func testMessageStaysWhileARefreshRuns() async {
        contests.result = .success([single("kept")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        contests.result = .failure(RawError())
        await store.refresh()
        XCTAssertFalse(list.isTryingAgain)

        var release: CheckedContinuation<Void, Never>?
        contests.gate = { await withCheckedContinuation { release = $0 } }
        let running = Task { await list.tryAgain() }
        while release == nil { await Task.yield() }

        XCTAssertEqual(list.message, .refreshFailed)
        XCTAssertTrue(list.isTryingAgain)

        contests.result = .success([single("kept")])
        release?.resume()
        await running.value

        XCTAssertNil(list.message)
        XCTAssertFalse(list.isTryingAgain)
    }

    /// The copy of each message, and which of them offer Try again.
    func testMessageCopy() {
        XCTAssertEqual(VotingListMessage.refreshFailed.title, "Couldn't refresh the list.")
        XCTAssertNil(VotingListMessage.refreshFailed.subtitle)
        XCTAssertTrue(VotingListMessage.refreshFailed.offersTryAgain)

        XCTAssertEqual(VotingListMessage.nodeListIncomplete.title, "Some masternodes may be missing.")
        XCTAssertEqual(VotingListMessage.nodeListIncomplete.subtitle, "Finish syncing.")
        XCTAssertFalse(VotingListMessage.nodeListIncomplete.offersTryAgain)

        XCTAssertEqual(VotingListMessage.historyUnavailable.title, "Couldn't read your vote history.")
        XCTAssertEqual(VotingListMessage.historyUnavailable.subtitle, "Voting is paused.")
        XCTAssertTrue(VotingListMessage.historyUnavailable.offersTryAgain)
    }

    // MARK: Vote toasts (AC-06)

    func testClosingTheToastClearsIt() {
        let list = makeList(makeStore())
        list.showToast(.voted(username: "johndoe"))

        list.clearToast()

        XCTAssertNil(list.toast)
    }

    /// The tap that starts an attempt clears the last toast, before any dialog.
    func testAnAttemptStartingClearsTheToast() {
        let voting = VotingViewModel(store: makeStore())
        voting.list.showToast(.failed("No connection"))

        voting.attemptWillStart(on: single("johndoe"))

        XCTAssertNil(voting.toast)
    }

    /// AC-06b: the last vote's outcome goes at the tap too, so an attempt that
    /// ends without a send (a dialog cancelled, voting ended) never reopens
    /// the previous result sheet.
    func testAnAttemptStartingClearsTheLastOutcome() async {
        votingWallet()
        contests.result = .success([single("alice")])
        let store = makeStore()
        let voting = VotingViewModel(store: store)
        await store.refresh()
        await store.send(choice: .lock, on: single("alice"), from: store.votableNodes)
        XCTAssertNotNil(store.outcome)

        voting.attemptWillStart(on: single("alice"))

        XCTAssertNil(store.outcome)
    }

    /// AC-12: a vote the ticked masternodes already hold is told in a toast,
    /// not as an error.
    func testAVoteAlreadyHeldIsToldInASuccessToast() {
        let voting = VotingViewModel(store: makeStore())

        voting.reportAlreadyVoted(on: single("johndoe"))

        XCTAssertEqual(voting.toast?.message, "Your masternodes already voted this way on johndoe")
        XCTAssertEqual(voting.toast?.style, .success)
    }

    /// AC-15: a per-contest read that fails is an unknown history, even with
    /// one cached, and a vote that stops on it says so.
    func testAFailedHistoryReadStopsTheVoteAndSaysSo() async {
        votingWallet()
        contests.result = .success([single("alice")])
        history.records = [vote(node(1), on: "alice", .lock)]
        let store = makeStore()
        let voting = VotingViewModel(store: store)
        await store.refresh()
        XCTAssertNotNil(store.voteHistoryByContest["alice"]?.votesLeft(node(1).proTxHash))

        history.records = nil
        let limit = await voting.voteHistory(for: "alice")
        XCTAssertNil(limit.votesLeft(node(1).proTxHash), "unknown, not the cached history")

        let attempt = VoteAttemptCoordinator(host: voting)
        await attempt.start(.vote(.towards(identityId: "alice-id1")), on: single("alice"))
        XCTAssertNil(attempt.presentation)
        XCTAssertEqual(voting.toast?.message, "Couldn't read your vote history.")
        XCTAssertEqual(voting.toast?.style, .error)
    }

    /// AC-06b: the result sheet names the contest its report is about, not the
    /// contest of whatever request came last.
    func testTheResultSheetNamesTheReportsContest() async {
        let alice = DPNSContest(normalizedLabel: "alice", endTime: nil, hasWinner: false, abstainVotes: 0,
                                lockVotes: 0, contenders: [DPNSContender(identityId: "a", voteTally: 1)],
                                requestedLabels: ["Alice"])
        contests.result = .success([alice, single("bob")])
        let store = makeStore()
        let voting = VotingViewModel(store: store)
        await store.refresh()
        let report = VoteCastReport(normalizedLabel: "alice", choice: .lock,
                                    outcomes: [VoteOutcome(node: node(1), failure: nil),
                                               VoteOutcome(node: node(2), failure: "No connection")])

        XCTAssertEqual(voting.username(of: report), "Alice")
    }

    func testNoOpenContests() async {
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertEqual(list.emptyState, .noContests)
    }

    /// AC-08: the filter keeps nothing — never the no-contests state.
    func testFilterThatKeepsNothingIsNoMatchNotNoContests() async {
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.filter.type = .hasBlockedVotes

        XCTAssertEqual(list.emptyState, .filterMatchesNothing)
    }

    func testSearchThatFindsNothingIsNoSearchMatch() async {
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.searchQuery = "zzz"

        XCTAssertEqual(list.emptyState, .searchMatchesNothing)
    }

    func testRowsShowNoEmptyState() async {
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertNil(list.emptyState)
    }

    /// AC-09, no voting keys: the wallet holds no vote to filter by.
    func testMyVotesFilterWithoutVotingKeysCannotFilter() async {
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.filter.type = .notVoted

        guard case .cannotFilterByMyVotes(let reason)? = list.emptyState else {
            return XCTFail("expected cannot-filter, got \(String(describing: list.emptyState))")
        }
        XCTAssertTrue(reason.contains("voting keys"))
    }

    /// AC-09, history unavailable.
    func testMyVotesFilterWithUnreadableHistoryCannotFilter() async {
        votingWallet()
        history.records = nil
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.filter.type = .approved

        guard case .cannotFilterByMyVotes(let reason)? = list.emptyState else {
            return XCTFail("expected cannot-filter, got \(String(describing: list.emptyState))")
        }
        XCTAssertEqual(reason, "Pull down to try again.")
    }

    /// AC-09, the masternode list may be incomplete.
    func testMyVotesFilterWithAnIncompleteNodeListCannotFilter() async {
        votingWallet()
        nodes.resolution = .init(nodes: nodes.resolution.nodes, mayBeIncomplete: true)
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.filter.type = .notVoted

        guard case .cannotFilterByMyVotes(let reason)? = list.emptyState else {
            return XCTFail("expected cannot-filter, got \(String(describing: list.emptyState))")
        }
        XCTAssertTrue(reason.contains("missing from this list"))
    }

    /// Before the wallet's sync is done the nodes read so far may not be all
    /// of this wallet's, so its own votes cannot be told yet.
    func testMyVotesFilterBeforeTheWalletsSyncIsDoneCannotFilter() async {
        votingWallet()
        nodes.isNodeListSynced = false
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.filter.type = .notVoted

        XCTAssertFalse(list.canFilterByMyVotes)
        guard case .cannotFilterByMyVotes(let reason)? = list.emptyState else {
            return XCTFail("expected cannot-filter, got \(String(describing: list.emptyState))")
        }
        XCTAssertEqual(reason, "The masternode list is still syncing. Try again in a moment.")
    }

    /// AC-09, AC-12: before voting is set up no vote is this wallet's own, so
    /// the types that read them cannot filter — not even by the stored ticks.
    /// Setup alone, with the filter left as it was, lets the same ticks' votes
    /// filter.
    func testMyVotesFilterBeforeSetupCannotFilter() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        prefs.isVotingSetUp = false
        let alice = single("alice")
        contests.result = .success([alice])
        history.records = [vote(a, on: "alice", .towards(identityId: "alice-id1"))]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        for type in [VotingTypeFilter.notVoted, .approved] {
            list.filter.type = type
            guard case .cannotFilterByMyVotes(let reason)? = list.emptyState else {
                return XCTFail("\(type): expected cannot-filter, got \(String(describing: list.emptyState))")
            }
            XCTAssertEqual(reason, "Set up voting to filter by your votes.")
        }

        XCTAssertEqual(list.filter.type, .approved)

        store.confirmVotingSetup(ticked: [a.proTxHash])

        XCTAssertNil(list.emptyState)
        XCTAssertEqual(list.visibleContests.map(\.normalizedLabel), ["alice"])
    }

    /// With the votes known, a my-votes filter that keeps nothing is a plain no-match.
    func testMyVotesFilterWithKnownVotesThatKeepsNothingIsNoMatch() async {
        votingWallet()
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.filter.type = .approved

        XCTAssertEqual(list.emptyState, .filterMatchesNothing)
    }

    /// AC-09: after a refresh adds a contest whose history is still loading,
    /// a filter by my vote shows the loading state, not only the contests
    /// already known.
    func testMyVotesFilterWaitsForTheHistoryOfNewContests() async {
        votingWallet()
        contests.result = .success([single("alice")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        list.filter.type = .notVoted
        XCTAssertEqual(list.visibleContests.map(\.normalizedLabel), ["alice"])

        contests.result = .success([single("alice"), single("bob")])
        history.holdsNextRead = true
        let refresh = Task { await store.refresh() }
        for _ in 0..<1000 where !history.isHolding { await Task.yield() }
        XCTAssertTrue(history.isHolding, "the history read did not start")

        XCTAssertTrue(list.visibleContests.isEmpty)
        XCTAssertEqual(list.emptyState, .loading)

        history.releaseRead()
        await refresh.value
        XCTAssertEqual(Set(list.visibleContests.map(\.normalizedLabel)), ["alice", "bob"])
    }

    // MARK: The row header's VoiceOver hint (AC-10, AC-11)

    func testHeaderHintSaysWhatTheTapDoes() async {
        contests.result = .success([contest("solo", requests: 1), contest("many", requests: 3)])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        let solo = contest("solo", requests: 1), many = contest("many", requests: 3)

        XCTAssertEqual(list.headerAccessibilityHint(for: solo), "Opens the request details")
        XCTAssertEqual(list.headerAccessibilityHint(for: many), "Opens the requests for this name")

        list.toggleExpanded("many")

        XCTAssertEqual(list.headerAccessibilityHint(for: many), "Hides the requests for this name")
    }

    /// A name with no requests has nothing to open: no hint, and the card
    /// disables its header.
    func testHeaderOfANameWithNoRequestsHasNoHint() {
        let list = makeList(makeStore())
        let none = DPNSContest(normalizedLabel: "none", endTime: nil, hasWinner: false,
                               abstainVotes: 0, lockVotes: 2, contenders: [])

        XCTAssertNil(list.headerAccessibilityHint(for: none))
    }

    // MARK: Day groups follow the time zone (AC-01)

    /// The zone changes while the list is open: the next recompute (the
    /// screen's significant-time-change hook) groups by the new zone. 23:30
    /// UTC on 2 Nov is today in UTC and tomorrow in Kyiv.
    func testATimeZoneChangeRegroupsTheLiveList() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8)))
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 23, minute: 30)))
        contests.result = .success([DPNSContest(normalizedLabel: "late", endTime: end, hasWinner: false,
                                                abstainVotes: 0, lockVotes: 0, contenders: [])])
        let store = makeStore()
        let list = VotingListViewModel(
            store: store, normalizedLabel: { $0.lowercased() }, now: { now }, calendar: { calendar })
        await store.refresh()
        XCTAssertEqual(list.sections.map(\.daysLeft), [0])

        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Kyiv"))
        list.recomputeVisible()

        XCTAssertEqual(list.sections.map(\.daysLeft), [1])
    }

    // MARK: The row's "You voted" line (AC-07, AC-17)

    /// An abstain takes a vote back: a name whose ticked nodes only abstain is
    /// listed under "I have not voted", so its row must not say "You voted".
    func testAbstainOnlyRowSaysNothingVoted() {
        let one = contest("johndoe", requests: 1)
        let several = contest("alice", requests: 3)

        XCTAssertFalse(VotingContestCard.hasVoteWithoutPill([.abstain], contenders: one.contenders, isExpanded: false))
        XCTAssertFalse(VotingContestCard.hasVoteWithoutPill(
            [.abstain], contenders: several.contenders, isExpanded: false))
    }

    /// An approve on a collapsed several-request name has no pill on the row:
    /// the line says it, with or without an abstain next to it.
    func testApproveNoPillCarriesSaysYouVoted() {
        let several = contest("alice", requests: 3)
        let approve = VoteChoice.towards(identityId: "alice-id2")

        XCTAssertTrue(VotingContestCard.hasVoteWithoutPill(
            [approve], contenders: several.contenders, isExpanded: false))
        XCTAssertTrue(VotingContestCard.hasVoteWithoutPill(
            [approve, .abstain], contenders: several.contenders, isExpanded: false))
        XCTAssertFalse(VotingContestCard.hasVoteWithoutPill(
            [approve], contenders: several.contenders, isExpanded: true), "expanded, its pill carries it")
        XCTAssertFalse(VotingContestCard.hasVoteWithoutPill([.lock], contenders: several.contenders, isExpanded: false))
    }

    // MARK: Expand and collapse (AC-10)

    func testTogglingExpandsThenTappingAgainCollapses() async {
        contests.result = .success([contest("johndoe", requests: 3)])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertFalse(list.isExpanded("johndoe"), "collapsed by default")

        list.toggleExpanded("johndoe")
        XCTAssertTrue(list.isExpanded("johndoe"))

        list.toggleExpanded("johndoe")
        XCTAssertFalse(list.isExpanded("johndoe"))
    }

    func testExpandStateIsPerContest() async {
        contests.result = .success([contest("johndoe", requests: 3), contest("janedoe", requests: 2)])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        list.toggleExpanded("johndoe")

        XCTAssertTrue(list.isExpanded("johndoe"))
        XCTAssertFalse(list.isExpanded("janedoe"))
    }

    func testRowStaysExpandedAcrossAFilterChangeAndARefreshWhileShown() async {
        contests.result = .success([contest("johndoe", requests: 3), contest("solo", requests: 1)])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        list.toggleExpanded("johndoe")

        list.filter.onlyDuplicates = true
        XCTAssertEqual(list.visibleContests.map(\.normalizedLabel), ["johndoe"])
        XCTAssertTrue(list.isExpanded("johndoe"), "still shown after a filter change")

        await store.refresh()
        XCTAssertTrue(list.isExpanded("johndoe"), "still shown after a refresh")
    }

    func testOneRequestContestIsNotExpandable() async {
        contests.result = .success([contest("solo", requests: 1), contest("johndoe", requests: 3)])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertFalse(list.isExpandable(contest("solo", requests: 1)))
        XCTAssertTrue(list.isExpandable(contest("johndoe", requests: 3)))

        list.toggleExpanded("solo")
        XCTAssertFalse(list.isExpanded("solo"), "no expand pill, so nothing to expand")
    }

    // MARK: Per-request fill

    func testOnlyTheRequestCarryingMyVoteIsFilled() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let johndoe = contest("johndoe", requests: 3)
        contests.result = .success([johndoe])
        history.records = [vote(a, on: "johndoe", .towards(identityId: "johndoe-id2"))]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        let rows = list.requestRows(for: johndoe)

        XCTAssertEqual(rows.map(\.identityId), ["johndoe-id1", "johndoe-id2", "johndoe-id3"])
        XCTAssertEqual(rows.map(\.isMine), [false, true, false])
        XCTAssertEqual(rows.map(\.votes), [2, 4, 6])
    }

    func testNoRequestIsFilledWhenOnlyAnUntickedNodeVoted() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let johndoe = contest("johndoe", requests: 3)
        contests.result = .success([johndoe])
        history.records = [vote(b, on: "johndoe", .towards(identityId: "johndoe-id2"))]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertEqual(list.requestRows(for: johndoe).map(\.isMine), [false, false, false])
    }

    // MARK: Pill taps (AC-17)

    /// A filled pill is the way to take my vote back, so it is not shown as
    /// disabled although no ticked node can cast that choice again.
    func testFilledPillStaysTappableAndTakesTheVoteBack() async throws {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let johndoe = contest("johndoe", requests: 2)
        contests.result = .success([johndoe])
        let mine = VoteChoice.towards(identityId: "johndoe-id2")
        history.records = [vote(a, on: "johndoe", mine)]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertEqual(store.liveChoice(of: a, on: "johndoe"), mine, "a holds it already")
        XCTAssertTrue(list.canTapPill(mine, on: "johndoe"))
        let cancel = list.voteRequest(for: mine, on: johndoe)
        XCTAssertEqual(cancel.choice, .abstain)
        XCTAssertEqual(cancel.cancelling, mine)
    }

    /// screens.md SCR-01 «sending»: the tapped pill shows progress while its
    /// vote is sent, and the contest's other pills are disabled, not busy.
    func testWhileAVoteIsSentOnlyTheTappedPillIsBusy() async {
        votingWallet()
        let alice = single("alice")
        contests.result = .success([alice])
        let caster = HeldCaster()
        let store = VotingStore(contests: contests, nodes: nodes, caster: caster, history: history, prefs: prefs)
        let voting = VotingViewModel(store: store)
        await store.refresh()
        let approve = VoteChoice.towards(identityId: "alice-id1")
        let attempt = VoteAttemptCoordinator(host: voting)

        let send = Task { await attempt.start(.vote(approve), on: alice) }
        await yield(until: { caster.started })

        XCTAssertEqual(voting.list.sendingPill(on: "alice"), approve)
        XCTAssertEqual(
            VotingContestCard.pillStatus(of: approve, isCasting: true, sendingPill: approve, canTap: true), .busy)
        XCTAssertEqual(
            VotingContestCard.pillStatus(of: .lock, isCasting: true, sendingPill: approve, canTap: true), .disabled)

        caster.release()
        await send.value
        XCTAssertNil(voting.list.sendingPill(on: "alice"))
    }

    /// A pill tapped earlier, whose attempt ended at a dialog, is not the pill
    /// of the next send: a send that did not start from a pill (Try again)
    /// names none, and the card busies every pill.
    func testAnEarlierTapIsNotTheNextSendsPill() async {
        votingWallet()
        let alice = single("alice")
        contests.result = .success([alice])
        let caster = HeldCaster()
        let store = VotingStore(contests: contests, nodes: nodes, caster: caster, history: history, prefs: prefs)
        let voting = VotingViewModel(store: store)
        await store.refresh()
        _ = voting.list.voteRequest(for: .lock, on: alice)

        let send = Task { await store.send(choice: .lock, on: alice, from: store.votableNodes) }
        await yield(until: { caster.started })

        XCTAssertNil(voting.list.sendingPill(on: "alice"))
        caster.release()
        await send.value
    }

    /// One vote at a time: while a vote on one name is sent, no pill of any
    /// other name takes a tap, so its report and Try again stay its own.
    func testWhileAVoteIsSentNoOtherNamesPillTakesATap() async {
        votingWallet()
        let alice = single("alice"), bob = single("bob")
        contests.result = .success([alice, bob])
        let caster = HeldCaster()
        let store = VotingStore(contests: contests, nodes: nodes, caster: caster, history: history, prefs: prefs)
        let voting = VotingViewModel(store: store)
        await store.refresh()
        XCTAssertTrue(voting.list.canTapPill(.lock, on: "bob"))

        let attempt = VoteAttemptCoordinator(host: voting)
        let send = Task { await attempt.start(.vote(.towards(identityId: "alice-id1")), on: alice) }
        await yield(until: { caster.started })

        XCTAssertFalse(voting.list.canTapPill(.lock, on: "bob"))
        XCTAssertFalse(voting.list.canTapPill(.towards(identityId: "bob-id1"), on: "bob"))
        caster.release()
        await send.value
        XCTAssertTrue(voting.list.canTapPill(.lock, on: "bob"))
    }

    /// AC-14: «Voting with» names what a tap would vote with. With every
    /// masternode unticked after setup that is nothing, so it asks to select.
    func testVotingWithAsksToSelectWhenNothingIsTicked() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let store = makeStore()
        let voting = VotingViewModel(store: store)
        await store.refresh()

        store.setTick(a.proTxHash, false)

        XCTAssertEqual(voting.votingWithSummary, "Select nodes")
    }

    /// Before voting is set up a tap opens «Add your voting keys», so «Voting
    /// with» names no node — not the first one, nor a stored tick.
    func testVotingWithAsksToSelectBeforeSetup() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        prefs.isVotingSetUp = false
        let store = makeStore()
        let voting = VotingViewModel(store: store)
        await store.refresh()

        XCTAssertEqual(voting.votingWithSummary, "Select nodes")
    }

    /// AC-12, AC-17: before voting is set up no pill is filled — not even
    /// by a vote the stored ticks hold — so a tap asks for its own choice and
    /// «Add your voting keys» casts what its button says. Once set up, the
    /// same history fills the pill.
    func testBeforeSetupAStoredTicksVoteFillsNoPill() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        prefs.isVotingSetUp = false
        let johndoe = contest("johndoe", requests: 2)
        contests.result = .success([johndoe])
        history.records = [vote(a, on: "johndoe", .lock)]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertEqual(store.myChoices(on: "johndoe"), [])
        let request = list.voteRequest(for: .lock, on: johndoe)
        XCTAssertEqual(request.choice, .lock)
        XCTAssertNil(request.cancelling)

        store.confirmVotingSetup(ticked: [a.proTxHash])

        XCTAssertEqual(store.myChoices(on: "johndoe"), [.lock])
    }

    func testOutlinedPillAsksForItsOwnChoice() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let johndoe = contest("johndoe", requests: 2)
        contests.result = .success([johndoe])
        history.records = [vote(a, on: "johndoe", .towards(identityId: "johndoe-id2"))]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        let other = VoteChoice.towards(identityId: "johndoe-id1")
        XCTAssertTrue(list.canTapPill(other, on: "johndoe"))
        let request = list.voteRequest(for: other, on: johndoe)
        XCTAssertEqual(request.choice, other)
        XCTAssertNil(request.cancelling)
    }

    /// AC-17: a tap on a filled pill cancels even when another ticked node
    /// could still cast that choice, instead of casting it again from that node.
    func testFilledPillCancelsAlthoughAnotherTickedNodeCouldCastIt() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        let johndoe = contest("johndoe", requests: 2)
        contests.result = .success([johndoe])
        let mine = VoteChoice.towards(identityId: "johndoe-id2")
        history.records = [vote(a, on: "johndoe", mine)]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertNil(store.liveChoice(of: b, on: "johndoe"), "b holds nothing and could cast it")
        XCTAssertTrue(list.canTapPill(mine, on: "johndoe"))
        let cancel = list.voteRequest(for: mine, on: johndoe)
        XCTAssertEqual(cancel.choice, .abstain)
        XCTAssertEqual(cancel.cancelling, mine)
    }

    /// AC-03: the row stays as it was once the contest closes; a tap is told
    /// that voting has ended instead of doing nothing.
    func testFilledPillStaysTappableOnceTheContestClosed() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let johndoe = DPNSContest(
            normalizedLabel: "johndoe", endTime: Date().addingTimeInterval(86_400), hasWinner: false,
            abstainVotes: 0, lockVotes: 0, contenders: [DPNSContender(identityId: "johndoe-id1", voteTally: 2)])
        contests.result = .success([johndoe])
        history.records = [vote(a, on: "johndoe", .lock)]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertTrue(list.canTapPill(.lock, on: "johndoe"), "open: the filled pill takes the vote back")

        contests.state = .success(DPNSContestVoteState(normalizedLabel: "johndoe", contenders: [], abstainVotes: 0,
                                                       lockVotes: 1, outcome: .locked, resolvedAt: epoch))
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertTrue(list.canTapPill(.lock, on: "johndoe"))
    }

    /// AC-15: a tap after the fifth vote shows "No votes left", so the pill is
    /// not disabled ahead of it.
    func testFilledPillStaysTappableWhenItsHolderHasNoVoteLeft() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest("johndoe", requests: 2)])
        history.records = [CastVoteRecord(proTxHash: a.proTxHash, normalizedLabel: "johndoe", choice: .lock,
                                          castAt: epoch, castCount: VoteLimit.maxCastsPerNode)]
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertEqual(store.myChoices(on: "johndoe"), [.lock])
        XCTAssertTrue(list.canTapPill(.lock, on: "johndoe"))
        XCTAssertTrue(list.canTapPill(.towards(identityId: "johndoe-id1"), on: "johndoe"))
    }

    /// Voting is paused while the vote history cannot be read: no pill takes a tap.
    func testNoPillIsTappableWhileTheHistoryCannotBeRead() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest("johndoe", requests: 2)])
        history.records = nil
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        XCTAssertTrue(store.historyUnavailable)
        XCTAssertFalse(list.canTapPill(.lock, on: "johndoe"))
        XCTAssertFalse(list.canTapPill(.towards(identityId: "johndoe-id1"), on: "johndoe"))
    }

    // MARK: Subtitle and VoiceOver strings

    /// A filled pill that can be tapped says it takes my vote back; an
    /// outlined, disabled or busy pill says nothing more than its label.
    func testOnlyATappableFilledPillHasTheTakeBackHint() {
        XCTAssertEqual(VotingContestCard.pillAccessibilityHint(isSelected: true, status: .enabled),
                       "Takes your vote back")
        XCTAssertNil(VotingContestCard.pillAccessibilityHint(isSelected: false, status: .enabled))
        XCTAssertNil(VotingContestCard.pillAccessibilityHint(isSelected: true, status: .disabled))
        XCTAssertNil(VotingContestCard.pillAccessibilityHint(isSelected: true, status: .busy))
    }

    func testRequestCountSubtitle() {
        let list = makeList(makeStore())
        XCTAssertEqual(list.requestCountText(for: contest("johndoe", requests: 3)), "3 requests")
    }

    func testExpandPillSpeaksStateAndRequestCount() {
        let list = makeList(makeStore())
        let johndoe = contest("johndoe", requests: 3)

        XCTAssertEqual(list.expandAccessibilityLabel(for: johndoe, isExpanded: false), "Show requests for johndoe")
        XCTAssertEqual(list.expandAccessibilityLabel(for: johndoe, isExpanded: true), "Hide requests for johndoe")
        XCTAssertEqual(list.expandAccessibilityValue(for: johndoe), "3 requests")
    }

    func testRequestApprovePillSpeaksIdentityAndVotes() async {
        let johndoe = contest("johndoe", requests: 3)
        contests.result = .success([johndoe])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()

        let row = list.requestRows(for: johndoe)[1]

        XCTAssertEqual(row.accessibilityLabel, "Approve john … -id2")
        XCTAssertEqual(row.accessibilityValue, "4 votes")
    }
}

// MARK: - VotingRequestRow

final class VotingRequestRowTests: XCTestCase {
    /// VoiceOver reads a request by its first and last four characters, not
    /// the whole 44-character id.
    func testARequestIsSpokenByAShortIdentity() {
        let row = VotingRequestRow(identityId: "Hx4kP9mT2pLw8RzYb5NcHf7Ud4EaQ1sV3jK6nB2cD8gF", votes: 3, isMine: false)

        XCTAssertEqual(row.spokenIdentity, "Hx4k … D8gF")
        XCTAssertFalse(row.accessibilityLabel.contains(row.identityId))
        XCTAssertTrue(row.accessibilityLabel.contains("Hx4k … D8gF"))
    }

    func testAShortIdIsSpokenWhole() {
        XCTAssertEqual(VotingRequestRow(identityId: "abc", votes: 0, isMine: false).spokenIdentity, "abc")
    }
}
