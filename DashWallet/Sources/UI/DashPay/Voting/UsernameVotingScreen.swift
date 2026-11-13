//
//  UsernameVotingScreen.swift
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
import DashUIKit
import SwiftDashSDK
import SwiftUI

// MARK: - UsernameVotingScreen

/// Menu → Voting. Lists every open DPNS username contest on the network and
/// lets masternodes and evonodes registered to this wallet vote on them.
///
/// Browsing needs no masternode. Voting needs the voting key of at least one
/// active masternode: derived by the wallet, or added through the voting-key
/// flow a pill tap or the bar's menu opens.
struct UsernameVotingScreen: View {
    /// Pops the UIKit stack. The screen lives inside its own `NavigationStack`
    /// (see `MainMenuScreen.showVoting`), so the back button has to be wired
    /// explicitly — SwiftUI cannot see the UIKit stack underneath it.
    let onClose: () -> Void

    @StateObject private var viewModel: VotingViewModel
    @State private var showingFilters = false
    /// The voting-key flow opened from the menu or the «Voting with» row.
    @State private var showsKeyFlow = false
    /// A vote started from a pill, handed to ``View/voteFlow(_:viewModel:)``.
    @State private var voteRequest: VoteFlowRequest?
    /// The request opened from a row.
    @State private var openedRequest: OpenedRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct OpenedRequest: Hashable {
        let normalizedLabel: String
        let identityId: String
    }

    init(onClose: @escaping () -> Void, viewModel: VotingViewModel? = nil) {
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: viewModel ?? VotingViewModel())
    }

    private var store: VotingStore { viewModel.store }
    private var list: VotingListViewModel { viewModel.list }

    private var screenTitle: String { NSLocalizedString("Username Voting", comment: "Voting") }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            scrollingContent
        }
        .background(Color.dash.primaryBackground)
        // The DashUIKit bar replaces the system one; the title stays for
        // VoiceOver's screen title and the long-press back menu.
        .navigationTitle(screenTitle)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DashUIKit.FilterBar(
                value: list.filter.sort.title,
                title: NSLocalizedString("Filtered by", comment: "Voting"),
                filterAccessibilityLabel: NSLocalizedString("Filter", comment: "Voting"),
                replacement: list.toast.map { $0.view(onClose: list.clearToast) }) {
                showingFilters = true
            }
        }
        .sheet(isPresented: $showingFilters) {
            VotingFiltersSheet(filter: list.filter) { list.filter = $0 }
        }
        .navigationDestination(item: $openedRequest) { opened in
            RequestDetailsScreen(
                voting: viewModel, normalizedLabel: opened.normalizedLabel, identityId: opened.identityId)
        }
        .voteFlow($voteRequest, viewModel: viewModel)
        .sheet(isPresented: $showsKeyFlow) {
            // Not opened from a vote: manage mode, with no vote button.
            VotingKeysFlow(
                mode: .manage,
                viewModel: viewModel,
                onFinish: { _ in showsKeyFlow = false })
        }
        .task { await store.refreshIfNeeded() }
        // "Voting ends today / in N days" is relative to today.
        // Midnight and time-zone changes, delivered on return if they happened
        // while the app was suspended.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            list.recomputeVisible()
        }
        // The toast and the message appear where VoiceOver is not looking; say them.
        .onChange(of: list.toast?.id) {
            if let message = list.toast?.message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: list.message) {
            if let message = list.message {
                AccessibilityNotification.Announcement(
                    [message.title, message.subtitle].compactMap { $0 }.joined(separator: " ")).post()
            }
        }
    }

    // MARK: Bar

    /// Round back, and the «…» menu with «Voting keys»: manage mode has no
    /// other entry. Back is off while a vote runs: the vote outlives the
    /// screen, and a reopened screen would not know it is still sending.
    private var navigationBar: some View {
        DashUIKit.NavigationBar(
            leading: {
                DashUIKit.NavigationBarElement.back.button(action: onClose)
                    .disabled(store.isVoteBusy)
            },
            trailing: { votingMenu })
    }

    private var scrollingContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DashUIKit.TopIntroView(
                    title: screenTitle,
                    mainDescription: NSLocalizedString(
                        "As a masternode owner you can vote to approve requested usernames before users will be able to create it.",
                        comment: "Voting"),
                    secondaryDescription: NSLocalizedString(
                        "You can block the creation of the usernames that you feel inappropriate.",
                        comment: "Voting"),
                    descriptionColor: Color.dash.secondaryText)
                    .padding(.top, 10)

                header
                    .padding(.top, 20)

                DashUIKit.SearchBar(
                    text: Binding(get: { list.searchQuery }, set: { list.searchQuery = $0 }),
                    placeholder: NSLocalizedString("Search by username", comment: "Voting"))
                    .padding(.top, 20)

                lastingMessage

                votingWithRow

                contestList
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .refreshable { await store.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 1) {
                // The filter's type and how many open contests it keeps,
                // whatever the search narrows the list to.
                Text(list.filter.title)
                    .dashFont(.headline)
                    .foregroundStyle(Color.dash.primaryText)
                // No count while the type reads this wallet's votes and they
                // are not known for every contest: it would not be a count.
                if !list.filter.type.readsMyVotes || list.myVotesKnownForList {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("%d usernames", comment: "Voting"),
                        list.filterMatchCount))
                        .dashFont(.footnote)
                        .foregroundStyle(Color.dash.tertiaryText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            DashUIKit.DashButton(
                text: NSLocalizedString("Filter", comment: "Voting"),
                leadingIcon: DashUIKit.DashIcon.Common.filterS.source,
                size: .small,
                style: .plainBlack,
                action: { showingFilters = true })
        }
    }

    /// Voting keys (manage mode: which masternodes vote), which the design
    /// keeps behind this menu. Labelled, so it does not hide behind a bare icon.
    private var votingMenu: some View {
        DashUIKit.NavigationBarCircleMenu(
            .system("ellipsis"),
            accessibilityLabel: Text(NSLocalizedString("Voting options", comment: "Voting"))) {
            Button {
                showsKeyFlow = true
            } label: {
                Label(NSLocalizedString("Voting keys", comment: "Voting"), systemImage: "key")
            }
            // A vote reads the ticked nodes after its history read; a change
            // made meanwhile would slip into it.
            .disabled(store.isVoteBusy)
        }
    }

    // MARK: States

    /// The one lasting state, the first item under the search field: above
    /// the rows and above the empty, no-match and cannot-filter states, which
    /// stay. No close button; it goes when its state ends. While a list read
    /// runs, Try again takes no tap and dims.
    @ViewBuilder
    private var lastingMessage: some View {
        if let message = list.message {
            DashUIKit.SystemMessageView(
                title: message.title,
                subtitle: message.subtitle,
                buttonName: message.offersTryAgain ? NSLocalizedString("Try again", comment: "Voting") : nil,
                onAction: message.offersTryAgain ? { Task { await list.tryAgain() } } : nil)
                .disabled(list.isTryingAgain)
                .padding(.top, 12)
        }
    }

    /// Which nodes a tap votes with, when there is a choice to make: voting
    /// with several masternodes links them to each other publicly, so the
    /// current choice stays visible without opening the picker.
    @ViewBuilder
    private var votingWithRow: some View {
        if viewModel.votableNodes.count > 1 {
            Button { showsKeyFlow = true } label: {
                HStack(spacing: 8) {
                    Text(NSLocalizedString("Voting with", comment: "Voting"))
                        .dashFont(.footnote)
                        .foregroundStyle(Color.dash.tertiaryText)
                    Text(viewModel.votingWithSummary)
                        .dashFont(.footnoteMedium)
                        .foregroundStyle(Color.dash.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dash.tertiaryText)
                        .accessibilityHidden(true)
                }
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .disabled(store.isVoteBusy)
        }
    }

    private func retryLoad() {
        Task { await store.retry() }
    }

    @ViewBuilder
    private var contestList: some View {
        switch list.emptyState {
        case .loading:
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .couldNotLoad:
            // No list read has succeeded yet: say so, rather than that
            // nothing is being contested — that was never checked.
            VotingEmptyState(
                icon: "exclamationmark.triangle",
                title: NSLocalizedString("Couldn't load the contests", comment: "Voting"),
                message: NSLocalizedString("Pull down to try again.", comment: "Voting"),
                action: (
                    title: NSLocalizedString("Try again", comment: "Voting"),
                    perform: { retryLoad() }))
                .padding(.vertical, 40)
        case .cannotFilterByMyVotes(let reason):
            VotingEmptyState(
                icon: "exclamationmark.triangle",
                title: NSLocalizedString("Can't filter by your votes right now", comment: "Voting"),
                message: reason,
                action: (
                    title: NSLocalizedString("Reset filters", comment: "Voting"),
                    perform: { list.filter = .default }))
                .padding(.vertical, 40)
        case .filterMatchesNothing:
            VotingEmptyState(
                icon: "line.3.horizontal.decrease.circle",
                title: NSLocalizedString("No usernames match this filter", comment: "Voting"),
                message: NSLocalizedString("Change the filter or reset it to see every open contest.", comment: "Voting"),
                action: (
                    title: NSLocalizedString("Reset filters", comment: "Voting"),
                    perform: { list.filter = .default }))
                .padding(.vertical, 40)
        case .noContests:
            VotingEmptyState(
                icon: "checkmark.seal",
                title: NSLocalizedString("No open contests", comment: "Voting"),
                message: NSLocalizedString(
                    "No usernames are being contested right now. Contests open when two or more people request the same name.",
                    comment: "Voting"))
                .padding(.vertical, 40)
        case .searchMatchesNothing:
            VotingEmptyState(
                icon: "checkmark.seal",
                title: NSLocalizedString("No matching contests", comment: "Voting"),
                message: NSLocalizedString("No open contest matches that search.", comment: "Voting"))
                .padding(.vertical, 40)
        case nil:
            ForEach(list.sections) { section in
                Text(section.title)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                // Rows straight in the lazy stack, so only those on screen are built.
                ForEach(section.contests) { contest in
                    card(for: contest)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private func card(for contest: DPNSContest) -> some View {
        let label = contest.normalizedLabel
        return VotingContestCard(
            contest: contest,
            myChoices: store.myChoices(on: label),
            isCasting: store.isSending(normalizedLabel: label),
            sendingPill: list.sendingPill(on: label),
            canTapPill: { list.canTapPill($0, on: label) },
            onVote: { voteRequest = list.voteRequest(for: $0, on: contest) },
            onOpenRequest: { openedRequest = OpenedRequest(normalizedLabel: label, identityId: $0) },
            headerHint: list.headerAccessibilityHint(for: contest),
            expansion: list.isExpandable(contest) ? expansion(for: contest) : nil)
    }

    private func expansion(for contest: DPNSContest) -> VotingContestCard.Expansion {
        let label = contest.normalizedLabel
        let isExpanded = list.isExpanded(label)
        return VotingContestCard.Expansion(
            isExpanded: isExpanded,
            countText: list.requestCountText(for: contest),
            pillLabel: list.expandAccessibilityLabel(for: contest, isExpanded: isExpanded),
            pillValue: list.expandAccessibilityValue(for: contest),
            requests: list.requestRows(for: contest),
            // The card grows or shrinks while the requests fade, in one
            // transaction with the chevron and «You voted»; under Reduce
            // Motion the row opens and closes at once.
            onToggle: {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { list.toggleExpanded(label) }
            })
    }
}

// MARK: - ContestDeadlineLabel

/// Renders the real Platform deadline, or "Unknown" when the query did not
/// carry one. Never estimates: mainnet contests run 14 days and testnet ones
/// 90 minutes, so a guessed deadline would be wrong by weeks on testnet.
struct ContestDeadlineLabel: View {
    let endTime: Date?

    var body: some View {
        Group {
            if let endTime {
                if endTime <= Date() {
                    Text(NSLocalizedString("Closing", comment: "Voting"))
                        .foregroundColor(.orange)
                } else {
                    Text(endTime, style: .relative)
                        .foregroundColor(Color.dash.secondaryText)
                }
            } else {
                Text(NSLocalizedString("Deadline unknown", comment: "Voting"))
                    .foregroundColor(Color.dash.tertiaryText)
            }
        }
        .font(.caption)
        .monospacedDigit()
    }
}

// MARK: - Shared small views

struct VotingEmptyState: View {
    let icon: String
    let title: String
    let message: String
    /// A button under the message.
    var action: (title: String, perform: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Color.dash.tertiaryText)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption)
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
            if let action {
                DashUIKit.DashButton(
                    text: action.title,
                    size: .small,
                    style: .plainBlack,
                    action: action.perform)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

struct VotingBanner: View {
    enum Tone { case error, success, warning }

    let text: String
    let tone: Tone
    /// A button under the text, inside the banner.
    var action: (title: String, perform: () -> Void)? = nil
    /// Rounded corners, for a banner set in a list's margins rather than
    /// running edge to edge.
    var isRounded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let action {
                Button(action.title, action: action.perform)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .padding(.leading, 24)
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: isRounded ? 12 : 0, style: .continuous))
    }

    private var iconName: String {
        switch tone {
        case .error: return "exclamationmark.triangle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .error: return .red
        case .success: return .green
        case .warning: return .orange
        }
    }
}

// MARK: - UsernameVotingHostingController

/// Hosts Username Voting in the menu's UIKit stack, in its own
/// `NavigationStack`. While a vote runs the swipe-back is off, as the bar's
/// back button is (see ``UsernameVotingScreen``).
final class UsernameVotingHostingController: UIHostingController<AnyView> {
    private let store: VotingStore
    private var busy: AnyCancellable?

    init(onClose: @escaping () -> Void) {
        let viewModel = VotingViewModel()
        store = viewModel.store
        super.init(rootView: AnyView(NavigationStack {
            UsernameVotingScreen(onClose: onClose, viewModel: viewModel)
        }))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        busy = store.isVoteBusyPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isBusy in
                self?.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isBusy
            }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        busy = nil
        // The screen underneath gets its swipe-back as usual.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

// MARK: - Previews

#if DEBUG
// Shared by the voting screens' previews.
struct PreviewContests: VotingContestReading {
    let contests: [DPNSContest]
    var failure: Error?
    /// Answers the first load, then fails every later one.
    var failAfterFirstLoad = false
    private let loaded = PreviewLoadCounter()

    init(contests: [DPNSContest], failure: Error? = nil, failAfterFirstLoad: Bool = false) {
        self.contests = contests
        self.failure = failure
        self.failAfterFirstLoad = failAfterFirstLoad
    }

    func activeContests() async throws -> [DPNSContest] {
        if let failure { throw failure }
        if failAfterFirstLoad, loaded.next() > 1 { throw VotingPreviewError.unavailable }
        return contests
    }

    func voteState(normalizedLabel: String) async throws -> DPNSContestVoteState? { nil }
}

private final class PreviewLoadCounter {
    private var count = 0
    func next() -> Int { count += 1; return count }
}

struct PreviewNodes: VotableMasternodeResolving {
    var nodes: [VoterNode] = []
    var mayBeIncomplete = false

    func votableNodes() -> MasternodeVoterRegistry.Resolution {
        .init(nodes: nodes, mayBeIncomplete: mayBeIncomplete)
    }
}

struct PreviewCaster: VoteCasting {
    func cast(choice: VoteChoice, onNormalizedLabel normalizedLabel: String, with nodes: [VoterNode]) async throws
        -> VoteCastReport {
        throw VotingPreviewError.unavailable
    }
}

final class PreviewHistory: VoteHistoryDAO {
    /// `nil`: the history cannot be read.
    private let records: [CastVoteRecord]?

    init(records: [CastVoteRecord]? = []) {
        self.records = records
    }

    func record(_ record: CastVoteRecord, network: String) async throws {}
    func votes(forContest normalizedLabel: String, network: String) async -> [CastVoteRecord]? {
        records?.filter { $0.normalizedLabel == normalizedLabel }
    }
    func votes(forContests normalizedLabels: Set<String>, network: String) async -> [CastVoteRecord]? {
        records?.filter { normalizedLabels.contains($0.normalizedLabel) }
    }
    func deleteAll() {}
}

final class PreviewPrefs: VotingSelectionStoring {
    var votingNodeSelection: Set<Data>
    var isVotingSetUp: Bool

    init(selection: Set<Data> = [], isVotingSetUp: Bool = false) {
        votingNodeSelection = selection
        self.isVotingSetUp = isVotingSetUp
    }
}

private enum VotingPreviewError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Dash Platform is not connected yet." }
}

@MainActor
private func previewScreen(
    contests: [DPNSContest],
    nodes: [VoterNode] = [],
    mayBeIncomplete: Bool = false,
    failure: Error? = nil,
    failAfterFirstLoad: Bool = false,
    historyUnreadable: Bool = false,
    filterType: VotingTypeFilter = .all,
    toast: VotingToast? = nil
) -> some View {
    let store = VotingStore(
        contests: PreviewContests(contests: contests, failure: failure, failAfterFirstLoad: failAfterFirstLoad),
        nodes: PreviewNodes(nodes: nodes, mayBeIncomplete: mayBeIncomplete),
        caster: PreviewCaster(),
        history: PreviewHistory(records: historyUnreadable ? nil : []),
        prefs: PreviewPrefs())
    let viewModel = VotingViewModel(store: store)
    viewModel.list.filter.type = filterType
    if let toast { viewModel.list.showToast(toast) }
    return NavigationStack {
        UsernameVotingScreen(onClose: {}, viewModel: viewModel)
    }
    // A second load, queued behind the screen's own first one, which fails.
    .task { if failAfterFirstLoad { await store.refresh() } }
}

private let previewEnd = Date(timeIntervalSince1970: 1_800_000_000)

private let previewContests: [DPNSContest] = [
    DPNSContest(normalizedLabel: "johndoe", endTime: previewEnd, hasWinner: false,
                abstainVotes: 0, lockVotes: 2, contenders: []),
    DPNSContest(normalizedLabel: "a11ce", endTime: previewEnd.addingTimeInterval(3 * 86_400), hasWinner: false,
                abstainVotes: 1, lockVotes: 0, contenders: []),
    DPNSContest(normalizedLabel: "somelongusernamethatkeepsgoingandgoing", endTime: nil, hasWinner: false,
                abstainVotes: 0, lockVotes: 0, contenders: []),
]

private let previewNode = VoterNode(
    proTxHash: Data([1]), isEvonode: false, typeIndex: 1, serviceAddress: nil, keySource: .walletIndex(0))

#Preview("Loaded") {
    previewScreen(contests: previewContests, nodes: [previewNode])
}

#Preview("No open contests") {
    previewScreen(contests: [], nodes: [previewNode])
}

#Preview("Node list may be incomplete") {
    previewScreen(contests: previewContests, mayBeIncomplete: true)
}

#Preview("Load failed") {
    previewScreen(contests: [], failure: VotingPreviewError.unavailable)
}

#Preview("Refresh failed with rows") {
    previewScreen(contests: previewContests, nodes: [previewNode], failAfterFirstLoad: true)
}

#Preview("Vote history unreadable") {
    previewScreen(contests: previewContests, nodes: [previewNode], failAfterFirstLoad: true, historyUnreadable: true)
}

#Preview("Vote failed toast") {
    previewScreen(
        contests: previewContests, nodes: [previewNode],
        toast: .failed("Couldn't reach the network. Your vote was not cast."))
}

#Preview("Voted toast") {
    previewScreen(contests: previewContests, nodes: [previewNode], toast: .voted(username: "johndoe"))
}

#Preview("Filter matches nothing") {
    previewScreen(contests: previewContests, nodes: [previewNode], filterType: .approved)
}

#Preview("Can't filter by your votes") {
    previewScreen(contests: previewContests, filterType: .notVoted)
}
#endif
