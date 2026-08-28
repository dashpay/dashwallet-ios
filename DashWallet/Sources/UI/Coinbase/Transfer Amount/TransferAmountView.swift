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

// MARK: - TransferAmountView

struct TransferAmountView<ViewModel: TransferAmountViewModelProtocol>: View {
    @StateObject private var viewModel: ViewModel
    @State private var showLocalCurrency = false
    private let onBack: (() -> Void)?

    init(viewModel: ViewModel, onBack: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onBack = onBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { NavigationBarElement.back.button { onBack?() } }
            )

            VStack(alignment: .leading, spacing: 20) {
                TopIntro(title: NSLocalizedString("Transfer DASH", comment: "Coinbase"))

                DashUIKit.EnterAmountView(
                    value: $viewModel.inputValue,
                    selectedCurrency: $viewModel.selectedCurrency,
                    options: viewModel.currencyOptions,
                    onMax: { viewModel.setMax() },
                    onCurrencyTap: { showLocalCurrency = true }
                )
                .frame(height: 70)

                ConverterCard(
                    fromItem: viewModel.fromItem.converterCardItem(showsBalance: true),
                    toItem: viewModel.toItem.converterCardItem(showsBalance: true),
                    onSwap: { viewModel.switchDirection() }
                )

                // Exact received amount ("22 DASH ≈ $6.04") — the network fee is added on top, so it
                // does not reduce this. An error (e.g. insufficient balance) supersedes it.
                ReceiveEstimateView(
                    isVisible: !viewModel.inputValue.isEmpty,
                    title: NSLocalizedString("You will receive", comment: "Coinbase"),
                    amount: viewModel.receiveAmount,
                    fiat: viewModel.receiveFiat,
                    errorMessage: viewModel.errorMessage,
                    approximate: false
                )
                .animation(.easeInOut(duration: 0.2), value: viewModel.receiveAmount)
                .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)

                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)

            if viewModel.isNetworkOnline {
                keyboard
            } else {
                NetworkUnavailableStateView()
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showLocalCurrency) {
            let dialog = DashUIKit.BottomSheet(showBackButton: Binding<Bool>.constant(false)) {
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

    // MARK: - Keyboard

    private var keyboard: some View {
        HardwareNumericKeyboardView(
            value: Binding(
                get: { viewModel.inputValue },
                set: { viewModel.setInput($0) }
            ),
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Transfer", comment: "Coinbase"),
            actionEnabled: viewModel.canContinue,
            inProgress: viewModel.isProcessing,
            actionHandler: { viewModel.transfer() }
        )
    }
}

// MARK: - TransferSourceItem → ConverterCardItem

private extension TransferSourceItem {
    /// Maps the app-level row data onto DashUIKit's `ConverterCardItem`.
    func converterCardItem(showsBalance: Bool) -> ConverterCardItem {
        ConverterCardItem(
            icon: .custom(iconAssetName, bundle: .main),
            title: title,
            subtitle: subtitle,
            dashBalance: dashBalance,
            fiat: fiatBalanceFormatted,
            showsBalance: showsBalance
        )
    }
}

#if DEBUG

// MARK: - Preview mock

/// Lightweight stand-in for `TransferAmountViewModel` so previews don't touch
/// `Coinbase.shared` / the network monitor. Intents mutate local state only.
@MainActor
final class MockTransferAmountViewModel: TransferAmountViewModelProtocol {
    @Published var inputValue: String
    @Published var selectedCurrency: DashUIKit.CurrencyOption = .dash
    @Published private(set) var fromItem: TransferSourceItem
    @Published private(set) var toItem: TransferSourceItem
    @Published private(set) var isNetworkOnline: Bool
    @Published private(set) var canContinue: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var receiveAmount: String?
    @Published private(set) var receiveFiat: String?

    var currencyOptions: [DashUIKit.CurrencyOption] { [.dash, .fiat("USD")] }

    init(
        inputValue: String = "0.5",
        isNetworkOnline: Bool = true,
        canContinue: Bool = true,
        errorMessage: String? = nil,
        receiveAmount: String? = "0.5 DASH",
        receiveFiat: String? = "$120.00"
    ) {
        self.inputValue = inputValue
        self.isNetworkOnline = isNetworkOnline
        self.canContinue = canContinue
        self.errorMessage = errorMessage
        self.receiveAmount = receiveAmount
        self.receiveFiat = receiveFiat
        self.fromItem = TransferSourceItem(
            title: "Coinbase",
            subtitle: nil,
            dashBalance: 420_000_000,
            fiatBalanceFormatted: "$410.00",
            iconAssetName: "Coinbase"
        )
        self.toItem = TransferSourceItem(
            title: "Dash",
            subtitle: kWalletName,
            dashBalance: 123_456_789,
            fiatBalanceFormatted: "$120.00",
            iconAssetName: "image.explore.dash.wts.dash"
        )
    }

    func setInput(_ raw: String) { inputValue = raw }
    func setMax() { inputValue = "4.2" }
    func switchDirection() { swap(&fromItem, &toItem) }
    func selectFiatCurrency(_ code: String) { selectedCurrency = .fiat(code) }
    func transfer() {}
}

#Preview("Online") {
    TransferAmountView(viewModel: MockTransferAmountViewModel())
        .background(Color.dash.primaryBackground)
}

#Preview("Offline") {
    TransferAmountView(viewModel: MockTransferAmountViewModel(isNetworkOnline: false))
        .background(Color.dash.primaryBackground)
}

#Preview("Error") {
    TransferAmountView(
        viewModel: MockTransferAmountViewModel(
            canContinue: false,
            errorMessage: NSLocalizedString("Amount too low", comment: "")
        )
    )
    .background(Color.dash.primaryBackground)
}
#endif
