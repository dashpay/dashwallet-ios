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

import DashUIKit
import SwiftDashSDK
import SwiftUI

// MARK: - UsernameVotingScreen

/// Menu → Voting. Lists every open DPNS username contest on the network and
/// lets masternodes and evonodes registered to this wallet vote on them.
///
/// Browsing needs no masternode. Voting needs the voting key of at least one
/// active masternode: derived by the wallet, or added through the voting-key
/// flow this screen's header opens.
struct UsernameVotingScreen: View {
    /// Pops the UIKit stack. The screen lives inside its own `NavigationStack`
    /// (see `MainMenuScreen.showVoting`), so the back button has to be wired
    /// explicitly — SwiftUI cannot see the UIKit stack underneath it.
    let onClose: () -> Void

    @StateObject private var viewModel = VotingViewModel()
    @State private var showingNodePicker = false
    @State private var showingFilters = false
    /// Where the voting-key flow opens, while it is shown.
    @State private var keyFlowStart: VotingKeysFlow.Start?
    /// A vote started from a pill, handed to ``View/voteFlow(_:viewModel:)``.
    @State private var voteRequest: VoteFlowRequest?
    /// The contest opened from a row.
    @State private var openedContest: OpenedContest?

    /// A contest pushed from the list, identified by its label so the
    /// destination keeps its snapshot while it pops.
    private struct OpenedContest: Hashable {
        let contest: DPNSContest
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.contest.normalizedLabel == rhs.contest.normalizedLabel }
        func hash(into hasher: inout Hasher) { hasher.combine(contest.normalizedLabel) }
    }

    private var screenTitle: String { NSLocalizedString("Username Voting", comment: "Voting") }

    var body: some View {
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
                    text: $viewModel.searchQuery,
                    placeholder: NSLocalizedString("Search by username", comment: "Voting"))
                    .padding(.top, 20)

                if hasBanners {
                    banners
                        .padding(.top, 12)
                }

                votingWithRow

                contestList
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.dash.primaryBackground)
        // The title lives in the scrolling intro, as designed; the bar keeps it
        // for VoiceOver's screen title and the long-press back menu only.
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(NSLocalizedString("Back", comment: ""))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                votingMenu
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DashUIKit.FilterBar(
                value: viewModel.filter.sort.title,
                title: NSLocalizedString("Filtered by", comment: "Voting"),
                filterAccessibilityLabel: NSLocalizedString("Filter", comment: "Voting"),
                replacement: viewModel.toast.map(\.view)) {
                showingFilters = true
            }
        }
        .sheet(isPresented: $showingFilters) {
            VotingFiltersSheet(filter: viewModel.filter) { viewModel.filter = $0 }
        }
        .navigationDestination(item: $openedContest) { opened in
            ContestDetailScreen(contest: opened.contest, viewModel: viewModel)
        }
        .voteFlow($voteRequest, viewModel: viewModel)
        .sheet(isPresented: $showingNodePicker) {
            VotingNodeSelectionSheet(
                nodes: viewModel.votableNodes,
                selectedNodeIDs: $viewModel.selectedNodeIDs)
        }
        .sheet(item: $keyFlowStart) { start in
            // Not opened from a vote, so the list's button only closes.
            VotingKeysFlow(
                start: start,
                continuesToVote: false,
                viewModel: viewModel,
                onFinish: { _ in keyFlowStart = nil })
        }
        .task { await viewModel.refreshIfNeeded() }
        .refreshable { await viewModel.refresh() }
        // "Voting ends today / in N days" is relative to today.
        // Midnight and time-zone changes, delivered on return if they happened
        // while the app was suspended.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            viewModel.recomputeVisible()
        }
        // The toast appears where VoiceOver is not looking; say it.
        .onChange(of: viewModel.toast?.id) {
            if let message = viewModel.toast?.message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 1) {
                // The filter's type and how many open contests it keeps,
                // whatever the search narrows the list to.
                Text(viewModel.filter.title)
                    .dashFont(.headline)
                    .foregroundStyle(Color.dash.primaryText)
                // No count while the type reads this wallet's votes and they
                // are not known for every contest: it would not be a count.
                if !viewModel.filter.type.readsMyVotes || viewModel.myVotesKnownForList {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("%d usernames", comment: "Voting"),
                        viewModel.filterMatchCount))
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

    /// Voting keys and the node choice, which the design has no place for
    /// yet. Labelled, so none of them hides behind a bare icon.
    private var votingMenu: some View {
        Menu {
            Button {
                keyFlowStart = viewModel.canVote ? .keyList : .addKey
            } label: {
                Label(NSLocalizedString("Voting keys", comment: "Voting"), systemImage: "key")
            }
            // With more than one node the user chooses WHICH nodes a tap votes
            // with: that choice links those masternodes to each other publicly.
            if viewModel.votableNodes.count > 1 {
                Button {
                    showingNodePicker = true
                } label: {
                    Label(NSLocalizedString("Voting nodes", comment: "Voting"), systemImage: "server.rack")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(NSLocalizedString("Voting options", comment: "Voting"))
    }

    // MARK: States

    /// No node to vote with, and the node list is complete — while it may be
    /// incomplete, its own banner says so instead of "no voting keys".
    private var showsBrowseOnly: Bool {
        viewModel.hasLoadedOnce && !viewModel.canVote && !viewModel.nodeListMayBeIncomplete
    }

    private var hasBanners: Bool {
        showsBrowseOnly || viewModel.nodeListMayBeIncomplete || viewModel.loadError != nil
            || viewModel.historyUnavailable
    }

    private var banners: some View {
        VStack(spacing: 8) {
            // A wallet without a voting key can still browse; a pill tap asks
            // for a key first. Say so up front, and offer the key here too —
            // there may be no pill to tap.
            if showsBrowseOnly {
                VotingBanner(
                    text: NSLocalizedString(
                        "This wallet holds no active masternode voting keys, so it cannot vote yet. Tap a vote to add a key.",
                        comment: "Voting"),
                    tone: .warning,
                    action: (NSLocalizedString("Add masternode voting key", comment: "Voting"), { keyFlowStart = .addKey }),
                    isRounded: true)
            }
            if viewModel.nodeListMayBeIncomplete {
                VotingBanner(
                    text: NSLocalizedString(
                        "Some of your masternodes may be missing from this list — the wallet could not read your full voting-key pool. Finish syncing and reopen this screen.",
                        comment: "Voting"),
                    tone: .warning,
                    isRounded: true)
            }
            if let loadError = viewModel.loadError {
                VotingBanner(text: loadError, tone: .error, isRounded: true)
            }
            // Without the history the list cannot tell which votes are cast,
            // so it holds the vote controls back; say why.
            if viewModel.historyUnavailable {
                VotingBanner(
                    text: NSLocalizedString(
                        "Couldn't read your vote history, so voting is paused. Pull down to try again.",
                        comment: "Voting"),
                    tone: .error,
                    isRounded: true)
            }
        }
    }

    /// Which nodes a tap votes with, when there is a choice to make: voting
    /// with several masternodes links them to each other publicly, so the
    /// current choice stays visible without opening the picker.
    @ViewBuilder
    private var votingWithRow: some View {
        if viewModel.votableNodes.count > 1 {
            Button { showingNodePicker = true } label: {
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
        }
    }

    @ViewBuilder
    private var contestList: some View {
        if !viewModel.hasLoadedOnce {
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if viewModel.visibleContests.isEmpty && viewModel.loadError != nil && viewModel.contests.isEmpty {
            // The load failed and nothing is cached: say so, rather than that
            // nothing is being contested — that was never checked.
            VotingEmptyState(
                icon: "exclamationmark.triangle",
                title: NSLocalizedString("Couldn't load the contests", comment: "Voting"),
                message: NSLocalizedString("Pull down to try again.", comment: "Voting"))
                .padding(.vertical, 40)
        } else if viewModel.visibleContests.isEmpty && !viewModel.contests.isEmpty
                    && viewModel.filter.type.readsMyVotes,
                  let reason = viewModel.myVotesUnavailableReason {
            // The type needs this wallet's votes, which cannot be told right
            // now. Not the filter's fault.
            VotingEmptyState(
                icon: "exclamationmark.triangle",
                title: NSLocalizedString("Can't filter by your votes right now", comment: "Voting"),
                message: reason,
                action: (
                    title: NSLocalizedString("Reset filters", comment: "Voting"),
                    perform: { viewModel.filter = .default }))
                .padding(.vertical, 40)
        } else if viewModel.visibleContests.isEmpty && !viewModel.contests.isEmpty
                    && viewModel.filter.type.readsMyVotes && !viewModel.myVotesKnownForList {
            // This wallet's history is still loading for some contests, so
            // neither the filter nor a search can say yet that nothing matches.
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if viewModel.visibleContests.isEmpty && !viewModel.contests.isEmpty
                    && viewModel.filterMatchCount == 0
                    && (!viewModel.filter.type.readsMyVotes || viewModel.myVotesKnownForList) {
            // Open contests exist and the filter alone hides them all; when it
            // is the search, the search's empty state below says so.
            VotingEmptyState(
                icon: "line.3.horizontal.decrease.circle",
                title: NSLocalizedString("No usernames match this filter", comment: "Voting"),
                message: NSLocalizedString("Change the filter or reset it to see every open contest.", comment: "Voting"),
                action: (
                    title: NSLocalizedString("Reset filters", comment: "Voting"),
                    perform: { viewModel.filter = .default }))
                .padding(.vertical, 40)
        } else if viewModel.visibleContests.isEmpty {
            VotingEmptyState(
                icon: "checkmark.seal",
                title: viewModel.searchQuery.isEmpty
                    ? NSLocalizedString("No open contests", comment: "Voting")
                    : NSLocalizedString("No matching contests", comment: "Voting"),
                message: viewModel.searchQuery.isEmpty
                    ? NSLocalizedString(
                        "No usernames are being contested right now. Contests open when two or more people request the same name.",
                        comment: "Voting")
                    : NSLocalizedString(
                        "No open contest matches that search.",
                        comment: "Voting"))
                .padding(.vertical, 40)
        } else {
            ForEach(viewModel.sections) { section in
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
            myChoices: viewModel.myChoices(on: label),
            isCasting: viewModel.castingLabels.contains(label),
            canStartVote: { viewModel.canStartVote($0, on: label) },
            onVote: { choice in voteRequest = VoteFlowRequest(contest: contest, choice: choice) },
            onOpen: { openedContest = OpenedContest(contest: contest) })
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
