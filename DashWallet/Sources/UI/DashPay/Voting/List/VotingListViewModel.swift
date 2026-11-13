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
    /// Set by the filters sheet's Apply. With "Only requests with links" on,
    /// each set asks again for the links that could not be checked — also
    /// when the sheet hands back the same filter, which is how «apply the
    /// filter again» retries them (AC-09b).
    @Published var filter: VotingFilter = .default {
        didSet {
            guard filter != oldValue || filter.onlyWithLinks else { return }
            recomputeVisible(retryingFailedLinks: filter.onlyWithLinks)
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
    /// Whether "Only requests with links" can be applied: every request it
    /// would look at has a known link. `.known` when the filter is off.
    @Published private(set) var linksForFilter: LinksForFilter = .known

    enum LinksForFilter: Equatable {
        case known
        /// Some request's link is still being read (AC-09b: loading).
        case reading
        /// Some request's link could not be checked (AC-09b: cannot filter).
        case failed
    }

    /// The outcome of the last vote, shown in the list's bottom bar (and, for
    /// an error, on Request details) until it is closed or the next vote
    /// attempt starts.
    @Published private(set) var toast: VotingToast?

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

    /// What the list shows in place of, or above, its rows. The full-screen
    /// error only while no list read has succeeded since the screen opened;
    /// after one, a failed refresh keeps what is on screen (AC-02).
    var loadState: VotingListLoadState {
        if !store.hasLoadedOnce { return .loading }
        if store.loadFailed && !store.didLoadContests { return .couldNotLoad }
        if store.contests.isEmpty { return .noContests }
        return .contests(refreshFailed: store.loadFailed)
    }

    /// The one lasting state shown above the rows, highest first: the vote
    /// history, the failed refresh, the incomplete node list. None until a
    /// list read has succeeded since the screen opened, so never with the
    /// first load's indicator or the full-screen error.
    var message: VotingListMessage? {
        guard store.didLoadContests else { return nil }
        if store.historyUnavailable { return .historyUnavailable }
        if store.loadFailed { return .refreshFailed }
        if store.nodeListMayBeIncomplete { return .nodeListIncomplete }
        return nil
    }

    /// A full read of the list is queued or running — pull to refresh, the
    /// first load or Try again: the message's Try again shows progress.
    var isTryingAgain: Bool { store.isRefreshing }

    /// The message's Try again: reads the list and the vote history again,
    /// unless a read is already queued or running.
    func tryAgain() async {
        await store.retry()
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
            // A synced, complete node list without a voting node: the wallet
            // has no votes, which no retry changes (AC-09).
            if store.nodeListSynced, !store.nodeListMayBeIncomplete, !store.canVote { return .noVotingKeys }
            // Not the filter's fault: this wallet's votes cannot be told (AC-09).
            if let reason = myVotesUnavailableReason { return .cannotFilterByMyVotes(reason: reason) }
            // Still loading for some contests: nothing can be said to match yet.
            if !myVotesKnownForList { return .loading }
        }
        // Links not all known: the list would be wrong (AC-09b).
        switch linksForFilter {
        case .reading: return .loading
        case .failed: return .cannotFilterByLinks
        case .known: break
        }
        // The filter alone hides every open contest (AC-08); otherwise the search does.
        return filterMatchCount == 0 ? .filterMatchesNothing : .searchMatchesNothing
    }

    /// Also called when the day changes, so "Voting ends today / in N days"
    /// stays true on a screen left open past midnight.
    func recomputeVisible() {
        recomputeVisible(retryingFailedLinks: false)
    }

    private func recomputeVisible(retryingFailedLinks: Bool) {
        linksForFilter = filter.onlyWithLinks ? readLinks(retryingFailed: retryingFailedLinks) : .known
        // Search matching keeps order and does not depend on the filter, so
        // filtering first gives both the header count and the rows.
        myVotesKnownForList = canFilterByMyVotes
            && store.contests.allSatisfy { store.hasLoadedVoteHistory(for: $0.normalizedLabel) }
        // A filter by my vote shows nothing until every contest can be told:
        // after a refresh the new contests' history is still loading, and
        // showing only the contests already known would be a partial list.
        // While the links cannot all be told, the links filter keeps nothing.
        let canTell = linksForFilter == .known && !(filter.type.readsMyVotes && !myVotesKnownForList)
        let kept = canTell ? filtered(store.contests) : []
        filterMatchCount = kept.count
        let visible = searchMatches(in: kept)
        // Days always go soonest first; the sort orders names inside a day.
        // The flat list takes the same order as the grouped one.
        sections = VotingListSection.group(visible, now: now(), calendar: calendar())
        visibleContests = sections.flatMap(\.contests)
    }

    /// Whether this wallet's own votes can be told for the types that read
    /// them: not when the history could not be read, nor while a voting node
    /// may be missing from the store's votable nodes (its votes would not count),
    /// nor before voting is set up, when no vote is this wallet's own (AC-12).
    var canFilterByMyVotes: Bool {
        !store.historyUnavailable && !store.nodeListMayBeIncomplete && store.isVotingSetUp
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
        if !store.isVotingSetUp {
            return NSLocalizedString("Set up voting to filter by your votes.", comment: "Voting")
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
        filter.apply(to: input, myChoices: knownChoices(on:)) { contest, request in
            let link = store.linkState(normalizedLabel: contest.normalizedLabel, identityId: request.identityId)
            if case .published = link { return true }
            return false
        }
    }

    /// The links the links filter needs: those of every request the rest of
    /// the filter keeps. Asks the store for each one never asked (and, when
    /// `retryingFailed`, each one that could not be checked), and says
    /// whether all are known.
    private func readLinks(retryingFailed: Bool) -> LinksForFilter {
        var withoutLinks = filter
        withoutLinks.onlyWithLinks = false
        var result = LinksForFilter.known
        var toAsk: Set<VotingStore.RequestKey> = []
        for contest in withoutLinks.apply(to: store.contests, myChoices: knownChoices(on:)) {
            for request in contest.contenders {
                let label = contest.normalizedLabel, identity = request.identityId
                let state = store.linkState(normalizedLabel: label, identityId: identity)
                if state == nil || (retryingFailed && state == .failed) {
                    toAsk.insert(VotingStore.RequestKey(normalizedLabel: label, identityId: identity))
                    result = .reading
                } else if state == .reading {
                    result = .reading
                } else if state == .failed, result == .known {
                    result = .failed
                }
            }
        }
        // One ask for all of them, after this recompute: the store marks them
        // reading in one change and looks up each name once. Not awaited, so
        // a screen that goes away does not keep the store and its lookups.
        if !toAsk.isEmpty {
            Task { [weak store] in store?.askForLinks(toAsk, retryingFailed: retryingFailed) }
        }
        return result
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

    /// Opens or closes a several-request name. Opening looks up the link of
    /// each request, for its «Link included».
    func toggleExpanded(_ normalizedLabel: String) {
        guard let contest = store.contests.first(where: { $0.normalizedLabel == normalizedLabel }),
              isExpandable(contest) else { return }
        guard expandedLabels.insert(normalizedLabel).inserted else {
            expandedLabels.remove(normalizedLabel)
            return
        }
        let keys = contest.contenders.map {
            VotingStore.RequestKey(normalizedLabel: normalizedLabel, identityId: $0.identityId)
        }
        store.askForLinks(Set(keys), retryingFailed: true, first: true)
    }

    /// A request's day, "12 Feb 2023"; its time is `requestTimeFormatter`'s,
    /// drawn after it in a lighter colour as in the design.
    let requestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// A request's time of day, "9:45".
    let requestTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// One row per request, in the contender order, each with its date, its
    /// link mark and its own approve pill state: filled where a ticked node's
    /// vote lands on that request.
    func requestRows(for contest: DPNSContest) -> [VotingRequestRow] {
        let mine = store.myChoices(on: contest.normalizedLabel)
        return contest.contenders.map { contender in
            let link = store.linkState(normalizedLabel: contest.normalizedLabel, identityId: contender.identityId)
            let hasLink: Bool
            if case .published = link { hasLink = true } else { hasLink = false }
            return VotingRequestRow(
                identityId: contender.identityId,
                votes: Int(contender.voteTally),
                isMine: mine.contains(.towards(identityId: contender.identityId)),
                dateText: contender.createdAt.map(requestDateFormatter.string(from:)),
                timeText: contender.createdAt.map(requestTimeFormatter.string(from:)),
                hasLink: hasLink)
        }
    }

    // MARK: Pills

    /// Whether a list pill takes a tap. Every tap runs the vote gates, which
    /// tell an ended contest (AC-03) and "No votes left" (AC-15) themselves, so
    /// a pill is disabled only while voting is paused (the vote history cannot
    /// be read, so the vote limit is unknown) and while a vote is being sent:
    /// one vote at a time, so a send's report and Try again stay its own.
    func canTapPill(_ choice: VoteChoice, on normalizedLabel: String) -> Bool {
        !store.historyUnavailable && !store.isVoteBusy
    }

    /// The pill whose vote is being sent on this contest; `nil` when none is,
    /// or when the send did not start from a pill (Try again).
    func sendingPill(on normalizedLabel: String) -> VoteChoice? {
        store.sendingPill(on: normalizedLabel)
    }

    /// The vote a pill tap asks for: the pill's choice, or, on a filled pill,
    /// an abstain from the ticked nodes holding it.
    func voteRequest(for choice: VoteChoice, on contest: DPNSContest) -> VoteFlowRequest {
        guard store.myChoices(on: contest.normalizedLabel).contains(choice) else {
            return VoteFlowRequest(contest: contest, choice: choice)
        }
        return VoteFlowRequest(contest: contest, choice: .abstain, cancelling: choice)
    }

    /// What a tap on the row's name does: one request opens its details,
    /// several open or close in place. `nil` for a name with no request,
    /// whose header has nothing to open.
    func headerAccessibilityHint(for contest: DPNSContest) -> String? {
        guard !contest.contenders.isEmpty else { return nil }
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

    /// An error toast stays until it is cleared: by ``clearToast(id:)`` from
    /// its close button, or by ``clearToast()`` as the next vote attempt
    /// starts (AC-06); a success toast also clears itself by id after
    /// ``VotingToast/hidesAfter``.
    func showToast(_ toast: VotingToast) {
        self.toast = toast
    }

    func clearToast() {
        toast = nil
    }

    /// Clears the toast only while it is still the one with `id`, so an older
    /// toast's timer never clears the toast that replaced it.
    func clearToast(id: VotingToast.ID) {
        guard toast?.id == id else { return }
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
    /// The request's day; `nil` when Platform gave no date, and the row shows the identity instead.
    let dateText: String?
    /// The request's time of day, shown after `dateText`; `nil` with it.
    let timeText: String?
    /// The requester published a link: the row says «Link included».
    let hasLink: Bool

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
    /// No list read has succeeded since the screen opened.
    case couldNotLoad
    /// The load succeeded and no contest is open.
    case noContests
    /// Contests are held; `refreshFailed` when the last refresh failed.
    case contests(refreshFailed: Bool)
}

// MARK: - VotingListMessage

/// A lasting state of the list, shown as a message above the rows while it
/// lasts. It has no close button: it goes when its state ends.
enum VotingListMessage: Equatable {
    /// The vote history cannot be read, so voting is paused.
    case historyUnavailable
    /// A full read of the list failed after one had succeeded (AC-02).
    case refreshFailed
    /// A masternode this wallet votes with may be missing (AC-03b).
    case nodeListIncomplete

    var title: String {
        switch self {
        case .historyUnavailable:
            return NSLocalizedString("Couldn't read your vote history.", comment: "Voting")
        case .refreshFailed:
            return NSLocalizedString("Couldn't refresh the list.", comment: "Voting")
        case .nodeListIncomplete:
            return NSLocalizedString("Some masternodes may be missing.", comment: "Voting")
        }
    }

    var subtitle: String? {
        switch self {
        case .historyUnavailable:
            return NSLocalizedString("Voting is paused.", comment: "Voting")
        case .refreshFailed:
            return nil
        case .nodeListIncomplete:
            return NSLocalizedString("Finish syncing.", comment: "Voting")
        }
    }

    /// Whether the message has "Try again", which reads the list and the
    /// vote history again.
    var offersTryAgain: Bool {
        self != .nodeListIncomplete
    }
}

// MARK: - VotingListEmptyState

/// What the list shows in place of its rows.
enum VotingListEmptyState: Equatable {
    case loading
    /// No list read has succeeded since the screen opened (AC-02).
    case couldNotLoad
    /// A type by my vote while this wallet's votes cannot be told, and why (AC-09).
    case cannotFilterByMyVotes(reason: String)
    /// A type by my vote while the synced node list holds no voting node of
    /// this wallet: it has no votes to filter by (AC-09).
    case noVotingKeys
    /// "Only requests with links" while some request's link could not be checked (AC-09b).
    case cannotFilterByLinks
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

/// A short message in the list's bottom bar: a vote that landed on every
/// node, one every ticked masternode already held, one that failed outright,
/// a vote on a contest that has ended, or a vote history that could not be
/// read. Request details shows only this name's error toasts (a failed vote,
/// an ended contest, an unreadable history) and its already-voted notice,
/// never a landed vote. A mixed vote is not a toast: its report lists each
/// node's outcome.
struct VotingToast: Identifiable, Equatable {
    let id = UUID()
    let message: String

    enum Style {
        case success
        case error
    }

    let style: Style

    /// Only an error toast can be closed by hand (AC-06); a success toast
    /// hides itself, as in the design.
    var showsCloseButton: Bool { style == .error }

    /// How long the toast stays: a success toast hides after 3 s; an error
    /// toast (`nil`) stays until it is closed or the next attempt (AC-06).
    var hidesAfter: Duration? { style == .success ? .seconds(3) : nil }

    /// The vote was already held, so Request details tells it too: nothing
    /// was sent and the screen stays.
    var isAlreadyVoted = false

    static func voted(username: String) -> VotingToast {
        VotingToast(
            message: String(format: NSLocalizedString("Voted %@ username", comment: "Voting"), username),
            style: .success)
    }

    /// Every abstain of a cancel landed (AC-17).
    static func voteCancelled(username: String) -> VotingToast {
        VotingToast(
            message: String(format: NSLocalizedString("Vote cancelled on %@", comment: "Voting"), username),
            style: .success)
    }

    /// Every vote of the attempt failed; `reason` in plain words (AC-06).
    static func failed(_ reason: String) -> VotingToast {
        VotingToast(message: reason, style: .error)
    }

    /// A vote every ticked masternode already holds: nothing was sent (AC-12).
    static func alreadyVoted(username: String) -> VotingToast {
        let format = NSLocalizedString("Already voted this way on %@", comment: "Voting")
        return VotingToast(message: String(format: format, username), style: .success, isAlreadyVoted: true)
    }

    /// Every vote of a Quick voting run landed (AC-18).
    static func quickVotingDone() -> VotingToast {
        VotingToast(
            message: NSLocalizedString("Quick voting done", comment: "Voting"),
            style: .success)
    }

    /// A vote on a contest whose voting end has passed (AC-03).
    static func votingEnded(username: String) -> VotingToast {
        VotingToast(
            message: String(format: NSLocalizedString("Voting on %@ has ended", comment: "Voting"), username),
            style: .error)
    }
}
