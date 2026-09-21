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

    /// The choice the user tapped, held until they confirm in the sheet.
    @State private var pendingChoice: VoteChoice?

    private var current: DPNSContest {
        viewModel.contests.first { $0.normalizedLabel == contest.normalizedLabel } ?? contest
    }

    /// The contest resolved while this screen was open. The tallies below are
    /// the last ones read, and no further vote can be accepted.
    private var isClosed: Bool {
        viewModel.isClosed(normalizedLabel: contest.normalizedLabel)
    }

    /// Whether this screen may offer votes at all. Deliberately NOT gated on
    /// "every node has already voted": Platform replaces a vote with one state
    /// transition (five per node per contest), so a node that already voted can
    /// still change its mind — which is what the hint at the bottom of this
    /// screen has always told the user to do. Whether a *particular* choice is
    /// castable is decided per row by `nodes(for:)`.
    private var canVote: Bool {
        viewModel.canVote && !isClosed && viewModel.hasLoadedVoteHistory(for: contest.normalizedLabel)
    }

    /// The nodes one tap on `choice` would cast with — none when every selected
    /// node already holds it, or has spent its five casts.
    private func nodes(for choice: VoteChoice) -> [VoterNode] {
        viewModel.nodesForVote(choice, on: contest.normalizedLabel)
    }

    private func canVote(_ choice: VoteChoice) -> Bool {
        canVote && !nodes(for: choice).isEmpty
    }

    /// What a tap on this choice will do, so the button says it rather than
    /// leaving the user to infer it.
    private func voteTitle(for choice: VoteChoice) -> String {
        let pending = nodes(for: choice)
        if pending.count <= 1 { return NSLocalizedString("Vote", comment: "Voting") }
        return String(format: NSLocalizedString("Vote ×%d", comment: "Voting"), pending.count)
    }

    /// How many of this wallet's nodes have voted here.
    /// Nodes of ours with a live vote here. Not the number of vote *records*:
    /// a node that changed its mind has two of those and is still one node,
    /// which used to render as "2 of 1 nodes voted".
    private var castCount: Int { viewModel.votedNodeCount(on: contest.normalizedLabel) }

    private var allNodesVoted: Bool {
        viewModel.canVote && viewModel.nodesYetToVote(on: contest.normalizedLabel).isEmpty
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
                            Text(String(
                                format: NSLocalizedString("%d of %d nodes voted", comment: "Voting"),
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
                        votingEndsAt: current.endTime,
                        isLeading: contender.id == current.leadingContender?.id
                            && current.lockVotes <= contender.voteTally,
                        canVote: canVote(.towards(identityId: contender.identityId)),
                        voteTitle: voteTitle(for: .towards(identityId: contender.identityId)),
                        onVote: { pendingChoice = .towards(identityId: contender.identityId) })
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
                    onVote: { pendingChoice = .lock })
                VoteTallyRow(
                    title: NSLocalizedString("Abstain", comment: "Voting"),
                    subtitle: NSLocalizedString("Take no side", comment: "Voting"),
                    tally: current.abstainVotes,
                    systemImage: "minus.circle",
                    canVote: canVote(.abstain),
                    voteTitle: voteTitle(for: .abstain),
                    onVote: { pendingChoice = .abstain })
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

            if !viewModel.canVote && !isClosed {
                Section {
                    Text(NSLocalizedString(
                        "Only masternodes and evonodes can vote on usernames. This wallet holds no active masternode voting keys.",
                        comment: "Voting"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
        }
        .navigationTitle(current.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadVotedNodes(for: contest.normalizedLabel) }
        .refreshable { await viewModel.refreshContest(normalizedLabel: contest.normalizedLabel) }
        .sheet(item: $pendingChoice) { choice in
            CastVoteSheet(
                contest: current,
                choice: choice,
                viewModel: viewModel)
        }
    }
}

// MARK: - ContenderRow

private struct ContenderRow: View {
    let contender: DPNSContender
    /// Passed through to the details screen, which shows the stored form and
    /// looks this contender's published link up by it.
    let normalizedLabel: String
    let votingEndsAt: Date?
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
                ContenderDetailScreen(
                    contender: contender,
                    normalizedLabel: normalizedLabel,
                    votingEndsAt: votingEndsAt,
                    canVote: canVote,
                    voteTitle: voteTitle,
                    onVote: onVote)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contender.displayNameOrIdentity)
                            .font(.subheadline)
                            .monospaced(contender.displayLabel == nil)
                        Text(String(format: NSLocalizedString("%u votes", comment: "Voting"),
                                    contender.voteTally))
                            .font(.caption)
                            .foregroundColor(isLeading ? .green : Color.dash.secondaryText)
                            .fontWeight(isLeading ? .semibold : .regular)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Color.dash.secondaryText)
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

// MARK: - ContenderDetailScreen

/// One contender, in the same four fields — and the same shape — as the
/// requester's own "Request details": the name as this person typed it, the
/// proof of identity they published, who they are on Platform, and when the
/// result is due. The vote control comes along so the decision can be made
/// where the evidence is.
private struct ContenderDetailScreen: View {
    let contender: DPNSContender
    let normalizedLabel: String
    let votingEndsAt: Date?
    let canVote: Bool
    let voteTitle: String
    let onVote: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// nil while the lookup runs, `.some(nil)` once it has answered with
    /// nothing — "checking" and "none published" are different answers.
    @State private var link: URL??

    private enum Layout {
        static let cardSpacing: CGFloat = 2
        static let rowHPadding: CGFloat = 14
        static let rowVPadding: CGFloat = 12
        static let labelSpacing: CGFloat = 20
        static let rowMinHeight: CGFloat = 46
    }

    private var requestedLabel: String {
        contender.displayLabel ?? normalizedLabel
    }

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.back.button(action: { dismiss() }) })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.TopIntroView(
                        title: NSLocalizedString("Contender details", comment: "Voting"),
                        mainDescription: NSLocalizedString(
                            "What this person published to show the name is theirs. None of it is verified by the network — it is what you are voting on.",
                            comment: "Voting"))
                        .padding(.horizontal, 20)

                    VStack(spacing: Layout.cardSpacing) {
                        detailRow(NSLocalizedString("Username", comment: "Voting")) {
                            Text(requestedLabel)
                        }
                        detailRow(NSLocalizedString("Link", comment: "Voting")) {
                            linkValue
                        }
                        detailRow(NSLocalizedString("Identity", comment: "Voting")) {
                            Text(contender.identityId)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        detailRow(NSLocalizedString("Results", comment: "Voting")) {
                            Text(votingEndsAt.map { DWDateFormatter.sharedInstance.dateAndTime(from: $0) }
                                ?? NSLocalizedString("Unknown", comment: "Voting"))
                        }
                    }
                    .modifier(DashUIKit.MenuViewModifier(shadowRadius: 20))
                    .padding(.horizontal, 20)

                    if canVote {
                        DashUIKit.DashButton(
                            text: voteTitle,
                            fillsWidth: true,
                            size: .large,
                            style: .filledBlue,
                            action: {
                                // The cast sheet belongs to the screen behind
                                // this one; step back rather than stack a
                                // second presentation on top of it.
                                dismiss()
                                onVote()
                            })
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .task {
            guard link == nil else { return }
            link = .some((try? await IdentityVerifyService.shared.publishedURL(
                forLabel: normalizedLabel, ownedBy: contender.identityId)) ?? nil)
        }
    }

    @ViewBuilder
    private var linkValue: some View {
        switch link {
        case .none:
            HStack(spacing: 6) {
                SwiftUI.ProgressView()
                Text(NSLocalizedString("Checking…", comment: "Voting"))
            }
            .foregroundColor(Color.dash.secondaryText)
        case .some(.none):
            Text(NSLocalizedString("None", comment: "Voting"))
                .foregroundColor(Color.dash.secondaryText)
        case .some(.some(let url)):
            Link(destination: url) {
                HStack(spacing: 6) {
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.right.square")
                }
                .foregroundStyle(Color.dash.blue)
            }
        }
    }

    private func detailRow<Value: View>(
        _ label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .top, spacing: Layout.labelSpacing) {
            Text(label)
                .dashFont(.subheadMedium)
                .foregroundColor(Color.dash.tertiaryText)
                .fixedSize()

            value()
                .dashFont(.subhead)
                .foregroundColor(Color.dash.primaryText)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Layout.rowHPadding)
        .padding(.vertical, Layout.rowVPadding)
        .frame(minHeight: Layout.rowMinHeight)
    }
}
