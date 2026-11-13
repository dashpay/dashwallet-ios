//
//  VotingKeysViewModel.swift
//  DashWallet
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

import Foundation

// MARK: - VotingKeysSource

/// What "Add your voting keys" reads and writes.
@MainActor
protocol VotingKeysSource: AnyObject {
    /// The masternodes this wallet can vote with: derived from it and imported.
    var votableNodes: [VoterNode] { get }
    /// Whether ``votableNodes`` may be missing some of this wallet's nodes.
    var nodeResolution: VotingStore.NodeResolution { get }
    /// The masternodes the user ticked that can vote; `nil` while none was
    /// ticked yet or the masternodes are not known yet.
    var tickedNodeIDs: Set<Data>? { get }
    /// Whether the remembered choice holds a node ``votableNodes`` does not
    /// show (an incomplete node list): a choice exists, even with none shown.
    var remembersHiddenNodes: Bool { get }
    /// Keep the ticks shown and mark voting set up (the vote button of "Add your voting keys").
    func confirmVotingSetup(ticked: Set<Data>)
    /// One tick the user changed, kept without changing whether voting is set up (manage mode).
    func setTick(_ proTxHash: Data, _ isTicked: Bool)
    /// How many of `nodes` would send `choice` on the contest of the vote
    /// being made: a node that already holds it or has no vote left sends
    /// nothing. `nil` when that contest's history is not known.
    func votesToCast(_ choice: VoteChoice, from nodes: Set<Data>) -> Int?
}

// MARK: - VotingKeysViewModel

/// "Add your voting keys" (SCR-04): which masternodes vote, ticked one by one.
///
/// A wallet that never chose votes with one masternode: voting with several
/// at once publicly links them, so that stays something the user ticks
/// (AC-14). In vote mode the ticks are kept only when the Block or Approve
/// button is tapped, which also sets voting up (AC-12); in manage mode each
/// tick is kept at once, without setting voting up, and there is no vote
/// button.
@MainActor
final class VotingKeysViewModel: ObservableObject {
    enum Mode: Equatable {
        /// Opened by a vote attempt; the button repeats this choice.
        case vote(VoteChoice)
        /// Opened from the list's menu, before or after setup; it starts from the stored ticks.
        case manage
    }

    let mode: Mode
    @Published private(set) var ticked: Set<Data>

    private let source: VotingKeysSource
    /// Vote mode: ticks on nodes an incomplete node list does not show. Not
    /// shown or counted, but kept by the vote button (see ``rowsChanged()``).
    private var hiddenTicks: Set<Data> = []

    init(mode: Mode, source: VotingKeysSource) {
        self.mode = mode
        self.source = source
        // A remembered node the list does not show is a choice too (see ``rowsChanged()``).
        let fallback: Set<Data>
        if case .vote = mode, source.remembersHiddenNodes {
            fallback = []
        } else {
            fallback = Set(source.votableNodes.first.map { [$0.proTxHash] } ?? [])
        }
        ticked = source.tickedNodeIDs ?? fallback
    }

    var rows: [VoterNode] { source.votableNodes }

    /// What the screen watches to call ``rowsChanged()``: the rows, and
    /// whether the list is complete, which decides what a hidden tick keeps.
    struct RowsState: Equatable {
        let ids: [Data]
        let resolution: VotingStore.NodeResolution
    }

    var rowsState: RowsState { RowsState(ids: rows.map(\.proTxHash), resolution: source.nodeResolution) }

    func isTicked(_ node: VoterNode) -> Bool {
        ticked.contains(node.proTxHash)
    }

    func toggle(_ node: VoterNode) {
        let isTicked = !ticked.contains(node.proTxHash)
        if isTicked {
            ticked.insert(node.proTxHash)
        } else {
            ticked.remove(node.proTxHash)
        }
        if mode == .manage { source.setTick(node.proTxHash, isTicked) }
    }

    /// After the rows changed (a key added or removed, the node list resolved
    /// further): show the ticks of the rows there are, and tick the only row
    /// when nothing was chosen. A new row is not ticked otherwise: voting with
    /// it as well would link it to the others.
    ///
    /// Nothing is forgotten here: a row that is gone is only not shown. The
    /// store decides what the remembered choice loses (see
    /// ``VotingStore/confirmVotingSetup(ticked:)``). In manage mode the ticks
    /// shown are the store's, so a node that comes back is ticked again; an
    /// empty choice the user left (the only ticked key removed) stays empty,
    /// and the only-row tick is kept only when the node list is complete, as an
    /// incomplete one may hide nodes of this wallet. In vote mode a tick on a
    /// row an incomplete list stops showing is kept in ``hiddenTicks`` and
    /// confirmed with the rest; a complete list drops it. With no rows the
    /// node list is not known yet, so the ticks stay as they are.
    func rowsChanged() {
        guard !rows.isEmpty else { return }
        let live = Set(rows.map(\.proTxHash))
        var next: Set<Data>
        let nothingChosen: Bool
        if mode == .manage {
            next = source.tickedNodeIDs ?? []
            nothingChosen = source.tickedNodeIDs == nil
        } else {
            let draft = ticked.union(hiddenTicks)
            hiddenTicks = source.nodeResolution == .complete ? [] : draft.subtracting(live)
            next = draft.intersection(live)
            // A remembered node the list does not show is a choice too.
            nothingChosen = draft.isEmpty && !source.remembersHiddenNodes
        }
        if next.isEmpty, nothingChosen, rows.count == 1, let only = rows.first {
            next = [only.proTxHash]
            if mode == .manage, source.nodeResolution == .complete { source.setTick(only.proTxHash, true) }
        }
        guard next != ticked else { return }
        ticked = next
    }

    /// Several ticked masternodes vote together, which links them publicly.
    var showsLinkingWarning: Bool { ticked.count > 1 }

    /// "2 votes will be cast", under the vote button: the ticked nodes that
    /// will send this choice on this name, or every ticked node while the
    /// name's history is not known. `nil` in manage mode or with none to send.
    var castCaption: String? {
        guard case .vote(let choice) = mode else { return nil }
        let count = source.votesToCast(choice, from: ticked) ?? ticked.count
        guard count > 0 else { return nil }
        return count == 1
            ? NSLocalizedString("1 vote will be cast", comment: "Voting")
            : String(format: NSLocalizedString("%d votes will be cast", comment: "Voting"), count)
    }

    /// The vote button's choice; `nil` in manage mode, which has none.
    var voteChoice: VoteChoice? {
        if case .vote(let choice) = mode { return choice }
        return nil
    }

    /// Nothing ticked, nothing to vote with.
    var canConfirm: Bool { !ticked.isEmpty }

    /// Keep the ticks and set voting up; the caller then tries the vote again.
    func confirm() {
        guard canConfirm else { return }
        source.confirmVotingSetup(ticked: ticked.union(hiddenTicks))
    }
}

// MARK: - VotingStore + VotingKeysSource

extension VotingStore: VotingKeysSource {}
