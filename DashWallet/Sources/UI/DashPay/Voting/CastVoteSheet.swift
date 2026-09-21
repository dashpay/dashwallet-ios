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

    /// The nodes this choice can be cast with: everything except nodes that
    /// already hold *this* choice — Platform rejects a repeat of the same vote
    /// — and nodes that have spent the five casts it allows per contest.
    ///
    /// A node holding a different choice belongs here. Replacing its vote is a
    /// single state transition, and excluding it was what made changing your
    /// mind impossible from this sheet.
    private var candidateNodes: [VoterNode] {
        viewModel.nodesForVote(choice, on: contest.normalizedLabel)
    }

    /// Nodes left out because they already hold this exact choice.
    private var holdingThisChoice: Int {
        viewModel.votableNodes.filter {
            viewModel.liveChoice(of: $0, on: contest.normalizedLabel) == choice
        }.count
    }

    /// Nodes left out because they have no casts left on this contest.
    private var outOfCasts: Int {
        max(0, viewModel.votableNodes.count - candidateNodes.count - holdingThisChoice)
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
                // Same set the sheet lists — nodes that can cast THIS choice,
                // including ones whose current vote it would replace.
                selectedNodeIDs = Set(candidateNodes.map(\.proTxHash))
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
                if holdingThisChoice > 0 {
                    Text(String(
                        format: NSLocalizedString(
                            "%d of your nodes already voted this way and are not listed. Any node voting differently is listed — its vote will be replaced.",
                            comment: "Voting"),
                        holdingThisChoice))
                } else if outOfCasts > 0 {
                    Text(String(
                        format: NSLocalizedString(
                            "%d of your nodes have used all 5 votes Dash Platform allows on one contest.",
                            comment: "Voting"),
                        outOfCasts))
                } else if selectedNodeIDs.count < candidateNodes.count, candidateNodes.count > 1 {
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


    private func toggle(_ node: VoterNode) {
        if selectedNodeIDs.contains(node.proTxHash) {
            selectedNodeIDs.remove(node.proTxHash)
        } else {
            selectedNodeIDs.insert(node.proTxHash)
        }
    }

    /// The spelling a human recognizes. Platform indexes `10stest`; the person
    /// asked for `iostest`, and that is what the rest of this flow shows —
    /// naming the stored form here made the two screens look like two names.
    private var displayLabel: String {
        if case .towards(let identityId) = choice,
           let contender = contest.contenders.first(where: { $0.identityId == identityId }),
           let label = contender.displayLabel {
            return label
        }
        return contest.contenders.compactMap(\.displayLabel).first ?? contest.normalizedLabel
    }

    private var summaryTitle: String {
        switch choice {
        case .towards:
            return String(
                format: NSLocalizedString("Award “%@” to this contender", comment: "Voting"),
                displayLabel)
        case .lock:
            return String(
                format: NSLocalizedString("Lock “%@” so nobody gets it", comment: "Voting"),
                displayLabel)
        case .abstain:
            return String(
                format: NSLocalizedString("Abstain on “%@”", comment: "Voting"),
                displayLabel)
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
