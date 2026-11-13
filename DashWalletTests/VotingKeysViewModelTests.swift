//
//  VotingKeysViewModelTests.swift
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
import XCTest

// MARK: - FakeKeysSource

@MainActor
private final class FakeKeysSource: VotingKeysSource {
    var votableNodes: [VoterNode] = []
    var nodeResolution: VotingStore.NodeResolution = .complete
    /// The remembered choice; the ticks shown are the part of it that is votable, as in the store.
    var remembered: Set<Data>?
    var tickedNodeIDs: Set<Data>? {
        remembered.map { $0.intersection(votableNodes.map(\.proTxHash)) }
    }
    var remembersHiddenNodes: Bool {
        !(remembered ?? []).subtracting(votableNodes.map(\.proTxHash)).isEmpty
    }
    private(set) var confirmed: Set<Data>?
    /// Each explicit tick change, in order.
    private(set) var ticks: [(Data, Bool)] = []

    /// What ``votesToCast(_:from:)`` answers; `nil` is an unknown history.
    var votesToCastResult: Int?

    func confirmVotingSetup(ticked: Set<Data>) { confirmed = ticked }
    func votesToCast(_ choice: VoteChoice, from nodes: Set<Data>) -> Int? { votesToCastResult }
    func setTick(_ proTxHash: Data, _ isTicked: Bool) {
        ticks.append((proTxHash, isTicked))
        var next = remembered ?? []
        if isTicked { next.insert(proTxHash) } else { next.remove(proTxHash) }
        remembered = next
    }
}

// MARK: - VotingKeysViewModelTests

/// "Add your voting keys" (AC-12, AC-14): one masternode by default, the
/// vote count, the linking warning, and when the ticks are kept.
@MainActor
final class VotingKeysViewModelTests: XCTestCase {
    private var source: FakeKeysSource!

    override func setUp() async throws {
        source = FakeKeysSource()
        source.votableNodes = [node(1), node(2)]
    }

    private func node(_ byte: UInt8) -> VoterNode {
        VoterNode(proTxHash: Data([byte]), isEvonode: false, typeIndex: UInt32(byte),
                  serviceAddress: "10.0.0.\(byte):9999", keySource: .walletIndex(0))
    }

    private func viewModel(_ mode: VotingKeysViewModel.Mode = .vote(.lock)) -> VotingKeysViewModel {
        VotingKeysViewModel(mode: mode, source: source)
    }

    // MARK: Default tick (AC-14)

    func testNeverChosenTicksOnlyTheFirstMasternode() {
        let vm = viewModel()

        XCTAssertEqual(vm.ticked, [Data([1])])
        XCTAssertEqual(vm.castCaption, "1 vote will be cast")
        XCTAssertFalse(vm.showsLinkingWarning)
    }

    /// SCR-04 «empty · no masternodes»: no rows, nothing ticked, and the
    /// vote button stays disabled until a key is added.
    func testNoMasternodesIsTheEmptyStateWithTheVoteButtonDisabled() {
        source.votableNodes = []

        let vm = viewModel()

        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertTrue(vm.ticked.isEmpty)
        XCTAssertFalse(vm.canConfirm)
        XCTAssertNil(vm.castCaption)
    }

    func testAnEarlierChoiceIsTickedAgain() {
        source.remembered = [Data([2])]

        XCTAssertEqual(viewModel().ticked, [Data([2])])
    }

    // MARK: Ticks, count and warning (AC-14)

    func testTwoTickedSayTwoVotesAndWarnAboutLinking() {
        let vm = viewModel()

        vm.toggle(node(2))

        XCTAssertEqual(vm.castCaption, "2 votes will be cast")
        XCTAssertTrue(vm.showsLinkingWarning)
    }

    func testNoneTickedDisablesTheVoteButton() {
        let vm = viewModel()

        vm.toggle(node(1))

        XCTAssertTrue(vm.ticked.isEmpty)
        XCTAssertFalse(vm.canConfirm)
        XCTAssertNil(vm.castCaption)
    }

    // MARK: When the ticks are kept (AC-12)

    func testVoteModeKeepsTheTicksOnlyOnConfirm() {
        let vm = viewModel(.vote(.towards(identityId: "contender-1")))
        vm.toggle(node(2))
        XCTAssertNil(source.confirmed)
        XCTAssertTrue(source.ticks.isEmpty, "a tick is not a choice until the vote button")

        vm.confirm()

        XCTAssertEqual(source.confirmed, [Data([1]), Data([2])])
    }

    func testQuickVotingModeKeepsTheTicksOnConfirmAndHasNoSingleVoteChoice() {
        let vm = viewModel(.quickVoting)
        vm.toggle(node(2))
        XCTAssertTrue(source.ticks.isEmpty)
        XCTAssertNil(vm.voteChoice, "its button is «Vote for all», not Block or Approve")
        XCTAssertTrue(vm.hasVoteButton)
        XCTAssertNil(vm.castCaption, "the Quick voting sheet tells the counts next")

        vm.confirm()

        XCTAssertEqual(source.confirmed, [Data([1]), Data([2])])
    }

    func testConfirmWithNothingTickedKeepsNothing() {
        let vm = viewModel()
        vm.toggle(node(1))

        vm.confirm()

        XCTAssertNil(source.confirmed)
    }

    func testManageModeKeepsEachTickAndHasNoVoteButton() {
        source.remembered = [Data([1])]
        let vm = viewModel(.manage)

        vm.toggle(node(2))

        XCTAssertEqual(source.remembered, [Data([1]), Data([2])])
        XCTAssertEqual(source.ticks.map(\.0), [Data([2])], "only the tapped node is sent")
        XCTAssertNil(vm.voteChoice)
        XCTAssertNil(vm.castCaption)
        XCTAssertNil(source.confirmed, "managing keys does not set voting up")
    }

    func testTheVoteButtonRepeatsTheTappedChoice() {
        XCTAssertEqual(viewModel(.vote(.lock)).voteChoice, .lock)
    }

    // MARK: Rows added or removed

    func testAnAddedKeyIsNotTickedWhenOthersAre() {
        let vm = viewModel()
        source.votableNodes.append(node(3))

        vm.rowsChanged()

        XCTAssertEqual(vm.ticked, [Data([1])])
    }

    func testTheOnlyRowIsTickedWhenNothingIs() {
        source.votableNodes = []
        let vm = viewModel()
        XCTAssertTrue(vm.ticked.isEmpty)

        source.votableNodes = [node(7)]
        vm.rowsChanged()

        XCTAssertEqual(vm.ticked, [Data([7])])
    }

    /// A row that is gone is only not shown: the screen forgets nothing, and
    /// the node is ticked again when it comes back.
    func testARemovedRowIsNotShownTickedButStaysRemembered() {
        source.remembered = [Data([1]), Data([2])]
        let vm = viewModel(.manage)
        source.votableNodes = [node(1)]
        source.nodeResolution = .partial

        vm.rowsChanged()
        XCTAssertEqual(vm.ticked, [Data([1])])
        XCTAssertTrue(source.ticks.isEmpty)

        source.votableNodes = [node(1), node(2)]
        source.nodeResolution = .complete
        vm.rowsChanged()
        XCTAssertEqual(vm.ticked, [Data([1]), Data([2])])
    }

    /// The only row of a partial list is ticked on screen but not kept: the
    /// list may hide nodes of this wallet.
    func testTheOnlyRowOfAPartialListIsNotKept() {
        let vm = viewModel(.manage)
        source.votableNodes = [node(1)]
        source.nodeResolution = .partial

        vm.rowsChanged()

        XCTAssertEqual(vm.ticked, [Data([1])])
        XCTAssertTrue(source.ticks.isEmpty)
        XCTAssertNil(source.remembered)
    }

    /// Removing the key of the only ticked node leaves the choice empty: the
    /// node left is not ticked for the user, so the next vote asks again.
    func testRemovingTheOnlyTickedKeyTicksNoOtherNode() {
        source.remembered = [Data([2])]
        let vm = viewModel(.manage)
        XCTAssertEqual(vm.ticked, [Data([2])])

        source.votableNodes = [node(1)]
        source.remembered = []
        vm.rowsChanged()

        XCTAssertTrue(vm.ticked.isEmpty)
        XCTAssertTrue(source.ticks.isEmpty)
        XCTAssertEqual(source.remembered, [])
    }

    /// In vote mode a tick on a node a partial list stops showing is kept: it
    /// is shown again when the node is back, and the vote button keeps it.
    func testVoteModeKeepsATickAPartialListHides() {
        let vm = viewModel()
        vm.toggle(node(2))
        XCTAssertEqual(vm.ticked, [Data([1]), Data([2])])

        source.votableNodes = [node(1)]
        source.nodeResolution = .partial
        vm.rowsChanged()
        XCTAssertEqual(vm.ticked, [Data([1])])
        XCTAssertEqual(vm.castCaption, NSLocalizedString("1 vote will be cast", comment: "Voting"))

        vm.confirm()
        XCTAssertEqual(source.confirmed, [Data([1]), Data([2])])

        source.votableNodes = [node(1), node(2)]
        source.nodeResolution = .complete
        vm.rowsChanged()
        XCTAssertEqual(vm.ticked, [Data([1]), Data([2])])
    }

    /// A choice a complete list proved gone stays a choice: the one row left
    /// is not ticked for the user.
    func testVoteModeTicksNoRowAfterACompleteListProvesTheChoiceGone() {
        let vm = viewModel()
        vm.toggle(node(1))
        vm.toggle(node(2))
        XCTAssertEqual(vm.ticked, [Data([2])])

        source.votableNodes = [node(1)]
        source.nodeResolution = .partial
        vm.rowsChanged()
        source.nodeResolution = .complete
        vm.rowsChanged()

        XCTAssertTrue(vm.ticked.isEmpty)
    }

    /// The caption counts the votes that will be sent on this name: a ticked
    /// node that already holds the choice or has no vote left sends none.
    func testTheCaptionCountsTheVotesThatWillBeSent() {
        let vm = viewModel()
        vm.toggle(node(2))
        source.votesToCastResult = 1

        XCTAssertEqual(vm.castCaption, NSLocalizedString("1 vote will be cast", comment: "Voting"))

        source.votesToCastResult = 0
        XCTAssertNil(vm.castCaption)

        source.votesToCastResult = nil
        XCTAssertEqual(vm.castCaption, String(format: NSLocalizedString("%d votes will be cast", comment: "Voting"), 2))
    }

    /// A complete list proves a node gone: its vote-mode tick is dropped.
    func testVoteModeDropsATickACompleteListHides() {
        let vm = viewModel()
        vm.toggle(node(2))

        source.votableNodes = [node(1)]
        source.nodeResolution = .partial
        vm.rowsChanged()
        source.nodeResolution = .complete
        vm.rowsChanged()
        vm.confirm()

        XCTAssertEqual(source.confirmed, [Data([1])])
    }

    /// The remembered choice holds a node a partial list does not show: a
    /// choice exists, so the one row shown is not ticked for the user.
    func testVoteModeTicksNoRowWhileTheRememberedChoiceIsHidden() {
        source.remembered = [Data([1])]
        source.votableNodes = [node(2)]
        source.nodeResolution = .partial
        let vm = viewModel()
        XCTAssertTrue(vm.ticked.isEmpty)

        source.votableNodes = [node(3)]
        vm.rowsChanged()

        XCTAssertTrue(vm.ticked.isEmpty)
        XCTAssertFalse(vm.canConfirm)
    }

    /// The list turns complete with the same rows: the screen still rechecks
    /// the ticks, so a hidden tick the complete list proved gone does not
    /// come back with a later partial list.
    func testVoteModeForgetsAHiddenTickWhenTheListTurnsCompleteWithTheSameRows() {
        let vm = viewModel()
        vm.toggle(node(2))

        source.votableNodes = [node(1)]
        source.nodeResolution = .partial
        vm.rowsChanged()
        let partial = vm.rowsState
        source.nodeResolution = .complete
        XCTAssertNotEqual(vm.rowsState, partial, "the screen calls rowsChanged() on this change")
        vm.rowsChanged()

        source.votableNodes = [node(1), node(3)]
        source.nodeResolution = .partial
        vm.rowsChanged()
        vm.confirm()

        XCTAssertEqual(source.confirmed, [Data([1])])
    }

    /// The node list goes empty while the SDK or the masternode list is not
    /// ready: the stored choice is not wiped, and it is back when the nodes are.
    func testAnEmptyNodeListKeepsTheStoredTicks() {
        source.remembered = [Data([1]), Data([2])]
        let vm = viewModel(.manage)

        source.votableNodes = []
        vm.rowsChanged()
        XCTAssertEqual(vm.ticked, [Data([1]), Data([2])])
        XCTAssertTrue(source.ticks.isEmpty, "nothing is saved while no node is known")

        source.votableNodes = [node(1), node(2)]
        vm.rowsChanged()
        XCTAssertEqual(vm.ticked, [Data([1]), Data([2])])
        XCTAssertTrue(source.ticks.isEmpty)
    }
}
