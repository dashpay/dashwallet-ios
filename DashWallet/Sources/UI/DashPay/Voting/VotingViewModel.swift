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
    @Published private(set) var isLoading = false
    /// Set when a refresh fails. The list keeps showing the last good data.
    @Published private(set) var loadError: String?
    /// `false` until the first refresh completes, so the empty state is not
    /// shown while the first fetch is still in flight.
    @Published private(set) var hasLoadedOnce = false

    @Published var searchQuery: String = ""
    @Published var sort: ContestSort = .endingSoonest

    /// Result banner for the most recent casting run.
    @Published var lastCastReport: VoteCastReport?
    /// Error from a casting run that never got as far as broadcasting.
    @Published var castError: String?
    @Published private(set) var isCasting = false

    // MARK: Dependencies

    private let contestsService: ContestedNamesService
    private let registry: MasternodeVoterRegistry
    private let caster: MasternodeVoteCaster

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
        return sorted(contests.filter { $0.normalizedLabel.contains(needle) })
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

        votableNodes = registry.votableNodes()

        do {
            contests = try await contestsService.activeContests()
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
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
            await refreshContest(normalizedLabel: contest.normalizedLabel)
        } catch {
            castError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    func dismissCastResult() {
        lastCastReport = nil
        castError = nil
    }
}
