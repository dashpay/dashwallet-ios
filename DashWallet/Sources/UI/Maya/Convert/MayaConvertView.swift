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
    @State private var topMenuItemHeight: CGFloat = Layout.topMenuItemHeightFallback
    @State private var bottomMenuItemHeight: CGFloat = Layout.topMenuItemHeightFallback
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

    private var conversionCard: some View {
        VStack(spacing: Layout.cardSpacing) {
            MayaConvertCardRow(slot: .top) { dashSourceRow }
            MayaConvertCardRow(slot: .bottom) { coinDestinationRow }
        }
        .overlay(alignment: .top) {
            arrowDivider
                .offset(y: arrowCenterY - (Layout.arrowBadgeSize / 2) - Layout.cardSpacing - 3)
        }
        .onPreferenceChange(MayaConvertRowHeightKey.self) { heights in
            if let h = heights[.top], h > 0 { topMenuItemHeight = h }
            if let h = heights[.bottom], h > 0 { bottomMenuItemHeight = h }
        }
    }

    /// Source row: Dash / Dash Wallet with the trailing balance + fiat. Non-interactive
    /// (`action: nil`); the card chrome / non-interactivity live in `MayaConvertCardRow`.
    private var dashSourceRow: some View {
        MenuItem(
            title: NSLocalizedString("Dash", comment: "Maya"),
            subtitleView: AnyView(
                Text(NSLocalizedString("Dash Wallet", comment: "Maya"))
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            ),
            icon: .custom("dashCircleFilled"),
            trailingView: AnyView(
                DashBalanceView(
                    balance: viewModel.enteredDashFormatted,
                    fiat: viewModel.enteredAmountIsZero ? nil : viewModel.enteredFiatFormatted
                )
            ),
            action: nil
        )
    }

    /// Destination row: coin name / address with the remote coin icon. The address can be long,
    /// so its subtitle keeps the previous unlimited wrapping.
    private var coinDestinationRow: some View {
        MenuItem(
            title: viewModel.coin.name,
            subtitleView: AnyView(
                Text(viewModel.address)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            ),
            iconView: AnyView(MayaCoinIconView(coin: viewModel.coin, size: Layout.iconSize, cornerRadius: 7)),
            action: nil
        )
    }

    private var arrowCenterY: CGFloat {
        let topCenterY = topMenuItemHeight / 2
        let bottomCenterY = topMenuItemHeight + Layout.cardSpacing + (bottomMenuItemHeight / 2)
        return (topCenterY + bottomCenterY) / 2
    }

    private var arrowDivider: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.arrowBadgeCornerRadius, style: .continuous)
                .fill(Color.secondaryBackground)
                .frame(width: Layout.arrowBadgeSize + 5, height: Layout.arrowBadgeSize + 5)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.arrowBadgeCornerRadius, style: .continuous)
                        .stroke(Color.primaryBackground, lineWidth: Layout.arrowBadgeInset)
                )
                .overlay(
                    ArrowDownIcon(
                        size: CGSize(width: 6.6, height: 11),
                        color: Color(uiColor: UIColor(red: 0, green: 0.55, blue: 0.89, alpha: 1))
                    )
                )
        }
        .frame(height: Layout.arrowBadgeSize + 5)
        .padding(.horizontal, Layout.padding)
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
