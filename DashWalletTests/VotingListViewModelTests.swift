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
    var state: DPNSContestVoteState?
    func activeContests() async throws -> [DPNSContest] { try result.get() }
    func voteState(normalizedLabel: String) async throws -> DPNSContestVoteState? { state }
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

    /// AC-02: the banner over kept rows says it in plain words, never the
    /// error's own text.
    func testRefreshFailedBannerIsPlainWords() async {
        contests.result = .success([single("kept")])
        let store = makeStore()
        let list = makeList(store)
        await store.refresh()
        XCTAssertNil(list.refreshFailedText)

        contests.result = .failure(RawError())
        await store.refresh()

        XCTAssertEqual(list.refreshFailedText, "Couldn't refresh.")
        XCTAssertNil(list.emptyState, "the kept rows show")
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

        XCTAssertFalse(store.canStartVote(mine, on: "johndoe"), "a holds it already")
        XCTAssertTrue(list.canTapPill(mine, on: "johndoe"))
        let cancel = list.voteRequest(for: mine, on: johndoe)
        XCTAssertEqual(cancel.choice, .abstain)
        XCTAssertEqual(cancel.cancelling, mine)
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

        XCTAssertTrue(store.canStartVote(mine, on: "johndoe"), "b holds nothing and could cast it")
        XCTAssertTrue(list.canTapPill(mine, on: "johndoe"))
        let cancel = list.voteRequest(for: mine, on: johndoe)
        XCTAssertEqual(cancel.choice, .abstain)
        XCTAssertEqual(cancel.cancelling, mine)
    }

    func testFilledPillCannotBeTappedOnceTheContestClosed() async {
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

        contests.state = DPNSContestVoteState(normalizedLabel: "johndoe", contenders: [], abstainVotes: 0,
                                              lockVotes: 1, outcome: .locked, resolvedAt: epoch)
        await store.refreshContest(normalizedLabel: "johndoe")

        XCTAssertFalse(list.canTapPill(.lock, on: "johndoe"))
    }

    func testFilledPillCannotBeTappedWhenItsHolderHasNoVoteLeft() async {
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
        XCTAssertFalse(list.canTapPill(.lock, on: "johndoe"))
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
