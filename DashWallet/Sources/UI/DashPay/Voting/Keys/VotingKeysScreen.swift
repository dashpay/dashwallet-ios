//
//  VotingKeysScreen.swift
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

// MARK: - VotingKeysFlow

/// The voting-key screens as one sheet: "Add your voting keys" and, over it,
/// the key input. When the wallet's sync is done and it has no node, the
/// flow opens on the key input; before the sync is done the list shows its
/// empty state, whose "Add masternode voting key" opens the input.
///
/// In vote mode a vote attempt opened it, and its Block or Approve button
/// keeps the ticks, sets voting up and goes back to that attempt, whose gates
/// run again from the top. In manage mode the list's menu opened it.
struct VotingKeysFlow: View {
    let mode: VotingKeysViewModel.Mode
    @ObservedObject var viewModel: VotingViewModel
    /// Closes the flow; `true` when the vote button was tapped.
    let onFinish: (_ continueToVote: Bool) -> Void

    /// Decided once, when the flow opens: state, so a re-render after a key
    /// change does not decide it again. Cleared when the list's "Add
    /// masternode voting key" is tapped.
    @State private var opensOnKeyInput: Bool
    @State private var isAddingKey: Bool
    /// Set when the last key entered added only some of its nodes; shown on
    /// the list until the next attempt.
    @State private var importNotice: String?

    init(
        mode: VotingKeysViewModel.Mode,
        viewModel: VotingViewModel,
        onFinish: @escaping (_ continueToVote: Bool) -> Void
    ) {
        self.mode = mode
        self.viewModel = viewModel
        self.onFinish = onFinish
        // With no masternode and no imported key there is nothing to tick:
        // the flow opens on "Enter voting key" (design 3830:20529).
        let opensOnKeyInput = viewModel.keysFlowOpensOnKeyInput
        _opensOnKeyInput = State(initialValue: opensOnKeyInput)
        _isAddingKey = State(initialValue: opensOnKeyInput)
    }

    var body: some View {
        NavigationStack {
            VotingKeysScreen(
                voting: viewModel,
                mode: mode,
                importNotice: importNotice,
                onAddKey: {
                    // The list has been shown: back from this key input
                    // returns to it, even when it is empty.
                    opensOnKeyInput = false
                    importNotice = nil
                    isAddingKey = true
                },
                onFinish: onFinish)
            .navigationDestination(isPresented: $isAddingKey) {
                VotingKeyInputScreen(
                    // Back from the first key leaves the flow, not an empty list.
                    onBack: {
                        if opensOnKeyInput, viewModel.votableNodes.isEmpty {
                            onFinish(false)
                        } else {
                            isAddingKey = false
                        }
                    },
                    onVerified: { notice in
                        importNotice = notice
                        viewModel.refreshVotableNodes()
                        isAddingKey = false
                    })
            }
        }
    }
}

// MARK: - VotingKeysScreen

/// "Add your voting keys" (SCR-04): the masternodes derived from this wallet
/// and the ones whose keys the user added, each with a tick-box. Keys the user
/// added can be removed in manage mode; keys the wallet derives cannot, so
/// those rows carry no remove control.
private struct VotingKeysScreen: View {
    @ObservedObject var voting: VotingViewModel
    @StateObject private var keys: VotingKeysViewModel
    /// Some nodes of the last key entered were not added.
    let importNotice: String?
    let onAddKey: () -> Void
    let onFinish: (_ continueToVote: Bool) -> Void

    @State private var nodePendingRemoval: VoterNode?
    @State private var removalError: String?

    init(
        voting: VotingViewModel,
        mode: VotingKeysViewModel.Mode,
        importNotice: String?,
        onAddKey: @escaping () -> Void,
        onFinish: @escaping (_ continueToVote: Bool) -> Void
    ) {
        self.voting = voting
        _keys = StateObject(wrappedValue: VotingKeysViewModel(mode: mode, source: voting.store))
        self.importNotice = importNotice
        self.onAddKey = onAddKey
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.back.button(action: { onFinish(false) }) })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.TopIntroView(
                        title: NSLocalizedString("Add your voting keys", comment: "Voting"),
                        mainDescription: NSLocalizedString(
                            "The IP address(es) below are associated with this wallet. Tick the ones that should vote.",
                            comment: "Voting"),
                        descriptionColor: Color.dash.secondaryText)

                    if let importNotice {
                        VotingBanner(text: importNotice, tone: .warning, isRounded: true)
                    }

                    if let removalError {
                        VotingBanner(text: removalError, tone: .error, isRounded: true)
                    }

                    if !keys.rows.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(keys.rows) { node in
                                nodeRow(node)
                            }
                        }
                        .modifier(DashUIKit.MenuViewModifier(shadowRadius: 20))
                    }

                    if keys.showsLinkingWarning {
                        VotingBanner(
                            text: NSLocalizedString(
                                "Voting with several masternodes at once publicly links them to each other.",
                                comment: "Voting"),
                            tone: .warning,
                            isRounded: true)
                    }

                    DashUIKit.DashButton(
                        text: NSLocalizedString("Add masternode voting key", comment: "Voting"),
                        leadingIcon: .system("plus"),
                        size: .medium,
                        style: .plainBlue,
                        action: onAddKey)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let choice = keys.voteChoice {
                voteButton(
                    title: choice == .lock
                        ? NSLocalizedString("Block", comment: "Voting")
                        : NSLocalizedString("Approve", comment: "Voting"),
                    style: choice == .lock ? .filledRed : .filledBlue)
            } else if keys.mode == .quickVoting {
                voteButton(title: NSLocalizedString("Vote for all", comment: "Voting"), style: .filledBlue)
            }
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .onChange(of: keys.rowsState) { keys.rowsChanged() }
        .confirmationDialog(
            NSLocalizedString("Remove voting key", comment: "Voting"),
            isPresented: Binding(
                get: { nodePendingRemoval != nil },
                set: { if !$0 { nodePendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: nodePendingRemoval
        ) { node in
            Button(NSLocalizedString("Remove", comment: ""), role: .destructive) {
                removalError = voting.removeImportedVotingKey(for: node)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: { _ in
            Text(NSLocalizedString(
                "This node will no longer vote from this wallet. You can add its voting key again at any time.",
                comment: "Voting"))
        }
    }

    /// Block in red or Approve in blue, matching the tapped pill, with the vote
    /// count under it; «Vote for all» in blue for Quick voting.
    private func voteButton(title: String, style: DashUIKit.DashButtonStyle) -> some View {
        VStack(spacing: 12) {
            DashUIKit.DashButton(
                text: title,
                isEnabled: keys.canConfirm,
                fillsWidth: true,
                size: .large,
                style: style,
                action: {
                    keys.confirm()
                    onFinish(true)
                })
            if let caption = keys.castCaption {
                Text(caption)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
            }
        }
        .padding(20)
    }

    private func nodeRow(_ node: VoterNode) -> some View {
        HStack(spacing: 0) {
            DashUIKit.RadioButtonRow(
                title: node.serviceAddress ?? node.shortProTxHash,
                subtitle: rowCaption(node),
                isSelected: keys.isTicked(node),
                style: .checkbox) { keys.toggle(node) }

            // Only a key the user added can be taken away, and only when
            // managing keys. A derived key is part of the wallet, and a remove
            // control that did nothing would lie.
            if !keys.hasVoteButton, node.keySource == .trackedVault {
                Button {
                    removalError = nil
                    nodePendingRemoval = node
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.dash.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Remove voting key", comment: "Voting"))
                .padding(.trailing, 6)
            }
        }
    }

    /// "Masternode 3 · Added by you" — which node, and where its key comes
    /// from, since that decides whether the row can be removed.
    private func rowCaption(_ node: VoterNode) -> String {
        let origin: String
        switch node.keySource {
        case .trackedVault:
            origin = NSLocalizedString("Added by you", comment: "Voting")
        case .walletIndex:
            origin = NSLocalizedString("From this wallet", comment: "Voting")
        }
        return "\(node.displayName) · \(origin)"
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func keysPreview(
    _ nodes: [VoterNode],
    mode: VotingKeysViewModel.Mode,
    selection: Set<Data> = []
) -> some View {
    let store = VotingStore(
        contests: PreviewContests(contests: []),
        nodes: PreviewNodes(nodes: nodes),
        caster: PreviewCaster(),
        history: PreviewHistory(),
        prefs: PreviewPrefs(selection: selection, isVotingSetUp: !selection.isEmpty))
    store.refreshVotableNodes()
    return VotingKeysFlow(
        mode: mode,
        viewModel: VotingViewModel(store: store),
        onFinish: { _ in })
}

private func keysPreviewNode(_ byte: UInt8, imported: Bool = false) -> VoterNode {
    VoterNode(
        proTxHash: Data([byte]), isEvonode: byte == 3, typeIndex: UInt32(byte),
        serviceAddress: "172.16.\(byte).10:9999",
        keySource: imported ? .trackedVault : .walletIndex(UInt32(byte)))
}

#Preview("Vote mode, block, one ticked") {
    keysPreview([keysPreviewNode(1), keysPreviewNode(2)], mode: .vote(.lock))
}

#Preview("Vote mode, approve, two ticked") {
    keysPreview(
        [keysPreviewNode(1), keysPreviewNode(2), keysPreviewNode(3, imported: true)],
        mode: .vote(.towards(identityId: "contender")),
        selection: [Data([1]), Data([2])])
}

#Preview("Manage mode, imported key") {
    keysPreview(
        [keysPreviewNode(1), keysPreviewNode(2, imported: true)],
        mode: .manage,
        selection: [Data([1])])
}

#Preview("Quick voting") {
    keysPreview([keysPreviewNode(1), keysPreviewNode(2)], mode: .quickVoting)
}

#Preview("No masternodes") {
    keysPreview([], mode: .vote(.lock))
}
#endif
