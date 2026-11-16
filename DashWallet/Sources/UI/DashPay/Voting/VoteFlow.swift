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
/// `cancelling` is the choice an abstain takes back: only the nodes holding it
/// cast (AC-17).
struct VoteFlowRequest: Identifiable {
    let id = UUID()
    let contest: DPNSContest
    let choice: VoteChoice
    var cancelling: VoteChoice?
}

extension View {
    /// Runs a vote the user asked for through a ``VoteAttemptCoordinator``:
    /// the gates in their fixed order, one dialog at a time, the voting-key
    /// flow when voting is not set up, then the send. Shared by the voting
    /// list and Request details so both take the same path to a cast.
    func voteFlow(_ request: Binding<VoteFlowRequest?>, viewModel: VotingViewModel) -> some View {
        modifier(VoteFlowModifier(request: request, viewModel: viewModel))
    }
}

// MARK: - VoteFlowModifier

private struct VoteFlowModifier: ViewModifier {
    @Binding var request: VoteFlowRequest?
    @ObservedObject var viewModel: VotingViewModel
    @StateObject private var attempt: VoteAttemptCoordinator

    /// The result sheet of a mixed vote, shown once no dialog is up (SCR-10).
    @State private var showsResult = false
    @State private var isRetrying = false

    /// The dialog on screen. It stays set while the dialog fades out, so the
    /// cover keeps its content until it is gone.
    @State private var shownDialog: VoteAttemptCoordinator.Presentation?
    /// The cover is presented without the system's slide; the dialog fades in
    /// and out inside it, as the app's other dialogs do.
    @State private var coverUp = false
    @State private var dialogOpacity = 0.0
    /// The keys sheet's choice, kept while the sheet animates away.
    @State private var keysChoice: VoteChoice?

    private static let fade = 0.2

    init(request: Binding<VoteFlowRequest?>, viewModel: VotingViewModel) {
        _request = request
        self.viewModel = viewModel
        _attempt = StateObject(wrappedValue: VoteAttemptCoordinator(host: viewModel))
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) {
                guard let request else { return }
                self.request = nil
                route(request)
            }
            .onChange(of: attempt.presentation, initial: true) { _, presentation in
                presentationChanged(to: presentation)
            }
            .fullScreenCover(isPresented: $coverUp, onDismiss: showResultIfAny) {
                ZStack {
                    Color.dash.backgroundOverlay.ignoresSafeArea()
                    if let shown = shownDialog, let kind = shown.dialog {
                        VoteAttemptDialog(
                            kind: kind,
                            onConfirm: { Task { await attempt.confirm(shown); showResultIfAny() } },
                            onDismiss: attempt.dismiss)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .opacity(dialogOpacity)
                .presentationBackground(.clear)
                .onAppear { withAnimation(.easeOut(duration: Self.fade)) { dialogOpacity = 1 } }
            }
            .sheet(isPresented: keysShown, onDismiss: keysDismissed) {
                if let choice = keysChoice {
                    VotingKeysFlow(
                        mode: .vote(choice),
                        viewModel: viewModel,
                        onFinish: { attempt.finishKeys(continueToVote: $0) })
                }
            }
            .sheet(isPresented: $showsResult) {
                if case .mixed(let report)? = viewModel.store.outcome {
                    VoteResultSheet(
                        report: report,
                        username: viewModel.username(of: report),
                        isRetrying: isRetrying,
                        onTryAgain: tryAgain,
                        onClose: { showsResult = false })
                }
            }
    }

    /// A dialog fades in over a cover presented without animation, replaces
    /// the one up in place, or fades out before the cover goes.
    private func presentationChanged(to presentation: VoteAttemptCoordinator.Presentation?) {
        if case .addKeys(let choice) = presentation { keysChoice = choice }
        guard presentation?.dialog != nil else {
            guard coverUp else { return }
            withAnimation(.easeIn(duration: Self.fade)) {
                dialogOpacity = 0
            } completion: {
                // Another dialog of a new attempt came up while this one faded.
                guard attempt.presentation?.dialog == nil else {
                    shownDialog = attempt.presentation
                    withAnimation(.easeOut(duration: Self.fade)) { dialogOpacity = 1 }
                    return
                }
                var noSlide = SwiftUI.Transaction()
                noSlide.disablesAnimations = true
                withTransaction(noSlide) { coverUp = false }
                shownDialog = nil
            }
            return
        }
        if coverUp {
            withAnimation(.easeInOut(duration: Self.fade)) { shownDialog = presentation }
        } else {
            shownDialog = presentation
            dialogOpacity = 0
            var noSlide = SwiftUI.Transaction()
            noSlide.disablesAnimations = true
            withTransaction(noSlide) { coverUp = true }
        }
    }

    private var keysShown: Binding<Bool> {
        Binding(
            get: {
                if case .addKeys = attempt.presentation { return true }
                return false
            },
            set: { if !$0 { attempt.finishKeys(continueToVote: false) } })
    }

    /// A vote starts an attempt, unless one is already running.
    private func route(_ request: VoteFlowRequest) {
        guard !attempt.isRunning, !viewModel.store.isVoteBusy else { return }
        let intent: VoteAttempt.Intent = request.cancelling.map { .cancel($0) } ?? .vote(request.choice)
        Task {
            await attempt.start(intent, on: viewModel.latest(request.contest))
            showResultIfAny()
        }
    }

    private func keysDismissed() {
        Task {
            await attempt.presentationDismissed()
            showResultIfAny()
        }
    }

    /// Opens the report of a mixed vote once the attempt is over and nothing
    /// else is on screen; a second sheet cannot be presented over the dialog.
    private func showResultIfAny() {
        guard !attempt.isRunning, attempt.presentation == nil, !coverUp,
              case .mixed? = viewModel.store.outcome
        else { return }
        showsResult = true
    }

    /// Resends the failed masternodes; the sheet closes once every vote landed.
    private func tryAgain() {
        guard !isRetrying else { return }
        isRetrying = true
        Task {
            await viewModel.retryFailed()
            isRetrying = false
            if case .mixed? = viewModel.store.outcome { return }
            showsResult = false
        }
    }
}
