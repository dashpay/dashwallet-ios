//
//  RequestDetailsViewModelTests.swift
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

/// Lands every vote on every node it is given.
private struct LandingCaster: VoteCasting {
    func cast(choice: VoteChoice, onNormalizedLabel normalizedLabel: String, with nodes: [VoterNode]) async throws
        -> VoteCastReport {
        VoteCastReport(normalizedLabel: normalizedLabel, choice: choice,
                       outcomes: nodes.map { VoteOutcome(node: $0, failure: nil) })
    }
}

private final class FakeHistory: VoteHistoryDAO {
    var records: [CastVoteRecord]? = []
    func record(_ record: CastVoteRecord, network: String) async throws {}
    func votes(forContest normalizedLabel: String, network: String) async -> [CastVoteRecord]? {
        records?.filter { $0.normalizedLabel == normalizedLabel }
    }
    func votes(forContests normalizedLabels: Set<String>, network: String) async -> [CastVoteRecord]? {
        records?.filter { normalizedLabels.contains($0.normalizedLabel) }
    }
    func deleteAll() {}
}

private final class FakePrefs: VotingSelectionStoring {
    var votingNodeSelection: Set<Data> = []
    /// A wallet that set voting up, unless a test says otherwise.
    var isVotingSetUp = true
}

private struct LookupFailure: Error {}

// MARK: - Tests

/// Request details: what the screen shows for one request, the link states,
/// and whether the action approves or cancels an approval.
@MainActor
final class RequestDetailsViewModelTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let label = "johndoe"
    private let identityId = "johndoe-id2"
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

    private var votingEnd: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 25
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    /// en_US + UTC, medium date: «Oct 25, 2026».
    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private func node(_ byte: UInt8) -> VoterNode {
        VoterNode(proTxHash: Data([byte]), isEvonode: false, typeIndex: UInt32(byte),
                  serviceAddress: nil, keySource: .walletIndex(0))
    }

    private func contest(endTime: Date? = nil, requestDates: [Date?] = [nil, nil]) -> DPNSContest {
        let contenders = [
            DPNSContender(identityId: "johndoe-id1", voteTally: 2, displayLabel: "JohnDoe", createdAt: requestDates[0]),
            DPNSContender(identityId: identityId, voteTally: 4, displayLabel: "johndoe", createdAt: requestDates[1])
        ]
        return DPNSContest(normalizedLabel: label, endTime: endTime, hasWinner: false,
                           abstainVotes: 0, lockVotes: 0, contenders: contenders)
    }

    private func vote(_ node: VoterNode, _ choice: VoteChoice) -> CastVoteRecord {
        CastVoteRecord(proTxHash: node.proTxHash, normalizedLabel: label, choice: choice, castAt: epoch)
    }

    private func makeStore(
        link: @escaping @MainActor (String, String) async throws -> URL? = { _, _ in nil }
    ) async -> VotingStore {
        let store = VotingStore(contests: contests, nodes: nodes, caster: FakeCaster(), history: history,
                                prefs: prefs, linkLookup: VotingStore.lookingUpEachRequest(link))
        await store.refresh()
        return store
    }

    /// Links handed to the system to open.
    private var opened: [URL] = []

    private func makeVM(_ store: VotingStore) -> RequestDetailsViewModel {
        RequestDetailsViewModel(store: store, normalizedLabel: label, identityId: identityId,
                                dateFormatter: formatter,
                                openLink: { [weak self] in self?.opened.append($0) })
    }

    // MARK: Fields (AC-11)

    func testShowsUsernameIdentityAndVotingEndFromTheStore() async {
        contests.result = .success([contest(endTime: votingEnd)])
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.username, "johndoe")
        XCTAssertEqual(vm.identityId, "johndoe-id2")
        XCTAssertEqual(vm.votingEnd, votingEnd)
    }

    func testTheVotingPeriodRunsFromTheEarliestRequestDateToTheVotingEnd() async {
        let earlier = votingEnd.addingTimeInterval(-14 * 86_400)
        contests.result = .success([contest(
            endTime: votingEnd, requestDates: [earlier, earlier.addingTimeInterval(86_400)])])
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.votingPeriodStart, earlier, "the other request was first, not this one")
        XCTAssertEqual(vm.votingPeriodText, "\(formatter.string(from: earlier)) – Oct 25, 2026")
    }

    /// A one-contest read that returned a full page may have cut the first
    /// request off: the start is not provided until a list refresh.
    func testAPossiblyCutReadLeavesThePeriodStartNotProvided() async {
        contests.result = .success([contest(endTime: votingEnd, requestDates: [votingEnd, votingEnd])])
        let store = await makeStore()
        contests.state = DPNSContestVoteState(
            normalizedLabel: label,
            contenders: (1...VotingStore.contestReadRequestLimit).map {
                DPNSContender(identityId: "\(label)-id\($0)", voteTally: 0, createdAt: votingEnd)
            },
            abstainVotes: 0, lockVotes: 0, outcome: .ongoing, resolvedAt: nil)
        await store.refreshContest(normalizedLabel: label)
        let vm = makeVM(store)

        XCTAssertNil(vm.votingPeriodStart)
        XCTAssertEqual(vm.votingPeriodText, "Not provided – Oct 25, 2026")
    }

    func testAnUndatedRequestLeavesThePeriodStartNotProvided() async {
        contests.result = .success([contest(endTime: votingEnd, requestDates: [nil, votingEnd])])
        let vm = makeVM(await makeStore())

        XCTAssertNil(vm.votingPeriodStart)
        XCTAssertEqual(vm.votingPeriodText, "Not provided – Oct 25, 2026")
    }

    // MARK: Link states

    func testLinkStartsInReadingStateBeforeTheLookupRuns() async {
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.linkState, .reading)
        XCTAssertNil(vm.linkText, "no text while the check is in flight")
    }

    func testNoPublishedLinkReadsNotProvided() async {
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore(link: { _, _ in nil }))

        await vm.loadLink()

        XCTAssertEqual(vm.linkState, .none)
        XCTAssertEqual(vm.linkText, "Not provided")
    }

    func testFailedLookupReadsCouldntCheckAndNeverNotProvided() async {
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore(link: { _, _ in throw LookupFailure() }))

        await vm.loadLink()

        XCTAssertEqual(vm.linkState, .failed)
        XCTAssertEqual(vm.linkText, "Couldn't check for a link")
        XCTAssertNotEqual(vm.linkText, "Not provided", "the check never ran (guardrail 3)")
    }

    func testPublishedLinkShowsTheFullURL() async {
        contests.result = .success([contest()])
        let url = URL(string: "https://example.com/proof/johndoe")!
        let vm = makeVM(await makeStore(link: { _, _ in url }))

        await vm.loadLink()

        XCTAssertEqual(vm.linkState, .published(url))
        XCTAssertEqual(vm.linkText, "https://example.com/proof/johndoe")
    }

    func testLookupIsAskedForThisRequestsLabelAndIdentity() async {
        contests.result = .success([contest()])
        var asked: (String, String)?
        let vm = makeVM(await makeStore(link: { label, identity in
            asked = (label, identity)
            return nil
        }))

        await vm.loadLink()

        XCTAssertEqual(asked?.0, "johndoe")
        XCTAssertEqual(asked?.1, "johndoe-id2")
    }

    func testStateIsReadingWhileAReopenChecksAFailedLinkAgain() async {
        contests.result = .success([contest()])
        var release: CheckedContinuation<URL?, Error>?
        var started = false
        var first = true
        let vm = makeVM(await makeStore(link: { _, _ in
            if first { first = false; throw LookupFailure() }
            started = true
            return try await withCheckedThrowingContinuation { release = $0 }
        }))
        await vm.loadLink()
        XCTAssertEqual(vm.linkState, .failed)

        // Request details opened again: its `.task` asks once more.
        let retry = Task { await vm.loadLink() }
        await yield(until: { started })

        XCTAssertEqual(vm.linkState, .reading)
        release?.resume(returning: nil)
        await retry.value
        XCTAssertEqual(vm.linkState, .none)
    }

    func testTryAgainAsksForTheLinkWithoutWaitingForIt() async {
        contests.result = .success([contest()])
        var release: CheckedContinuation<URL?, Error>?
        var first = true
        let vm = makeVM(await makeStore(link: { _, _ in
            if first { first = false; throw LookupFailure() }
            return try await withCheckedThrowingContinuation { release = $0 }
        }))
        await vm.loadLink()
        XCTAssertEqual(vm.linkState, .failed)

        // Returns at once: nothing is left waiting when the screen closes.
        vm.retryLink()
        XCTAssertEqual(vm.linkState, .reading)

        await yield(until: { release != nil })
        release?.resume(returning: nil)
        await yield(until: { vm.linkState != .reading })
        XCTAssertEqual(vm.linkState, .none, "the lookup itself still fills the store")
    }

    func testTryAgainIsLookedUpBeforeTheNamesWaitingForTheFilter() async {
        contests.result = .success([contest()])
        var held: [(label: String, answer: CheckedContinuation<URL?, Error>)] = []
        var first = true
        let store = await makeStore(link: { label, _ in
            if first { first = false; throw LookupFailure() }
            return try await withCheckedThrowingContinuation { held.append((label, $0)) }
        })
        let vm = makeVM(store)
        await vm.loadLink()
        XCTAssertEqual(vm.linkState, .failed)

        // The links filter: four names looked up, name5 waiting.
        store.askForLinks(Set((1...5).map { VotingStore.RequestKey(normalizedLabel: "name\($0)", identityId: "id") }),
                          retryingFailed: false)
        await yield(until: { held.count == 4 })
        guard held.count == 4 else { return }

        vm.retryLink()
        held.removeFirst().answer.resume(returning: nil)
        await yield(until: { held.count == 4 })
        guard held.count == 4 else { return }
        XCTAssertEqual(held[3].label, label, "Try again goes before the filter's backlog")

        // The other three of the filter, this name, then name5.
        for _ in 1...5 {
            await yield(until: { !held.isEmpty })
            guard !held.isEmpty else { return }
            held.removeFirst().answer.resume(returning: nil)
        }
        await yield(until: { vm.linkState != .reading })
        XCTAssertEqual(vm.linkState, .none)
    }

    // MARK: My approve (AC-17)

    func testActionIsCancelApprovalWhenATickedNodesLiveChoiceApprovesThisRequest() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest()])
        history.records = [vote(a, .towards(identityId: identityId))]
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.approveAction, .cancelApproval)
        XCTAssertEqual(vm.approveTitle, "Cancel approval")
    }

    /// AC-12, AC-17: before voting is set up the stored ticks' approve is not
    /// «mine», so the button asks to approve.
    func testActionIsVoteToApproveBeforeSetupThoughAStoredTickApproved() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        prefs.isVotingSetUp = false
        contests.result = .success([contest()])
        history.records = [vote(a, .towards(identityId: identityId))]
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.approveAction, .voteToApprove)
    }

    func testActionIsVoteToApproveWhenNobodyVoted() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.approveAction, .voteToApprove)
        XCTAssertEqual(vm.approveTitle, "Vote to approve")
    }

    func testActionIsVoteToApproveWhenTheLiveChoiceIsAnotherRequest() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest()])
        history.records = [vote(a, .towards(identityId: "johndoe-id1"))]
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.approveAction, .voteToApprove)
    }

    func testActionIsVoteToApproveWhenTheLiveChoiceIsBlockOrAbstain() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        contests.result = .success([contest()])
        history.records = [vote(a, .lock), vote(b, .abstain)]
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.approveAction, .voteToApprove)
    }

    func testOnlyTickedNodesCountForCancelApproval() async {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest()])
        history.records = [vote(b, .towards(identityId: identityId))]
        let vm = makeVM(await makeStore())

        XCTAssertEqual(vm.approveAction, .voteToApprove, "the approving node is not ticked")
    }

    // MARK: Cancel approval sends only from the nodes holding it (AC-17)

    func testCancelApprovalAbstainsOnlyFromTheTickedNodesHoldingThisApprove() async throws {
        let a = node(1), b = node(2)
        nodes.resolution = .init(nodes: [a, b], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash, b.proTxHash]
        contests.result = .success([contest()])
        history.records = [vote(a, .towards(identityId: identityId)), vote(b, .lock)]
        let store = await makeStore()
        let vm = makeVM(store)

        let request = try XCTUnwrap(vm.voteRequest())

        XCTAssertEqual(request.choice, .abstain)
        XCTAssertEqual(request.cancelling, .towards(identityId: identityId))
    }

    func testVoteToApproveAsksForThisRequestsApprove() async throws {
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore())

        let request = try XCTUnwrap(vm.voteRequest())

        XCTAssertEqual(request.choice, .towards(identityId: identityId))
        XCTAssertNil(request.cancelling)
    }

    // MARK: No dead button (AC-03, AC-11)

    func testApproveIsEnabledWithoutVotingKeysSoTheKeyFlowCanOpen() async {
        contests.result = .success([contest(endTime: Date().addingTimeInterval(86_400))])
        let vm = makeVM(await makeStore())
        XCTAssertTrue(vm.canApprove)
    }

    /// One vote at a time: while another name's vote is sent, this request
    /// cannot be approved (SCR-03 «sending · other contest»).
    func testApproveIsDisabledWhileAnotherNamesVoteIsSent() async {
        let other = DPNSContest(normalizedLabel: "janedoe", endTime: nil, hasWinner: false,
                                abstainVotes: 0, lockVotes: 0,
                                contenders: [DPNSContender(identityId: "janedoe-id1", voteTally: 1)])
        contests.result = .success([contest(), other])
        let caster = HeldCaster()
        let store = VotingStore(contests: contests, nodes: nodes, caster: caster, history: history, prefs: prefs)
        await store.refresh()
        let vm = makeVM(store)
        XCTAssertTrue(vm.canApprove)

        let send = Task { await store.send(choice: .lock, on: other, from: store.votableNodes) }
        await yield(until: { caster.started })

        XCTAssertFalse(vm.canApprove)
        caster.release()
        await send.value
        XCTAssertTrue(vm.canApprove)
    }

    /// screens.md SCR-03 «sending»: this request's own vote keeps the button
    /// enabled, so it shows the loading look; its spinner takes the taps.
    func testApproveStaysEnabledWhileThisNamesVoteIsSent() async {
        contests.result = .success([contest()])
        let caster = HeldCaster()
        let store = VotingStore(contests: contests, nodes: nodes, caster: caster, history: history, prefs: prefs)
        await store.refresh()
        let vm = makeVM(store)

        let send = Task { await store.send(choice: .towards(identityId: identityId), on: contest(), from: []) }
        await yield(until: { caster.started })

        XCTAssertTrue(store.isSending(normalizedLabel: label))
        XCTAssertTrue(vm.canApprove)
        caster.release()
        await send.value
    }

    /// AC-03: the tap is told that voting has ended, so the button stays enabled.
    func testApproveStaysEnabledOnceTheContestClosed() async {
        contests.result = .success([contest(endTime: Date().addingTimeInterval(86_400))])
        let store = await makeStore()
        let vm = makeVM(store)

        contests.state = DPNSContestVoteState(normalizedLabel: label, contenders: [], abstainVotes: 0, lockVotes: 0,
                                              outcome: .locked, resolvedAt: epoch)
        await store.refreshContest(normalizedLabel: label)

        XCTAssertTrue(vm.canApprove)
    }

    /// AC-15: the tap shows "No votes left", so the button stays enabled.
    func testApproveStaysEnabledWhenNoTickedNodeHasAVoteLeft() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest()])
        history.records = [CastVoteRecord(proTxHash: a.proTxHash, normalizedLabel: label, choice: .lock,
                                          castAt: epoch, castCount: VoteLimit.maxCastsPerNode)]
        let vm = makeVM(await makeStore())

        XCTAssertTrue(vm.canApprove)
    }

    /// Voting is paused while the vote history cannot be read.
    func testApproveIsDisabledWhileTheHistoryCannotBeRead() async {
        contests.result = .success([contest()])
        history.records = nil
        let store = await makeStore()
        let vm = makeVM(store)

        XCTAssertTrue(store.historyUnavailable)
        XCTAssertFalse(vm.canApprove)
    }

    // MARK: Back to the list on success only (SCR-03)

    func testOnlyAVoteFromHereThatLandedReturnsToTheList() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest()])
        let store = VotingStore(contests: contests, nodes: nodes, caster: LandingCaster(), history: history,
                                prefs: prefs)
        await store.refresh()
        let vm = makeVM(store)

        await store.send(choice: .towards(identityId: identityId), on: contest(), from: [a])

        XCTAssertTrue(vm.returnsToList(after: store.outcome))
        XCTAssertFalse(vm.returnsToList(after: .failure("No connection")))
        XCTAssertFalse(vm.returnsToList(after: nil))
    }

    /// SCR-03 «sending · other contest»: another name's vote, sent from the
    /// list before this screen opened, does not close this screen when it
    /// lands.
    func testAnotherNamesOutcomeStaysOffThisScreen() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        let other = DPNSContest(normalizedLabel: "janedoe", endTime: nil, hasWinner: false,
                                abstainVotes: 0, lockVotes: 0,
                                contenders: [DPNSContender(identityId: "janedoe-id1", voteTally: 1)])
        contests.result = .success([contest(), other])
        let store = VotingStore(contests: contests, nodes: nodes, caster: LandingCaster(), history: history,
                                prefs: prefs)
        await store.refresh()
        let vm = makeVM(store)

        await store.send(choice: .lock, on: other, from: [a])

        guard case .success = store.outcome else { return XCTFail("janedoe's vote landed") }
        XCTAssertFalse(vm.returnsToList(after: store.outcome))
    }

    /// SCR-03: another name's vote that fails, sent from the list, shows its
    /// error on the list only; this screen's own failed vote shows here.
    func testAnotherNamesFailedVoteShowsNoErrorHere() async throws {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        prefs.isVotingSetUp = true
        let other = DPNSContest(normalizedLabel: "janedoe", endTime: nil, hasWinner: false,
                                abstainVotes: 0, lockVotes: 0,
                                contenders: [DPNSContender(identityId: "janedoe-id1", voteTally: 1)])
        contests.result = .success([contest(), other])
        let store = VotingStore(contests: contests, nodes: nodes, caster: FakeCaster(), history: history,
                                prefs: prefs)
        let voting = VotingViewModel(store: store)
        await store.refresh()
        let vm = makeVM(store)

        await voting.send(.lock, on: other, from: [a.proTxHash], skipped: [], pill: .lock)

        let othersError = try XCTUnwrap(voting.toast)
        XCTAssertEqual(othersError.style, .error)
        XCTAssertFalse(vm.showsToast(othersError))
        XCTAssertFalse(vm.returnsToList(after: store.outcome))

        let approve = VoteChoice.towards(identityId: identityId)
        await voting.send(approve, on: contest(), from: [a.proTxHash], skipped: [], pill: approve)

        XCTAssertTrue(vm.showsToast(try XCTUnwrap(voting.toast)))
    }

    /// AC-12, AC-14b: before setup «Vote to approve» is offered although a
    /// stored tick approved; after the keys nothing is sent, and this screen
    /// tells it and stays. Another name's notice stays on the list.
    func testAVoteTheTicksAlreadyHoldIsToldHere() async throws {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        prefs.isVotingSetUp = false
        let other = DPNSContest(normalizedLabel: "janedoe", endTime: nil, hasWinner: false,
                                abstainVotes: 0, lockVotes: 0,
                                contenders: [DPNSContender(identityId: "janedoe-id1", voteTally: 1)])
        contests.result = .success([contest(), other])
        history.records = [vote(a, .towards(identityId: identityId))]
        let store = VotingStore(contests: contests, nodes: nodes, caster: FakeCaster(), history: history,
                                prefs: prefs)
        let voting = VotingViewModel(store: store)
        await store.refresh()
        let vm = makeVM(store)
        let attempt = VoteAttemptCoordinator(host: voting)
        XCTAssertEqual(vm.approveAction, .voteToApprove)

        await attempt.start(.vote(.towards(identityId: identityId)), on: contest())
        XCTAssertEqual(attempt.presentation, .addKeys(.towards(identityId: identityId)))
        store.confirmVotingSetup(ticked: [a.proTxHash])
        attempt.finishKeys(continueToVote: true)
        await attempt.presentationDismissed()

        XCTAssertNil(store.outcome, "nothing was sent")
        let notice = try XCTUnwrap(voting.toast)
        XCTAssertEqual(notice.message, "Already voted this way on johndoe")
        XCTAssertTrue(vm.showsToast(notice))
        XCTAssertFalse(vm.returnsToList(after: store.outcome))

        voting.attemptWillStart(on: other)
        voting.reportAlreadyVoted(on: other)
        XCTAssertFalse(vm.showsToast(try XCTUnwrap(voting.toast)))
    }

    /// A gate that stops this screen's own attempt is told here.
    func testThisScreensAttemptShowsItsErrorHere() async {
        contests.result = .success([contest()])
        let store = await makeStore()
        let vm = makeVM(store)
        let voting = VotingViewModel(store: store)

        voting.attemptWillStart(on: contest())

        XCTAssertTrue(vm.showsToast(.failed("Couldn't read your vote history.")))
        XCTAssertFalse(vm.showsToast(.voted(username: "johndoe")), "a landed vote is told by the list")
    }

    /// The contest left the list while the screen was open: the fields keep
    /// what they showed, and the button no longer pretends it can vote.
    func testFieldsKeepTheLastKnownContestAfterItLeftTheList() async {
        let renamed = DPNSContest(
            normalizedLabel: label, endTime: nil, hasWinner: false, abstainVotes: 0, lockVotes: 0,
            contenders: [DPNSContender(identityId: identityId, voteTally: 4, displayLabel: "JohnDOE")])
        contests.result = .success([renamed])
        let store = await makeStore()
        let vm = makeVM(store)
        XCTAssertEqual(vm.username, "JohnDOE")

        contests.result = .success([])
        await store.refresh()

        XCTAssertEqual(vm.username, "JohnDOE")
        XCTAssertFalse(vm.canApprove)
    }

    // MARK: The link opens outside the app (AC-11)

    func testTappingAWebLinkHandsTheFullLinkToTheSystem() async throws {
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore())
        let url = try XCTUnwrap(URL(string: "https://x.com/johndoe/status/1?ref=dash"))

        vm.open(url)

        XCTAssertEqual(opened, [url])
    }

    func testACustomSchemeLinkIsNeverOpened() async throws {
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore())

        vm.open(try XCTUnwrap(URL(string: "dash:XyZ?amount=10")))

        XCTAssertEqual(opened, [])
    }
}
