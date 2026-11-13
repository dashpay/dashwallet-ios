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
    func votes(forContests normalizedLabels: Set<String>, network: String) async -> [CastVoteRecord]? {
        records?.filter { normalizedLabels.contains($0.normalizedLabel) }
    }
    func deleteAll() {}
}

private final class FakePrefs: VotingSelectionStoring {
    var votingNodeSelection: Set<Data> = []
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

    private func contest(endTime: Date? = nil) -> DPNSContest {
        let contenders = [
            DPNSContender(identityId: "johndoe-id1", voteTally: 2, displayLabel: "JohnDoe"),
            DPNSContender(identityId: identityId, voteTally: 4, displayLabel: "johndoe")
        ]
        return DPNSContest(normalizedLabel: label, endTime: endTime, hasWinner: false,
                           abstainVotes: 0, lockVotes: 0, contenders: contenders)
    }

    private func vote(_ node: VoterNode, _ choice: VoteChoice) -> CastVoteRecord {
        CastVoteRecord(proTxHash: node.proTxHash, normalizedLabel: label, choice: choice, castAt: epoch)
    }

    private func makeStore() async -> VotingStore {
        let store = VotingStore(contests: contests, nodes: nodes, caster: FakeCaster(), history: history,
                                prefs: prefs)
        await store.refresh()
        return store
    }

    /// Links handed to the system to open.
    private var opened: [URL] = []

    private func makeVM(
        _ store: VotingStore,
        link: @escaping (String, String) async throws -> URL? = { _, _ in nil }
    ) -> RequestDetailsViewModel {
        RequestDetailsViewModel(store: store, normalizedLabel: label, identityId: identityId,
                                linkLookup: link, dateFormatter: formatter,
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

    func testRequestDateIsUnknownBeforeStage5bSoThePeriodReadsNotProvidedThenTheVotingEnd() async {
        contests.result = .success([contest(endTime: votingEnd)])
        let vm = makeVM(await makeStore())

        XCTAssertNil(vm.requestDate)
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
        let vm = makeVM(await makeStore(), link: { _, _ in nil })

        await vm.loadLink()

        XCTAssertEqual(vm.linkState, .none)
        XCTAssertEqual(vm.linkText, "Not provided")
    }

    func testFailedLookupReadsCouldntCheckAndNeverNotProvided() async {
        contests.result = .success([contest()])
        let vm = makeVM(await makeStore(), link: { _, _ in throw LookupFailure() })

        await vm.loadLink()

        XCTAssertEqual(vm.linkState, .failed)
        XCTAssertEqual(vm.linkText, "Couldn't check for a link")
        XCTAssertNotEqual(vm.linkText, "Not provided", "the check never ran (guardrail 3)")
    }

    func testPublishedLinkShowsTheFullURL() async {
        contests.result = .success([contest()])
        let url = URL(string: "https://example.com/proof/johndoe")!
        let vm = makeVM(await makeStore(), link: { _, _ in url })

        await vm.loadLink()

        XCTAssertEqual(vm.linkState, .published(url))
        XCTAssertEqual(vm.linkText, "https://example.com/proof/johndoe")
    }

    func testLookupIsAskedForThisRequestsLabelAndIdentity() async {
        contests.result = .success([contest()])
        var asked: (String, String)?
        let vm = makeVM(await makeStore(), link: { label, identity in
            asked = (label, identity)
            return nil
        })

        await vm.loadLink()

        XCTAssertEqual(asked?.0, "johndoe")
        XCTAssertEqual(asked?.1, "johndoe-id2")
    }

    func testStateIsReadingWhileALaterLookupIsInFlight() async {
        contests.result = .success([contest()])
        var release: CheckedContinuation<URL?, Error>?
        var started = false
        var first = true
        let vm = makeVM(await makeStore(), link: { _, _ in
            if first { first = false; return nil }
            started = true
            return try await withCheckedThrowingContinuation { release = $0 }
        })
        await vm.loadLink()
        XCTAssertEqual(vm.linkState, .none)

        let retry = Task { await vm.loadLink() }
        while !started { await Task.yield() }

        XCTAssertEqual(vm.linkState, .reading)
        release?.resume(returning: nil)
        await retry.value
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
        XCTAssertEqual(store.nodesToCancel(.towards(identityId: identityId), on: label).map(\.proTxHash),
                       [a.proTxHash], "b's block on the name is not touched")
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

    func testApproveIsDisabledOnceTheContestClosed() async {
        contests.result = .success([contest(endTime: Date().addingTimeInterval(86_400))])
        let store = await makeStore()
        let vm = makeVM(store)

        contests.state = DPNSContestVoteState(normalizedLabel: label, contenders: [], abstainVotes: 0, lockVotes: 0,
                                              outcome: .locked, resolvedAt: epoch)
        await store.refreshContest(normalizedLabel: label)

        XCTAssertFalse(vm.canApprove)
    }

    func testApproveIsDisabledWhenNoTickedNodeHasAVoteLeft() async {
        let a = node(1)
        nodes.resolution = .init(nodes: [a], mayBeIncomplete: false)
        prefs.votingNodeSelection = [a.proTxHash]
        contests.result = .success([contest()])
        history.records = [CastVoteRecord(proTxHash: a.proTxHash, normalizedLabel: label, choice: .lock,
                                          castAt: epoch, castCount: VoteLimit.maxCastsPerNode)]
        let vm = makeVM(await makeStore())

        XCTAssertFalse(vm.canApprove)
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
