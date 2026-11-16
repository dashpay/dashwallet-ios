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
/// design's "Enter voting key" (Android's "Enter your voting key"), pushed
/// over the voting-keys list by its «Add masternode voting key».
struct VotingKeyInputScreen: View {
    let onBack: () -> Void
    /// Called once the key made at least one node votable, with a notice
    /// when some of its nodes could not be added — the caller shows it where
    /// the flow lands, since this screen is gone by then.
    let onVerified: (_ partialImportNotice: String?) -> Void

    @StateObject private var viewModel = VotingKeyInputViewModel()
    @State private var isFieldFocused = false
    @State private var showScanner = false

    var body: some View {
        VotingKeyInputContent(
            keyText: $viewModel.keyText,
            error: viewModel.error,
            isVerifying: viewModel.isVerifying,
            canVerify: viewModel.canVerify,
            isFieldFocused: $isFieldFocused,
            onBack: onBack,
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
            onVerify: verify)
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

// MARK: - VotingKeyInputContent

/// The layout of "Enter voting key", from values and actions only.
struct VotingKeyInputContent: View {
    @Binding var keyText: String
    /// The reason the last Verify failed, under the field; `nil` when none did.
    let error: String?
    let isVerifying: Bool
    let canVerify: Bool
    @Binding var isFieldFocused: Bool
    let onBack: () -> Void
    let onScanQR: () -> Void
    let onPaste: () -> Void
    let onVerify: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.back.button(action: onBack) })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.TopIntroView(
                        title: NSLocalizedString("Enter voting key", comment: "Voting"),
                        mainDescription: NSLocalizedString(
                            "Masternodes and evonodes vote on usernames. Enter a node's voting private key to vote with it from this wallet. The key is kept in this device's keychain.",
                            comment: "Voting"))

                    DashUIKit.AddressFieldView(
                        text: $keyText,
                        label: NSLocalizedString("Masternode voting private key", comment: "Voting"),
                        placeholder: NSLocalizedString("Paste or scan the key", comment: "Voting"),
                        hasError: error != nil,
                        errorText: error,
                        isDisabled: isVerifying,
                        onScanQR: onScanQR,
                        onPaste: onPaste,
                        isFocused: $isFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(onVerify)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashUIKit.DashButton(
                text: NSLocalizedString("Verify", comment: "Voting"),
                isEnabled: canVerify,
                isLoading: isVerifying,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: onVerify)
                .padding(20)
        }
        .background(Color.dash.primaryBackground)
    }
}

#if DEBUG
private enum KeyInputPreview {
    static let key = "XpreviewOnlyNotARealVotingKey0000000000000000000000"

    static func content(
        key: String = "",
        error: String? = nil,
        isVerifying: Bool = false
    ) -> some View {
        VotingKeyInputContent(
            keyText: .constant(key), error: error, isVerifying: isVerifying,
            canVerify: !isVerifying && !key.isEmpty, isFieldFocused: .constant(false),
            onBack: {}, onScanQR: {}, onPaste: {}, onVerify: {})
    }
}

#Preview("Empty") { KeyInputPreview.content() }
#Preview("Filled") { KeyInputPreview.content(key: KeyInputPreview.key) }
#Preview("Verifying") { KeyInputPreview.content(key: KeyInputPreview.key, isVerifying: true) }
#Preview("Invalid key") {
    KeyInputPreview.content(key: "not-a-key", error: "You have entered an invalid key")
}
#Preview("Not associated") {
    KeyInputPreview.content(
        key: KeyInputPreview.key,
        error: "You have entered a key that is not associated to an active Masternode")
}
#Preview("Dark") {
    KeyInputPreview.content(key: KeyInputPreview.key).preferredColorScheme(.dark)
}
#endif
