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

// MARK: - MenuCardStyle

private struct MenuCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
    }
}

// MARK: - MayaConvertView

struct MayaConvertView: View {

    private enum Layout {
        static let iconSize: CGFloat = 30
        static let hSpacing: CGFloat = 10
        static let textSpacing: CGFloat = 1
        static let padding: CGFloat = 10
        static let hPadding: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let contentSpacing: CGFloat = 20
        static let arrowIconSize: CGFloat = 24
        static let arrowIconHeight: CGFloat = 12
    }

    enum MenuItemState {
        case coin(MayaCryptoCurrency, address: String)
        case dash(balance: String)
    }

    @StateObject private var viewModel: MayaConvertViewModel
    @State private var showLocalCurrency = false
    private let onContinue: () -> Void

    init(viewModel: MayaConvertViewModel, onContinue: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            amountSection
            keyboard
        }
        .sheet(isPresented: $showLocalCurrency) {
            let dialog = BottomSheet(
                showBackButton: Binding<Bool>.constant(false)
            ) {
                LocalCurrencyView { code in
                    App.shared.fiatCurrency = code
                    viewModel.objectWillChange.send()
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
            .frame(height: 100)
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
        VStack(spacing: 2) {
            menuItem(state: .dash(balance: viewModel.dashBalance))
            arrowDivider
            menuItem(state: .coin(viewModel.coin, address: viewModel.address))
        }
        .modifier(MenuCardStyle())
    }

    private var arrowDivider: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray100)
                .frame(height: 1)
                .padding(.horizontal, Layout.padding)

            ZStack {
                Circle()
                    .stroke(Color.gray100, lineWidth: 1)
                    .frame(width: Layout.arrowIconSize, height: Layout.arrowIconSize)

                Icon(name: .custom("downarrow-icon", maxHeight: Layout.arrowIconHeight))
            }
            .background(Color.secondaryBackground)
        }
    }

    // MARK: - Receive Section

    @ViewBuilder
    private var receiveSection: some View {
        if !viewModel.inputValue.isEmpty {
            VStack(alignment: .center, spacing: 0) {
                if viewModel.isLoading {
                    SwiftUI.ProgressView()
                } else if let amount = viewModel.receiveAmount {
                    Text(NSLocalizedString("Receive amount", comment: "Maya"))
                        .font(.caption1)
                        .foregroundStyle(Color.tertiaryText)

                    Text("~ \(amount)")
                        .font(.subhead)
                        .foregroundStyle(Color.primaryText)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption1)
                        .foregroundStyle(Color.systemRed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
        }
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        NumericKeyboardView(
            value: $viewModel.inputValue,
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
    }

    // MARK: - Menu Item

    @ViewBuilder
    private func menuItem(state: MenuItemState) -> some View {
        HStack(spacing: Layout.hSpacing) {
            menuItemIcon(for: state)
            menuItemLabels(for: state)
            Spacer(minLength: 0)
            if case .dash(let balance) = state {
                balanceView(balance: balance)
                    .frame(maxWidth: .infinity, alignment: .trailing)

            }
        }
        .padding(Layout.padding)
    }

    // MARK: - Menu Item Subviews

    @ViewBuilder
    private func menuItemIcon(for state: MenuItemState) -> some View {
        switch state {
        case .coin(let coin, _):
            MayaCoinIconView(coin: coin, size: Layout.iconSize, cornerRadius: 7)
        case .dash:
            Icon(name: .custom("dashCircleFilled"))
                .frame(width: Layout.iconSize, height: Layout.iconSize)
        }
    }

    private func menuItemLabels(for state: MenuItemState) -> some View {
        VStack(alignment: .leading, spacing: Layout.textSpacing) {
            Text(menuItemTitle(for: state))
                .font(.subheadMedium)
                .foregroundColor(.primaryText)

            Text(menuItemSubtitle(for: state))
                .font(.footnote)
                .foregroundColor(.tertiaryText)
        }
    }

    private func menuItemTitle(for state: MenuItemState) -> String {
        switch state {
        case .coin(let coin, _): return coin.name
        case .dash: return NSLocalizedString("Dash", comment: "Maya")
        }
    }

    private func menuItemSubtitle(for state: MenuItemState) -> String {
        switch state {
        case .coin(_, let address): return address
        case .dash: return NSLocalizedString("Dash Wallet", comment: "Maya")
        }
    }

    private func balanceView(balance: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 4) {
                Text(String(format: NSLocalizedString("Balance: %@", comment: "Maya"), balance))
                    .font(.subhead)
                    .foregroundColor(.primaryText)

                Icon(name: .custom("dash-logo-black", maxHeight: 12))
            }

            Text(viewModel.dashBalanceFiat)
                .font(.caption1)
                .foregroundColor(.tertiaryText)
        }
    }
}

#if DEBUG
#Preview {
    MayaConvertView(
        viewModel: MayaConvertViewModel(
            coin: MayaCryptoCurrency.supportedCoins[0],
            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        )
    )
    .background(Color.primaryBackground)
    .padding(.top, 80)
}
#endif
