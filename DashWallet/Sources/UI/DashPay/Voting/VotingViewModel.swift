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

// MARK: - ContestSort

enum ContestSort: String, CaseIterable, Identifiable {
    case endingSoonest
    case name
    case mostVotes
    case mostLockVotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .endingSoonest: return NSLocalizedString("Ending soonest", comment: "Voting")
        case .name: return NSLocalizedString("Name", comment: "Voting")
        case .mostVotes: return NSLocalizedString("Most votes", comment: "Voting")
        case .mostLockVotes: return NSLocalizedString("Most lock votes", comment: "Voting")
        }
    }
}

// MARK: - VotingViewModel

/// Backing model for the username-voting section.
///
/// Owns the live contest list, the wallet's votable nodes, and the casting
/// flow. Everything it publishes comes from Platform or from the wallet's
/// on-chain masternode registrations — there is no local vote arithmetic and
/// no seeded data.
@MainActor
final class VotingViewModel: ObservableObject {

    // MARK: Published state

    /// The *open* contests. A contest that resolves leaves this list.
    @Published private(set) var contests: [DPNSContest] = [] {
        didSet { recomputeVisible() }
    }
    /// Labels observed to have resolved while the user was looking at them,
    /// so an already-open detail screen can say so instead of offering a vote
    /// that can no longer be accepted.
    @Published private(set) var closedLabels: Set<String> = []
    @Published private(set) var votableNodes: [VoterNode] = [] {
        didSet { votableNodeIDs = Set(votableNodes.map(\.proTxHash)) }
    }
    /// ``votableNodes`` as a set, kept with it rather than rebuilt per row.
    private(set) var votableNodeIDs: Set<Data> = []
    /// The wallet's voting-key pool could only be read at its shallow
    /// fallback depth and some active registration went unmatched, so a node
    /// you can actually vote with may be missing from ``votableNodes``.
    @Published private(set) var nodeListMayBeIncomplete = false
    @Published private(set) var isLoading = false
    /// Set when a refresh fails. The list keeps showing the last good data.
    @Published private(set) var loadError: String?
    /// `false` until the first refresh completes, so the empty state is not
    /// shown while the first fetch is still in flight.
    @Published private(set) var hasLoadedOnce = false

    @Published var searchQuery: String = "" {
        didSet {
            normalizedNeedle = contestsService.normalizedLabel(
                for: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
            recomputeVisible()
        }
    }
    /// The search query, homograph-normalized once per edit rather than on
    /// every recompute of the list.
    private var normalizedNeedle: String?
    @Published var sort: ContestSort = .endingSoonest {
        didSet { recomputeVisible() }
    }

    /// Contests matching the search box, in the selected order. Recomputed when
    /// the contests, the search or the sort change — not on every render, since
    /// matching a search normalizes it through the SDK.
    @Published private(set) var visibleContests: [DPNSContest] = []
    /// ``visibleContests`` grouped by the day voting ends.
    @Published private(set) var sections: [VotingListSection] = []

    /// Also called when the day changes, so "Voting ends today / in N days"
    /// stays true on a screen left open past midnight.
    func recomputeVisible() {
        let visible = filteredContests()
        visibleContests = visible
        // Grouped by end day only for the end-day order; another sort is one
        // run across the whole list, or "Most votes" would not put the most
        // voted contest first.
        sections = sort == .endingSoonest
            ? VotingListSection.group(visible, now: Date(), calendar: .current)
            : [VotingListSection(daysLeft: nil, contests: visible, isUngrouped: true)]
    }

    /// The latest copy of `contest` in the list, so a screen opened from an
    /// older snapshot shows today's counts.
    func latest(_ contest: DPNSContest) -> DPNSContest {
        contests.first { $0.normalizedLabel == contest.normalizedLabel } ?? contest
    }

    /// True once a contest fetch has actually succeeded. Distinct from
    /// ``hasLoadedOnce``, which only records that a load was attempted.
    private var didLoadContests = false

    /// Multi-select mode, the replacement for the old "Quick Voting" screen.
    @Published var isSelecting = false
    @Published private(set) var selectedLabels: Set<String> = []
    /// Per-contest results of the most recent bulk run.
    @Published var bulkReports: [VoteCastReport]?

    /// Which of our nodes voted, per contest. Keyed by contest so a screen can
    /// never be answered with another contest's history — and so an ABSENT
    /// entry is distinguishable from "none voted here", which is what makes
    /// gating on load possible.
    @Published private(set) var votedProTxHashesByContest: [String: Set<Data>] = [:]

    /// proTxHashes of the nodes the next vote will use, shared by the single
    /// contest screen and the bulk sheet and persisted so the next contest
    /// opens with the same nodes ticked.
    ///
    /// Persisted rather than re-asked because it is a privacy choice: voting
    /// with several nodes at once links those masternodes to each other, and
    /// that should stay the user's standing decision, not something re-made
    /// under time pressure on every contest.
    @Published var selectedNodeIDs: Set<Data> = VotingPrefs.shared.votingNodeSelection {
        didSet { VotingPrefs.shared.votingNodeSelection = selectedNodeIDs }
    }

    /// The selected nodes, in registration order, restricted to ones that are
    /// still votable — a remembered node that has since been revoked or left
    /// the masternode list must not silently come back.
    var selectedNodes: [VoterNode] {
        votableNodes.filter { selectedNodeIDs.contains($0.proTxHash) }
    }

    /// Result banner for the most recent casting run.
    @Published var lastCastReport: VoteCastReport?
    /// Error from a casting run that never got as far as broadcasting.
    @Published var castError: String?
    @Published private(set) var isCasting = false

    // MARK: Dependencies

    private let contestsService: ContestedNamesService
    private let registry: MasternodeVoterRegistry
    private let caster: MasternodeVoteCaster
    private let history: VoteHistoryDAO = VoteHistoryDAOImpl.shared
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
        tracker: (@MainActor () -> VotingKeyMasternodeTracking?)? = nil
    ) {
        let contestsService = contestsService ?? ContestedNamesService()
        let registry = registry ?? MasternodeVoterRegistry()
        self.contestsService = contestsService
        self.registry = registry
        self.vault = vault ?? TrackedMasternodeKeyVault()
        self.tracker = tracker ?? { SwiftDashSDKHost.shared.manager }
        self.caster = MasternodeVoteCaster(registry: registry, contests: contestsService)
    }

    // MARK: Derived state


    var canVote: Bool { !votableNodes.isEmpty }

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

    /// The contests matching the search box, in the selected order.
    ///
    /// The query is homograph-normalized before matching because Platform
    /// stores normalized labels — someone typing "alice" is looking for
    /// "a11ce", and a raw substring match would find nothing.
    private func filteredContests() -> [DPNSContest] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sorted(contests) }

        // Normalization needs the SDK, and so does `contests` — a non-empty
        // list means the handle is up, so this only returns nil when there is
        // nothing to filter anyway. Leaving the list unfiltered beats
        // matching against a locally-guessed spelling of the label.
        // Normalized when the query was typed; again here only if the SDK was
        // not up yet then.
        if normalizedNeedle == nil {
            normalizedNeedle = contestsService.normalizedLabel(for: trimmed)
        }
        guard let needle = normalizedNeedle else {
            return sorted(contests)
        }
        // Match the normalized form *and* the spellings people actually typed,
        // so searching "pizza" finds the contest whether the row is showing
        // "pizza" or the normalized "p1zza".
        let raw = trimmed.lowercased()
        return sorted(contests.filter { contest in
            contest.normalizedLabel.contains(needle)
                || contest.requestedLabels.contains { $0.lowercased().contains(raw) }
        })
    }

    private func sorted(_ input: [DPNSContest]) -> [DPNSContest] {
        switch sort {
        case .endingSoonest:
            // Already ordered by the service; keep that order.
            return input
        case .name:
            return input.sorted { $0.normalizedLabel < $1.normalizedLabel }
        case .mostVotes:
            return input.sorted { $0.totalVotes > $1.totalVotes }
        case .mostLockVotes:
            return input.sorted { $0.lockVotes > $1.lockVotes }
        }
    }

    // MARK: Loading

    /// The loads below — the whole list, every contest's history, one
    /// contest's history, one contest's tallies — run one at a time, in the
    /// order they were asked for. Each reads the store or Platform when its
    /// turn comes and applies what it read before the next one starts, so a
    /// load that read earlier can never land after one that read later and
    /// put back what was there before a vote.
    private var loadQueueTail: Task<Void, Never>?

    /// A queued load must call only `perform…` functions, never the public
    /// wrappers: those wait for the queue's tail, which would be itself.
    private func serially(_ load: @escaping @MainActor () async -> Void) async {
        let previous = loadQueueTail
        let next = Task { @MainActor in
            await previous?.value
            await load()
        }
        loadQueueTail = next
        await next.value
    }

    func refresh() async {
        await serially { [weak self] in await self?.performRefresh() }
    }

    private func performRefresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        refreshVotableNodes()

        do {
            contests = try await contestsService.activeContests()
            // A contest Platform lists as open again is not closed.
            closedLabels.subtract(contests.map(\.normalizedLabel))
            loadError = nil
            didLoadContests = true
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }

        // After the contests, so every listed contest gets a known history —
        // an empty one included — and its vote controls are not held back
        // waiting for a per-contest load.
        await performLoadAllVoteHistory()
    }

    /// This wallet's vote history for every contest, in one query, so the list
    /// can mark the user's own vote on every row without a query per row.
    ///
    /// Fills the same per-contest maps ``loadVotedNodes(for:)`` fills for one
    /// contest. A listed contest with no records gets an empty history: after a
    /// full load "no records" means "nobody voted", not "not loaded yet".
    private func loadAllVoteHistory() async {
        await serially { [weak self] in await self?.performLoadAllVoteHistory() }
    }

    private func performLoadAllVoteHistory() async {
        let labels = Set(contests.map(\.normalizedLabel))
        // A failed read leaves every history unknown — not "nobody voted",
        // which would offer nodes for votes they already hold — and says so.
        guard let records = await history.votes(
            forContests: labels, network: MasternodeVoteCaster.networkKey)
        else {
            historyUnavailable = true
            return
        }
        historyUnavailable = false
        let byLabel = Dictionary(grouping: records, by: \.normalizedLabel)
        // Merged in: a contest not in the list (one open on its own screen
        // after it closed) keeps the history it has.
        var voted = votedProTxHashesByContest
        var histories = voteHistoryByContest
        for label in labels {
            let contestRecords = byLabel[label] ?? []
            voted[label] = Set(contestRecords.map(\.proTxHash))
            histories[label] = NodeVoteHistory(contestRecords)
        }
        votedProTxHashesByContest = voted
        voteHistoryByContest = histories
    }

    /// This wallet's vote history could not be read, so the list cannot tell
    /// which votes are already cast and holds its vote controls back.
    @Published private(set) var historyUnavailable = false

    /// Re-resolve which nodes this wallet can vote with, and nothing else.
    ///
    /// The voting-key screens call this after adding or removing a key. A full
    /// ``refresh()`` would also re-query every open contest over the network,
    /// which a key change does not affect.
    func refreshVotableNodes() {
        let resolution = registry.votableNodes()
        votableNodes = resolution.nodes
        nodeListMayBeIncomplete = resolution.mayBeIncomplete

        // Settle the remembered selection against the nodes that actually
        // exist now, so the picker and the "voting with" row agree with what a
        // tap would really do.
        //
        // Only when the node list actually resolved. `votableNodes()` returns
        // empty while the SDK is starting or the masternode phase has not
        // synced, and settling against that would compute an empty selection
        // and PERSIST it — destroying a multi-node choice the user made, with
        // the next vote silently falling back to one node.
        if !votableNodes.isEmpty {
            let settled = effectiveSelectedNodeIDs
            if settled != selectedNodeIDs {
                selectedNodeIDs = settled
            }
        }
    }

    /// The screen's initial load, which does nothing once contests are in hand.
    ///
    /// `.task` re-runs when the list reappears — including on the way back from
    /// a contest — and `refresh()` re-queries every active contest over the
    /// network, which takes long enough to read as the screen hanging. Nothing
    /// about returning from a contest invalidates the list: casting already
    /// refreshes the one contest it touched via ``refreshContest(normalizedLabel:)``,
    /// and pull-to-refresh still forces a real reload.
    ///
    /// Keyed on contests actually having loaded rather than on an attempt, so a
    /// first load that failed still retries instead of stranding the user on an
    /// empty list.
    func refreshIfNeeded() async {
        // Checked when its turn comes: a list that reappears while the first
        // load is still queued must not queue a second full refresh.
        await serially { [weak self] in
            guard let self, !self.didLoadContests else { return }
            await self.performRefresh()
        }
    }

    /// Re-read one contest's tallies after voting on it, so the row reflects
    /// the vote without a full refresh.
    ///
    /// A contest that has since resolved — or that Platform no longer holds
    /// contenders for — leaves `contests` and is recorded in ``closedLabels``.
    /// `contests` is the *open* contest list: leaving a settled contest in it
    /// would offer a Vote button whose only possible outcome is the caster's
    /// closed-poll rejection.
    func refreshContest(normalizedLabel: String) async {
        await serially { [weak self] in await self?.performRefreshContest(normalizedLabel: normalizedLabel) }
    }

    private func performRefreshContest(normalizedLabel: String) async {
        let state: DPNSContestVoteState?
        do {
            state = try await contestsService.voteState(normalizedLabel: normalizedLabel)
        } catch {
            // The query failed, so we learned nothing about this contest.
            // Leave the cached row exactly as it was rather than treating a
            // network blip as a resolution.
            return
        }

        // A successful query returning no contenders means Platform holds no
        // poll for the label. For a row that was in the active list moments
        // ago, that is a contest which resolved and was pruned.
        guard let state, !state.isResolved else {
            close(normalizedLabel: normalizedLabel)
            return
        }

        guard let index = contests.firstIndex(where: { $0.normalizedLabel == normalizedLabel })
        else { return }

        let existing = contests[index]
        contests[index] = DPNSContest(
            normalizedLabel: existing.normalizedLabel,
            endTime: existing.endTime,
            hasWinner: false,
            abstainVotes: state.abstainVotes,
            lockVotes: state.lockVotes,
            contenders: state.contenders,
            // The vote state carries no requested spellings; without these the
            // row would fall back to the normalized label ("p1zza") after a vote.
            requestedLabels: existing.requestedLabels)
    }

    private func close(normalizedLabel: String) {
        contests.removeAll { $0.normalizedLabel == normalizedLabel }
        closedLabels.insert(normalizedLabel)
    }

    /// Whether a contest the user is looking at has closed under them. The
    /// detail screen reads this to swap its vote controls for a closed notice
    /// instead of silently showing a stale snapshot with live-looking buttons.
    func isClosed(normalizedLabel: String) -> Bool {
        closedLabels.contains(normalizedLabel)
    }

    // MARK: Vote history

    /// One contest's history reduced to what the casting rules read: each
    /// node's live vote and how many casts it has spent.
    ///
    /// Shared by the single-contest screen and the bulk planner so the five-
    /// cast ceiling is applied by one rule — a planner that only looked at the
    /// live choice offered exhausted nodes that Platform then rejects.
    struct NodeVoteHistory {
        private(set) var latest: [Data: CastVoteRecord] = [:]
        private(set) var casts: [Data: Int] = [:]

        init(_ records: [CastVoteRecord]) {
            // One row per node per contest — a change overwrites the row it
            // came from — so the ceiling is read from the row's own
            // `castCount`, not from how many rows a node has. Counting rows
            // could never reach five.
            for record in records {
                casts[record.proTxHash] = max(casts[record.proTxHash] ?? 0, record.castCount)
                if let seen = latest[record.proTxHash], seen.castAt >= record.castAt { continue }
                latest[record.proTxHash] = record
            }
        }

        func liveChoice(of proTxHash: Data) -> VoteChoice? {
            latest[proTxHash]?.choice
        }

        /// The live choices of `nodes`, for marking "my vote" on a list row.
        func liveChoices(of nodes: Set<Data>) -> Set<VoteChoice> {
            Set(latest.filter { nodes.contains($0.key) }.values.map(\.choice))
        }

        /// One more cast by `node`, now holding `choice`, as the store records it.
        mutating func recordCast(of node: Data, on normalizedLabel: String, choice: VoteChoice, at date: Date) {
            casts[node, default: 0] += 1
            latest[node] = CastVoteRecord(
                proTxHash: node,
                normalizedLabel: normalizedLabel,
                choice: choice,
                castAt: date,
                castCount: casts[node] ?? 1)
        }

        /// Whether Platform would still accept another vote from this node here.
        func hasCastsLeft(_ proTxHash: Data) -> Bool {
            (casts[proTxHash] ?? 0) < VotingViewModel.maxCastsPerNodePerContest
        }
    }

    /// Per contest, rebuilt for one contest by `loadVotedNodes(for:)` and for
    /// every listed contest by `loadAllVoteHistory()`.
    private var voteHistoryByContest: [String: NodeVoteHistory] = [:]

    /// Nodes that have not yet voted on this contest, in registration order.
    ///
    /// Empty until this contest's history has loaded. The screen evaluates this
    /// before its `.task` completes, and treating "not loaded" as "nobody
    /// voted" would offer nodes that already voted — a duplicate Platform
    /// rejects, spending one of the masternode's per-contest votes.
    func nodesYetToVote(on normalizedLabel: String) -> [VoterNode] {
        guard let voted = votedProTxHashesByContest[normalizedLabel] else { return [] }
        return votableNodes.filter { !voted.contains($0.proTxHash) }
    }

    /// Whether this contest's vote history is known yet. Callers disable the
    /// vote control until it is, rather than acting on an unknown.
    func hasLoadedVoteHistory(for normalizedLabel: String) -> Bool {
        votedProTxHashesByContest[normalizedLabel] != nil
    }

    /// Load which of our nodes already voted on one contest. Called when its
    /// detail screen opens, so the vote button knows what is left.
    func loadVotedNodes(for normalizedLabel: String) async {
        await serially { [weak self] in await self?.performLoadVotedNodes(for: normalizedLabel) }
    }

    private func performLoadVotedNodes(for normalizedLabel: String) async {
        // A failed read leaves what was known: an empty history would offer
        // nodes for votes they already hold.
        guard let records = await history.votes(
            forContest: normalizedLabel,
            network: MasternodeVoteCaster.networkKey)
        else { return }
        votedProTxHashesByContest[normalizedLabel] = Set(records.map(\.proTxHash))
        voteHistoryByContest[normalizedLabel] = NodeVoteHistory(records)
    }

    /// How many of this wallet's nodes have a live vote here — nodes, not
    /// records. A node that changed its mind has two records and is still one
    /// node, which is what "%d of %d nodes voted" is counting.
    func votedNodeCount(on normalizedLabel: String) -> Int {
        votedProTxHashesByContest[normalizedLabel]?.count ?? 0
    }

    /// This node's live choice on this contest, when it has one.
    func liveChoice(of node: VoterNode, on normalizedLabel: String) -> VoteChoice? {
        voteHistoryByContest[normalizedLabel]?.liveChoice(of: node.proTxHash)
    }

    /// The nodes a tap on `choice` should cast with: the remembered selection,
    /// minus nodes already holding that exact choice (Platform rejects a
    /// duplicate) and minus nodes that have spent the five casts it allows per
    /// contest. A node holding a *different* choice belongs here — replacing
    /// its vote is one state transition, and it is the whole point of being
    /// able to change your mind from this screen.
    func nodesForVote(_ choice: VoteChoice, on normalizedLabel: String) -> [VoterNode] {
        guard hasLoadedVoteHistory(for: normalizedLabel) else { return [] }
        let chosen = effectiveSelectedNodeIDs
        let history = voteHistoryByContest[normalizedLabel] ?? NodeVoteHistory([])
        return votableNodes.filter { node in
            guard chosen.contains(node.proTxHash) else { return false }
            guard history.hasCastsLeft(node.proTxHash) else { return false }
            return history.liveChoice(of: node.proTxHash) != choice
        }
    }

    /// `votes_allowed_per_masternode` in the platform version this app talks
    /// to; the sixth cast is refused with `MasternodeVotedTooManyTimesError`.
    static let maxCastsPerNodePerContest = 5

    /// The remembered selection, or a single node when nothing was ever
    /// chosen. Never every node by default: see ``VotingPrefs``.
    ///
    /// Also recovers from a selection that no longer matches any votable node
    /// (nodes revoked, or a different wallet), which would otherwise leave the
    /// vote button permanently disabled with no way to see why.
    var effectiveSelectedNodeIDs: Set<Data> {
        let live = selectedNodeIDs.intersection(votableNodeIDs)
        if !live.isEmpty { return live }
        return Set(votableNodes.first.map { [$0.proTxHash] } ?? [])
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

    /// Cast `choice` on `contest` with `nodes`, then refresh that contest.
    /// Returns `true` when every node's vote landed. That outcome is told by a
    /// toast, so the caller can close its sheet right away; anything less is
    /// left in ``lastCastReport`` / ``castError`` for the sheet to show.
    ///
    /// The toast is shown as soon as the votes are recorded, and the contest's
    /// tallies are re-read from Platform afterwards — waiting for that network
    /// query first could let the toast expire under the still-open sheet.
    @discardableResult
    func cast(choice: VoteChoice, on contest: DPNSContest, with nodes: [VoterNode]) async -> Bool {
        let label = contest.normalizedLabel
        isCasting = true
        castError = nil
        castingLabels.insert(label)
        // A new vote clears the last outcome, so a toast from the previous
        // vote never sits next to this one.
        toast = nil
        defer { isCasting = false }

        do {
            let report = try await caster.cast(
                choice: choice,
                onNormalizedLabel: label,
                with: nodes)
            // What was just recorded is known here: apply it now rather than
            // wait for the store read, which may queue behind a slow refresh.
            applyRecordedVotes(of: report, on: label)
            // Then confirm from the store and Platform. The contest's pills stay
            // busy until that lands, so a queued earlier read cannot offer a
            // node for the vote it now holds in between.
            Task { [weak self] in
                await self?.loadVotedNodes(for: label)
                await self?.refreshContest(normalizedLabel: label)
                self?.castingLabels.remove(label)
            }
            if report.isCompleteSuccess {
                showToast(.voted(username: contest.displayTitle))
                return true
            }
            lastCastReport = report
            return false
        } catch {
            castingLabels.remove(label)
            castError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return false
        }
    }

    /// Adds the votes `report` says landed to the contest's known history, as
    /// the caster recorded them. Nothing when the history is not known yet:
    /// the store reload that follows fills it.
    private func applyRecordedVotes(of report: VoteCastReport, on normalizedLabel: String) {
        guard var contestHistory = voteHistoryByContest[normalizedLabel] else { return }
        let now = Date()
        for outcome in report.succeeded {
            contestHistory.recordCast(
                of: outcome.node.proTxHash, on: normalizedLabel, choice: report.choice, at: now)
        }
        voteHistoryByContest[normalizedLabel] = contestHistory
        votedProTxHashesByContest[normalizedLabel, default: []]
            .formUnion(report.succeeded.map(\.node.proTxHash))
    }

    /// Whether a tap on `choice` may start a vote on this contest: the key flow
    /// when the wallet has no node, otherwise only once the contest's history
    /// is known and some selected node can still cast that choice — not one
    /// already holding it, not one out of casts. One rule for the list and the
    /// contest screen.
    func canStartVote(_ choice: VoteChoice, on normalizedLabel: String) -> Bool {
        guard !isClosed(normalizedLabel: normalizedLabel) else { return false }
        guard canVote else { return true }
        return !nodesForVote(choice, on: normalizedLabel).isEmpty
    }

    // MARK: List state

    /// Contests with a vote in flight. Their pills show a spinner and take no
    /// taps while it is sent.
    @Published private(set) var castingLabels: Set<String> = []

    /// The outcome of the last vote, shown in the list's bottom bar and over
    /// the contest screen.
    @Published private(set) var toast: VotingToast?

    /// How long a toast stays before it clears itself.
    static let toastDuration: Duration = .seconds(3)

    private func showToast(_ toast: VotingToast) {
        self.toast = toast
        Task { [weak self, id = toast.id] in
            try? await Task.sleep(for: Self.toastDuration)
            // Only the toast this task was started for: a newer one has its own timer.
            if self?.toast?.id == id { self?.toast = nil }
        }
    }

    /// The choices this wallet's nodes currently hold on a contest, from local
    /// history. Empty when none of them voted, or before the history loaded.
    func myChoices(on normalizedLabel: String) -> Set<VoteChoice> {
        guard let history = voteHistoryByContest[normalizedLabel] else { return [] }
        // Only nodes this wallet votes with: the history table is per device,
        // and a node whose key was removed is no longer this wallet's vote.
        return history.liveChoices(of: votableNodeIDs)
    }


    func dismissCastResult() {
        lastCastReport = nil
        castError = nil
        bulkReports = nil
    }

    // MARK: Multi-select

    func toggleSelection(_ contest: DPNSContest) {
        // Ineligible rows are not selectable at all rather than selectable and
        // then dropped at cast time, which would silently vote on fewer names
        // than the user ticked.
        guard isBulkEligible(contest) else { return }
        if selectedLabels.contains(contest.normalizedLabel) {
            selectedLabels.remove(contest.normalizedLabel)
        } else {
            selectedLabels.insert(contest.normalizedLabel)
        }
    }

    func isSelected(_ contest: DPNSContest) -> Bool {
        selectedLabels.contains(contest.normalizedLabel)
    }

    func selectAllVisible() {
        selectedLabels = Set(visibleContests.filter(isBulkEligible).map(\.normalizedLabel))
    }

    func endSelecting() {
        isSelecting = false
        selectedLabels = []
    }

    /// Combined voting weight this run would add, across every selected
    /// contest — nodes × contests, since each node votes once per contest.
    func bulkWeight(nodes: [VoterNode]) -> UInt32 {
        UInt32(selectedLabels.count) &* nodes.totalVoteWeight
    }

    /// Whether `contest` can be picked for a bulk run.
    ///
    /// Only single-contender contests qualify. A bulk run applies one decision
    /// across many names, and with two or more requesters "approve" has no
    /// single meaning — the user would be picking a winner per contest without
    /// seeing who they are. Restricting the selection is what makes
    /// ``BulkChoice/soleRequester`` well-defined.
    func isBulkEligible(_ contest: DPNSContest) -> Bool {
        contest.contenders.count == 1
    }

    /// The decision a bulk run applies. Unlike ``VoteChoice`` this is not a
    /// single wire value: `soleRequester` resolves to a different contender
    /// identity per contest.
    enum BulkChoice: Hashable {
        case abstain
        case lock
        /// Award each selected name to its only requester.
        case soleRequester
    }

    /// Resolve `choice` against one contest, or `nil` when it cannot apply.
    private func resolvedChoice(_ choice: BulkChoice, for contest: DPNSContest) -> VoteChoice? {
        switch choice {
        case .abstain: return .abstain
        case .lock: return .lock
        case .soleRequester:
            // Guarded rather than force-unwrapped: selection eligibility is a
            // UI rule, and a contest can gain a contender between the pick and
            // the cast. Dropping it is safer than voting for the wrong id.
            guard contest.contenders.count == 1,
                  let sole = contest.contenders.first else { return nil }
            return .towards(identityId: sole.identityId)
        }
    }

    /// What a bulk run would actually do, given what this wallet already voted.
    ///
    /// A masternode may CHANGE its vote on a contest — Platform accepts up to 5
    /// votes per masternode per contest — so an earlier vote is only an
    /// obstacle when it was the SAME choice. Those are true no-ops and get
    /// dropped; a different earlier choice is a deliberate change and is
    /// carried out, because refusing it would make a recorded vote permanent
    /// in a way Platform does not.
    struct BulkPlan {
        /// Per contest: the wire choice and the nodes that will actually cast.
        let work: [(label: String, choice: VoteChoice, nodes: [VoterNode])]
        /// (node, name) pairs dropped because that node already cast THIS same
        /// choice there — re-sending would spend an allowance to change nothing.
        let duplicatePairs: Int
        /// (node, name) pairs that will REPLACE a different earlier vote.
        let changedPairs: Int
        /// (node, name) pairs dropped because that node has spent every cast
        /// Platform allows on that contest. Kept apart from `duplicatePairs`:
        /// those already hold the requested choice, these could not get it at
        /// all, and the user should be told which.
        let exhaustedPairs: Int
        /// The choice being replaced, when every replaced vote agrees — `nil`
        /// when they differ, so the prompt never names one falsely.
        let replacedChoice: VoteChoice?

        var hasWork: Bool { work.contains { !$0.nodes.isEmpty } }
        var totalPairs: Int { work.reduce(0) { $0 + $1.nodes.count } }
        /// Whether the user should be asked before this runs.
        var needsConfirmation: Bool { duplicatePairs > 0 || changedPairs > 0 || exhaustedPairs > 0 }
    }

    /// How one contest's selected nodes split under a bulk choice.
    struct BulkContestSplit {
        var casting: [VoterNode] = []
        var duplicates = 0
        var changed = 0
        var exhausted = 0
        var replacedChoices = Set<VoteChoice>()
    }

    /// Split `nodes` for one contest by what each already did there.
    ///
    /// A node already holding `choice` is a duplicate whatever its allowance —
    /// nothing is lost by skipping it. Otherwise a node with no casts left is
    /// dropped as exhausted before it can be counted as a replacement: the
    /// caster does not re-check the allowance, so anything that reaches the
    /// batch is broadcast and refused.
    static func splitForBulk(
        _ nodes: [VoterNode],
        choice: VoteChoice,
        history: NodeVoteHistory
    ) -> BulkContestSplit {
        var split = BulkContestSplit()
        for node in nodes {
            let prior = history.liveChoice(of: node.proTxHash)
            if prior == choice {
                split.duplicates += 1
            } else if !history.hasCastsLeft(node.proTxHash) {
                split.exhausted += 1
            } else if let prior {
                split.changed += 1
                split.replacedChoices.insert(prior)
                split.casting.append(node)
            } else {
                split.casting.append(node)
            }
        }
        return split
    }

    /// Build the plan for the current selection without casting anything.
    func planBulk(choice: BulkChoice, with nodes: [VoterNode]) async -> BulkPlan {
        // Order the run the way the list is ordered so the result list reads
        // in the same sequence the user selected from. `soleRequester`
        // resolves per contest, so each label carries its own wire choice.
        let selected = visibleContests.filter { selectedLabels.contains($0.normalizedLabel) }

        var work: [(label: String, choice: VoteChoice, nodes: [VoterNode])] = []
        var duplicatePairs = 0
        var changedPairs = 0
        var exhaustedPairs = 0
        var replacedChoices = Set<VoteChoice>()

        for contest in selected {
            guard let wireChoice = resolvedChoice(choice, for: contest) else { continue }
            // Unreadable history: leave the contest out rather than plan as if
            // none of the nodes had voted there.
            guard let records = await history.votes(
                forContest: contest.normalizedLabel,
                network: MasternodeVoteCaster.networkKey)
            else { continue }

            let split = Self.splitForBulk(
                nodes, choice: wireChoice, history: NodeVoteHistory(records))
            duplicatePairs += split.duplicates
            changedPairs += split.changed
            exhaustedPairs += split.exhausted
            replacedChoices.formUnion(split.replacedChoices)

            if !split.casting.isEmpty {
                work.append((contest.normalizedLabel, wireChoice, split.casting))
            }
        }

        return BulkPlan(
            work: work,
            duplicatePairs: duplicatePairs,
            changedPairs: changedPairs,
            exhaustedPairs: exhaustedPairs,
            replacedChoice: replacedChoices.count == 1 ? replacedChoices.first : nil)
    }

    /// Surface that a planned run had nothing left to do.
    ///
    /// Distinct from a failure: the selection was valid, but planning dropped
    /// every contest in it. Reported here so the sheet does not call the caster
    /// with an empty batch and get "select at least one masternode" back.
    func reportNothingToCast() {
        castError = NSLocalizedString(
            "None of the selected usernames can take this vote any more — reopen them to see their current requests.",
            comment: "Voting")
    }

    /// Cast a plan produced by ``planBulk(choice:with:)``.
    func castBulk(plan: BulkPlan) async {
        isCasting = true
        castError = nil
        defer { isCasting = false }

        let work = plan.work
        let labels = work.map(\.label)

        do {
            let reports = try await caster.castBulk(work)
            bulkReports = reports
            // The list's pills read this history, so the next tap must not
            // offer a node for a vote it now already holds.
            await loadAllVoteHistory()
            for label in labels {
                await refreshContest(normalizedLabel: label)
            }
        } catch {
            castError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}

// MARK: - VotingListSection

/// The voting list's groups: contests whose voting ends on the same calendar
/// day, soonest first. Rows inside a group keep the order they came in, which
/// is the list's chosen sort.
struct VotingListSection: Identifiable, Equatable {
    /// Days from today to the day voting ends; `nil` when the end is unknown.
    let daysLeft: Int?
    let contests: [DPNSContest]
    /// The whole list as one run, shown without a header (a sort other than
    /// the end-day order).
    var isUngrouped = false

    var id: Int { isUngrouped ? Int.min : (daysLeft ?? Int.max) }

    var title: String {
        switch daysLeft {
        case nil:
            return NSLocalizedString("Voting end unknown", comment: "Voting")
        case 0:
            return NSLocalizedString("Voting ends today", comment: "Voting")
        case let days?:
            return String.localizedStringWithFormat(
                NSLocalizedString("Voting ends in %d days", comment: "Voting"), days)
        }
    }

    /// Group `contests` by end day relative to `now` in `calendar`. A contest
    /// whose end has already passed today is still "today" (it is closing); an
    /// end on an earlier day also counts as today rather than a negative count.
    static func group(_ contests: [DPNSContest], now: Date, calendar: Calendar) -> [VotingListSection] {
        let today = calendar.startOfDay(for: now)
        var order: [Int?] = []
        var buckets: [Int?: [DPNSContest]] = [:]
        for contest in contests {
            let key: Int? = contest.endTime.map { end in
                let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: end)).day ?? 0
                return max(days, 0)
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(contest)
        }
        return order
            .sorted { ($0 ?? Int.max) < ($1 ?? Int.max) }
            .map { VotingListSection(daysLeft: $0, contests: buckets[$0] ?? []) }
    }
}

// MARK: - VotingToast

/// A vote that landed on every node, told briefly in the list's bottom bar or
/// over the contest screen. A
/// partial or failed vote is not a toast: the cast sheet stays open and lists
/// each node's outcome.
struct VotingToast: Identifiable, Equatable {
    let id = UUID()
    let message: String

    static func voted(username: String) -> VotingToast {
        VotingToast(message: String(format: NSLocalizedString("Voted %@ username", comment: "Voting"), username))
    }
}
