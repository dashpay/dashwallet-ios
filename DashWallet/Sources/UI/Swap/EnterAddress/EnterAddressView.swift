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

import DashUIKit
import SwiftUI
import UIKit

// MARK: - EnterAddressView

struct EnterAddressView: View {
    @ObservedObject var viewModel: EnterAddressViewModel
    @StateObject private var reachability = NetworkReachabilityMonitor()
    var onBack: (() -> Void)?
    var onScanQR: (() -> Void)?
    var onContinue: ((String) -> Void)?
    var onLoginUphold: (() -> Void)?
    var onLoginCoinbase: (() -> Void)?

    var body: some View {
        ZStack {
            Color.dash.primaryBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } },
                    central: {
                        Text(NSLocalizedString("Enter address", comment: "Maya"))
                            .dashFont(.subheadMedium)
                            .foregroundColor(Color.dash.primaryText)
                    }
                )

                // Offline: hide the whole address-entry content (address sources and the
                // server-side address validation both need network) and show the offline state,
                // matching Convert / Order Preview. Continue stays disabled below.
                if reachability.isOnline {
                    addressContent
                } else {
                    NetworkUnavailableStateView()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 40)

                    Spacer(minLength: 0)
                }

                continueButton
                    .padding(.horizontal, 60)
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: viewModel.addressText) { _ in
            viewModel.onAddressChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // UIKit app lifecycle: scenePhase isn't driven here, so refresh on the foreground
            // notification — the only moment iOS exposes another app's freshly-copied clipboard.
            viewModel.refreshClipboardAddress()
        }
        .onAppear {
            viewModel.loadAddressSources()
            // Refresh whenever the screen (re)appears so the clipboard card is never stale.
            viewModel.refreshClipboardAddress()
        }
    }

    // MARK: - Content

    /// The online address-entry content: address field + sources menu + clipboard rows.
    private var addressContent: some View {
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
            .modifier(MenuViewModifier())
            .padding(.horizontal, 20)
            .padding(.top, 10)
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
                .dashFont(.footnote)
                .foregroundColor(Color.dash.tertiaryText)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)

            addressSourceRow(type: .uphold, state: viewModel.upholdState) {
                if case .loggedOut = viewModel.upholdState { onLoginUphold?() }
                else { viewModel.selectUpholdAddress() }
            }

            addressSourceRow(type: .coinbase, state: viewModel.coinbaseState) {
                if case .loggedOut = viewModel.coinbaseState { onLoginCoinbase?() }
                else { viewModel.selectCoinbaseAddress() }
            }
        }
    }

    // MARK: - Clipboard

    private var clipboardPermissionRow: some View {
        Button(action: { viewModel.pasteFromClipboard() }) {
            DashUIKit.MenuItem(
                leadingIcon: .custom("masternode-keys"),
                title: NSLocalizedString("Clipboard", comment: "Maya"),
                helpText: NSLocalizedString("Show content in the clipboard", comment: "Maya"),
                accessory: .none
            )
        }
        .buttonStyle(.plain)
    }

    private func clipboardContentRow(_ content: String) -> some View {
        addressSourceRow(type: .clipboard, state: .available(content)) {
            viewModel.pasteFromClipboard()
        }
    }

    // MARK: - Address Source Row (DashUIKit.MenuItem)

    @ViewBuilder
    private func addressSourceRow(
        type: AddressSourceType,
        state: AddressSourceState,
        onTap: @escaping () -> Void
    ) -> some View {
        let isDisabled: Bool = {
            switch state { case .loading, .notAvailable: return true; default: return false }
        }()

        Button(action: onTap) {
            DashUIKit.MenuItem(
                leadingIcon: leadingIcon(for: type),
                title: type.title,
                helpText: helpText(for: state),
                accessory: accessory(for: state, onTap: onTap)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func leadingIcon(for type: AddressSourceType) -> DashIconSource {
        switch type {
        case .uphold:    return .custom("menu-uphold")
        case .coinbase:  return .custom("menu-coinbase")
        case .clipboard: return .custom("masternode-keys")
        }
    }

    private func helpText(for state: AddressSourceState) -> String? {
        switch state {
        case .available(let address): return address
        case .notAvailable:           return NSLocalizedString("Not available", comment: "Maya")
        case .loading:                return NSLocalizedString("Loading...", comment: "Maya")
        case .loggedOut:              return nil
        }
    }

    private func accessory(
        for state: AddressSourceState,
        onTap: @escaping () -> Void
    ) -> MenuItemAccessory {
        switch state {
        case .loggedOut:
            return .button(DashUIKit.DashButton(
                text: NSLocalizedString("Log In", comment: "Maya"),
                size: .small,
                style: .plainBlue,
                action: onTap
            ))
        case .loading, .available, .notAvailable:
            return .none
        }
    }

    // MARK: - Continue Button

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
