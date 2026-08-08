//
//  CastVoteSheet.swift
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

// MARK: - CastVoteSheet

/// Confirms a vote: which nodes will cast it, how much weight that carries,
/// and what Platform's rules mean for changing it later.
struct CastVoteSheet: View {
    let contest: DPNSContest
    let choice: VoteChoice
    @ObservedObject var viewModel: VotingViewModel

    @Environment(\.dismiss)
    private var dismiss
    @State private var selectedNodeIDs: Set<Data> = []

    private var selectedNodes: [VoterNode] {
        candidateNodes.filter { selectedNodeIDs.contains($0.proTxHash) }
    }

    /// Only nodes that have not voted on this contest yet. A node with a vote
    /// on record is not offered again — Platform rejects a repeat of the same
    /// choice, and re-listing it would invite that error.
    private var candidateNodes: [VoterNode] {
        viewModel.nodesYetToVote(on: contest.normalizedLabel)
    }

    var body: some View {
        NavigationView {
            Group {
                if let report = viewModel.lastCastReport {
                    VoteResultView(report: report) {
                        viewModel.dismissCastResult()
                        dismiss()
                    }
                } else {
                    confirmForm
                }
            }
            .navigationTitle(NSLocalizedString("Cast vote", comment: "Voting"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) {
                        viewModel.dismissCastResult()
                        dismiss()
                    }
                    .disabled(viewModel.isCasting)
                }
            }
        }
        .onAppear {
            if selectedNodeIDs.isEmpty {
                // Honour the privacy mode: one node preselected by default,
                // all of them only when the user asked for that.
                selectedNodeIDs = Set(
                    viewModel.nodesForNextVote(on: contest.normalizedLabel).map(\.proTxHash))
            }
        }
    }

    private var confirmForm: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summaryTitle)
                        .font(.headline)
                    Text(summaryDetail)
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
                .padding(.vertical, 4)
            }

            if let castError = viewModel.castError {
                Section { VotingBanner(text: castError, tone: .error).listRowInsets(EdgeInsets()) }
            }

            Section {
                ForEach(candidateNodes) { node in
                    NodeSelectionRow(
                        node: node,
                        isSelected: selectedNodeIDs.contains(node.proTxHash),
                        toggle: { toggle(node) })
                }
            } header: {
                Text(NSLocalizedString("Vote with", comment: "Voting"))
            } footer: {
                if alreadyVoted > 0 {
                    Text(String(
                        format: NSLocalizedString(
                            "%d of your nodes already voted here and are not listed.",
                            comment: "Voting"),
                        alreadyVoted))
                } else if viewModel.selectedNodeIDs.count < viewModel.votableNodes.count,
                          viewModel.votableNodes.count > 1 {
                    Text(NSLocalizedString(
                        "Selecting fewer nodes reveals less about which masternodes you run.",
                        comment: "Voting"))
                }
            }

            Section {
                Text(NSLocalizedString(
                    "Each masternode has one live vote per contest. You can change it later, but Dash Platform allows only 5 votes in total per masternode per contest.",
                    comment: "Voting"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }

            Section {
                Button {
                    Task {
                        await viewModel.cast(choice: choice, on: contest, with: selectedNodes)
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isCasting {
                            SwiftUI.ProgressView()
                        } else {
                            Text(castButtonTitle).fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(selectedNodes.isEmpty || viewModel.isCasting)
            }
        }
    }

    private var alreadyVoted: Int {
        viewModel.votableNodes.count - candidateNodes.count
    }

    private func toggle(_ node: VoterNode) {
        if selectedNodeIDs.contains(node.proTxHash) {
            selectedNodeIDs.remove(node.proTxHash)
        } else {
            selectedNodeIDs.insert(node.proTxHash)
        }
    }

    private var summaryTitle: String {
        switch choice {
        case .towards:
            return String(
                format: NSLocalizedString("Award “%@” to this contender", comment: "Voting"),
                contest.normalizedLabel)
        case .lock:
            return String(
                format: NSLocalizedString("Lock “%@” so nobody gets it", comment: "Voting"),
                contest.normalizedLabel)
        case .abstain:
            return String(
                format: NSLocalizedString("Abstain on “%@”", comment: "Voting"),
                contest.normalizedLabel)
        }
    }

    private var summaryDetail: String {
        if case .towards(let identityId) = choice {
            return String(
                format: NSLocalizedString("Contender %@", comment: "Voting"),
                identityId)
        }
        return NSLocalizedString(
            "This still counts as your masternodes having voted in this contest.",
            comment: "Voting")
    }

    private var castButtonTitle: String {
        String(
            format: NSLocalizedString("Cast %u votes", comment: "Voting"),
            selectedNodes.totalVoteWeight)
    }
}

// MARK: - NodeSelectionRow

private struct NodeSelectionRow: View {
    let node: VoterNode
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : Color.dash.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(node.serviceAddress ?? node.shortProTxHash)
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }

                Spacer()

                Text(String(format: NSLocalizedString("%u votes", comment: "Voting"), node.voteWeight))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - VoteResultView

/// Reports exactly what landed. A run where some nodes succeeded and others
/// failed is shown as such — never rounded up to "done" or down to "failed".
private struct VoteResultView: View {
    let report: VoteCastReport
    let onDone: () -> Void

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: report.isCompleteSuccess
                          ? "checkmark.circle.fill"
                          : (report.succeeded.isEmpty ? "xmark.circle.fill" : "exclamationmark.circle.fill"))
                        .font(.system(size: 40))
                        .foregroundColor(report.isCompleteSuccess
                                         ? .green
                                         : (report.succeeded.isEmpty ? .red : .orange))
                    Text(headline)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if !report.succeeded.isEmpty {
                        Text(String(
                            format: NSLocalizedString("%u votes counted for “%@”", comment: "Voting"),
                            report.acceptedWeight, report.normalizedLabel))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            if !report.failed.isEmpty {
                Section(NSLocalizedString("Not cast", comment: "Voting")) {
                    ForEach(report.failed) { outcome in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.node.displayName)
                                .font(.subheadline)
                            Text(outcome.failure ?? "")
                                .font(.caption)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button(action: onDone) {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Done", comment: "")).fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
    }

    private var headline: String {
        if report.isCompleteSuccess {
            return NSLocalizedString("Vote cast", comment: "Voting")
        }
        if report.succeeded.isEmpty {
            return NSLocalizedString("No votes were cast", comment: "Voting")
        }
        return String(
            format: NSLocalizedString("%d of %d masternodes voted", comment: "Voting"),
            report.succeeded.count, report.outcomes.count)
    }
}
