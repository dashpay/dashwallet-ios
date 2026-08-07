//
//  BulkVoteSheet.swift
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

// MARK: - BulkSelectionBar

/// Bottom bar shown while multi-select is active: how many contests are
/// picked, how much weight that carries, and the way into the bulk sheet.
struct BulkSelectionBar: View {
    @ObservedObject var viewModel: VotingViewModel
    @State private var showSheet = false

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: NSLocalizedString("%d selected", comment: "Voting"),
                                viewModel.selectedLabels.count))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if !viewModel.selectedLabels.isEmpty {
                        Text(String(
                            format: NSLocalizedString("%u votes in total", comment: "Voting"),
                            viewModel.bulkWeight(nodes: viewModel.votableNodes)))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                    }
                }

                Spacer()

                Button(NSLocalizedString("Select all", comment: "Voting")) {
                    viewModel.selectAllVisible()
                }
                .font(.subheadline)

                Button {
                    showSheet = true
                } label: {
                    Text(NSLocalizedString("Vote", comment: "Voting"))
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedLabels.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(.bar)
        .sheet(isPresented: $showSheet) {
            BulkVoteSheet(viewModel: viewModel) {
                showSheet = false
                viewModel.endSelecting()
            }
        }
    }
}

// MARK: - BulkVoteSheet

/// Applies one choice across every selected contest.
///
/// Only Abstain and Lock are offered. "Approve" names a specific contender, so
/// it cannot generalize across contests — and the legacy screen's "vote for
/// whoever submitted first" rule is not reproducible either: contender
/// submission time lives inside the serialized `domain` document, which the
/// FFI returns as opaque hex. Rather than guess an ordering, approving stays a
/// per-contest action on the detail screen.
struct BulkVoteSheet: View {
    @ObservedObject var viewModel: VotingViewModel
    let onFinished: () -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var choice: VoteChoice = .abstain
    @State private var selectedNodeIDs: Set<Data> = []

    private var selectedNodes: [VoterNode] {
        viewModel.votableNodes.filter { selectedNodeIDs.contains($0.proTxHash) }
    }

    var body: some View {
        NavigationView {
            Group {
                if let reports = viewModel.bulkReports {
                    BulkResultView(reports: reports) {
                        viewModel.dismissCastResult()
                        dismiss()
                        onFinished()
                    }
                } else {
                    form
                }
            }
            .navigationTitle(NSLocalizedString("Vote on several", comment: "Voting"))
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
                selectedNodeIDs = Set(viewModel.votableNodes.map(\.proTxHash))
            }
        }
    }

    private var form: some View {
        List {
            Section {
                Text(String(
                    format: NSLocalizedString(
                        "This applies one choice to all %d selected usernames.",
                        comment: "Voting"),
                    viewModel.selectedLabels.count))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }

            if let castError = viewModel.castError {
                Section { VotingBanner(text: castError, tone: .error).listRowInsets(EdgeInsets()) }
            }

            Section(NSLocalizedString("Choice", comment: "Voting")) {
                Picker(NSLocalizedString("Choice", comment: "Voting"), selection: $choice) {
                    Text(NSLocalizedString("Abstain", comment: "Voting")).tag(VoteChoice.abstain)
                    Text(NSLocalizedString("Lock", comment: "Voting")).tag(VoteChoice.lock)
                }
                .pickerStyle(.segmented)

                Text(choice == .abstain
                     ? NSLocalizedString("Records your masternodes as having voted, without taking a side.",
                                         comment: "Voting")
                     : NSLocalizedString("Votes that nobody should receive these usernames.",
                                         comment: "Voting"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }

            Section(NSLocalizedString("Vote with", comment: "Voting")) {
                ForEach(viewModel.votableNodes) { node in
                    Button {
                        if selectedNodeIDs.contains(node.proTxHash) {
                            selectedNodeIDs.remove(node.proTxHash)
                        } else {
                            selectedNodeIDs.insert(node.proTxHash)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedNodeIDs.contains(node.proTxHash)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedNodeIDs.contains(node.proTxHash)
                                                 ? .accentColor : Color.dash.tertiaryText)
                            Text(node.displayName)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(String(format: NSLocalizedString("%u votes", comment: "Voting"),
                                        node.voteWeight))
                                .font(.caption)
                                .foregroundColor(Color.dash.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button {
                    Task { await viewModel.castBulk(choice: choice, with: selectedNodes) }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isCasting {
                            SwiftUI.ProgressView()
                        } else {
                            Text(String(
                                format: NSLocalizedString("Vote on %d usernames", comment: "Voting"),
                                viewModel.selectedLabels.count))
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(selectedNodes.isEmpty || viewModel.isCasting)
            }
        }
    }
}

// MARK: - BulkResultView

/// Per-contest outcome of a bulk run. Contests are listed individually rather
/// than summarized, because a run can partly succeed in two directions at once
/// — some contests closed, some nodes rejected.
private struct BulkResultView: View {
    let reports: [VoteCastReport]
    let onDone: () -> Void

    private var fullySucceeded: [VoteCastReport] { reports.filter(\.isCompleteSuccess) }
    private var problematic: [VoteCastReport] { reports.filter { !$0.isCompleteSuccess } }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: problematic.isEmpty
                          ? "checkmark.circle.fill"
                          : (fullySucceeded.isEmpty ? "xmark.circle.fill" : "exclamationmark.circle.fill"))
                        .font(.system(size: 40))
                        .foregroundColor(problematic.isEmpty
                                         ? .green
                                         : (fullySucceeded.isEmpty ? .red : .orange))
                    Text(String(
                        format: NSLocalizedString("%d of %d usernames voted on", comment: "Voting"),
                        fullySucceeded.count, reports.count))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            if !problematic.isEmpty {
                Section(NSLocalizedString("Needs attention", comment: "Voting")) {
                    ForEach(problematic, id: \.normalizedLabel) { report in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.normalizedLabel)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            ForEach(report.failed) { outcome in
                                Text("\(outcome.node.displayName): \(outcome.failure ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
}
