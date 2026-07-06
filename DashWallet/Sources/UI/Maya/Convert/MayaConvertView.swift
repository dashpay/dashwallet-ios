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

// MARK: - MayaConvertView

struct MayaConvertView: View {

    private enum Layout {
        static let iconSize: CGFloat = 30
        static let padding: CGFloat = 10
        static let hPadding: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let contentSpacing: CGFloat = 20
        static let cardSpacing: CGFloat = 5
        static let topMenuItemHeightFallback: CGFloat = 74
        static let arrowIconHeight: CGFloat = 11
        static let arrowBadgeSize: CGFloat = 30
        static let arrowBadgeCornerRadius: CGFloat = 10
        static let arrowBadgeInset: CGFloat = 5
    }

    @StateObject private var viewModel: MayaConvertViewModel
    @StateObject private var reachability = NetworkReachabilityMonitor()
    @State private var showLocalCurrency = false
    private let onBack: (() -> Void)?
    private let onContinue: () -> Void

    init(viewModel: MayaConvertViewModel, onBack: (() -> Void)? = nil, onContinue: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationBar(leading: { NavigationBarElement.back.button { onBack?() } })
            TopIntro(title: NSLocalizedString("Convert Dash", comment: "Maya"))
                .padding(.horizontal, Layout.hPadding)
                .padding(.bottom, 6)
            amountSection
            if reachability.isOnline {
                keyboard
            } else {
                // Quote/amount entry needs network — replace the keyboard area with
                // the offline state, mirroring Coinbase's amount screen.
                NetworkUnavailableStateView()
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .padding(.horizontal, Layout.hPadding)
            }
        }
        .sheet(isPresented: $showLocalCurrency) {
            let dialog = BottomSheet(
                showBackButton: Binding<Bool>.constant(false)
            ) {
                LocalCurrencyView { code in
                    viewModel.selectFiatCurrency(code)
                    showLocalCurrency = false
                }
            }

            if #available(iOS 16.0, *) {
                dialog.presentationDetents([.large])
            } else {
                dialog
            }
        }
    }

    // MARK: - Top Section

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
            EnterAmountView(
                value: $viewModel.inputValue,
                selectedCurrency: $viewModel.selectedCurrency,
                options: viewModel.currencyOptions,
                onMax: { viewModel.setMax() },
                onCurrencyTap: { showLocalCurrency = true }
            )
            .frame(height: 70)
            conversionCard
            receiveSection
        }
        .padding(.horizontal, Layout.hPadding)
        .padding(.top, Layout.topPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: viewModel.inputValue.isEmpty)
    }

    // MARK: - Conversion Card

    /// One-directional (Dash → coin) card built on DashUIKit's `ConverterCard`. No `onSwap`, so it
    /// shows the static `arrow-down` badge. The Dash row keeps its formatted entered-amount balance
    /// and the coin row keeps the remote icon + full (unwrapped) address.
    private var conversionCard: some View {
        ConverterCard(
            fromItem: ConverterCardItem(
                icon: .custom("dashCircleFilled", bundle: .main),
                title: NSLocalizedString("Dash", comment: "Maya"),
                subtitle: NSLocalizedString("Dash Wallet", comment: "Maya"),
                trailingView: AnyView(
                    DashBalanceView(
                        balance: viewModel.enteredDashFormatted,
                        fiat: viewModel.enteredAmountIsZero ? nil : viewModel.enteredFiatFormatted
                    )
                )
            ),
            toItem: ConverterCardItem(
                iconView: AnyView(MayaCoinIconView(coin: viewModel.coin, size: Layout.iconSize, cornerRadius: 7)),
                title: viewModel.coin.name,
                subtitle: viewModel.address,
                subtitleLineLimit: nil,
                showsBalance: false
            )
        )
    }

    // MARK: - Receive Section

    @ViewBuilder
    private var receiveSection: some View {
        if !viewModel.inputValue.isEmpty {
            VStack(alignment: .center, spacing: 0) {
                if viewModel.isLoading {
                    SwiftUI.ProgressView()
                } else if let error = viewModel.errorMessage {
                    // An error (e.g. insufficient balance after coin-mode gross-up) supersedes the
                    // receive estimate — both can be set at once, so show the error first.
                    Text(error)
                        .font(.caption1)
                        .foregroundStyle(Color.systemRed)
                } else if let amount = viewModel.receiveAmount {
                    Text(NSLocalizedString("Receive amount", comment: "Maya"))
                        .font(.caption1)
                        .foregroundStyle(Color.tertiaryText)

                    Text("~ \(amount)")
                        .font(.subhead)
                        .foregroundStyle(Color.primaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
        }
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        NumericKeyboardView(
            value: Binding(
                get: { viewModel.inputValue },
                set: { viewModel.setInput($0) }
            ),
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Continue", comment: ""),
            actionEnabled: viewModel.canOpenOrderPreview,
            inProgress: viewModel.isLoading,
            actionHandler: onContinue
        )
        .frame(maxWidth: .infinity, maxHeight: 320)
        .padding(.horizontal, Layout.hPadding)
        .background(Color.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .background(Color.secondaryBackground, ignoresSafeAreaEdges: .bottom)
    }
}

#if DEBUG
#Preview {
    MayaConvertView(
        viewModel: MayaConvertViewModel(
            coin: MayaCryptoCurrency.supportedCoins[0],
            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        ),
        onBack: {}
    )
    .background(Color.primaryBackground)
}
#endif
