//
//  VotingListViewModel.swift
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

// MARK: - VotingListViewModel

/// Presentation state of the username list: the search, the filter, the
/// day-grouped rows and the toast. The contests, masternodes and votes they
/// are computed from live on ``VotingStore``.
@MainActor
final class VotingListViewModel: ObservableObject {
    @Published var searchQuery: String = "" {
        didSet {
            normalizedNeedle = normalizedLabel(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
            recomputeVisible()
        }
    }
    /// The search query, homograph-normalized once per edit rather than on
    /// every recompute of the list.
    private var normalizedNeedle: String?
    @Published var filter: VotingFilter = .default {
        didSet {
            guard filter != oldValue else { return }
            recomputeVisible()
        }
    }

    /// Contests matching the search box and the filter, in the filter's order.
    /// Recomputed when the contests, the search, the filter or this wallet's
    /// votes change — not on every render, since matching a search normalizes
    /// it through the SDK.
    @Published private(set) var visibleContests: [DPNSContest] = []
    /// How many open contests the filter keeps, whatever the search narrows
    /// the list to: the count next to the filter's name in the header.
    @Published private(set) var filterMatchCount = 0
    /// Whether the types that read this wallet's votes can classify every
    /// listed contest: the votes can be told, and each contest's history has
    /// loaded. Until then their count and an empty list say nothing.
    @Published private(set) var myVotesKnownForList = false
    /// ``visibleContests`` grouped by the day voting ends.
    @Published private(set) var sections: [VotingListSection] = []

    /// The outcome of the last vote, shown in the list's bottom bar and over
    /// the contest screen.
    @Published private(set) var toast: VotingToast?

    /// How long a toast stays before it clears itself.
    static let toastDuration: Duration = .seconds(3)

    private let store: VotingStore
    private let normalizedLabel: @MainActor (String) -> String?
    private let now: () -> Date
    /// Read on every recompute: the user's time zone can change while the
    /// list is open.
    private let calendar: () -> Calendar
    private var storeChanges: AnyCancellable?

    init(
        store: VotingStore,
        normalizedLabel: @escaping @MainActor (String) -> String? = {
            ContestedNamesService().normalizedLabel(for: $0)
        },
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.store = store
        self.normalizedLabel = normalizedLabel
        self.now = now
        self.calendar = calendar
        storeChanges = store.stateDidChange.sink { [weak self] in self?.recomputeVisible() }
        recomputeVisible()
    }

    /// What the list shows in place of, or above, its rows.
    var loadState: VotingListLoadState {
        if !store.hasLoadedOnce { return .loading }
        if store.loadFailed && store.contests.isEmpty { return .couldNotLoad }
        if store.contests.isEmpty { return .noContests }
        return .contests(refreshFailed: store.loadFailed)
    }

    /// The banner over the kept rows when the last refresh failed (AC-02).
    var refreshFailedText: String? {
        guard loadState == .contests(refreshFailed: true) else { return nil }
        return NSLocalizedString("Couldn't refresh.", comment: "Voting")
    }

    /// What the list shows instead of rows; `nil` when rows show.
    var emptyState: VotingListEmptyState? {
        switch loadState {
        case .loading:
            return .loading
        case .couldNotLoad:
            // Try again is running: show it rather than the old failure.
            return store.isRefreshing ? .loading : .couldNotLoad
        case .noContests:
            return .noContests
        case .contests:
            break
        }
        guard visibleContests.isEmpty else { return nil }
        if filter.type.readsMyVotes {
            // Not the filter's fault: this wallet's votes cannot be told (AC-09).
            if let reason = myVotesUnavailableReason { return .cannotFilterByMyVotes(reason: reason) }
            // Still loading for some contests: nothing can be said to match yet.
            if !myVotesKnownForList { return .loading }
        }
        // The filter alone hides every open contest (AC-08); otherwise the search does.
        return filterMatchCount == 0 ? .filterMatchesNothing : .searchMatchesNothing
    }

    /// Also called when the day changes, so "Voting ends today / in N days"
    /// stays true on a screen left open past midnight.
    func recomputeVisible() {
        // Search matching keeps order and does not depend on the filter, so
        // filtering first gives both the header count and the rows.
        myVotesKnownForList = canFilterByMyVotes
            && store.contests.allSatisfy { store.hasLoadedVoteHistory(for: $0.normalizedLabel) }
        // A filter by my vote shows nothing until every contest can be told:
        // after a refresh the new contests' history is still loading, and
        // showing only the contests already known would be a partial list.
        let kept = filter.type.readsMyVotes && !myVotesKnownForList ? [] : filtered(store.contests)
        filterMatchCount = kept.count
        let visible = searchMatches(in: kept)
        // Days always go soonest first; the sort orders names inside a day.
        // The flat list takes the same order as the grouped one.
        sections = VotingListSection.group(visible, now: now(), calendar: calendar())
        visibleContests = sections.flatMap(\.contests)
    }

    /// Whether this wallet's own votes can be told for the types that read
    /// them: not when the history could not be read, nor while a voting node
    /// may be missing from the store's votable nodes (its votes would not count).
    var canFilterByMyVotes: Bool {
        !store.historyUnavailable && !store.nodeListMayBeIncomplete && store.canVote
    }

    /// Why this wallet's own votes cannot be told, as the next step for the
    /// user; `nil` when they can. Without a voting node the wallet holds no
    /// vote to tell, so the types that read them have nothing to go on.
    var myVotesUnavailableReason: String? {
        if store.historyUnavailable {
            return NSLocalizedString("Pull down to try again.", comment: "Voting")
        }
        if store.nodeListMayBeIncomplete {
            return NSLocalizedString(
                "Some of your masternodes may be missing from this list — the wallet could not read your full voting-key pool. Finish syncing and reopen this screen.",
                comment: "Voting")
        }
        if !store.canVote {
            return NSLocalizedString(
                "This wallet's masternode voting keys aren't available right now, so it has no votes to filter by.",
                comment: "Voting")
        }
        return nil
    }

    /// The contests in `input` matching the search box, in their order.
    ///
    /// The query is homograph-normalized before matching because Platform
    /// stores normalized labels — someone typing "alice" is looking for
    /// "a11ce", and a raw substring match would find nothing.
    private func searchMatches(in input: [DPNSContest]) -> [DPNSContest] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }

        // Normalization needs the SDK, and so does `contests` — a non-empty
        // list means the handle is up, so this only returns nil when there is
        // nothing to filter anyway. Leaving the list unfiltered beats
        // matching against a locally-guessed spelling of the label.
        // Normalized when the query was typed; again here only if the SDK was
        // not up yet then.
        if normalizedNeedle == nil {
            normalizedNeedle = normalizedLabel(trimmed)
        }
        guard let needle = normalizedNeedle else {
            return input
        }
        // Match the normalized form *and* the spellings people actually typed,
        // so searching "pizza" finds the contest whether the row is showing
        // "pizza" or the normalized "p1zza".
        let raw = trimmed.lowercased()
        return input.filter { contest in
            contest.normalizedLabel.contains(needle)
                || contest.requestedLabels.contains { $0.lowercased().contains(raw) }
        }
    }

    private func filtered(_ input: [DPNSContest]) -> [DPNSContest] {
        filter.apply(to: input, myChoices: knownChoices(on:))
    }

    /// This wallet's choices on a contest, or `nil` while they are not known
    /// (history not loaded or unreadable, node list maybe incomplete): the
    /// filters by my vote then leave the contest out rather than guess.
    private func knownChoices(on normalizedLabel: String) -> Set<VoteChoice>? {
        guard canFilterByMyVotes, store.hasLoadedVoteHistory(for: normalizedLabel) else { return nil }
        return store.myChoices(on: normalizedLabel)
    }

    // MARK: Expanded rows (session only)

    /// The names whose several requests are open in place.
    @Published private var expandedLabels: Set<String> = []

    func isExpanded(_ normalizedLabel: String) -> Bool {
        expandedLabels.contains(normalizedLabel)
    }

    /// A name with a single request has no expand pill, so nothing to open.
    func isExpandable(_ contest: DPNSContest) -> Bool {
        contest.contenders.count > 1
    }

    func toggleExpanded(_ normalizedLabel: String) {
        guard let contest = store.contests.first(where: { $0.normalizedLabel == normalizedLabel }),
              isExpandable(contest) else { return }
        if !expandedLabels.insert(normalizedLabel).inserted {
            expandedLabels.remove(normalizedLabel)
        }
    }

    /// One row per request, in the contender order, each with its own approve
    /// pill state: filled where a ticked node's vote lands on that request.
    func requestRows(for contest: DPNSContest) -> [VotingRequestRow] {
        let mine = store.myChoices(on: contest.normalizedLabel)
        return contest.contenders.map { contender in
            VotingRequestRow(
                identityId: contender.identityId,
                votes: Int(contender.voteTally),
                isMine: mine.contains(.towards(identityId: contender.identityId)))
        }
    }

    // MARK: Pills

    /// Whether a tap on a list pill can start anything. A filled pill takes my
    /// vote back (AC-17), so it stays tappable while a ticked node holding that
    /// choice can still abstain; an outlined pill follows
    /// ``VotingStore/canStartVote(_:on:)``.
    func canTapPill(_ choice: VoteChoice, on normalizedLabel: String) -> Bool {
        guard store.myChoices(on: normalizedLabel).contains(choice) else {
            return store.canStartVote(choice, on: normalizedLabel)
        }
        return !store.isClosed(normalizedLabel: normalizedLabel)
            && !store.nodesToCancel(choice, on: normalizedLabel).isEmpty
    }

    // TODO(voting-4): the pill gates (No votes left, One vote left) run in the vote-attempt coordinator.
    /// The vote a pill tap asks for: the pill's choice, or, on a filled pill,
    /// an abstain from the ticked nodes holding it.
    func voteRequest(for choice: VoteChoice, on contest: DPNSContest) -> VoteFlowRequest {
        guard store.myChoices(on: contest.normalizedLabel).contains(choice) else {
            return VoteFlowRequest(contest: contest, choice: choice)
        }
        return VoteFlowRequest(contest: contest, choice: .abstain, cancelling: choice)
    }

    /// What a tap on the row's name does: one request opens its details,
    /// several open or close in place.
    func headerAccessibilityHint(for contest: DPNSContest) -> String {
        guard isExpandable(contest) else {
            return NSLocalizedString("Opens the request details", comment: "Voting")
        }
        return isExpanded(contest.normalizedLabel)
            ? NSLocalizedString("Hides the requests for this name", comment: "Voting")
            : NSLocalizedString("Opens the requests for this name", comment: "Voting")
    }

    func requestCountText(for contest: DPNSContest) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%d requests", comment: "Voting"), contest.contenders.count)
    }

    func expandAccessibilityLabel(for contest: DPNSContest, isExpanded: Bool) -> String {
        let format = isExpanded
            ? NSLocalizedString("Hide requests for %@", comment: "Voting")
            : NSLocalizedString("Show requests for %@", comment: "Voting")
        return String(format: format, contest.displayTitle)
    }

    func expandAccessibilityValue(for contest: DPNSContest) -> String {
        requestCountText(for: contest)
    }

    // MARK: Toast

    func showToast(_ toast: VotingToast) {
        self.toast = toast
        Task { [weak self, id = toast.id] in
            try? await Task.sleep(for: Self.toastDuration)
            // Only the toast this task was started for: a newer one has its own timer.
            if self?.toast?.id == id { self?.toast = nil }
        }
    }

    func clearToast() {
        toast = nil
    }
}

// MARK: - VotingRequestRow

/// One request of a several-request name, as listed when its row is open.
struct VotingRequestRow: Equatable {
    let identityId: String
    let votes: Int
    /// A ticked node's vote lands on this request: its approve pill is filled.
    let isMine: Bool

    /// The identity as VoiceOver reads it: its first and last four
    /// characters, enough to tell a row's requests apart; Request details
    /// shows the whole id.
    var spokenIdentity: String {
        guard identityId.count > 8 else { return identityId }
        return "\(identityId.prefix(4)) … \(identityId.suffix(4))"
    }

    var accessibilityLabel: String {
        String(format: NSLocalizedString("Approve %@", comment: "Voting"), spokenIdentity)
    }

    var accessibilityValue: String {
        String.localizedStringWithFormat(NSLocalizedString("%d votes", comment: "Voting"), votes)
    }
}

// MARK: - VotingListLoadState

enum VotingListLoadState: Equatable {
    /// The first load has not finished.
    case loading
    /// The load failed and nothing is cached.
    case couldNotLoad
    /// The load succeeded and no contest is open.
    case noContests
    /// Contests are held; `refreshFailed` when the last refresh failed.
    case contests(refreshFailed: Bool)
}

// MARK: - VotingListEmptyState

/// What the list shows in place of its rows.
enum VotingListEmptyState: Equatable {
    case loading
    /// The load failed and nothing is cached (AC-02).
    case couldNotLoad
    /// A type by my vote while this wallet's votes cannot be told, and why (AC-09).
    case cannotFilterByMyVotes(reason: String)
    /// Open contests exist and the filter keeps none (AC-08).
    case filterMatchesNothing
    /// The load succeeded and no contest is open.
    case noContests
    /// The filter keeps some, the search none.
    case searchMatchesNothing
}

// MARK: - VotingListSection

/// The voting list's groups: contests whose voting ends on the same calendar
/// day, soonest first. Rows inside a group keep the order they came in, which
/// is the list's chosen sort.
struct VotingListSection: Identifiable, Equatable {
    /// Days from today to the day voting ends; `nil` when the end is unknown.
    let daysLeft: Int?
    let contests: [DPNSContest]

    var id: Int { daysLeft ?? Int.max }

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
