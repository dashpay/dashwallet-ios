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
    /// The UIKit stack this screen is pushed on; contest details are pushed
    /// onto it.
    let vc: UINavigationController
    /// Leaves the screen; the bar's back button calls it.
    let onClose: () -> Void

    @StateObject private var viewModel = VotingViewModel()
    @State private var showingNodePicker = false
    /// Where the voting-key flow opens, while it is shown.
    @State private var keyFlowStart: VotingKeysFlow.Start?

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    DashUIKit.NavigationBarElement.back.button(action: onClose)
                },
                central: {
                    Text(NSLocalizedString("Username voting", comment: "Voting"))
                        .dashFont(.subheadMedium)
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 60)
                },
                trailing: { trailingBarItem })

            DashUIKit.SearchBar(
                text: $viewModel.searchQuery,
                placeholder: NSLocalizedString("Search usernames", comment: "Voting"))
                .padding(.horizontal, 20)

            VoterCapacityHeader(
                nodes: viewModel.votableNodes,
                totalWeight: viewModel.totalVoteWeight,
                effectiveSelection: viewModel.effectiveSelectedNodeIDs,
                selectedNodeIDs: $viewModel.selectedNodeIDs,
                onEditSelection: { showingNodePicker = true },
                onAddKey: { keyFlowStart = .addKey },
                onShowKeys: { keyFlowStart = .keyList })

            if viewModel.nodeListMayBeIncomplete {
                VotingBanner(
                    text: NSLocalizedString(
                        "Some of your masternodes may be missing from this list — the wallet could not read your full voting-key pool. Finish syncing and reopen this screen.",
                        comment: "Voting"),
                    tone: .warning)
            }

            if let loadError = viewModel.loadError {
                VotingBanner(text: loadError, tone: .error)
            }

            contestList
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelecting {
                BulkSelectionBar(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingNodePicker) {
            VotingNodeSelectionSheet(
                nodes: viewModel.votableNodes,
                selectedNodeIDs: $viewModel.selectedNodeIDs)
                .presentationDragIndicator(.hidden)
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
    }

    /// "Done" ends selection mode; otherwise the sort / vote-on-several menu.
    @ViewBuilder
    private var trailingBarItem: some View {
        if viewModel.isSelecting {
            DashUIKit.DashButton(
                text: NSLocalizedString("Done", comment: ""),
                size: .small,
                style: .plainBlue) {
                    viewModel.endSelecting()
                }
        } else {
            DashUIKit.NavigationBarCircleMenu(
                .system("ellipsis"),
                accessibilityLabel: Text(NSLocalizedString("More", comment: "Voting"))
            ) {
                Picker(NSLocalizedString("Sort by", comment: "Voting"), selection: $viewModel.sort) {
                    ForEach(ContestSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                // Voting on many contests at once replaces the old
                // "Quick Voting" screen. Only offered when this wallet
                // can actually vote.
                if viewModel.canVote && !viewModel.visibleContests.isEmpty {
                    Divider()
                    Button {
                        viewModel.isSelecting = true
                    } label: {
                        Label(NSLocalizedString("Vote on several", comment: "Voting"),
                              systemImage: "checklist")
                    }
                }
            }
        }
    }

    private func showContest(_ contest: DPNSContest) {
        let screen = ContestDetailScreen(vc: vc, contest: contest, viewModel: viewModel)
        vc.pushViewController(UIHostingController(rootView: screen), animated: true)
    }

    @ViewBuilder
    private var contestList: some View {
        if !viewModel.hasLoadedOnce {
            Spacer()
            SwiftUI.ProgressView()
            Spacer()
        } else if viewModel.visibleContests.isEmpty {
            Spacer()
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
            Spacer()
        } else {
            List(viewModel.visibleContests) { contest in
                if viewModel.isSelecting {
                    let eligible = viewModel.isBulkEligible(contest)
                    Button {
                        viewModel.toggleSelection(contest)
                    } label: {
                        HStack(spacing: 10) {
                            // Contested names are shown but not selectable:
                            // hiding them would make the list silently differ
                            // from the browsing list, so say why instead.
                            Image(systemName: !eligible
                                  ? "minus.circle"
                                  : (viewModel.isSelected(contest)
                                     ? "checkmark.circle.fill" : "circle"))
                                .foregroundColor(!eligible
                                                 ? Color.dash.tertiaryText
                                                 : (viewModel.isSelected(contest)
                                                    ? .accentColor : Color.dash.tertiaryText))
                            VStack(alignment: .leading, spacing: 2) {
                                ContestRow(contest: contest)
                                if !eligible {
                                    Text(NSLocalizedString(
                                        "Several people requested this name — open it to choose between them.",
                                        comment: "Voting"))
                                        .font(.caption2)
                                        .foregroundColor(Color.dash.tertiaryText)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!eligible)
                } else {
                    Button {
                        showContest(contest)
                    } label: {
                        ListDisclosureRow {
                            ContestRow(contest: contest)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - VoterCapacityHeader

/// States plainly how much voting power this wallet actually has. When it has
/// none, it says so and offers to add a masternode voting key — it never
/// implies a check passed that did not.
private struct VoterCapacityHeader: View {
    let nodes: [VoterNode]
    let totalWeight: UInt32
    /// proTxHashes the next vote will use. Tapping the row edits it.
    /// The selection a vote will ACTUALLY use — the effective set, not the raw
    /// persisted one. They differ when the stored set is empty or stale, and
    /// describing the raw set would show "Select nodes" while a tap votes with
    /// the fallback node.
    let effectiveSelection: Set<Data>
    @Binding var selectedNodeIDs: Set<Data>
    /// Opens the node picker.
    let onEditSelection: () -> Void
    /// Opens the voting-key input — offered when there is no node.
    let onAddKey: () -> Void
    /// Opens the list of nodes this wallet votes with.
    let onShowKeys: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: nodes.isEmpty ? "person.crop.circle.badge.questionmark" : "server.rack")
                .foregroundColor(nodes.isEmpty ? Color.dash.secondaryText : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                if nodes.isEmpty {
                    Text(NSLocalizedString("Browsing only", comment: "Voting"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(NSLocalizedString(
                        "This wallet holds no active masternode voting keys, so it cannot vote.",
                        comment: "Voting"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                    // The only way to a voting key outside advanced mode, where
                    // Governance → Masternodes is not shown.
                    Button(NSLocalizedString("Add masternode voting key", comment: "Voting"), action: onAddKey)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                } else {
                    Text(nodeSummary)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(weightSummary)
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if !nodes.isEmpty {
                Button(action: onShowKeys) {
                    Label(NSLocalizedString("Voting keys", comment: "Voting"), systemImage: "key")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.secondaryBackground)

        // With more than one node the user needs to see WHICH nodes a tap
        // will vote with, because that choice links those masternodes to each
        // other publicly. With one node there is nothing to choose.
        if nodes.count > 1 {
            Button(action: onEditSelection) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Voting with", comment: "Voting"))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                        Text(selectionSummary)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color.dash.primaryText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dash.secondaryBackground)
        }
    }

    /// Names the nodes a vote will use, so the privacy consequence of the
    /// current selection is legible without opening the picker.
    private var selectionSummary: String {
        let chosen = nodes.filter { effectiveSelection.contains($0.proTxHash) }
        guard !chosen.isEmpty else {
            return NSLocalizedString("Select nodes", comment: "Voting")
        }
        if chosen.count == nodes.count {
            return String(format: NSLocalizedString(
                "All %d nodes", comment: "Voting"), chosen.count)
        }
        return chosen.map(\.displayName).joined(separator: ", ")
    }

    private var nodeSummary: String {
        let evonodes = nodes.filter(\.isEvonode).count
        let regularNodes = nodes.count - evonodes
        var parts: [String] = []
        if evonodes > 0 {
            parts.append(String(format: NSLocalizedString("%d evonodes", comment: "Voting"), evonodes))
        }
        if regularNodes > 0 {
            parts.append(String(format: NSLocalizedString("%d masternodes", comment: "Voting"), regularNodes))
        }
        return parts.joined(separator: ", ")
    }

    private var weightSummary: String {
        String(
            format: NSLocalizedString(
                "%u votes per contest — evonodes count as 4, masternodes as 1",
                comment: "Voting"),
            totalWeight)
    }
}

// MARK: - ContestRow

struct ContestRow: View {
    let contest: DPNSContest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(contest.displayTitle)
                        .font(.headline)
                    // Platform keys the contest by the homograph-normalized
                    // form; keep it visible so the name being voted on is
                    // never ambiguous, but behind the spelling people typed.
                    if contest.displayTitleDiffersFromNormalized {
                        Text(contest.normalizedLabel)
                            .font(.caption2)
                            .monospaced()
                            .foregroundColor(Color.dash.tertiaryText)
                    }
                }
                Spacer()
                ContestDeadlineLabel(endTime: contest.endTime)
            }

            HStack(spacing: 12) {
                Label(
                    String(format: NSLocalizedString("%d requests", comment: "Voting"),
                           contest.contenders.count),
                    systemImage: "person.2")
                if contest.lockVotes > 0 {
                    Label("\(contest.lockVotes)", systemImage: "lock")
                }
                if contest.abstainVotes > 0 {
                    Label("\(contest.abstainVotes)", systemImage: "minus.circle")
                }
                Spacer()
                Text(String(format: NSLocalizedString("%u votes", comment: "Voting"),
                            contest.totalVotes))
            }
            .font(.caption)
            .foregroundColor(Color.dash.secondaryText)
        }
        .padding(.vertical, 4)
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

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Color.dash.tertiaryText)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

struct VotingBanner: View {
    enum Tone { case error, success, warning }

    let text: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
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
