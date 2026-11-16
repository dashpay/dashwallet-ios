//
//  VotingViewModel.swift
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

import Combine
import Foundation
import SwiftDashSDK
import SwiftUI

// MARK: - VotingViewModel

/// Backing model for the username-voting section's casting and voting-key
/// flows. The data every screen reads lives on ``store`` and the list's
/// presentation state on ``list``; this type composes them for the existing
/// screens and forwards their reads.
@MainActor
final class VotingViewModel: ObservableObject {
    // MARK: Composition

    let store: VotingStore
    let list: VotingListViewModel
    private var changes = Set<AnyCancellable>()

    // MARK: Casting state

    /// Result banner for the most recent casting run.
    @Published var lastCastReport: VoteCastReport?
    /// Error from a casting run that never got as far as broadcasting.
    @Published var castError: String?

    // MARK: Dependencies

    private let vault: TrackedMasternodeKeyVaulting
    /// Read when needed, not once: the SDK manager comes and goes with the wallet.
    private let tracker: @MainActor () -> VotingKeyMasternodeTracking?

    /// Default arguments would have to be evaluated in a nonisolated context,
    /// but both services are `@MainActor`, so the defaults are applied inside
    /// this `@MainActor` body instead.
    init(
        contestsService: ContestedNamesService? = nil,
        registry: MasternodeVoterRegistry? = nil,
        vault: TrackedMasternodeKeyVaulting? = nil,
        tracker: (@MainActor () -> VotingKeyMasternodeTracking?)? = nil,
        store: VotingStore? = nil
    ) {
        let contestsService = contestsService ?? ContestedNamesService()
        let registry = registry ?? MasternodeVoterRegistry()
        self.vault = vault ?? TrackedMasternodeKeyVault()
        self.tracker = tracker ?? { SwiftDashSDKHost.shared.manager }
        let store = store ?? VotingStore(
            contests: contestsService,
            nodes: registry,
            caster: MasternodeVoteCaster(
                registry: registry, contests: contestsService, history: VoteHistoryDAOImpl.shared),
            history: VoteHistoryDAOImpl.shared,
            prefs: VotingPrefs.shared)
        let list = VotingListViewModel(
            store: store, normalizedLabel: { contestsService.normalizedLabel(for: $0) })
        self.store = store
        self.list = list
        // Screens observe this model; tell them when either part changes.
        store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &changes)
        list.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &changes)
    }

    // MARK: Reads forwarded from the store

    var canVote: Bool { store.canVote }
    var votableNodes: [VoterNode] { store.votableNodes }
    var effectiveSelectedNodeIDs: Set<Data> { store.effectiveSelectedNodeIDs }
    var selectedNodeIDs: Set<Data> {
        get { store.selectedNodeIDs }
        set { store.selectedNodeIDs = newValue }
    }
    var toast: VotingToast? { list.toast }

    func latest(_ contest: DPNSContest) -> DPNSContest { store.latest(contest) }
    func isClosed(normalizedLabel: String) -> Bool { store.isClosed(normalizedLabel: normalizedLabel) }
    func hasLoadedVoteHistory(for normalizedLabel: String) -> Bool {
        store.hasLoadedVoteHistory(for: normalizedLabel)
    }
    func nodesYetToVote(on normalizedLabel: String) -> [VoterNode] { store.nodesYetToVote(on: normalizedLabel) }
    func votedNodeCount(on normalizedLabel: String) -> Int { store.votedNodeCount(on: normalizedLabel) }
    func nodesForVote(_ choice: VoteChoice, on normalizedLabel: String) -> [VoterNode] {
        store.nodesForVote(choice, on: normalizedLabel)
    }
    func canStartVote(_ choice: VoteChoice, on normalizedLabel: String) -> Bool {
        store.canStartVote(choice, on: normalizedLabel)
    }
    func castCandidates(
        for choice: VoteChoice, cancelling: VoteChoice?, on normalizedLabel: String
    ) -> VotingStore.CastCandidates {
        store.castCandidates(for: choice, cancelling: cancelling, on: normalizedLabel)
    }
    func loadVotedNodes(for normalizedLabel: String) async { await store.loadVotedNodes(for: normalizedLabel) }
    func refreshContest(normalizedLabel: String) async { await store.refreshContest(normalizedLabel: normalizedLabel) }
    func refreshVotableNodes() { store.refreshVotableNodes() }
    func isSending(normalizedLabel: String) -> Bool { store.isSending(normalizedLabel: normalizedLabel) }

    /// Names the nodes a vote will use, so the privacy consequence of the
    /// current selection is legible without opening the picker. Describes the
    /// selection a vote will actually use, not the raw persisted one.
    var votingWithSummary: String {
        let chosen = votableNodes.filter { effectiveSelectedNodeIDs.contains($0.proTxHash) }
        guard !chosen.isEmpty else {
            return NSLocalizedString("Select nodes", comment: "Voting")
        }
        if chosen.count == votableNodes.count {
            return String.localizedStringWithFormat(NSLocalizedString("All %d nodes", comment: "Voting"), chosen.count)
        }
        return chosen.map(\.displayName).joined(separator: ", ")
    }

    // MARK: Voting keys

    /// Remove a voting key the user added, so that node stops voting from this
    /// wallet. Returns a message when the key could not be removed.
    ///
    /// Only for ``VotingKeySource/trackedVault`` nodes: a key derived from the
    /// wallet cannot be removed, only the wallet can. The node is untracked as
    /// well once no other key of it is left, so it does not linger in the
    /// tracked-masternode registry as a key-less row nobody asked to keep — but
    /// a node that still holds an owner or payout key stays tracked, because
    /// those keys serve withdrawals, not voting.
    func removeImportedVotingKey(for node: VoterNode) -> String? {
        guard node.keySource == .trackedVault else { return nil }

        // `removeKey` already counts an item that was gone as removed, so
        // `false` is a real keychain failure: the key may still be stored,
        // and the node must stay exactly as it was.
        guard vault.removeKey(for: node.proTxHash, role: .voting) else {
            return NSLocalizedString(
                "Could not remove the voting key. Try again.",
                comment: "Voting")
        }
        // Untrack only once every other key of the node is confirmed gone. A
        // read that fails says nothing about the key, and untracking a node
        // that still holds an owner or payout key would take its withdrawals
        // away — so any doubt keeps it tracked.
        let othersConfirmedAbsent = TrackedMasternodeKeyVault.managedRoles
            .filter { $0 != .voting }
            .allSatisfy { vault.keyPresence(for: node.proTxHash, role: $0) == .absent }
        if othersConfirmedAbsent, let manager = tracker() {
            // Best-effort: a registry row left behind holds no key and cannot
            // vote, so a failure here changes nothing the user can see.
            manager.untrackForVoting(proTxHash: node.proTxHash)
        }
        refreshVotableNodes()
        return nil
    }

    // MARK: Casting

    /// Cast `choice` on `contest` with `nodes` through the store, which also
    /// re-reads that contest. Returns `true` when every node's vote landed.
    /// That outcome is told by a toast, so the caller can close its sheet
    /// right away; anything less is left in ``lastCastReport`` /
    /// ``castError`` for the sheet to show.
    @discardableResult
    func cast(choice: VoteChoice, on contest: DPNSContest, with nodes: [VoterNode]) async -> Bool {
        castError = nil
        // A new vote clears the last outcome, so a toast from the previous
        // vote never sits next to this one.
        list.clearToast()
        await store.send(choice: choice, on: contest, from: nodes)

        switch store.outcome {
        case .success(let toast):
            list.showToast(toast)
            return true
        case .mixed(let report):
            lastCastReport = report
        case .failure(let message):
            castError = message
        case nil:
            break
        }
        return false
    }

    func dismissCastResult() {
        lastCastReport = nil
        castError = nil
    }
}
