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

struct EnterAddressView: View {
    @ObservedObject var viewModel: EnterAddressViewModel
    var onScanQR: (() -> Void)?
    var onContinue: ((String) -> Void)?
    var onLoginUphold: (() -> Void)?
    var onLoginCoinbase: (() -> Void)?

    var body: some View {
        ZStack {
            Color.primaryBackground
                .ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        addressField
                            .padding(.top, 20)

                        if let error = viewModel.addressValidationErrorMessage ?? viewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.systemRed)
                                .padding(.horizontal, 16)
                                .padding(.top, -10)
                        }

                        addressSourcesMenu

                        if viewModel.hasClipboardContent {
                            if viewModel.isClipboardRevealed {
                                clipboardSection
                            } else {
                                showClipboardButton
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                continueButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            viewModel.loadAddressSources()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Address Field

    private var addressField: some View {
        HStack(spacing: 8) {
            TextField(viewModel.placeholderText, text: $viewModel.addressText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Button(action: { onScanQR?() }) {
                Image("scan-qr.accessory.icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NSLocalizedString("Scan QR code", comment: "Maya"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(viewModel.showAddressError ? Color.systemRed.opacity(0.05) : Color.gray400.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(viewModel.showAddressError ? Color.systemRed : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Address Sources Menu

    private var addressSourcesMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NSLocalizedString("Paste address from", comment: "Maya"))
                .font(.system(size: 13))
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

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
        .padding(6)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
        .shadow(color: .shadow, radius: 10, x: 0, y: 5)
    }

    // MARK: - Clipboard

    private var showClipboardButton: some View {
        Button(action: { viewModel.revealClipboard() }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14))
                    .foregroundColor(.dashBlue)

                Text(NSLocalizedString("Show content in the clipboard", comment: "Maya"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.dashBlue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Tap the address from the clipboard to paste it", comment: "Maya"))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondaryText)

            Button(action: { viewModel.pasteFromClipboard() }) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16))
                        .foregroundColor(.dashBlue)
                        .frame(width: 24, height: 24)

                    if let content = viewModel.revealedClipboardContent {
                        Text(content)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button(action: {
            let address = viewModel.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
            onContinue?(address)
        }, label: {
            Text(NSLocalizedString("Continue", comment: ""))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(viewModel.isAddressValid ? .white : Color(UIColor.label.withAlphaComponent(0.4)))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.isAddressValid ? Color.dashBlue : Color(UIColor.systemFill))
                .cornerRadius(12)
        })
        .disabled(!viewModel.isAddressValid)
    }
}
