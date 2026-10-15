//
//  VotingKeyInputScreen.swift
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
import SwiftUI

// MARK: - VotingKeyInputScreen

/// One field for a masternode voting private key, and a Verify button. The
/// Android wallet's "Enter your voting key", reached from a Vote tap when the
/// wallet has no node to vote with, or from the voting-keys list.
struct VotingKeyInputScreen: View {
    /// `.close` when this screen opens the flow, `.back` when it was pushed
    /// over the voting-keys list.
    let leadingElement: DashUIKit.NavigationBarElement
    let onLeading: () -> Void
    /// Called once the key made at least one node votable, with a notice
    /// when some of its nodes could not be added — the caller shows it where
    /// the flow lands, since this screen is gone by then.
    let onVerified: (_ partialImportNotice: String?) -> Void

    @StateObject private var viewModel = VotingKeyInputViewModel()
    @State private var isFieldFocused = false
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { leadingElement.button(action: onLeading) })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.TopIntroView(
                        title: NSLocalizedString("Enter your voting key", comment: "Voting"),
                        mainDescription: NSLocalizedString(
                            "Masternodes and evonodes vote on usernames. Enter a node's voting private key to vote with it from this wallet. The key is kept in this device's keychain.",
                            comment: "Voting"))

                    DashUIKit.AddressFieldView(
                        text: $viewModel.keyText,
                        label: NSLocalizedString("Masternode Voting Private Key", comment: "Voting"),
                        placeholder: NSLocalizedString("Paste or scan the key", comment: "Voting"),
                        hasError: viewModel.error != nil,
                        errorText: viewModel.error,
                        isDisabled: viewModel.isVerifying,
                        onScanQR: {
                            // Blur first: the keyboard would otherwise stay up
                            // behind the scanner and cover the field on return.
                            isFieldFocused = false
                            showScanner = true
                        },
                        onPaste: {
                            if let pasted = UIPasteboard.general.string {
                                viewModel.keyText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        },
                        isFocused: $isFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(verify)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashUIKit.DashButton(
                text: NSLocalizedString("Verify", comment: "Voting"),
                isEnabled: viewModel.canVerify,
                isLoading: viewModel.isVerifying,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: verify)
                .padding(20)
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        // Keyboard up on arrival, as on Android: pasting the key is the only
        // thing to do here.
        .onAppear { isFieldFocused = true }
        .sheet(isPresented: $showScanner) {
            QRScannerRepresentable(
                onScanned: { value in
                    viewModel.keyText = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    showScanner = false
                },
                onCancel: { showScanner = false })
                .ignoresSafeArea()
        }
    }

    private func verify() {
        guard viewModel.canVerify else { return }
        isFieldFocused = false
        Task {
            switch await viewModel.verifyAndAdd() {
            case .added: onVerified(nil)
            case .partiallyAdded(let notice): onVerified(notice)
            case .failed: break
            }
        }
    }
}
