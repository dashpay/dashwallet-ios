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

    private var canVote: Bool { viewModel.canVote && !isClosed }

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
                    Text(current.normalizedLabel)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(NSLocalizedString(
                        "Usernames are stored in a normalized form to prevent look-alike names, so this may differ from what each person typed.",
                        comment: "Voting"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                    HStack {
                        Text(NSLocalizedString("Voting ends", comment: "Voting"))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                        Spacer()
                        ContestDeadlineLabel(endTime: current.endTime)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(NSLocalizedString("Requesting this name", comment: "Voting")) {
                ForEach(current.contenders) { contender in
                    ContenderRow(
                        contender: contender,
                        isLeading: contender.id == current.leadingContender?.id
                            && current.lockVotes <= contender.voteTally,
                        canVote: canVote,
                        onVote: { pendingChoice = .towards(identityId: contender.identityId) })
                }
            }

            Section(NSLocalizedString("Other outcomes", comment: "Voting")) {
                VoteTallyRow(
                    title: NSLocalizedString("Lock the name", comment: "Voting"),
                    subtitle: NSLocalizedString("Nobody gets it", comment: "Voting"),
                    tally: current.lockVotes,
                    systemImage: "lock",
                    canVote: canVote,
                    onVote: { pendingChoice = .lock })
                VoteTallyRow(
                    title: NSLocalizedString("Abstain", comment: "Voting"),
                    subtitle: NSLocalizedString("Take no side", comment: "Voting"),
                    tally: current.abstainVotes,
                    systemImage: "minus.circle",
                    canVote: canVote,
                    onVote: { pendingChoice = .abstain })
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
        .navigationTitle(current.normalizedLabel)
        .navigationBarTitleDisplayMode(.inline)
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
    let isLeading: Bool
    let canVote: Bool
    let onVote: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortIdentity)
                    .font(.subheadline)
                    .monospaced()
                Text(String(format: NSLocalizedString("%u votes", comment: "Voting"),
                            contender.voteTally))
                    .font(.caption)
                    .foregroundColor(isLeading ? .green : Color.dash.secondaryText)
                    .fontWeight(isLeading ? .semibold : .regular)
            }

            Spacer()

            if canVote {
                Button(NSLocalizedString("Vote", comment: "Voting"), action: onVote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    /// Contenders are identified by identity id: Platform returns each
    /// requester's own spelling only inside a serialized document the app
    /// cannot decode, so showing a name here would mean inventing one.
    private var shortIdentity: String {
        guard contender.identityId.count > 16 else { return contender.identityId }
        return String(contender.identityId.prefix(8)) + "…" + String(contender.identityId.suffix(6))
    }
}

// MARK: - VoteTallyRow

private struct VoteTallyRow: View {
    let title: String
    let subtitle: String
    let tally: UInt32
    let systemImage: String
    let canVote: Bool
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
                Button(NSLocalizedString("Vote", comment: "Voting"), action: onVote)
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
