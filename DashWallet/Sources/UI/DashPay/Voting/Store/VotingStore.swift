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
    var isVotingSetUp: Bool { get set }
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
    /// Labels observed to have resolved while the user was looking at them.
    /// The vote gates treat such a contest as ended, so a tap on it is told
    /// that voting has ended instead of sending a vote Platform refuses.
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
    /// and Request details and persisted so the next vote uses the same
    /// nodes.
    ///
    /// Persisted rather than re-asked because it is a privacy choice: voting
    /// with several nodes at once links those masternodes to each other, and
    /// that should stay the user's standing decision, not something re-made
    /// under time pressure on every contest.
    ///
    /// Only the store writes it. It changes on the user's explicit acts — a
    /// tick, the vote button of "Add your voting keys", removing a key — and
    /// on one observation: a complete resolution forgets a remembered node
    /// that is no longer votable (see ``refreshVotableNodes()``). A node
    /// missing from a partial or unavailable resolution stays remembered; a
    /// vote uses only the remembered nodes that resolved (``tickedNodeIDs``).
    @Published private(set) var selectedNodeIDs: Set<Data> {
        didSet {
            prefs.votingNodeSelection = selectedNodeIDs
            stateDidChange.send()
        }
    }

    /// The one result of the latest vote attempt: a toast, an error message or
    /// the per-masternode report of a mixed run. Cleared when the next attempt
    /// starts.
    @Published private(set) var outcome: VoteAttemptOutcome? {
        didSet { outcomeVersion += 1 }
    }
    /// Counts every change of ``outcome``, so Try again publishes only over
    /// the outcome it started from.
    private var outcomeVersion = 0
    /// History reads of a vote in progress (the gates, Try again); while any
    /// runs, no other vote starts.
    @Published private var voteReads = 0

    /// Votes Platform accepted while this store lived whose history write
    /// failed, per contest. The store's rows are one cast short for each, so
    /// every history rebuild adds them back: the cast is spent (owner decision,
    /// 2026-11-05). Kept per screen open: a store is made each time Username Voting
    /// opens, and the next one starts without them (owner, 2026-11-06).
    private var unrecordedCasts: [String: [CastVoteRecord]] = [:]

    /// Contests with a vote in flight. Their pills show a spinner and take no
    /// taps until the votes are applied and the tallies re-read.
    @Published private(set) var sendingLabels: Set<String> = []
    /// The pill each send was tapped on, while it sends.
    private var sendingPills: [String: VoteChoice] = [:]

    /// The contest of the latest send, for Try again on its mixed outcome.
    private var lastSentContest: DPNSContest?

    /// The contest of the latest vote attempt, set at its start: ``outcome``
    /// and the attempt's toasts are about it until the next attempt starts.
    private(set) var attemptLabel: String?

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

    /// A node to vote with, and "Add your voting keys" confirmed once (AC-12).
    var isVotingSetUp: Bool { canVote && prefs.isVotingSetUp }

    // MARK: Remembered choice

    /// How far the latest node resolution can be trusted.
    enum NodeResolution: Equatable {
        /// No node resolved: the SDK or the masternode list is not ready.
        case unavailable
        /// Some nodes resolved; others of this wallet may be missing.
        case partial
        /// Every node of this wallet resolved.
        case complete
    }

    var nodeResolution: NodeResolution {
        if votableNodes.isEmpty { return .unavailable }
        return nodeListMayBeIncomplete ? .partial : .complete
    }

    /// The vote button of "Add your voting keys": keep the ticks shown and set
    /// voting up. Remembered nodes that are not shown stay unless the
    /// resolution is complete, which proves them gone.
    func confirmVotingSetup(ticked: Set<Data>) {
        let isComplete = nodeResolution == .complete
        let unseen = isComplete ? [] : selectedNodeIDs.subtracting(votableNodeIDs)
        // The flag first: the selection's change notice must already see voting set up.
        prefs.isVotingSetUp = true
        // A complete resolution also proves a ticked node that is not votable gone.
        selectedNodeIDs = unseen.union(isComplete ? ticked.intersection(votableNodeIDs) : ticked)
    }

    /// See ``VotingKeysSource/votesToCast(_:from:)``: on the contest of the
    /// latest vote attempt.
    func votesToCast(_ choice: VoteChoice, from nodes: Set<Data>) -> Int? {
        guard let label = attemptLabel, let history = voteHistoryByContest[label], history.isKnown else { return nil }
        return nodes.filter { (history.votesLeft($0) ?? 0) > 0 && history.liveChoice(of: $0) != choice }.count
    }

    /// One tick changed on "Add your voting keys" in manage mode: only that
    /// node's place in the remembered choice changes. Does not set voting up.
    func setTick(_ proTxHash: Data, _ isTicked: Bool) {
        if isTicked {
            selectedNodeIDs.insert(proTxHash)
        } else {
            selectedNodeIDs.remove(proTxHash)
        }
    }

    /// The user removed this node's voting key: it leaves the remembered choice.
    func forgetNode(_ proTxHash: Data) {
        selectedNodeIDs.remove(proTxHash)
    }

    /// The stored choice that is still votable — a remembered node that has
    /// since been revoked or left the masternode list must not silently come
    /// back. `nil` while none is chosen yet or the nodes are not known yet,
    /// which is not the same as an empty choice. Once voting is set up an
    /// empty choice stays empty, and the next vote opens "Add your voting
    /// keys" (AC-14); before that, ticks kept in manage mode are the choice.
    var tickedNodeIDs: Set<Data>? {
        guard !votableNodeIDs.isEmpty else { return nil }
        let live = selectedNodeIDs.intersection(votableNodeIDs)
        if prefs.isVotingSetUp { return live }
        return live.isEmpty ? nil : live
    }

    /// See ``VotingKeysSource/remembersHiddenNodes``.
    var remembersHiddenNodes: Bool {
        !selectedNodeIDs.subtracting(votableNodeIDs).isEmpty
    }

    /// The ticks whose votes are the user's own: none before voting is set
    /// up, so a vote the stored ticks hold fills no pill and a tap asks for
    /// its own choice, as «Add your voting keys» then casts (AC-12, AC-17).
    var myNodeIDs: Set<Data>? {
        prefs.isVotingSetUp ? tickedNodeIDs : nil
    }

    /// The latest copy of `contest` in the list, so a screen opened from an
    /// older snapshot shows today's counts.
    func latest(_ contest: DPNSContest) -> DPNSContest {
        contests.first { $0.normalizedLabel == contest.normalizedLabel } ?? contest
    }

    /// Whether a contest the user is looking at has closed under them. The
    /// vote gates read this as a voting end that has passed (AC-03).
    func isClosed(normalizedLabel: String) -> Bool {
        closedLabels.contains(normalizedLabel)
    }

    // MARK: Loading

    /// True once a contest fetch has actually succeeded. Distinct from
    /// ``hasLoadedOnce``, which only records that a load was attempted.
    private(set) var didLoadContests = false

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
        votableNodes = resolution.nodes
        nodeListMayBeIncomplete = resolution.mayBeIncomplete

        // Forget remembered nodes that are no longer votable, so a revoked
        // node does not come back ticked if it ever resolves again.
        //
        // Only from a complete resolution: an unavailable one (SDK starting,
        // masternode list not synced) or a partial one (a provider pool
        // unreadable) does not prove a missing node gone, and settling against
        // it would PERSIST a smaller choice than the user made. The vote never
        // needs the settling: it takes the remembered nodes that resolved
        // (``tickedNodeIDs``). And only once voting is set up: before that the
        // default tick is not a choice (AC-12).
        if nodeResolution == .complete, prefs.isVotingSetUp {
            // Only the user's own ticks: a node they did not tick is never saved in their place.
            let settled = selectedNodeIDs.intersection(votableNodeIDs)
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
            DWLogger.log("Voting: tallies of \(normalizedLabel) unreadable (\(type(of: error)))")
            return
        }
        // Platform's weighted counts (an evonode's vote counts 4), the numbers
        // the pills show; the contenders' tallies only, never their identities.
        if let state {
            let requests = state.contenders.map { String($0.voteTally) }.joined(separator: ", ")
            DWLogger.log("Voting: tallies of \(normalizedLabel): lock \(state.lockVotes), abstain \(state.abstainVotes), requests [\(requests)]")
        } else {
            DWLogger.log("Voting: tallies of \(normalizedLabel): no contenders")
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

    /// Some vote is being sent, on any contest.
    var isSendingAny: Bool { !sendingLabels.isEmpty }

    /// A vote holds the store: it is being sent, or its history is being read
    /// for the vote gates or Try again. One vote at a time, across the list,
    /// Request details and Try again.
    var isVoteBusy: Bool { isSendingAny || voteReads > 0 }

    /// ``isVoteBusy`` as it changes, for the UIKit host that holds the
    /// swipe-back while a vote runs.
    var isVoteBusyPublisher: AnyPublisher<Bool, Never> {
        $sendingLabels.combineLatest($voteReads)
            .map { !$0.isEmpty || $1 > 0 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// ``loadVotedNodes(for:)`` for a vote's gates: the read holds the vote slot.
    func loadVotedNodesForVote(for normalizedLabel: String) async -> Bool {
        voteReads += 1
        defer { voteReads -= 1 }
        return await loadVotedNodes(for: normalizedLabel)
    }

    /// The pill whose vote is being sent on this contest; `nil` when none is,
    /// or when the send did not start from a pill (Try again).
    func sendingPill(on normalizedLabel: String) -> VoteChoice? {
        guard isSending(normalizedLabel: normalizedLabel) else { return nil }
        return sendingPills[normalizedLabel]
    }

    /// Clears the previous attempt's outcome and starts one on `normalizedLabel`.
    func beginAttempt(on normalizedLabel: String) {
        attemptLabel = normalizedLabel
        outcome = nil
    }

    /// Casts `choice` on `contest` with `nodes` and sets ``outcome``.
    ///
    /// Returns once the caster has finished, the contest's history is rebuilt
    /// from the store's rows plus the unrecorded casts this store keeps, and its
    /// tallies are re-read. Both go through the load queue, so a load that read
    /// before the cast cannot land after it. One vote at a time: a send while
    /// any vote is in flight returns without casting, so that vote's report
    /// and Try again stay its own. `pill` is the pill the vote was
    /// tapped on, if any, for ``sendingPill(on:)`` while it sends.
    func send(
        choice: VoteChoice, on contest: DPNSContest, from nodes: [VoterNode], skipped: [VoterNode] = [],
        pill: VoteChoice? = nil
    ) async {
        let label = contest.normalizedLabel
        guard !isVoteBusy else { return }
        beginAttempt(on: label)
        sendingPills[label] = pill
        defer { sendingPills[label] = nil }
        if let result = await cast(choice: choice, on: contest, from: nodes, skipped: skipped) {
            outcome = result
        }
    }

    /// The cast behind ``send(choice:on:from:)``: returns its outcome and
    /// leaves ``outcome`` as it is, so Try again keeps the report on screen
    /// while it runs. `nil` when this contest is already in flight.
    /// `skipped` had no vote left: nothing is sent from them, and the report
    /// names them as «No votes left» (AC-15).
    private func cast(
        choice: VoteChoice, on contest: DPNSContest, from nodes: [VoterNode], skipped: [VoterNode] = []
    ) async -> VoteAttemptOutcome? {
        let label = contest.normalizedLabel
        guard sendingLabels.insert(label).inserted else { return nil }
        lastSentContest = contest
        defer { sendingLabels.remove(label) }

        var report: VoteCastReport
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
            return .failure(VoteErrorMessage.plain(for: error))
        }

        let castAt = now()
        let unrecorded = report.succeeded.filter { !$0.historyRecorded }.map {
            CastVoteRecord(proTxHash: $0.node.proTxHash, normalizedLabel: label, choice: report.choice, castAt: castAt)
        }
        unrecordedCasts[label, default: []].append(contentsOf: unrecorded)
        let landed = report
        await serially { [weak self] in
            guard let self else { return }
            // Without a readable store, patch what is known instead.
            if await !self.performLoadVotedNodes(for: label) {
                self.applyRecordedVotes(of: landed, on: label, at: castAt, startedAt: startedAt)
            }
        }
        await refreshContest(normalizedLabel: label)
        if !skipped.isEmpty {
            let noVotesLeft = NSLocalizedString("No votes left", comment: "Voting")
            report = VoteCastReport(
                normalizedLabel: label, choice: choice,
                outcomes: report.outcomes + skipped.map { VoteOutcome(node: $0, failure: noVotesLeft) })
        }

        if report.isCompleteSuccess {
            return .success(successToast(for: choice, on: contest))
        } else if report.succeeded.isEmpty {
            return .failure(report.failed.first?.failure
                ?? NSLocalizedString("The vote was not cast. Please try again.", comment: "Voting"))
        } else {
            return .mixed(report)
        }
    }

    /// Try again after a mixed vote (AC-06b): the masternodes whose vote
    /// failed go through the vote gates again (``VoteAttempt``) on a fresh read
    /// of the history, and those that may still vote resend the choice. A
    /// masternode the gates stop gets their reason in the report: voting has
    /// ended, the history could not be read, or no vote left. The report keeps
    /// every masternode, the earlier landed ones included, and stays the
    /// outcome while the resend runs; when every vote has landed the outcome
    /// is the success toast.
    func retryFailed() async {
        guard case .mixed(let report)? = outcome, let sent = lastSentContest,
              sent.normalizedLabel == report.normalizedLabel,
              !isVoteBusy
        else { return }
        let version = outcomeVersion
        let label = report.normalizedLabel
        let contest = latest(sent)
        let failed = report.failed.map(\.node)
        let history = await loadVotedNodesForVote(for: label)
            ? voteHistoryByContest[label] ?? VoteLimit(nil) : VoteLimit(nil)
        var attempt = VoteAttempt(
            intent: .vote(report.choice),
            votingEndsAt: isClosed(normalizedLabel: label) ? now() : contest.endTime,
            isVotingSetUp: true,
            tickedNodes: Set(failed.map(\.proTxHash)),
            history: history,
            now: now())
        // The first try already asked "One vote left" and the lock-is-final
        // question for this choice; the retry does not ask them again.
        attempt.confirm()
        attempt.confirm()
        guard let updated = await retryOutcomes(
            of: failed, choice: report.choice, at: attempt.step, on: contest, history: history)
        else { return }
        let merged = VoteCastReport(
            normalizedLabel: label,
            choice: report.choice,
            outcomes: report.outcomes.map { updated[$0.node.proTxHash] ?? $0 })
        // A newer attempt replaced or cleared the outcome meanwhile: it stays.
        guard outcomeVersion == version else { return }
        outcome = merged.isCompleteSuccess
            ? .success(successToast(for: report.choice, on: contest))
            : .mixed(merged)
    }

    /// What Try again's gate `step` makes of each failed masternode, sending
    /// from those it lets vote. `nil` for a step the retry cannot reach.
    private func retryOutcomes(
        of failed: [VoterNode], choice: VoteChoice, at step: VoteAttempt.Step, on contest: DPNSContest,
        history: VoteLimit
    ) async -> [Data: VoteOutcome]? {
        func all(_ reason: String?) -> [Data: VoteOutcome] {
            Dictionary(uniqueKeysWithValues: failed.map { ($0.proTxHash, VoteOutcome(node: $0, failure: reason)) })
        }
        switch step {
        case .votingEnded:
            return all(NSLocalizedString("Voting has ended", comment: "Voting"))
        case .historyUnavailable:
            return all(NSLocalizedString("Couldn't read your vote history.", comment: "Voting"))
        case .noVotesLeft:
            // A failed masternode that holds the choice by now has it.
            let holders = history.nodes(holding: choice, among: Set(failed.map(\.proTxHash))) ?? []
            return Dictionary(uniqueKeysWithValues: failed.map { node in
                (node.proTxHash, VoteOutcome(
                    node: node,
                    failure: holders.contains(node.proTxHash)
                        ? nil : NSLocalizedString("No votes left", comment: "Voting")))
            })
        case .nothingToSend:
            // Every failed masternode holds the choice by now.
            return all(nil)
        case .needsKeys, .confirmLastVote, .confirmBlock:
            // Not reached: the failed masternodes are ticked and both
            // confirmations were given.
            return nil
        case let .send(choice, senders):
            return await resend(choice, from: failed, senders: senders, on: contest, history: history)
        }
    }

    /// Try again's send: the failed masternodes the gates let vote send
    /// `choice`; any other one holds it by now or has no vote left.
    private func resend(
        _ choice: VoteChoice, from failed: [VoterNode], senders: Set<Data>, on contest: DPNSContest,
        history: VoteLimit
    ) async -> [Data: VoteOutcome] {
        let holders = history.nodes(holding: choice, among: Set(failed.map(\.proTxHash))) ?? []
        var updated: [Data: VoteOutcome] = [:]
        for node in failed where !senders.contains(node.proTxHash) {
            updated[node.proTxHash] = VoteOutcome(
                node: node,
                failure: holders.contains(node.proTxHash) ? nil : NSLocalizedString("No votes left", comment: "Voting"))
        }
        let sendable = failed.filter { senders.contains($0.proTxHash) }
        let retried: [VoteOutcome]
        switch await cast(choice: choice, on: contest, from: sendable) {
        case .success: retried = sendable.map { VoteOutcome(node: $0, failure: nil) }
        case .mixed(let again): retried = again.outcomes
        case .failure(let reason): retried = sendable.map { VoteOutcome(node: $0, failure: reason) }
        case nil: retried = []
        }
        for outcome in retried { updated[outcome.node.proTxHash] = outcome }
        return updated
    }

    private func successToast(for choice: VoteChoice, on contest: DPNSContest) -> VotingToast {
        choice == .abstain
            ? .voteCancelled(username: contest.displayTitle)
            : .voted(username: contest.displayTitle)
    }

    // MARK: Vote history

    /// Whether this contest's vote history is known yet. Callers disable the
    /// vote control until it is, rather than acting on an unknown.
    func hasLoadedVoteHistory(for normalizedLabel: String) -> Bool {
        votedProTxHashesByContest[normalizedLabel] != nil
    }

    /// Load which of our nodes already voted on one contest. A vote attempt
    /// and Try again call it at the tap, so the vote gates decide on today's
    /// history. `false` when the store could not be read; what was known stays.
    @discardableResult
    func loadVotedNodes(for normalizedLabel: String) async -> Bool {
        var read = false
        await serially { [weak self] in read = await self?.performLoadVotedNodes(for: normalizedLabel) ?? false }
        return read
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

    /// The choices the ticked nodes currently hold on a contest, from local
    /// history. Empty when none of them voted, when no node is ticked, before
    /// voting is set up, before the history loaded, or while the latest read
    /// failed: the last good read is not shown as today's votes.
    func myChoices(on normalizedLabel: String) -> Set<VoteChoice> {
        guard !historyUnavailable, let ticked = myNodeIDs,
              let history = voteHistoryByContest[normalizedLabel]
        else { return [] }
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
