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

/// The voting-key screens as one sheet: the key input and the list of nodes
/// this wallet votes with.
///
/// Presented from the voting list's header and from a contest's Vote button
/// when the wallet has no node to vote with. Android threads the chosen vote
/// through these screens and casts it on Submit; here the vote goes back to
/// the contest instead, which opens its usual `CastVoteSheet` — so the PIN
/// prompt, the per-node report and the five-cast ceiling live in one place.
struct VotingKeysFlow: View {
    enum Start {
        /// Open on the key input — the wallet has no node yet.
        case addKey
        /// Open on the list — the wallet already votes with some node.
        case keyList
    }

    let start: Start
    /// Whether a Vote tap opened this flow. The list then offers to go on to
    /// that vote instead of just closing.
    let continuesToVote: Bool
    @ObservedObject var viewModel: VotingViewModel
    /// Closes the flow; `true` when the user chose to go on and cast the vote
    /// that opened it.
    let onFinish: (_ continueToVote: Bool) -> Void

    /// The list replaces the input as the root once a key is verified, rather
    /// than being pushed over it: going "back" to an emptied key field would be
    /// a step that leads nowhere.
    @State private var showsList: Bool
    @State private var isAddingKey = false

    init(
        start: Start,
        continuesToVote: Bool,
        viewModel: VotingViewModel,
        onFinish: @escaping (_ continueToVote: Bool) -> Void
    ) {
        self.start = start
        self.continuesToVote = continuesToVote
        self.viewModel = viewModel
        self.onFinish = onFinish
        _showsList = State(initialValue: start == .keyList)
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsList {
                    VotingKeysScreen(
                        viewModel: viewModel,
                        continuesToVote: continuesToVote,
                        onAddKey: { isAddingKey = true },
                        onFinish: onFinish)
                } else {
                    VotingKeyInputScreen(
                        leadingElement: .close,
                        onLeading: { onFinish(false) },
                        onVerified: {
                            viewModel.refreshVotableNodes()
                            withAnimation { showsList = true }
                        })
                }
            }
            .navigationDestination(isPresented: $isAddingKey) {
                VotingKeyInputScreen(
                    leadingElement: .back,
                    onLeading: { isAddingKey = false },
                    onVerified: {
                        viewModel.refreshVotableNodes()
                        isAddingKey = false
                    })
            }
        }
    }
}

/// So a host can present the flow with `.sheet(item:)`, keyed on where it opens.
extension VotingKeysFlow.Start: Identifiable {
    var id: Self { self }
}

// MARK: - VotingKeysScreen

/// The nodes this wallet votes with — the Android wallet's "Add your voting
/// keys". Keys the user added can be removed here; keys the wallet derives
/// cannot, so those rows carry no remove control.
///
/// Rows are ``VotingViewModel/votableNodes``: the same list a vote is cast
/// from, so this screen can never show a node the cast sheet would not offer.
private struct VotingKeysScreen: View {
    @ObservedObject var viewModel: VotingViewModel
    let continuesToVote: Bool
    let onAddKey: () -> Void
    let onFinish: (_ continueToVote: Bool) -> Void

    @State private var nodePendingRemoval: VoterNode?
    @State private var removalError: String?

    private enum Layout {
        static let cardSpacing: CGFloat = 2
        static let rowHPadding: CGFloat = 14
        static let rowVPadding: CGFloat = 12
        static let rowMinHeight: CGFloat = 56
    }

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.close.button(action: { onFinish(false) }) })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.TopIntroView(
                        title: NSLocalizedString("Voting keys", comment: "Voting"),
                        mainDescription: NSLocalizedString(
                            "The IP address(es) below are associated with this wallet",
                            comment: "Voting"))

                    if let removalError {
                        VotingBanner(text: removalError, tone: .error)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if viewModel.votableNodes.isEmpty {
                        Text(NSLocalizedString(
                            "This wallet holds no active masternode voting keys, so it cannot vote.",
                            comment: "Voting"))
                            .dashFont(.subhead)
                            .foregroundColor(Color.dash.secondaryText)
                    } else {
                        VStack(spacing: Layout.cardSpacing) {
                            ForEach(viewModel.votableNodes) { node in
                                nodeRow(node)
                            }
                        }
                        .modifier(DashUIKit.MenuViewModifier(shadowRadius: 20))
                    }

                    DashUIKit.DashButton(
                        text: NSLocalizedString("Add masternode voting key", comment: "Voting"),
                        leadingIcon: .system("plus"),
                        size: .medium,
                        style: .plainBlue,
                        action: onAddKey)

                    if let selectionNote {
                        Text(selectionNote)
                            .dashFont(.footnote)
                            .foregroundColor(Color.dash.secondaryText)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashUIKit.DashButton(
                text: continuesToVote
                    ? NSLocalizedString("Continue", comment: "")
                    : NSLocalizedString("Done", comment: ""),
                // Going on to a vote needs a node to cast it with; closing
                // does not.
                isEnabled: !continuesToVote || viewModel.canVote,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: { onFinish(continuesToVote && viewModel.canVote) })
                .padding(20)
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .confirmationDialog(
            NSLocalizedString("Remove voting key", comment: "Voting"),
            isPresented: Binding(
                get: { nodePendingRemoval != nil },
                set: { if !$0 { nodePendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: nodePendingRemoval
        ) { node in
            Button(NSLocalizedString("Remove", comment: ""), role: .destructive) {
                removalError = viewModel.removeImportedVotingKey(for: node)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: { _ in
            Text(NSLocalizedString(
                "This node will no longer vote from this wallet. You can add its voting key again at any time.",
                comment: "Voting"))
        }
    }

    private func nodeRow(_ node: VoterNode) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.serviceAddress ?? node.shortProTxHash)
                    .dashFont(.subheadMedium)
                    .foregroundColor(Color.dash.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rowCaption(node))
                    .dashFont(.footnote)
                    .foregroundColor(Color.dash.secondaryText)
            }

            Spacer(minLength: 0)

            // Only a key the user added can be taken away. A derived key is
            // part of the wallet, and a remove control that did nothing — or
            // that untracked a node the wallet votes with anyway — would lie.
            if node.keySource == .trackedVault {
                Button {
                    removalError = nil
                    nodePendingRemoval = node
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(Color.dash.secondaryText)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Remove voting key", comment: "Voting"))
            }
        }
        .padding(.horizontal, Layout.rowHPadding)
        .padding(.vertical, Layout.rowVPadding)
        .frame(minHeight: Layout.rowMinHeight)
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

    /// With several nodes, says how many a single vote actually uses.
    ///
    /// Android casts with every stored key; this wallet casts with the nodes
    /// chosen under "Voting with" (one by default, because voting together
    /// links masternodes publicly). Stating Android's "%d votes will be cast"
    /// here would contradict the cast sheet.
    private var selectionNote: String? {
        guard viewModel.votableNodes.count > 1 else { return nil }
        let chosen = viewModel.votableNodes.filter {
            viewModel.effectiveSelectedNodeIDs.contains($0.proTxHash)
        }
        return String(
            format: NSLocalizedString(
                "A vote is cast with %d of these nodes, worth %u votes. Choose which ones under “Voting with”.",
                comment: "Voting"),
            chosen.count, chosen.totalVoteWeight)
    }
}
