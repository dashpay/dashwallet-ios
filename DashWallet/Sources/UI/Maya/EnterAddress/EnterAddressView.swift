//
//  EnterAddressView.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

// MARK: - EnterAddressView

struct EnterAddressView: View {
    @ObservedObject var viewModel: EnterAddressViewModel
    var onBack: (() -> Void)?
    var onScanQR: (() -> Void)?
    var onContinue: ((String) -> Void)?
    var onLoginUphold: (() -> Void)?
    var onLoginCoinbase: (() -> Void)?

    var body: some View {
        ZStack {
            Color.primaryBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                NavigationBar(
                    leading: { NavigationBarElement.back.button { onBack?() } },
                    central: { Text(NSLocalizedString("Enter address", comment: "Maya")).font(.subheadMedium) }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        addressField

                        addressSourcesMenu

                        if let clipboardContent = viewModel.clipboardContent {
                            clipboardContentRow(clipboardContent)
                        } else if viewModel.hasClipboardCandidate {
                            clipboardPermissionRow
                        }
                    }
                    .modifier(MayaMenuCardStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                continueButton
                    .padding(.horizontal, 60)
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: viewModel.addressText) { _ in
            viewModel.onAddressChanged()
        }
        .onAppear {
            viewModel.loadAddressSources()
        }
    }

    // MARK: - Address Field

    private var addressField: some View {
        AddressFieldView(
            text: $viewModel.addressText,
            label: viewModel.addressLabel,
            placeholder: viewModel.placeholderText,
            hasError: viewModel.showAddressError,
            errorText: viewModel.addressValidationErrorMessage ?? viewModel.errorMessage,
            onScanQR: onScanQR
        )
        .padding(14)
    }

    // MARK: - Address Sources Menu

    private var addressSourcesMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NSLocalizedString("Paste address from", comment: "Maya"))
                .font(.footnote)
                .foregroundColor(.tertiaryText)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)

            AddressSourceView(
                sourceType: .uphold,
                state: viewModel.upholdState,
                onTap: {
                    if case .loggedOut = viewModel.upholdState {
                        onLoginUphold?()
                    } else {
                        viewModel.selectUpholdAddress()
                    }
                }
            )

            AddressSourceView(
                sourceType: .coinbase,
                state: viewModel.coinbaseState,
                onTap: {
                    if case .loggedOut = viewModel.coinbaseState {
                        onLoginCoinbase?()
                    } else {
                        viewModel.selectCoinbaseAddress()
                    }
                }
            )
        }
    }

    // MARK: - Clipboard

    private var clipboardPermissionRow: some View {
        Button(action: { viewModel.pasteFromClipboard() }) {
            HStack(spacing: 10) {
                Icon(name: .custom("masternode-keys"))
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Clipboard")
                        .font(Font.subheadMedium)
                        .foregroundColor(Color.gray500)

                    Text(NSLocalizedString("Show content in the clipboard", comment: "Maya"))
                        .font(Font.footnote)
                        .foregroundColor(.tertiaryText)
                }

                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func clipboardContentRow(_ content: String) -> some View {
        AddressSourceView(
            sourceType: .clipboard,
            state: .available(content),
            onTap: {
                viewModel.pasteFromClipboard()
            }
        )
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        DashButton(
            text: NSLocalizedString("Continue", comment: ""),
            isEnabled: viewModel.isContinueEnabled) {
                guard let address = viewModel.attemptContinue() else { return }
                onContinue?(address)
            }
    }
}

#Preview("Default") {
    EnterAddressView(viewModel: EnterAddressViewModel(coin: MayaCryptoCurrency.supportedCoins[0]), onBack: {})
}

#Preview("Clipboard Revealed") {
    EnterAddressView(
        viewModel: {
            let viewModel = EnterAddressViewModel(coin: MayaCryptoCurrency.supportedCoins[0])
            viewModel.clipboardContent = "dash:Xq9M8LkYh6sQa7u7pVv3mY8i7fQ5j8m4Kc?amount=0.1"
            return viewModel
        }(),
        onBack: {}
    )
}
