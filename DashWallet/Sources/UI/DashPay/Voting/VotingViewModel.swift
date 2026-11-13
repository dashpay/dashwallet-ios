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
    /// The Quick voting run in flight, so leaving can stop it.
    private var quickVotingRun: Task<Void, Never>?
    /// The «Quick voting» menu item: keys, the Quick voting sheet, "One vote left", the run.
    private(set) lazy var quickVoting = QuickVotingViewModel(host: self)

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
        store: VotingStore? = nil,
        appDidEnterBackground: AnyPublisher<Void, Never>? = nil
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
        // A run stops when the app goes to the background (ADR-0037).
        let background = appDidEnterBackground
            ?? NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .map { _ in () }.eraseToAnyPublisher()
        background
            .sink { [weak self] in self?.stopQuickVoting() }
            .store(in: &changes)
    }

    // MARK: Reads forwarded from the store

    var canVote: Bool { store.canVote }

    /// The running Quick voting run, in words: its progress toast over the
    /// list and what VoiceOver says as the run starts. `nil` when none runs.
    var quickVotingStatus: String? {
        store.quickVotingProgress.map {
            String(format: NSLocalizedString("Quick voting… %1$d of %2$d done", comment: "Voting"), $0.done, $0.total)
        }
    }
    var votableNodes: [VoterNode] { store.votableNodes }
    var toast: VotingToast? { list.toast }

    func latest(_ contest: DPNSContest) -> DPNSContest { store.latest(contest) }
    func isClosed(normalizedLabel: String) -> Bool { store.isClosed(normalizedLabel: normalizedLabel) }
    func hasLoadedVoteHistory(for normalizedLabel: String) -> Bool {
        store.hasLoadedVoteHistory(for: normalizedLabel)
    }
    func loadVotedNodes(for normalizedLabel: String) async { await store.loadVotedNodes(for: normalizedLabel) }
    func refreshVotableNodes() { store.refreshVotableNodes() }

    /// The voting-key flow opens on "Enter voting key" only when, with the
    /// wallet's sync done, it has no node (SCR-04 «no keys»). Before the sync
    /// is done an empty list says nothing yet, so the flow opens on "Add your
    /// voting keys", whose empty state offers the key input.
    var keysFlowOpensOnKeyInput: Bool { votableNodes.isEmpty && store.nodeListSynced }
    func isSending(normalizedLabel: String) -> Bool { store.isSending(normalizedLabel: normalizedLabel) }

    /// Names the nodes a vote will use, so the privacy consequence of the
    /// current selection is legible without opening the picker: the ticked
    /// masternodes that can vote, or "Select nodes" when a tap would open
    /// "Add your voting keys": voting not set up, or none ticked (AC-12, AC-14).
    var votingWithSummary: String {
        let ticked = store.isVotingSetUp ? store.tickedNodeIDs ?? [] : []
        let chosen = votableNodes.filter { ticked.contains($0.proTxHash) }
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
        store.forgetNode(node.proTxHash)
        if othersConfirmedAbsent, let manager = tracker() {
            // Best-effort: a registry row left behind holds no key and cannot
            // vote, so a failure here changes nothing the user can see.
            manager.untrackForVoting(proTxHash: node.proTxHash)
        }
        refreshVotableNodes()
        return nil
    }

    // MARK: Casting

    /// Starts a Quick voting run of `plan`, unless one is running; its outcome
    /// is told as a single vote's (``showToast(for:)``).
    func startQuickVoting(_ plan: QuickVotePlan) {
        guard quickVotingRun == nil else { return }
        list.clearToast()
        // The task holds the store, not this model: a run of a screen that
        // is gone keeps no view model alive.
        let store = store
        quickVotingRun = Task { [weak self] in
            // The run's own outcome: a run that did not start leaves the
            // store's outcome to whichever attempt set it.
            let outcome = await store.runQuickVoting(plan)
            self?.showToast(for: outcome)
            self?.quickVotingRun = nil
            // The tallies after the toast, so it does not wait on Platform.
            await store.refreshAfterQuickVoting(outcome)
        }
    }

    /// A vote runs that leaving would not stop: a single vote or its Try
    /// again. Back stops a Quick voting run instead (ADR-0037).
    var holdsScreen: Bool { store.isVoteBusy && quickVotingRun == nil }

    /// Stops the run in flight: nothing more is sent, and the votes not sent
    /// are reported as not cast, for Try again.
    func stopQuickVoting() {
        quickVotingRun?.cancel()
    }

    /// A screen torn down without a pop stops its run too: the run's task
    /// holds the store, not this model.
    deinit {
        quickVotingRun?.cancel()
    }

    /// Try again after a mixed single vote: the store resends the failed
    /// masternodes, and a vote that now landed everywhere is told by the
    /// toast. After a Quick voting run it does nothing: that retry is a run
    /// too and goes only through ``tryAgainRun()``, which the screen can stop.
    func retryFailed() async {
        if case .mixedRun? = store.outcome { return }
        await store.retryFailed()
        showToast(for: store.outcome)
    }

    /// Starts Try again after a Quick voting run as a run, unless one is
    /// running: leaving the screen or the app going to the background stops
    /// it (ADR-0037). The returned task ends with the toast, before the
    /// tallies are re-read, and holds the store, not this model, so a screen
    /// torn down while it waits stops it too.
    func tryAgainRun() -> Task<Void, Never>? {
        guard case .mixedRun? = store.outcome, quickVotingRun == nil else { return nil }
        let store = store
        let retry = Task { [weak self] in
            await store.retryFailed()
            self?.showToast(for: store.outcome)
            self?.quickVotingRun = nil
            // The tallies after the toast, not awaited: the result sheet
            // closes without waiting on Platform.
            let outcome = store.outcome
            Task { await store.refreshAfterQuickVoting(outcome) }
        }
        quickVotingRun = retry
        return retry
    }

    /// A vote that landed everywhere is a toast, as is one that failed outright;
    /// a mixed one stays in the store's outcome for the result sheet.
    private func showToast(for outcome: VoteAttemptOutcome?) {
        switch outcome {
        case .success(let toast): list.showToast(toast)
        case .failure(let reason): list.showToast(.failed(reason))
        case .mixed, .mixedRun, nil: break
        }
    }
}

// MARK: - VoteAttemptHosting

extension VotingViewModel: VoteAttemptHosting {
    var isVotingSetUp: Bool { store.isVotingSetUp }
    /// The user's own ticks only; none ticked sends the attempt to the keys (AC-14).
    var tickedNodeIDs: Set<Data> { store.tickedNodeIDs ?? [] }

    /// The last vote's toast and outcome go at the tap that starts the next
    /// attempt, so neither sits under a dialog of the new one (AC-06).
    func attemptWillStart(on contest: DPNSContest) {
        list.clearToast()
        // Read now, so "Add your voting keys" or "Enter voting key" is
        // decided on the nodes as they are at the tap.
        store.refreshVotableNodes()
        store.beginAttempt(on: contest.normalizedLabel)
    }

    /// A read that fails is an unknown history, never the last one cached:
    /// the vote limit is decided on what Platform has now (AC-15).
    func voteHistory(for normalizedLabel: String) async -> VoteLimit {
        guard await store.loadVotedNodesForVote(for: normalizedLabel) else { return VoteLimit(nil) }
        return store.voteHistoryByContest[normalizedLabel] ?? VoteLimit(nil)
    }

    /// Cast through the store, which also re-reads that contest; the outcome
    /// is told as in ``showToast(for:)``.
    func send(
        _ choice: VoteChoice, on contest: DPNSContest, from nodeIDs: Set<Data>, skipped: Set<Data>, pill: VoteChoice
    ) async {
        // A new vote clears the last outcome, so a toast from the previous
        // vote never sits next to this one.
        list.clearToast()
        let nodes = store.votableNodes.filter { nodeIDs.contains($0.proTxHash) }
        let skippedNodes = store.votableNodes.filter { skipped.contains($0.proTxHash) }
        await store.send(choice: choice, on: contest, from: nodes, skipped: skippedNodes, pill: pill)
        showToast(for: store.outcome)
    }

    /// The name a result sheet shows for `report`.
    func username(of report: VoteCastReport) -> String {
        store.contests.first { $0.normalizedLabel == report.normalizedLabel }?.displayTitle
            ?? report.normalizedLabel
    }

    func reportVotingEnded(on contest: DPNSContest) {
        list.showToast(.votingEnded(username: contest.displayTitle))
    }

    func reportAlreadyVoted(on contest: DPNSContest) {
        list.showToast(.alreadyVoted(username: contest.displayTitle))
    }

    func reportHistoryUnavailable() {
        list.showToast(.failed(NSLocalizedString("Couldn't read your vote history.", comment: "Voting")))
    }
}

// MARK: - QuickVotingHosting

extension VotingViewModel: QuickVotingHosting {
    var shownContests: [DPNSContest] { list.visibleContests }
    var showsOnlyRequestsWithLinks: Bool { list.filter.onlyWithLinks }
    var nodeListMayMissNodes: Bool { store.nodeListMayMissNodes }

    func reportNodeListMayMissNodes() {
        list.showToast(.failed(NSLocalizedString("Some of your masternodes may be missing from this list.", comment: "Voting")))
    }

    func reloadVoteHistory() async -> Bool {
        await store.loadAllVoteHistory()
        return !store.historyUnavailable
    }

    func quickVotePlan(for shown: [DPNSContest]) -> QuickVotePlan {
        store.quickVotePlan(for: shown)
    }

    func username(of normalizedLabel: String) -> String {
        store.contests.first { $0.normalizedLabel == normalizedLabel }?.displayTitle ?? normalizedLabel
    }

    func quickVotingWillStart() {
        list.clearToast()
        store.refreshVotableNodes()
        store.beginQuickVoting()
    }
}
