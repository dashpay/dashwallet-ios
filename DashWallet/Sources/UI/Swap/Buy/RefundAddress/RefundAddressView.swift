//
//  RefundAddressView.swift
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
import UIKit

struct RefundAddressView: View {
    @ObservedObject var viewModel: RefundAddressViewModel
    @StateObject private var reachability = NetworkReachabilityMonitor()

    var onBack: (() -> Void)?
    var onScanQR: (() -> Void)?
    var onContinue: ((String) -> Void)?

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } },
                )

                VStack(spacing: 20) {
                    TopIntro(
                        title: NSLocalizedString("Enter refund address", comment: "Dash DEX"),
                        subtitle: viewModel.subtitle
                    )

                    if reachability.isOnline {
                        addressContent
                    } else {
                        NetworkUnavailableStateView()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 40)
                    }

                    Spacer(minLength: 0)

                    continueButton
                        .padding(.horizontal, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .onChange(of: viewModel.addressText) { _ in
            viewModel.onAddressChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshClipboardAddress()
        }
        .onAppear {
            viewModel.refreshClipboardAddress()
        }
    }

    // MARK: - Content

    private var addressContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            addressField

            if let clipboardContent = viewModel.clipboardContent {
                clipboardContentRow(clipboardContent)
            } else if viewModel.hasClipboardCandidate {
                clipboardPermissionRow
            }
        }
        .modifier(MenuViewModifier())
    }

    private var addressField: some View {
        AddressFieldView(
            text: $viewModel.addressText,
            label: viewModel.addressLabel,
            placeholder: viewModel.placeholderText,
            hasError: viewModel.showAddressError,
            errorText: viewModel.addressValidationErrorMessage,
            onScanQR: onScanQR
        )
        .padding(14)
    }

    private func clipboardContentRow(_ content: String) -> some View {
        Button(action: viewModel.pasteFromClipboard) {
            DashUIKit.MenuItem(
                leadingIcon: .custom("masternode-keys"),
                title: NSLocalizedString("Clipboard", comment: "Dash DEX"),
                helpText: content,
                accessory: .none
            )
        }
        .buttonStyle(.plain)
    }

    private var clipboardPermissionRow: some View {
        Button(action: { viewModel.pasteFromClipboard() }) {
            DashUIKit.MenuItem(
                leadingIcon: .custom("masternode-keys"),
                title: NSLocalizedString("Clipboard", comment: "Dash DEX"),
                helpText: NSLocalizedString("Show content in the clipboard", comment: "Dash DEX"),
                accessory: .none
            )
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Continue", comment: ""),
            isEnabled: viewModel.isContinueEnabled && reachability.isOnline,
            fillsWidth: true,
            size: .large,
            style: .filledBlue,
            action: {
                guard let address = viewModel.attemptContinue() else { return }
                onContinue?(address)
            }
        )
    }
}

#Preview("Default") {
    RefundAddressView(
        viewModel: RefundAddressViewModel(coin: SwapCryptoCurrency.supportedCoins[0]),
        onBack: {}
    )
}
