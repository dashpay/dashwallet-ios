//
//  VotingStore.swift
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

// MARK: - Dependencies

/// Reads the open contests and one contest's vote state from Platform.
@MainActor
protocol VotingContestReading {
    func activeContests() async throws -> [DPNSContest]
    func voteState(normalizedLabel: String) async throws -> DPNSContestVoteState?
}

/// Resolves the masternodes of this wallet that can vote.
@MainActor
protocol VotableMasternodeResolving {
    func votableNodes() -> MasternodeVoterRegistry.Resolution
    /// The wallet's sync is done (`SyncingActivityMonitor` `.syncDone`), so an
    /// empty ``votableNodes()`` means this wallet has no node rather than that
    /// the sync has not found it yet.
    var isNodeListSynced: Bool { get }
}

/// Casts a vote with a set of masternodes.
@MainActor
protocol VoteCasting {
    func cast(choice: VoteChoice, onNormalizedLabel normalizedLabel: String, with nodes: [VoterNode]) async throws
        -> VoteCastReport
}

/// Remembers which masternodes the user ticked to vote with.
protocol VotingSelectionStoring: AnyObject {
    var votingNodeSelection: Set<Data> { get set }
}

extension ContestedNamesService: VotingContestReading {}
extension MasternodeVoterRegistry: VotableMasternodeResolving {}
extension MasternodeVoteCaster: VoteCasting {}
extension VotingPrefs: VotingSelectionStoring {}

// MARK: - VotingStore

/// The one owner of the data every voting screen reads: the open contests,
/// the wallet's votable and ticked masternodes, and the vote history of those
/// contests. Screen view models hold presentation state only.
///
/// Loads — the whole list, every contest's history, one contest's history, one
/// contest's tallies — run one at a time, in the order they were asked for.
@MainActor
final class VotingStore: ObservableObject {
    // MARK: Published state

    /// The contests on the list: the open ones, plus any Platform closed
    /// early or left out of its last answer, until their voting end
    /// (sad §4 choice 6). ``closedLabels`` says which are closed.
    @Published private(set) var contests: [DPNSContest] = [] {
        didSet { stateDidChange.send() }
    }
    /// Labels observed to have resolved while the user was looking at them,
    /// so an already-open detail screen can say so instead of offering a vote
    /// that can no longer be accepted.
    @Published private(set) var closedLabels: Set<String> = []
    @Published private(set) var votableNodes: [VoterNode] = [] {
        didSet {
            let ids = Set(votableNodes.map(\.proTxHash))
            guard ids != votableNodeIDs else { return }
            votableNodeIDs = ids
            stateDidChange.send()
        }
    }
    /// ``votableNodes`` as a set, kept with it rather than rebuilt per row.
    private(set) var votableNodeIDs: Set<Data> = []
    /// ``votableNodes`` was read after the wallet's sync was done, so an empty
    /// one means this wallet has no node to vote with.
    @Published private(set) var nodeListSynced = false
    /// The wallet's voting-key pool could only be read at its shallow
    /// fallback depth and some active registration went unmatched, so a node
    /// you can actually vote with may be missing from ``votableNodes``.
    @Published private(set) var nodeListMayBeIncomplete = false {
        didSet { if nodeListMayBeIncomplete != oldValue { stateDidChange.send() } }
    }
    @Published private(set) var isLoading = false
    /// A full refresh is queued or running.
    @Published private(set) var isRefreshing = false
    /// Set when a refresh fails. The list keeps showing the last good data;
    /// the error itself goes to the log, never to the screen.
    @Published private(set) var loadFailed = false
    /// `false` until the first refresh completes, so the empty state is not
    /// shown while the first fetch is still in flight.
    @Published private(set) var hasLoadedOnce = false
    /// This wallet's vote history could not be read, so the list cannot tell
    /// which votes are already cast and holds its vote controls back.
    @Published private(set) var historyUnavailable = false {
        didSet { if historyUnavailable != oldValue { stateDidChange.send() } }
    }

    /// Which of our nodes voted, per contest. Keyed by contest so a screen can
    /// never be answered with another contest's history — and so an ABSENT
    /// entry is distinguishable from "none voted here", which is what makes
    /// gating on load possible.
    @Published private(set) var votedProTxHashesByContest: [String: Set<Data>] = [:]

    /// Per contest, rebuilt for one contest by `loadVotedNodes(for:)` and for
    /// every listed contest by `loadAllVoteHistory()`.
    @Published private(set) var voteHistoryByContest: [String: VoteLimit] = [:] {
        didSet { stateDidChange.send() }
    }

    /// proTxHashes of the nodes the next vote will use, shared by the list
    /// and the contest screen and persisted so the next contest
    /// opens with the same nodes ticked.
    ///
    /// Persisted rather than re-asked because it is a privacy choice: voting
    /// with several nodes at once links those masternodes to each other, and
    /// that should stay the user's standing decision, not something re-made
    /// under time pressure on every contest.
    @Published var selectedNodeIDs: Set<Data> {
        didSet {
            prefs.votingNodeSelection = selectedNodeIDs
            stateDidChange.send()
        }
    }

    /// The one result of the latest vote attempt: a toast, an error message or
    /// the per-masternode report of a mixed run. Cleared when the next attempt
    /// starts.
    @Published private(set) var outcome: VoteAttemptOutcome?

    /// Votes Platform accepted while this store lived whose history write
    /// failed, per contest. The store's rows are one cast short for each, so
    /// every history rebuild adds them back: the cast is spent (owner decision,
    /// 2026-11-05). Kept per screen open: a store is made each time Username Voting
    /// opens, and the next one starts without them (owner, 2026-11-06).
    private var unrecordedCasts: [String: [CastVoteRecord]] = [:]

    /// Contests with a vote in flight. Their pills show a spinner and take no
    /// taps until the votes are applied and the tallies re-read.
    @Published private(set) var sendingLabels: Set<String> = []

    /// Fires after any change a screen derives its rows from, with the new
    /// value already in place (``objectWillChange`` fires before).
    let stateDidChange = PassthroughSubject<Void, Never>()

    // MARK: Dependencies

    private let contestsReader: VotingContestReading
    private let nodes: VotableMasternodeResolving
    let caster: VoteCasting
    private let history: VoteHistoryDAO
    private let prefs: VotingSelectionStoring
    private let now: () -> Date

    init(
        contests: VotingContestReading,
        nodes: VotableMasternodeResolving,
        caster: VoteCasting,
        history: VoteHistoryDAO,
        prefs: VotingSelectionStoring,
        now: @escaping () -> Date = Date.init
    ) {
        self.contestsReader = contests
        self.nodes = nodes
        self.caster = caster
        self.history = history
        self.prefs = prefs
        self.now = now
        self.selectedNodeIDs = prefs.votingNodeSelection
    }

    // MARK: Derived state

    var canVote: Bool { !votableNodes.isEmpty }

    /// The stored choice that is still votable — a remembered node that has
    /// since been revoked or left the masternode list must not silently come
    /// back. `nil` while none is chosen yet, which is not the same as an empty
    /// choice.
    var tickedNodeIDs: Set<Data>? {
        let live = selectedNodeIDs.intersection(votableNodeIDs)
        return live.isEmpty ? nil : live
    }

    /// The remembered selection, or a single node when nothing was ever
    /// chosen. Never every node by default: see ``VotingPrefs``.
    ///
    /// Also recovers from a selection that no longer matches any votable node
    /// (nodes revoked, or a different wallet), which would otherwise leave the
    /// vote button permanently disabled with no way to see why.
    var effectiveSelectedNodeIDs: Set<Data> {
        tickedNodeIDs ?? Set(votableNodes.first.map { [$0.proTxHash] } ?? [])
    }

    /// The latest copy of `contest` in the list, so a screen opened from an
    /// older snapshot shows today's counts.
    func latest(_ contest: DPNSContest) -> DPNSContest {
        contests.first { $0.normalizedLabel == contest.normalizedLabel } ?? contest
    }

    /// Whether a contest the user is looking at has closed under them. The
    /// detail screen reads this to swap its vote controls for a closed notice
    /// instead of silently showing a stale snapshot with live-looking buttons.
    func isClosed(normalizedLabel: String) -> Bool {
        closedLabels.contains(normalizedLabel)
    }

    // MARK: Loading

    /// True once a contest fetch has actually succeeded. Distinct from
    /// ``hasLoadedOnce``, which only records that a load was attempted.
    private var didLoadContests = false

    /// Each load reads the store or Platform when its turn comes and applies
    /// what it read before the next one starts, so a load that read earlier
    /// can never land after one that read later and put back what was there
    /// before a vote.
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
        queuedRefreshes += 1
        defer { queuedRefreshes -= 1 }
        await serially { [weak self] in await self?.performRefresh() }
    }

    /// Try again: a refresh, unless one is already queued or running.
    func retry() async {
        guard !isRefreshing else { return }
        await refresh()
    }

    private var queuedRefreshes = 0 {
        didSet { isRefreshing = queuedRefreshes > 0 }
    }

    private func performRefresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        refreshVotableNodes()

        do {
            let open = try await contestsReader.activeContests()
            let listed = Set(open.map(\.normalizedLabel))
            // A contest the answer leaves out (closed early, or cut from the
            // list) stays with its last known votes until its voting end.
            let current = now()
            let kept = contests.filter { contest in
                guard !listed.contains(contest.normalizedLabel), let end = contest.endTime else { return false }
                return end > current
            }
            contests = open + kept
            // A contest Platform lists as open again is not closed.
            closedLabels.subtract(listed)
            loadFailed = false
            didLoadContests = true
        } catch {
            loadFailed = true
            DWLogger.log("Voting: contest list load failed (\(type(of: error)))")
        }

        // After the contests, so every listed contest gets a known history —
        // an empty one included — and its vote controls are not held back
        // waiting for a per-contest load.
        await performLoadAllVoteHistory()
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
        // Once contests have loaded this loads nothing, so it must not hide
        // Try again while the queue is busy with something else.
        guard !didLoadContests else { return }
        // Counted like a refresh, so Try again shows progress and queues
        // nothing while this one waits or runs.
        queuedRefreshes += 1
        defer { queuedRefreshes -= 1 }
        // Checked when its turn comes: a list that reappears while the first
        // load is still queued must not queue a second full refresh.
        await serially { [weak self] in
            guard let self, !self.didLoadContests else { return }
            await self.performRefresh()
        }
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
            (voted[label], histories[label]) = rebuiltHistory(of: label, from: byLabel[label] ?? [])
        }
        votedProTxHashesByContest = voted
        voteHistoryByContest = histories
    }

    /// Re-resolve which nodes this wallet can vote with, and nothing else.
    ///
    /// The voting-key screens call this after adding or removing a key. A full
    /// ``refresh()`` would also re-query every open contest over the network,
    /// which a key change does not affect.
    func refreshVotableNodes() {
        let resolution = nodes.votableNodes()
        nodeListSynced = nodes.isNodeListSynced
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

    /// Re-read one contest's tallies after voting on it, so the row reflects
    /// the vote without a full refresh.
    ///
    /// A contest that has since resolved is recorded in ``closedLabels``, so no
    /// vote can start on it, and keeps its row until its voting end. A refresh
    /// that fails or finds no contenders keeps the row until its voting end has
    /// passed.
    func refreshContest(normalizedLabel: String) async {
        await serially { [weak self] in await self?.performRefreshContest(normalizedLabel: normalizedLabel) }
    }

    private func performRefreshContest(normalizedLabel: String) async {
        let state: DPNSContestVoteState?
        do {
            state = try await contestsReader.voteState(normalizedLabel: normalizedLabel)
        } catch {
            // The query failed, so we learned nothing about this contest.
            // Leave the cached row exactly as it was rather than treating a
            // network blip as a resolution.
            return
        }

        // No contenders: the row keeps its last known votes until its voting
        // end, then the refresh drops it.
        guard let state else {
            if let end = contests.first(where: { $0.normalizedLabel == normalizedLabel })?.endTime,
               end <= now() {
                close(normalizedLabel: normalizedLabel)
            }
            return
        }

        guard !state.isResolved else {
            if let end = contests.first(where: { $0.normalizedLabel == normalizedLabel })?.endTime, end > now() {
                closedLabels.insert(normalizedLabel)
            } else {
                close(normalizedLabel: normalizedLabel)
            }
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

    // MARK: Sending

    func isSending(normalizedLabel: String) -> Bool {
        sendingLabels.contains(normalizedLabel)
    }

    /// Clears the previous attempt's outcome.
    func beginAttempt() {
        outcome = nil
    }

    /// Casts `choice` on `contest` with `nodes` and sets ``outcome``.
    ///
    /// Returns once the caster has finished, the contest's history is rebuilt
    /// from the store's rows plus the unrecorded casts this store keeps, and its
    /// tallies are re-read. Both go through the load queue, so a load that read
    /// before the cast cannot land after it. A second send on a contest already
    /// in flight returns without casting.
    func send(choice: VoteChoice, on contest: DPNSContest, from nodes: [VoterNode]) async {
        let label = contest.normalizedLabel
        guard sendingLabels.insert(label).inserted else { return }
        beginAttempt()
        defer { sendingLabels.remove(label) }

        let report: VoteCastReport
        let startedAt = now()
        do {
            report = try await caster.cast(choice: choice, onNormalizedLabel: label, with: nodes)
        } catch {
            // Platform's answer for a contest a full refresh left out: it is
            // closed, so no vote starts on it again. The row stays until its
            // voting end. Through the load queue, so a full refresh asked for
            // before this answer cannot list the contest open again.
            if case MasternodeVoteCaster.CastError.contestClosed = error {
                await serially { [weak self] in _ = self?.closedLabels.insert(label) }
            }
            outcome = .failure(VoteErrorMessage.plain(for: error))
            return
        }

        let castAt = now()
        let unrecorded = report.succeeded.filter { !$0.historyRecorded }.map {
            CastVoteRecord(proTxHash: $0.node.proTxHash, normalizedLabel: label, choice: report.choice, castAt: castAt)
        }
        unrecordedCasts[label, default: []].append(contentsOf: unrecorded)
        await serially { [weak self] in
            guard let self else { return }
            // Without a readable store, patch what is known instead.
            if await !self.performLoadVotedNodes(for: label) {
                self.applyRecordedVotes(of: report, on: label, at: castAt, startedAt: startedAt)
            }
        }
        await refreshContest(normalizedLabel: label)

        if report.isCompleteSuccess {
            outcome = .success(.voted(username: contest.displayTitle))
        } else if report.succeeded.isEmpty {
            outcome = .failure(report.failed.first?.failure
                ?? NSLocalizedString("The vote was not cast. Please try again.", comment: "Voting"))
        } else {
            outcome = .mixed(report)
        }
    }

    // MARK: Vote history

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

    /// `false` when the store could not be read.
    @discardableResult
    private func performLoadVotedNodes(for normalizedLabel: String) async -> Bool {
        // A failed read leaves what was known: an empty history would offer
        // nodes for votes they already hold.
        guard let records = await history.votes(
            forContest: normalizedLabel,
            network: MasternodeVoteCaster.networkKey)
        else { return false }
        (votedProTxHashesByContest[normalizedLabel], voteHistoryByContest[normalizedLabel]) =
            rebuiltHistory(of: normalizedLabel, from: records)
        return true
    }

    /// One contest's history from the store's rows plus the casts this store keeps
    /// that landed without a row.
    private func rebuiltHistory(of normalizedLabel: String, from records: [CastVoteRecord]) -> (Set<Data>, VoteLimit) {
        let unrecorded = unrecordedCasts[normalizedLabel] ?? []
        var limit = VoteLimit(records)
        for cast in unrecorded {
            limit.recordCast(of: cast.proTxHash, on: normalizedLabel, choice: cast.choice, at: cast.castAt)
        }
        return (Set(records.map(\.proTxHash)).union(unrecorded.map(\.proTxHash)), limit)
    }

    /// Adds the votes `report` says landed to the contest's known history.
    /// Nothing when the history is not known yet: it stays unknown until the
    /// next history load, which adds the unrecorded ones back. A node whose
    /// history already holds a cast from `startedAt` on was counted by a load
    /// that ran while the vote was in flight, so it is not counted again.
    private func applyRecordedVotes(
        of report: VoteCastReport, on normalizedLabel: String, at castAt: Date, startedAt: Date
    ) {
        guard var contestHistory = voteHistoryByContest[normalizedLabel] else { return }
        let uncounted = report.succeeded.filter { !contestHistory.hasCast(of: $0.node.proTxHash, since: startedAt) }
        for outcome in uncounted {
            contestHistory.recordCast(
                of: outcome.node.proTxHash, on: normalizedLabel, choice: report.choice, at: castAt)
        }
        voteHistoryByContest[normalizedLabel] = contestHistory
        votedProTxHashesByContest[normalizedLabel, default: []]
            .formUnion(report.succeeded.map(\.node.proTxHash))
    }

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
        let history = voteHistoryByContest[normalizedLabel] ?? VoteLimit([])
        return votableNodes.filter { node in
            guard chosen.contains(node.proTxHash) else { return false }
            guard (history.votesLeft(node.proTxHash) ?? 0) > 0 else { return false }
            return history.liveChoice(of: node.proTxHash) != choice
        }
    }

    /// The nodes cancelling `held` should abstain with: the remembered
    /// selection's nodes whose live choice is `held` and that have a vote left.
    /// A node holding anything else is not touched (AC-17).
    func nodesToCancel(_ held: VoteChoice, on normalizedLabel: String) -> [VoterNode] {
        nodesForVote(.abstain, on: normalizedLabel).filter { liveChoice(of: $0, on: normalizedLabel) == held }
    }

    /// What the cast sheet offers for a vote, and why ticked nodes are missing.
    struct CastCandidates {
        /// The nodes the vote can be cast with.
        let nodes: [VoterNode]
        /// Ticked nodes left out because they already hold this choice.
        let holdingThisChoice: Int
        /// Ticked nodes left out because they have no casts left here.
        let outOfCasts: Int
    }

    /// The cast sheet's nodes for `choice`: ``nodesForVote(_:on:)``, or
    /// ``nodesToCancel(_:on:)`` when the vote takes `cancelling` back. The
    /// counts cover the ticked nodes only — when cancelling, only the ticked
    /// holders of `cancelling` — so a node the user never ticked is not
    /// reported as out of votes.
    func castCandidates(for choice: VoteChoice, cancelling: VoteChoice?, on normalizedLabel: String) -> CastCandidates {
        let offered = cancelling.map { nodesToCancel($0, on: normalizedLabel) }
            ?? nodesForVote(choice, on: normalizedLabel)
        let ticked = effectiveSelectedNodeIDs
        let considered = votableNodes.filter { node in
            guard ticked.contains(node.proTxHash) else { return false }
            guard let cancelling else { return true }
            return liveChoice(of: node, on: normalizedLabel) == cancelling
        }
        let holding = considered.filter { liveChoice(of: $0, on: normalizedLabel) == choice }.count
        return CastCandidates(
            nodes: offered,
            holdingThisChoice: holding,
            outOfCasts: max(0, considered.count - offered.count - holding))
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

    /// The choices the ticked nodes currently hold on a contest, from local
    /// history. Empty when none of them voted, when no node is ticked, or
    /// before the history loaded (or when it could not be read).
    func myChoices(on normalizedLabel: String) -> Set<VoteChoice> {
        guard let ticked = tickedNodeIDs, let history = voteHistoryByContest[normalizedLabel] else { return [] }
        var choices = history.filledChoices(of: ticked) ?? []
        if let abstainers = history.nodes(holding: .abstain, among: ticked), !abstainers.isEmpty {
            choices.insert(.abstain)
        }
        return choices
    }
}

// MARK: - VoteAttemptOutcome

/// How a vote attempt ended.
enum VoteAttemptOutcome {
    /// Every masternode's vote landed.
    case success(VotingToast)
    /// Nothing landed; the reason in plain words.
    case failure(String)
    /// Some votes landed and some did not; the report lists each masternode.
    case mixed(VoteCastReport)
}
