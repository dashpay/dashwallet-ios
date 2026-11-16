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

import DashUIKit
import SwiftDashSDK
import SwiftUI

// MARK: - CastVoteSheet

/// Confirms a vote: which nodes will cast it, how much weight that carries,
/// and what Platform's rules mean for changing it later.
struct CastVoteSheet: View {
    let contest: DPNSContest
    let choice: VoteChoice
    /// Set when this abstain takes back a choice: only the nodes holding it
    /// are offered (AC-17).
    var cancelling: VoteChoice?
    @ObservedObject var viewModel: VotingViewModel

    @Environment(\.dismiss)
    private var dismiss
    @State private var selectedNodeIDs: Set<Data> = []
    /// What the sheet showed when Cast was tapped. A successful cast reloads
    /// the history while the sheet is still closing, and the live lists would
    /// then flash "already voted" with nothing left to cast.
    @State private var castSnapshot: VotingStore.CastCandidates?

    /// The nodes this choice can be cast with, and why ticked nodes are not
    /// among them. A node holding a different choice is offered: replacing its
    /// vote is a single state transition.
    private var candidates: VotingStore.CastCandidates {
        castSnapshot ?? viewModel.castCandidates(for: choice, cancelling: cancelling, on: contest.normalizedLabel)
    }

    private var candidateNodes: [VoterNode] { candidates.nodes }

    private var selectedNodes: [VoterNode] {
        candidateNodes.filter { selectedNodeIDs.contains($0.proTxHash) }
    }

    /// Nodes left out because they already hold this exact choice.
    private var holdingThisChoice: Int { candidates.holdingThisChoice }

    /// Nodes left out because they have no casts left on this contest.
    private var outOfCasts: Int { candidates.outOfCasts }

    var body: some View {
        DashUIKit.BottomSheet(
            title: NSLocalizedString("Cast vote", comment: "Voting"),
            showBackButton: .constant(false),
            // No swipe-down while a vote is being cast, same as the close button.
            isDismissalEnabled: .constant(!viewModel.isSending(normalizedLabel: contest.normalizedLabel)),
            isCloseButtonEnabled: !viewModel.isSending(normalizedLabel: contest.normalizedLabel),
            onClose: {
                viewModel.dismissCastResult()
                dismiss()
            },
            background: Color(UIColor.systemGroupedBackground)
        ) {
            if let report = viewModel.lastCastReport {
                VoteResultView(report: report) {
                    viewModel.dismissCastResult()
                    dismiss()
                }
            } else {
                confirmForm
            }
        }
        // Not swiped away mid-cast: the outcome belongs to this sheet, and the
        // next sheet would otherwise open into it.
        .interactiveDismissDisabled(viewModel.isSending(normalizedLabel: contest.normalizedLabel))
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
                if holdingThisChoice > 0 || outOfCasts > 0 {
                    // Both reasons when both apply: a node already voting this
                    // way and a node with no casts left are different answers,
                    // and showing one hides the other.
                    VStack(alignment: .leading, spacing: 2) {
                        if holdingThisChoice > 0 {
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "%d of your nodes already voted this way and are not listed. Any node voting differently is listed — its vote will be replaced.",
                                    comment: "Voting"),
                                holdingThisChoice))
                        }
                        if outOfCasts > 0 {
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "%d of your nodes have used all 5 votes Dash Platform allows on one contest.",
                                    comment: "Voting"),
                                outOfCasts))
                        }
                    }
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
                    castSnapshot = candidates
                    Task {
                        // Every node's vote landed: the screen behind says so in
                        // a toast. A partial or failed cast stays here, where the
                        // per-node outcomes can be read.
                        if await viewModel.cast(choice: choice, on: contest, with: selectedNodes) {
                            dismiss()
                        } else {
                            castSnapshot = nil
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSending(normalizedLabel: contest.normalizedLabel) {
                            SwiftUI.ProgressView()
                        } else {
                            Text(castButtonTitle).fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(selectedNodes.isEmpty || viewModel.isSending(normalizedLabel: contest.normalizedLabel))
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
        String.localizedStringWithFormat(
            NSLocalizedString("Cast %u votes", comment: "Voting"),
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

                Text(String.localizedStringWithFormat(NSLocalizedString("%u votes", comment: "Voting"), node.voteWeight))
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
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("%u votes counted for “%@”", comment: "Voting"),
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
        return String.localizedStringWithFormat(
            NSLocalizedString("%d of %d masternodes voted", comment: "Voting"),
            report.succeeded.count, report.outcomes.count)
    }
}

// MARK: - Previews

#if DEBUG
/// Shows the sheet once the store has loaded the contest's history, as the
/// vote flow does.
private struct CastVoteSheetPreview: View {
    let contest: DPNSContest
    let choice: VoteChoice
    var cancelling: VoteChoice?
    let viewModel: VotingViewModel
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded {
                CastVoteSheet(contest: contest, choice: choice, cancelling: cancelling, viewModel: viewModel)
            } else {
                SwiftUI.ProgressView()
            }
        }
        .task {
            await viewModel.store.refresh()
            loaded = true
        }
    }
}

private let castPreviewEnd = Date(timeIntervalSince1970: 1_800_000_000)
private let castPreviewCastAt = Date(timeIntervalSince1970: 1_799_000_000)

private func castPreviewNode(_ byte: UInt8, address: String) -> VoterNode {
    VoterNode(proTxHash: Data([byte]), isEvonode: byte == 3, typeIndex: UInt32(byte),
              serviceAddress: address, keySource: .walletIndex(UInt32(byte)))
}

private let castPreviewNodes = [
    castPreviewNode(1, address: "203.0.113.10:9999"),
    castPreviewNode(2, address: "203.0.113.11:9999"),
    castPreviewNode(3, address: "203.0.113.12:9999"),
]

private func castPreviewContest(_ label: String) -> DPNSContest {
    DPNSContest(
        normalizedLabel: label, endTime: castPreviewEnd, hasWinner: false, abstainVotes: 0, lockVotes: 2,
        contenders: [DPNSContender(identityId: "8Xq3Yz1mWd4k9PnVtR2sLbHc7JfEuAo5GiQwKx6TyMnZ", voteTally: 4,
                                   displayLabel: label)])
}

private func castPreviewRecord(
    _ node: VoterNode, _ label: String, _ choice: VoteChoice, casts: Int = 1
) -> CastVoteRecord {
    CastVoteRecord(proTxHash: node.proTxHash, normalizedLabel: label, choice: choice,
                   castAt: castPreviewCastAt, castCount: casts)
}

/// Holds no keys and touches no keychain.
private struct CastPreviewVault: TrackedMasternodeKeyVaulting {
    func key(for proTxHash: Data, role: MasternodeKeyRole) -> String? { nil }
    func store(_ keyText: String, for proTxHash: Data, role: MasternodeKeyRole) -> Bool { false }
    func removeKey(for proTxHash: Data, role: MasternodeKeyRole) -> Bool { false }
    func attachedRoles(for proTxHash: Data) -> Set<MasternodeKeyRole> { [] }
    func keyPresence(for proTxHash: Data, role: MasternodeKeyRole) -> TrackedMasternodeKeyPresence { .absent }
    func removeAllKeys(for proTxHash: Data) {}
}

@MainActor
private func castPreview(
    _ contest: DPNSContest,
    choice: VoteChoice,
    cancelling: VoteChoice? = nil,
    records: [CastVoteRecord] = [],
    castError: String? = nil,
    report: VoteCastReport? = nil
) -> some View {
    let store = VotingStore(
        contests: PreviewContests(contests: [contest]),
        nodes: PreviewNodes(nodes: castPreviewNodes),
        caster: PreviewCaster(),
        history: PreviewHistory(records: records),
        prefs: PreviewPrefs(selection: Set(castPreviewNodes.map(\.proTxHash))))
    let viewModel = VotingViewModel(vault: CastPreviewVault(), tracker: { nil }, store: store)
    viewModel.castError = castError
    viewModel.lastCastReport = report
    return CastVoteSheetPreview(contest: contest, choice: choice, cancelling: cancelling, viewModel: viewModel)
}

private let castPreviewApprove = VoteChoice.towards(identityId: "8Xq3Yz1mWd4k9PnVtR2sLbHc7JfEuAo5GiQwKx6TyMnZ")

#Preview("Vote") {
    castPreview(castPreviewContest("johndoe"), choice: castPreviewApprove)
}

#Preview("Block, one node already blocks") {
    castPreview(castPreviewContest("johndoe"), choice: .lock,
                records: [castPreviewRecord(castPreviewNodes[0], "johndoe", .lock)])
}

#Preview("Some nodes out of casts") {
    castPreview(castPreviewContest("johndoe"), choice: castPreviewApprove, records: [
        castPreviewRecord(castPreviewNodes[0], "johndoe", .lock, casts: VoteLimit.maxCastsPerNode),
        castPreviewRecord(castPreviewNodes[1], "johndoe", castPreviewApprove),
    ])
}

#Preview("Cancel approval") {
    castPreview(castPreviewContest("johndoe"), choice: .abstain, cancelling: castPreviewApprove, records: [
        castPreviewRecord(castPreviewNodes[0], "johndoe", castPreviewApprove),
        castPreviewRecord(castPreviewNodes[1], "johndoe", .lock),
        castPreviewRecord(castPreviewNodes[2], "johndoe", castPreviewApprove, casts: VoteLimit.maxCastsPerNode),
    ])
}

#Preview("Error") {
    castPreview(castPreviewContest("johndoe"), choice: castPreviewApprove,
                castError: "Authentication cancelled. Your vote was not cast.")
}

#Preview("Result (mixed)") {
    castPreview(castPreviewContest("johndoe"), choice: castPreviewApprove, report: VoteCastReport(
        normalizedLabel: "johndoe", choice: castPreviewApprove, outcomes: [
            VoteOutcome(node: castPreviewNodes[0], failure: nil),
            VoteOutcome(node: castPreviewNodes[1], failure: nil),
            VoteOutcome(node: castPreviewNodes[2], failure: "No votes left"),
        ]))
}

#Preview("No node can cast this") {
    castPreview(castPreviewContest("johndoe"), choice: .lock,
                records: castPreviewNodes.map { castPreviewRecord($0, "johndoe", .lock) })
}

#Preview("Long name") {
    castPreview(castPreviewContest("somelongusernamethatkeepsgoingandgoingandgoing"), choice: .lock)
}
#endif
