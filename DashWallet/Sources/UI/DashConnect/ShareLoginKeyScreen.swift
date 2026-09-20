//
//  ShareLoginKeyScreen.swift
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

/// Hand a nearby browser a bounded login key over Bluetooth.
///
/// The user picks how long the key lives and how much it may spend, the
/// wallet advertises the DashConnect Bluetooth service, and once a browser
/// writes its request the user compares the pairing code on both screens
/// and confirms. The view model then registers the key and serves the
/// encrypted login key; this view only renders the phases.
struct ShareLoginKeyScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel: ShareLoginKeyViewModel
    @ObservedObject private var peripheral: BrowserLoginPeripheral

    init(vc: UINavigationController, viewModel: ShareLoginKeyViewModel) {
        self.vc = vc
        _viewModel = StateObject(wrappedValue: viewModel)
        _peripheral = ObservedObject(wrappedValue: viewModel.peripheral)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    // Dimmed and inert rather than absent: the bar keeps its
                    // layout, and the user sees the screen is busy instead of
                    // a control that silently does nothing.
                    NavigationBarElement.back.button {
                        guard !viewModel.blocksDismissal else { return }
                        vc.popViewController(animated: true)
                    }
                    .disabled(viewModel.blocksDismissal)
                    .opacity(viewModel.blocksDismissal ? 0.4 : 1)
                }
            )

            TopIntro(
                title: NSLocalizedString("Sign in on a browser", comment: "DashConnect: Bluetooth login"),
                subtitle: NSLocalizedString(
                    "The browser gets its own key for your username. It stops working when it expires or once it has spent its limit, and it can never change your keys.",
                    comment: "DashConnect: Bluetooth login")
            )
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    limitsCard
                    phaseCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        // The swipe-back gesture bypasses the button above, and `onDisappear`
        // would then wipe a response the browser has not read yet.
        .onChange(of: viewModel.blocksDismissal) { blocks in
            vc.interactivePopGestureRecognizer?.isEnabled = !blocks
        }
        .onDisappear {
            vc.interactivePopGestureRecognizer?.isEnabled = true
            viewModel.stop()
        }
    }

    // MARK: - Limits

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Limits", comment: "DashConnect: Bluetooth login"))
                .dashFont(.title3Medium)
                .foregroundColor(Color.dash.primaryText)

            labeledPicker(
                NSLocalizedString("Valid for", comment: "DashConnect: login key lifetime"),
                selection: $viewModel.lifetime,
                options: ShareLoginKeyViewModel.Lifetime.allCases,
                title: \.title
            )
            labeledPicker(
                NSLocalizedString("Spend limit", comment: "DashConnect: login key budget"),
                selection: $viewModel.budget,
                options: ShareLoginKeyViewModel.Budget.allCases,
                title: \.title
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
        .disabled(!viewModel.isConfiguring)
        .opacity(viewModel.isConfiguring ? 1 : 0.6)
    }

    private func labeledPicker<Option: Hashable & Identifiable>(
        _ label: String,
        selection: Binding<Option>,
        options: [Option],
        title: KeyPath<Option, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .dashFont(.subhead)
                .foregroundColor(Color.dash.secondaryText)
            Picker(label, selection: selection) {
                ForEach(options) { option in
                    Text(option[keyPath: title]).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Phases

    @ViewBuilder private var phaseCard: some View {
        switch viewModel.phase {
        case .configuring:
            VStack(spacing: 12) {
                Text(NSLocalizedString(
                    "In the browser, choose “Sign in with your phone”, then pick “Dash Wallet” from the Bluetooth list.",
                    comment: "DashConnect: Bluetooth login"))
                .dashFont(.subhead)
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.center)

                DashButton(
                    text: NSLocalizedString("Start sharing", comment: "DashConnect: Bluetooth login"),
                    style: .filledBlue,
                    size: .large,
                    stretch: true,
                    action: viewModel.startAdvertising
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(12)

        case .advertising:
            statusCard(
                title: radioTitle,
                detail: NSLocalizedString("Keep this screen open while the browser connects.", comment: "DashConnect: Bluetooth login"),
                showsProgress: true
            ) {
                DashButton(
                    text: NSLocalizedString("Cancel", comment: ""),
                    style: .tintedBlue,
                    size: .large,
                    stretch: true,
                    action: viewModel.reset
                )
            }

        case .awaitingConfirmation(let pending):
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(String(
                        format: NSLocalizedString("%@ wants to sign in", comment: "DashConnect: Bluetooth login, app name"),
                        pending.appLabel))
                    .dashFont(.title3Medium)
                    .foregroundColor(Color.dash.primaryText)
                    Text(pending.contractId)
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.secondaryText)
                }

                VStack(spacing: 6) {
                    Text(NSLocalizedString("Pairing code", comment: "DashConnect: Bluetooth login"))
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.secondaryText)
                    Text(pending.pairingCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .kerning(6)
                        .foregroundColor(Color.dash.primaryText)
                        // The label is the six digits themselves, spaced so VoiceOver reads them
                        // one at a time. It carries no translatable text — the rule fires on the
                        // `" "` separator passed to `joined(separator:)`.
                        // a11y-ignore: A11Y009 spaced digits, no translatable text
                        .accessibilityLabel(pending.pairingCode.map(String.init).joined(separator: " "))
                    Text(NSLocalizedString("Only continue if the browser shows the same six digits.", comment: "DashConnect: Bluetooth login"))
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    DashButton(
                        text: String(
                            format: NSLocalizedString("Share a %@ key limited to %@", comment: "DashConnect: Bluetooth login, lifetime and budget"),
                            viewModel.lifetime.title,
                            viewModel.budget.title),
                        style: .filledBlue,
                        size: .large,
                        stretch: true,
                        action: viewModel.confirm
                    )
                    DashButton(
                        text: NSLocalizedString("Deny", comment: "DashConnect"),
                        style: .tintedBlue,
                        size: .large,
                        stretch: true,
                        action: viewModel.decline
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(12)

        case .registering:
            statusCard(
                title: NSLocalizedString("Registering the key…", comment: "DashConnect: Bluetooth login"),
                detail: NSLocalizedString("Platform is adding the browser's key to your username.", comment: "DashConnect: Bluetooth login"),
                showsProgress: true
            ) { EmptyView() }

        case .delivered(let keyId):
            deliveredCard(keyId: keyId)

        case .failed(let message):
            statusCard(
                title: NSLocalizedString("Couldn't share the key", comment: "DashConnect: Bluetooth login"),
                detail: message,
                showsProgress: false,
                isError: true
            ) {
                DashButton(
                    text: NSLocalizedString("Try again", comment: ""),
                    style: .filledBlue,
                    size: .large,
                    stretch: true,
                    action: viewModel.reset
                )
            }
        }

        if let radioError = peripheral.lastError {
            Text(radioError)
                .dashFont(.subhead)
                .foregroundColor(Color.dash.errorText)
                .multilineTextAlignment(.center)
        }
    }

    /// The key is registered and the response is on the characteristic, but
    /// it is only useful once the browser has actually read it — until then
    /// this card keeps the service up and the Done button away.
    @ViewBuilder private func deliveredCard(keyId: UInt32) -> some View {
        if viewModel.isAwaitingDeliveryAcknowledgement && !viewModel.deliveryWaitTimedOut {
            statusCard(
                title: NSLocalizedString("Sending the key to the browser…", comment: "DashConnect: Bluetooth login"),
                detail: NSLocalizedString("Keep this screen open until the browser confirms it received the key.", comment: "DashConnect: Bluetooth login"),
                showsProgress: true
            ) { EmptyView() }
        } else {
            statusCard(
                title: viewModel.isAwaitingDeliveryAcknowledgement
                    ? NSLocalizedString("The browser didn't confirm", comment: "DashConnect: Bluetooth login")
                    : NSLocalizedString("Login key delivered", comment: "DashConnect: Bluetooth login"),
                detail: viewModel.isAwaitingDeliveryAcknowledgement
                    ? String(
                        format: NSLocalizedString("Key %d is registered, but the browser never said it received it. If it can't sign in, share a new key — this one stops working when it expires or its budget runs out.", comment: "DashConnect: Bluetooth login"),
                        Int(keyId))
                    : String(
                        format: NSLocalizedString("The browser can now sign in. Key %d stops working when it expires or its budget runs out.", comment: "DashConnect: Bluetooth login"),
                        Int(keyId)),
                showsProgress: false,
                isError: viewModel.isAwaitingDeliveryAcknowledgement
            ) {
                DashButton(
                    text: NSLocalizedString("Done", comment: ""),
                    style: .filledBlue,
                    size: .large,
                    stretch: true,
                    action: { vc.popViewController(animated: true) }
                )
            }
        }
    }

    private func statusCard<Actions: View>(
        title: String,
        detail: String,
        showsProgress: Bool,
        isError: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 12) {
            if showsProgress {
                // The app declares its own `ProgressView: UIView`, which shadows
                // SwiftUI's in any file importing both.
                SwiftUI.ProgressView()
            }
            Text(title)
                .dashFont(.title3Medium)
                .foregroundColor(isError ? Color.dash.errorText : Color.dash.primaryText)
            Text(detail)
                .dashFont(.subhead)
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var radioTitle: String {
        switch peripheral.radioState {
        case .advertising:
            return NSLocalizedString("Waiting for a browser…", comment: "DashConnect: Bluetooth login")
        case .poweredOn:
            return NSLocalizedString("Publishing the Bluetooth service…", comment: "DashConnect: Bluetooth login")
        case .poweredOff:
            return NSLocalizedString("Bluetooth is off.", comment: "DashConnect: Bluetooth login")
        case .unauthorized:
            return NSLocalizedString("Bluetooth permission was denied.", comment: "DashConnect: Bluetooth login")
        case .unsupported:
            return NSLocalizedString("This device has no Bluetooth LE.", comment: "DashConnect: Bluetooth login")
        case .unknown:
            return NSLocalizedString("Starting Bluetooth…", comment: "DashConnect: Bluetooth login")
        }
    }
}

#Preview {
    ShareLoginKeyScreen(
        vc: UINavigationController(),
        viewModel: ShareLoginKeyViewModel(dataSource: MockDashConnectDataSource())
    )
}
