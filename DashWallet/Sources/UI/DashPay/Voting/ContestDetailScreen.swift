//
//  ContestDetailScreen.swift
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

// MARK: - ContestDetailScreen

/// One contest: who is competing for the name, how the masternode vote stands,
/// and the controls to add this wallet's own votes.
struct ContestDetailScreen: View {
    let contest: DPNSContest
    @ObservedObject var viewModel: VotingViewModel

    /// A vote (or a key-only request) handed to ``View/voteFlow(_:viewModel:)``.
    @State private var voteRequest: VoteFlowRequest?

    private var current: DPNSContest { viewModel.latest(contest) }

    /// The contest resolved while this screen was open. The tallies below are
    /// the last ones read, and no further vote can be accepted.
    private var isClosed: Bool {
        viewModel.isClosed(normalizedLabel: contest.normalizedLabel)
    }

    /// The nodes one tap on `choice` would cast with — none when every selected
    /// node already holds it, or has spent its five casts.
    private func nodes(for choice: VoteChoice) -> [VoterNode] {
        viewModel.nodesForVote(choice, on: contest.normalizedLabel)
    }

    /// The wallet has no node to vote with, but the contest is open. The Vote
    /// buttons stay and a tap asks for a voting key first — as on Android.
    /// Hiding them left a masternode owner with a fresh wallet no way into the
    /// key flow from where they wanted to vote.
    private var needsVotingKey: Bool {
        !viewModel.canVote && !isClosed
    }

    private func canVote(_ choice: VoteChoice) -> Bool {
        viewModel.canStartVote(choice, on: contest.normalizedLabel)
    }

    /// A Vote tap: the cast sheet when a node can cast it, else the key flow,
    /// which comes back here with the same choice.
    private func vote(_ choice: VoteChoice) {
        voteRequest = VoteFlowRequest(contest: current, choice: choice)
    }

    /// What a tap on this choice will do, so the button says it rather than
    /// leaving the user to infer it.
    private func voteTitle(for choice: VoteChoice) -> String {
        guard !needsVotingKey else { return NSLocalizedString("Vote", comment: "Voting") }
        let pending = nodes(for: choice)
        if pending.count <= 1 { return NSLocalizedString("Vote", comment: "Voting") }
        return String.localizedStringWithFormat(NSLocalizedString("Vote ×%d", comment: "Voting"), pending.count)
    }

    /// Nodes of ours with a live vote here. Not the number of vote *records*:
    /// a node that changed its mind has two of those and is still one node,
    /// which used to render as "2 of 1 nodes voted".
    private var castCount: Int { viewModel.votedNodeCount(on: contest.normalizedLabel) }

    /// Gated on the loaded history, like the vote controls: before it arrives
    /// `nodesYetToVote` is empty because nothing is known, and the screen
    /// announced "all voted" over a green counter until the load finished.
    private var allNodesVoted: Bool {
        viewModel.canVote
            && viewModel.hasLoadedVoteHistory(for: contest.normalizedLabel)
            && viewModel.nodesYetToVote(on: contest.normalizedLabel).isEmpty
    }

    var body: some View {
        List {
            if isClosed {
                Section {
                    VotingBanner(
                        text: NSLocalizedString(
                            "Voting on this username has closed. The counts below are the last ones read.",
                            comment: "Voting"),
                        tone: .warning)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if current.displayTitleDiffersFromNormalized {
                        LabeledContent(
                            NSLocalizedString("Stored as", comment: "Voting")
                        ) {
                            Text(current.normalizedLabel).monospaced()
                        }
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                        Text(NSLocalizedString(
                            "Dash stores usernames in a look-alike-safe form, so the stored name can differ from what each person typed.",
                            comment: "Voting"))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                    }
                    HStack {
                        Text(NSLocalizedString("Voting ends", comment: "Voting"))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                        Spacer()
                        ContestDeadlineLabel(endTime: current.endTime)
                    }

                    if viewModel.canVote {
                        HStack {
                            Text(NSLocalizedString("Your votes", comment: "Voting"))
                                .font(.caption)
                                .foregroundColor(Color.dash.secondaryText)
                            Spacer()
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString("%d of %d nodes voted", comment: "Voting"),
                                castCount, viewModel.votableNodes.count))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(allNodesVoted ? .green : Color.dash.secondaryText)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section(NSLocalizedString("Requesting this name", comment: "Voting")) {
                ForEach(current.contenders) { contender in
                    ContenderRow(
                        contender: contender,
                        normalizedLabel: contest.normalizedLabel,
                        voting: viewModel,
                        // Nobody leads before the first vote: with every tally at
                        // zero the first row was highlighted as if it were ahead.
                        isLeading: contender.id == current.leadingContender?.id
                            && contender.voteTally > 0
                            && current.lockVotes <= contender.voteTally,
                        canVote: canVote(.towards(identityId: contender.identityId)),
                        voteTitle: voteTitle(for: .towards(identityId: contender.identityId)),
                        onVote: { vote(.towards(identityId: contender.identityId)) })
                }
            }

            Section(NSLocalizedString("Other outcomes", comment: "Voting")) {
                VoteTallyRow(
                    title: NSLocalizedString("Lock the name", comment: "Voting"),
                    subtitle: NSLocalizedString("Nobody gets it", comment: "Voting"),
                    tally: current.lockVotes,
                    systemImage: "lock",
                    canVote: canVote(.lock),
                    voteTitle: voteTitle(for: .lock),
                    onVote: { vote(.lock) })
                VoteTallyRow(
                    title: NSLocalizedString("Abstain", comment: "Voting"),
                    subtitle: NSLocalizedString("Take no side", comment: "Voting"),
                    tally: current.abstainVotes,
                    systemImage: "minus.circle",
                    canVote: canVote(.abstain),
                    voteTitle: voteTitle(for: .abstain),
                    onVote: { vote(.abstain) })
            }

            if allNodesVoted && !isClosed {
                Section {
                    Text(NSLocalizedString(
                        "All of your masternodes have voted on this username. To change a vote, vote again for the outcome you now prefer — the new vote replaces the old one.",
                        comment: "Voting"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }

            // Kept alongside the visible Vote buttons: without it, a tap that
            // asks for a masternode key reads as a bug to someone who holds none.
            if needsVotingKey {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString(
                            "Only masternodes and evonodes can vote on usernames. Add a masternode voting key to vote from this wallet.",
                            comment: "Voting"))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                        Button(NSLocalizedString("Add voting key", comment: "Voting")) {
                            voteRequest = VoteFlowRequest(contest: current, choice: nil)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationTitle(current.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadVotedNodes(for: contest.normalizedLabel) }
        .refreshable { await viewModel.refreshContest(normalizedLabel: contest.normalizedLabel) }
        .voteFlow($voteRequest, viewModel: viewModel)
        // A vote that landed on every node says so here too: the cast sheet
        // closes on success instead of showing its result.
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toast {
                toast.view
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toast?.id)
    }
}

// MARK: - ContenderRow

private struct ContenderRow: View {
    let contender: DPNSContender
    /// Passed through to the details screen, which shows the stored form and
    /// looks this contender's published link up by it.
    let normalizedLabel: String
    let voting: VotingViewModel
    let isLeading: Bool
    let canVote: Bool
    let voteTitle: String
    let onVote: () -> Void

    var body: some View {
        HStack {
            // The name opens this contender; the button votes. Two controls in
            // one row, so the link wraps only the text — wrapping the row would
            // swallow the button's tap.
            NavigationLink {
                RequestDetailsScreen(
                    voting: voting,
                    normalizedLabel: normalizedLabel,
                    identityId: contender.identityId)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contender.displayNameOrIdentity)
                            .font(.subheadline)
                            .monospaced(contender.displayLabel == nil)
                        Text(String.localizedStringWithFormat(NSLocalizedString("%u votes", comment: "Voting"),
                                    contender.voteTally))
                            .font(.caption)
                            .foregroundColor(isLeading ? .green : Color.dash.secondaryText)
                            .fontWeight(isLeading ? .semibold : .regular)
                    }
                    // No chevron of our own: the List already draws the
                    // disclosure for a NavigationLink row, and two read as a
                    // glitch.
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if canVote {
                Button(voteTitle, action: onVote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - VoteTallyRow

private struct VoteTallyRow: View {
    let title: String
    let subtitle: String
    let tally: UInt32
    let systemImage: String
    let canVote: Bool
    let voteTitle: String
    let onVote: () -> Void

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(Color.dash.secondaryText)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }

            Spacer()

            Text("\(tally)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(Color.dash.secondaryText)

            if canVote {
                Button(voteTitle, action: onVote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - VoteChoice + Identifiable

extension VoteChoice: Identifiable {
    var id: String {
        switch self {
        case .towards(let identityId): return "towards:\(identityId)"
        case .abstain: return "abstain"
        case .lock: return "lock"
        }
    }
}
