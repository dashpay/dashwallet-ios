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
    @Published private(set) var contests: [DPNSContest] = []
    /// Labels observed to have resolved while the user was looking at them,
    /// so an already-open detail screen can say so instead of offering a vote
    /// that can no longer be accepted.
    @Published private(set) var closedLabels: Set<String> = []
    @Published private(set) var votableNodes: [VoterNode] = []
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

    @Published var searchQuery: String = ""
    @Published var sort: ContestSort = .endingSoonest

    /// True once a contest fetch has actually succeeded. Distinct from
    /// ``hasLoadedOnce``, which only records that a load was attempted.
    private var didLoadContests = false

    /// Multi-select mode, the replacement for the old "Quick Voting" screen.
    @Published var isSelecting = false
    @Published private(set) var selectedLabels: Set<String> = []
    /// Per-contest results of the most recent bulk run.
    @Published var bulkReports: [VoteCastReport]?

    /// How many of this wallet's nodes have already voted, per contest, from
    /// local history. Drives the "2 of 5 votes cast" line and excludes nodes
    /// that already voted from the next cast.
    @Published private(set) var castCountsByContest: [String: Int] = [:]
    /// Which of our nodes voted on the contest currently being viewed.
    @Published private(set) var votedProTxHashesForOpenContest: Set<Data> = []

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

    /// Default arguments would have to be evaluated in a nonisolated context,
    /// but both services are `@MainActor`, so the defaults are applied inside
    /// this `@MainActor` body instead.
    init(
        contestsService: ContestedNamesService? = nil,
        registry: MasternodeVoterRegistry? = nil
    ) {
        let contestsService = contestsService ?? ContestedNamesService()
        let registry = registry ?? MasternodeVoterRegistry()
        self.contestsService = contestsService
        self.registry = registry
        self.caster = MasternodeVoteCaster(registry: registry, contests: contestsService)
    }

    // MARK: Derived state

    /// Total Platform voting weight this wallet controls. Evonodes count 4×.
    var totalVoteWeight: UInt32 { votableNodes.totalVoteWeight }

    var canVote: Bool { !votableNodes.isEmpty }

    /// Contests matching the search box, in the selected order.
    ///
    /// The query is homograph-normalized before matching because Platform
    /// stores normalized labels — someone typing "alice" is looking for
    /// "a11ce", and a raw substring match would find nothing.
    var visibleContests: [DPNSContest] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sorted(contests) }

        // Normalization needs the SDK, and so does `contests` — a non-empty
        // list means the handle is up, so this only returns nil when there is
        // nothing to filter anyway. Leaving the list unfiltered beats
        // matching against a locally-guessed spelling of the label.
        guard let needle = contestsService.normalizedLabel(for: trimmed) else {
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

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        let resolution = registry.votableNodes()
        votableNodes = resolution.nodes
        nodeListMayBeIncomplete = resolution.mayBeIncomplete

        // Settle the remembered selection against the nodes that actually
        // exist now, so the picker and the "voting with" row agree with what a
        // tap would really do. Writing it back also migrates a wallet that
        // never had a selection (or whose nodes changed) onto a concrete one
        // instead of leaving the fallback implicit.
        let settled = effectiveSelectedNodeIDs
        if settled != selectedNodeIDs {
            selectedNodeIDs = settled
        }

        castCountsByContest = await history.voteCountsByContest(
            network: MasternodeVoteCaster.networkKey)

        do {
            contests = try await contestsService.activeContests()
            loadError = nil
            didLoadContests = true
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
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
        guard !didLoadContests else { return }
        await refresh()
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
            contenders: state.contenders)
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

    /// Votes this wallet has cast on `contest`, and how many it could cast in
    /// total — the "2 of 5" the row and detail screen show.
    func castCount(for normalizedLabel: String) -> Int {
        castCountsByContest[normalizedLabel] ?? 0
    }

    /// Nodes that have not yet voted on this contest, in registration order.
    func nodesYetToVote(on normalizedLabel: String) -> [VoterNode] {
        votableNodes.filter { !votedProTxHashesForOpenContest.contains($0.proTxHash) }
    }

    /// Load which of our nodes already voted on one contest. Called when its
    /// detail screen opens, so the vote button knows what is left.
    func loadVotedNodes(for normalizedLabel: String) async {
        let records = await history.votes(
            forContest: normalizedLabel,
            network: MasternodeVoteCaster.networkKey)
        votedProTxHashesForOpenContest = Set(records.map(\.proTxHash))
        castCountsByContest[normalizedLabel] = records.count
    }

    /// The nodes a single tap should vote with: the remembered selection,
    /// minus any that already voted on this contest.
    ///
    /// Returns empty when every selected node has already voted here — the
    /// caller disables the control rather than re-broadcasting a vote Platform
    /// would reject as a duplicate.
    func nodesForNextVote(on normalizedLabel: String) -> [VoterNode] {
        let remaining = nodesYetToVote(on: normalizedLabel)
        let chosen = effectiveSelectedNodeIDs
        return remaining.filter { chosen.contains($0.proTxHash) }
    }

    /// The remembered selection, or a single node when nothing was ever
    /// chosen. Never every node by default: see ``VotingPrefs``.
    ///
    /// Also recovers from a selection that no longer matches any votable node
    /// (nodes revoked, or a different wallet), which would otherwise leave the
    /// vote button permanently disabled with no way to see why.
    var effectiveSelectedNodeIDs: Set<Data> {
        let live = selectedNodeIDs.intersection(Set(votableNodes.map(\.proTxHash)))
        if !live.isEmpty { return live }
        return Set(votableNodes.first.map { [$0.proTxHash] } ?? [])
    }

    // MARK: Casting

    /// Cast `choice` on `contest` with `nodes`, then refresh that contest.
    func cast(choice: VoteChoice, on contest: DPNSContest, with nodes: [VoterNode]) async {
        isCasting = true
        castError = nil
        defer { isCasting = false }

        do {
            let report = try await caster.cast(
                choice: choice,
                onNormalizedLabel: contest.normalizedLabel,
                with: nodes)
            lastCastReport = report
            await loadVotedNodes(for: contest.normalizedLabel)
            await refreshContest(normalizedLabel: contest.normalizedLabel)
        } catch {
            castError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
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
        /// The choice being replaced, when every replaced vote agrees — `nil`
        /// when they differ, so the prompt never names one falsely.
        let replacedChoice: VoteChoice?

        var hasWork: Bool { work.contains { !$0.nodes.isEmpty } }
        var totalPairs: Int { work.reduce(0) { $0 + $1.nodes.count } }
        /// Whether the user should be asked before this runs.
        var needsConfirmation: Bool { duplicatePairs > 0 || changedPairs > 0 }
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
        var replacedChoices = Set<VoteChoice>()

        for contest in selected {
            guard let wireChoice = resolvedChoice(choice, for: contest) else { continue }
            let records = await history.votes(
                forContest: contest.normalizedLabel,
                network: MasternodeVoteCaster.networkKey)

            // A node can appear more than once here (it voted, then changed);
            // only its most recent vote says what its live choice is.
            var latestByNode: [Data: CastVoteRecord] = [:]
            for record in records {
                if let seen = latestByNode[record.proTxHash], seen.castAt >= record.castAt {
                    continue
                }
                latestByNode[record.proTxHash] = record
            }

            var casting: [VoterNode] = []
            for node in nodes {
                guard let prior = latestByNode[node.proTxHash] else {
                    casting.append(node)
                    continue
                }
                if prior.choice == wireChoice {
                    duplicatePairs += 1
                } else {
                    changedPairs += 1
                    replacedChoices.insert(prior.choice)
                    casting.append(node)
                }
            }

            if !casting.isEmpty {
                work.append((contest.normalizedLabel, wireChoice, casting))
            }
        }

        return BulkPlan(
            work: work,
            duplicatePairs: duplicatePairs,
            changedPairs: changedPairs,
            replacedChoice: replacedChoices.count == 1 ? replacedChoices.first : nil)
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
            for label in labels {
                await refreshContest(normalizedLabel: label)
            }
        } catch {
            castError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
