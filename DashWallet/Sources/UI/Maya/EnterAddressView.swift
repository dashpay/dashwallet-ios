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

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        addressField
                            .padding(.top, 20)

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.systemRed)
                                .padding(.top, -12)
                        }

                        if viewModel.clipboardContent != nil {
                            clipboardSection
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

                continueButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray400.opacity(0.1))
        .cornerRadius(16)
    }

    // MARK: - Clipboard Section

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Paste address from", comment: "Maya"))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondaryText)

            Button(action: { viewModel.pasteFromClipboard() }) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16))
                        .foregroundColor(.dashBlue)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Clipboard", comment: "Maya"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primaryText)

                        if let content = viewModel.clipboardContent {
                            Text(content)
                                .font(.system(size: 12))
                                .foregroundColor(.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondaryText)
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
        }) {
            Text(NSLocalizedString("Continue", comment: ""))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.isAddressValid ? Color.dashBlue : Color.gray400)
                .cornerRadius(12)
        }
        .disabled(!viewModel.isAddressValid)
    }
}
