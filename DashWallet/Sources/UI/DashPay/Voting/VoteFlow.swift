//
//  VoteFlow.swift
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

// MARK: - VoteFlowRequest

/// A vote the user asked for from a screen: which contest and which choice.
/// `choice` is `nil` when the user only asked to add a voting key.
struct VoteFlowRequest: Identifiable {
    let id = UUID()
    let contest: DPNSContest
    let choice: VoteChoice?
}

extension View {
    /// Runs a vote the user asked for: the cast sheet when this wallet has a
    /// node to vote with, otherwise the voting-key flow first, which comes back
    /// to the cast sheet with the same choice. Shared by the voting list and the
    /// contest screen so both take the same path to a cast.
    func voteFlow(_ request: Binding<VoteFlowRequest?>, viewModel: VotingViewModel) -> some View {
        modifier(VoteFlowModifier(request: request, viewModel: viewModel))
    }
}

// MARK: - VoteFlowModifier

private struct VoteFlowModifier: ViewModifier {
    @Binding var request: VoteFlowRequest?
    @ObservedObject var viewModel: VotingViewModel

    /// The vote waiting for confirmation in the cast sheet.
    @State private var pendingCast: VoteFlowRequest?
    /// The voting-key flow, open because this wallet had no node to vote with.
    @State private var keyFlow: VoteFlowRequest?
    /// Set when the key flow ended with "Continue": the vote to open the cast
    /// sheet for once the flow's sheet is gone.
    @State private var voteAfterKeyFlow: VoteFlowRequest?

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) {
                guard let request else { return }
                self.request = nil
                route(request)
            }
            // A sheet swiped away on a partial or failed result must not leave
            // it for the next sheet, which any list pill can now open.
            .sheet(item: $pendingCast, onDismiss: viewModel.dismissCastResult) { request in
                if let choice = request.choice {
                    CastVoteSheet(
                        contest: viewModel.latest(request.contest),
                        choice: choice,
                        viewModel: viewModel)
                }
            }
            .sheet(item: $keyFlow, onDismiss: openVoteAfterKeyFlow) { request in
                VotingKeysFlow(
                    start: .addKey,
                    continuesToVote: request.choice != nil,
                    viewModel: viewModel,
                    onFinish: { continueToVote in
                        voteAfterKeyFlow = continueToVote ? request : nil
                        keyFlow = nil
                    })
            }
    }

    /// The cast sheet when a node can cast, else the key flow. A key-only
    /// request (no choice) opens the key flow whatever the wallet holds.
    private func route(_ request: VoteFlowRequest) {
        if !viewModel.canVote || request.choice == nil {
            keyFlow = request
        } else {
            pendingCast = request
        }
    }

    /// Open the cast sheet for the vote that sent the user to the key flow.
    /// Deferred to the flow's `onDismiss`: a second sheet cannot be presented
    /// while the first is still on screen.
    private func openVoteAfterKeyFlow() {
        defer { voteAfterKeyFlow = nil }
        // The cast sheet opens even when the added key's node cannot cast this
        // choice (it already holds it, or has spent its casts): the sheet says
        // why, rather than the vote the user asked for vanishing.
        guard let request = voteAfterKeyFlow,
              request.choice != nil,
              viewModel.canVote,
              !viewModel.isClosed(normalizedLabel: request.contest.normalizedLabel)
        else { return }
        // The sheet reads which nodes already hold a vote here; with that
        // unknown it would say every node is out of votes.
        let label = request.contest.normalizedLabel
        if viewModel.hasLoadedVoteHistory(for: label) {
            pendingCast = request
        } else {
            Task {
                await viewModel.loadVotedNodes(for: label)
                // Still wanted: the contest may have closed, or another vote
                // started, while the history loaded.
                guard pendingCast == nil, keyFlow == nil,
                      !viewModel.isClosed(normalizedLabel: label)
                else { return }
                pendingCast = request
            }
        }
    }
}
