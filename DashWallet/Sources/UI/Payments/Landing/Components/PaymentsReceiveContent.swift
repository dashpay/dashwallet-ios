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

import SwiftUI
import DashUIKit

/// The Receive tab: the balance toggle, the QR for its address, and the two
/// actions on that address.
///
/// Takes the view model rather than a resolved address, because the toggle
/// writes back to it and the placeholder wording depends on which balance is
/// selected — passing the parts separately would just rebuild the same object.
struct PaymentsReceiveContent: View {
    @ObservedObject var viewModel: PaymentsLandingViewModel

    var onCopyAddress: () -> Void
    var onShareAddress: () -> Void
    var onSpecifyAmount: () -> Void
    /// `nil` renders the row dimmed and untappable. There is no import flow to
    /// route to yet — `ShortcutAction.importPrivateKey` is still a `break` in
    /// `HomeViewController+Shortcuts` — and a row that silently does nothing
    /// reads as a broken button.
    var onImportPrivateKey: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            ChainNetworkToggle(selection: $viewModel.network, options: ChainNetwork.allCases)
                .padding(.horizontal, 20)

            // main content
            VStack(alignment: .leading, spacing: 0) {

                VStack(alignment: .center, spacing: 20) {
                    qrCard

                    HStack(spacing: 40) {
                        if let address = viewModel.currentAddress {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Your DASH address", comment: "Payments"))
                                    .dashFont(.footnote)
                                    .foregroundStyle(Color.dash.secondaryText)

                                Text(address)
                                    .dashFont(.subhead)
                                    .foregroundColor(.dash.primaryText)
                                    .multilineTextAlignment(.leading)
                            }
                        } else {
                            Text(NSLocalizedString("No address available", comment: "Payments"))
                                .font(.footnote)
                                .foregroundColor(Color.dash.secondaryText)
                        }


                        DashUIKit.DashButton(
                            leadingIcon: .custom(DashIcon.Icons.copyOutline.rawValue, bundle: .dashUIKit),
                            isEnabled: hasAddress,
                            size: .medium,
                            style: .tintedGray,
                            action: onCopyAddress
                        )
                    }
                    .padding(.vertical, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 10)

                // `isEnabled:` rather than `.disabled(…)`: DashButton derives
                // its own colours from that property and applies `.disabled`
                // internally, so an outside modifier blocks the tap but leaves
                // the button looking live.
                HStack(spacing: 20) {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Share address", comment: "Payments"),
                        isEnabled: hasAddress,
                        size: .medium,
                        style: .tintedGray,
                        action: onShareAddress
                    )

                    DashUIKit.DashButton(
                        text: NSLocalizedString("Specify amount", comment: "Payments"),
                        isEnabled: hasAddress && viewModel.network == .core,
                        size: .medium,
                        style: .tintedGray,
                        action: onSpecifyAmount
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .modifier(MenuViewModifier(innerPadding: 0))

            // import private key - if needed

            if onImportPrivateKey != nil {
                Button {
                    onImportPrivateKey?()
                } label: {
                    DashUIKit.MenuItem(
                        leadingIcon: .custom(DashIcon.Menu.importPrivateKey.rawValue, bundle: .dashUIKit),
                        title: NSLocalizedString("Import private key", comment: "Payments"),
                        accessory: .none
                    )
                    .modifier(MenuViewModifier())
                }
                .buttonStyle(.plain)
            }

        }
    }

    private var hasAddress: Bool {
        viewModel.currentAddress != nil
    }

    // MARK: - QR

    @ViewBuilder
    private var qrCard: some View {
        VStack(spacing: 20) {
            if let address = viewModel.currentAddress,
               let qr = QRCodeGenerator.image(for: address) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .padding(10)
            } else if viewModel.network == .platform && !viewModel.platformIsReady {
                placeholder(NSLocalizedString("Platform sync starting…", comment: ""))
            } else if viewModel.network == .shielded {
                // Nil only until the shielded sub-wallet binds at startup
                // (the view model retries as the platform stack comes up).
                placeholder(NSLocalizedString("Shielded wallet starting…", comment: ""))
            } else {
                placeholder(NSLocalizedString("No address available", comment: ""))
            }
        }
    }

    /// Same 220pt square the QR occupies (200 + 10 padding a side), so
    /// switching balances doesn't make the actions below jump.
    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            SwiftUI.ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundColor(Color.dash.secondaryText)
        }
        .frame(width: 220, height: 220)
    }

}

#if DEBUG

@MainActor
private func receiveSample(
    network: ChainNetwork = .core,
    coreAddress: String? = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN"
) -> some View {
    PaymentsReceiveContent(
        viewModel: .makeForPreview(activeTab: .receive, network: network, coreAddress: coreAddress),
        onCopyAddress: {},
        onShareAddress: {},
        onSpecifyAmount: {})
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Core address") {
    receiveSample()
}

/// Both action pills disable without an address — the row must not collapse.
@available(iOS 17, *)
#Preview("No address") {
    receiveSample(coreAddress: nil)
}

#endif
