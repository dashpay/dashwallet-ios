//
//  QuickVotingFlow.swift
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

import SwiftUI

extension View {
    /// The screens of Quick voting, one at a time: "Add your voting keys",
    /// the Quick voting sheet, "One vote left" for the names getting their
    /// last vote, and the result sheet of a run where some names failed.
    func quickVotingFlow(_ quick: QuickVotingViewModel, viewModel: VotingViewModel) -> some View {
        modifier(QuickVotingFlowModifier(quick: quick, viewModel: viewModel))
    }
}

// MARK: - QuickVotingFlowModifier

private struct QuickVotingFlowModifier: ViewModifier {
    @ObservedObject var quick: QuickVotingViewModel
    @ObservedObject var viewModel: VotingViewModel

    /// The keys sheet is closing; `keysContinue` says whether with its vote button.
    @State private var keysClosing = false
    @State private var keysContinue = false
    /// "One vote left" waits for the Quick voting sheet to be gone.
    @State private var showsLastVotes = false
    @State private var showsResult = false
    @State private var isRetrying = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: keysShown, onDismiss: keysDismissed) {
                VotingKeysFlow(mode: .quickVoting, viewModel: viewModel) { continueToVote in
                    keysContinue = continueToVote
                    keysClosing = true
                }
            }
            .sheet(isPresented: confirmShown, onDismiss: confirmDismissed) {
                QuickVotingSheet(
                    votedCount: quick.votedCount,
                    skippedCount: quick.skippedCount,
                    approvesLinkedRequests: quick.approvesLinkedRequests,
                    onVote: quick.voteForAll,
                    onCancel: quick.cancel)
            }
            .fullScreenCover(isPresented: $showsLastVotes) {
                ZStack {
                    Color.dash.backgroundOverlay.ignoresSafeArea()
                    if case .lastVotes(let usernames) = quick.step {
                        VoteAttemptDialog(
                            kind: .lastVotes(usernames: usernames),
                            onConfirm: {
                                quick.confirmLastVotes()
                                closeLastVotes()
                            },
                            onDismiss: {
                                quick.cancel()
                                closeLastVotes()
                            })
                    }
                }
                .presentationBackground(.clear)
            }
            .sheet(isPresented: $showsResult) {
                if case .mixedRun(let run)? = viewModel.store.outcome {
                    QuickVotingResultSheet(
                        run: run,
                        username: { viewModel.username(of: $0) },
                        isRetrying: isRetrying,
                        onTryAgain: tryAgain,
                        onClose: { showsResult = false })
                }
            }
            .onReceive(viewModel.store.$outcome) { outcome in
                if case .mixedRun? = outcome { showsResult = true }
            }
    }

    private var keysShown: Binding<Bool> {
        Binding(
            get: { quick.step == .addKeys && !keysClosing },
            set: { if !$0 { keysClosing = true } })
    }

    private func keysDismissed() {
        let continueToVote = keysContinue
        keysClosing = false
        keysContinue = false
        Task { await quick.finishKeys(continueToVote: continueToVote) }
    }

    private var confirmShown: Binding<Bool> {
        Binding(
            get: { quick.step == .confirm },
            set: { if !$0, quick.step == .confirm { quick.cancel() } })
    }

    /// "One vote left" comes up once the sheet is gone; a second modal cannot
    /// be presented while the first one leaves.
    private func confirmDismissed() {
        guard case .lastVotes = quick.step else { return }
        var noSlide = SwiftUI.Transaction()
        noSlide.disablesAnimations = true
        withTransaction(noSlide) { showsLastVotes = true }
    }

    private func closeLastVotes() {
        var noSlide = SwiftUI.Transaction()
        noSlide.disablesAnimations = true
        withTransaction(noSlide) { showsLastVotes = false }
    }

    /// Resends the failed votes; the sheet closes once every one landed. The
    /// wait holds the run and this sheet's state, not the screen's model.
    private func tryAgain() {
        guard !isRetrying, let run = viewModel.tryAgainRun() else { return }
        isRetrying = true
        let store = viewModel.store
        let retrying = $isRetrying
        let result = $showsResult
        Task {
            await run.value
            retrying.wrappedValue = false
            if case .mixedRun? = store.outcome { return }
            result.wrappedValue = false
        }
    }
}
