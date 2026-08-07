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

import SwiftDashSDK
import SwiftUI

// MARK: - UsernameVotingScreen

/// Menu → Voting. Lists every open DPNS username contest on the network and
/// lets masternodes and evonodes registered to this wallet vote on them.
///
/// Browsing needs no masternode. The voting controls are enabled only when the
/// wallet derives the voting key of at least one active registration.
struct UsernameVotingScreen: View {
    @StateObject private var viewModel = VotingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VoterCapacityHeader(
                nodes: viewModel.votableNodes,
                totalWeight: viewModel.totalVoteWeight)

            if let loadError = viewModel.loadError {
                VotingBanner(text: loadError, tone: .error)
            }

            contestList
        }
        .navigationTitle(NSLocalizedString("Username voting", comment: "Voting"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Search usernames", comment: "Voting"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isSelecting {
                    Button(NSLocalizedString("Done", comment: "")) { viewModel.endSelecting() }
                } else {
                    Menu {
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelecting {
                BulkSelectionBar(viewModel: viewModel)
            }
        }
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
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
                        "No open contest matches that search. Names are stored in a normalized form, so “alice” is listed as “a11ce”.",
                        comment: "Voting"))
            Spacer()
        } else {
            List(viewModel.visibleContests) { contest in
                if viewModel.isSelecting {
                    Button {
                        viewModel.toggleSelection(contest)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: viewModel.isSelected(contest)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(viewModel.isSelected(contest)
                                                 ? .accentColor : Color.dash.tertiaryText)
                            ContestRow(contest: contest)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        ContestDetailScreen(contest: contest, viewModel: viewModel)
                    } label: {
                        ContestRow(contest: contest)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - VoterCapacityHeader

/// States plainly how much voting power this wallet actually has. When it has
/// none, it says so and points at where masternodes would appear — it never
/// implies a check passed that did not.
private struct VoterCapacityHeader: View {
    let nodes: [VoterNode]
    let totalWeight: UInt32

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
                        "This wallet holds no active masternode voting keys, so it cannot vote. Registered nodes appear under Tools → Masternodes.",
                        comment: "Voting"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.secondaryBackground)
    }

    private var nodeSummary: String {
        let evonodes = nodes.filter(\.isEvonode).count
        let masternodes = nodes.count - evonodes
        var parts: [String] = []
        if evonodes > 0 {
            parts.append(String(format: NSLocalizedString("%d evonodes", comment: "Voting"), evonodes))
        }
        if masternodes > 0 {
            parts.append(String(format: NSLocalizedString("%d masternodes", comment: "Voting"), masternodes))
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
            HStack {
                Text(contest.normalizedLabel)
                    .font(.headline)
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
