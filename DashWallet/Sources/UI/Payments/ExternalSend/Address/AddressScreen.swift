//
//  Created by Roman Chornyi
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

/// SCR-02 Address. Draws the ViewModel's state; the scan button and the next step are the flow's callbacks.
struct AddressScreen: View {
    @ObservedObject var viewModel: AddressViewModel

    var onBack: (() -> Void)?
    var onScan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    if let onBack {
                        DashUIKit.NavigationBarElement.back.button(action: onBack)
                    }
                },
                central: {
                    Text(NSLocalizedString("Address", comment: "External send"))
                        .dashFont(.headline)
                        .foregroundStyle(Color.dash.primaryText)
                })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.AddressFieldView(
                        text: Binding(get: { viewModel.text }, set: { viewModel.setText($0) }),
                        label: NSLocalizedString("DASH address", comment: "External send"),
                        placeholder: NSLocalizedString("Enter address", comment: "External send"),
                        hasError: fieldError != nil,
                        errorText: fieldError,
                        isDisabled: viewModel.isFieldReadOnly,
                        onScanQR: onScan)
                        .accessibilityIdentifier("send_address_field")

                    clipboardArea

                    if viewModel.state == .checkFailed {
                        DashUIKit.SystemMessageView(
                            title: NSLocalizedString(
                                "Couldn't check the identity. Check your connection and try again.",
                                comment: "External send"),
                            backgroundColor: Color.dash.redAlpha5,
                            buttonName: NSLocalizedString("Try again", comment: "External send"),
                            onAction: { Task { await viewModel.retry() } })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }

            DashUIKit.DashButton(
                text: viewModel.isFieldReadOnly
                    ? NSLocalizedString("Checking…", comment: "External send")
                    : NSLocalizedString("Continue", comment: "External send"),
                isEnabled: viewModel.canContinue,
                isLoading: viewModel.isFieldReadOnly,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: { Task { await viewModel.continueTapped() } })
                .accessibilityIdentifier("send_address_continue")
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .background(Color.dash.primaryBackground)
    }

    private var fieldError: String? {
        switch viewModel.state {
        case .invalid:
            return NSLocalizedString("Not a valid address for this network", comment: "External send")
        case .notFound:
            return NSLocalizedString("Identity not found", comment: "External send")
        default:
            return nil
        }
    }

    /// The Show clipboard button, or what the tap found, in the same place.
    @ViewBuilder private var clipboardArea: some View {
        switch viewModel.state {
        case .clipboard(let found):
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Tap the address from the clipboard to paste it", comment: "External send"))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
                Button(action: viewModel.fillFromClipboard) {
                    Text(clipboardText(found))
                        .dashFont(.subhead)
                        .foregroundStyle(Color.dash.blueText)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityIdentifier("send_address_clipboard_value")
            }
        case .clipboardNone:
            Text(NSLocalizedString("No address, Identity ID or dash: link on the clipboard", comment: "External send"))
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.secondaryText)
        default:
            DashUIKit.DashButton(
                text: NSLocalizedString("Show clipboard", comment: "External send"),
                isEnabled: !viewModel.isFieldReadOnly,
                size: .medium,
                style: .tintedBlue,
                action: viewModel.showClipboard)
                .accessibilityIdentifier("send_address_show_clipboard")
        }
    }

    /// A payment-request link has no address; the link itself is what the clipboard held.
    private func clipboardText(_ found: Destination) -> String {
        found.type == .paymentRequest ? (found.paymentRequestURL?.absoluteString ?? "") : found.text
    }
}

#if DEBUG

private let previewAddress = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN"
private let previewIdentityID = "4EfA9Jrvv7vTuTWfQsoCgQ9nQJi1JkZDzrmAu5AY4DpZ"

private struct PreviewClipboard: ClipboardReading {
    var content: String?

    func readString() -> String? { content }
}

private struct PreviewLookup: IdentityLooking {
    var result: IdentityLookupResult

    func lookup(id: String, network: WalletEnvironment.NetworkKind) async -> IdentityLookupResult { result }
}

@MainActor
private func previewScreen(_ state: AddressViewModel.State = .initial, text: String = "") -> some View {
    AddressScreen(viewModel: AddressViewModel.preview(state, text: text), onBack: {}, onScan: {})
}

@MainActor
private extension AddressViewModel {
    static func preview(_ state: State, text: String) -> AddressViewModel {
        let vm = AddressViewModel(network: .mainnet, identityLookup: PreviewLookup(result: .couldNotCheck),
                                  pasteboard: PreviewClipboard(content: nil))
        vm.setText(text)
        vm.setPreviewState(state)
        return vm
    }
}

#Preview("Default") { previewScreen() }

#Preview("Clipboard") {
    previewScreen(.clipboard(Destination(type: .coreAddress, text: previewAddress)))
}

#Preview("Clipboard none") { previewScreen(.clipboardNone) }

#Preview("Entered") { previewScreen(.entered, text: previewAddress) }

#Preview("Invalid") { previewScreen(.invalid(.invalid), text: "not-an-address") }

#Preview("Wrong network") { previewScreen(.invalid(.wrongNetwork), text: previewAddress) }

#Preview("Checking") { previewScreen(.checking, text: previewIdentityID) }

#Preview("Not found") { previewScreen(.notFound, text: previewIdentityID) }

#Preview("Could not check") { previewScreen(.checkFailed, text: previewIdentityID) }

#Preview("Long text, large Dynamic Type") {
    previewScreen(.clipboard(Destination(type: .platformAddress,
                                         text: "dash1kxqyzzjn8cl0sgr5vmw4pe3tq7h2fuaxd9yc6gs0lnrzv5w8j4ek3m2pt7qhxy9")))
        .dynamicTypeSize(.accessibility3)
}

#endif
