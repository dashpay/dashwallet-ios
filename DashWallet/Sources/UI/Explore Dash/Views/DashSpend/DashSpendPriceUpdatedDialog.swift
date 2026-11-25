//
//  Created for Dash Wallet.
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

/// Shown when a gift card provider asks for more Dash than the buyer confirmed: the two
/// prices, the difference, and the choice to pay the new price or cancel.
struct DashSpendPriceUpdatedDialog: View {
    let change: GiftCardPaymentGuard.PriceChange
    /// The most height the dialog may take; `nil` for its natural height. When the content
    /// is taller, the prices and the warning scroll and the buttons stay in place below them.
    var maxHeight: CGFloat? = nil
    let onPay: () -> Void
    let onCancel: () -> Void

    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: kDefaultCurrencyCode)

    private func fiat(_ amount: Decimal) -> String {
        fiatFormatter.string(from: NSDecimalNumber(decimal: amount)) ?? ""
    }

    private var approximateRequestedFiat: String { "≈ " + fiat(change.requestedFiat) }

    private var increasePercent: String {
        PercentageFormatter.format(percent: Self.percent(of: change.increaseFraction))
    }

    /// The increase in percent, to one decimal below 10% and to a whole percent from there.
    /// Rounded down, so an increase just under the warning level is not shown as that level.
    static func percent(of fraction: Decimal) -> Double {
        var percent = fraction * 100
        guard percent.isFinite else { return 0 }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &percent, percent < 10 ? 1 : 0, .down)
        return NSDecimalNumber(decimal: rounded).doubleValue
    }

    private var payButtonText: String {
        let amount = GiftCardAmountText.exactDash(change.requestedAmount)
        return String(localized: "Pay \(amount)", comment: "DashSpend: pay the Dash amount that follows")
    }

    var body: some View {
        DashSpendSheetBody(maxHeight: maxHeight) {
            VStack(spacing: 4) {
                Text(fiat(change.requestedFiat))
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                DashSpendDashFigure(text: GiftCardAmountText.exactDash(change.requestedAmount),
                                    color: .dash.blue)
            }
            .foregroundColor(.dash.blue)
            .padding(.horizontal, 20)

            details
        } buttons: {
            buttons
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            DashSpendDetailsRow(title: String(localized: "You confirmed", comment: "DashSpend")) {
                figures(fiat(change.confirmedFiat),
                        dash: GiftCardAmountText.approximateDash(change.confirmedAmount))
            }

            DashSpendDetailsRow(title: String(localized: "Provider asks", comment: "DashSpend")) {
                figures(approximateRequestedFiat,
                        dash: GiftCardAmountText.exactDash(change.requestedAmount))
            }

            DashSpendDetailsRow(title: String(localized: "Difference", comment: "DashSpend")) {
                figures("+\(increasePercent) · \(fiat(change.differenceFiat))",
                        dash: "+" + GiftCardAmountText.exactDash(change.differenceAmount))
            }

            if change.needsWarning {
                DashSpendDetailsRow(title: String(localized: "Final price", comment: "DashSpend")) {
                    Text(approximateRequestedFiat)
                        .font(.subhead)
                        .foregroundColor(.dash.primaryText)
                }

                warning
            }
        }
        .padding(6)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(20)
        .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
    }

    private func figures(_ fiat: String, dash: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(fiat)
                .font(.subhead)
                .foregroundColor(.dash.primaryText)
            DashSpendDashFigure(text: dash, font: .footnote, symbolSize: 10, color: .dash.secondaryText)
        }
    }

    /// The app's standard caution box, on the same yellow as its other cautions.
    private var warning: some View {
        DashUIKit.SystemMessageView(
            title: String(localized: "The price is \(increasePercent) higher than expected",
                          comment: "DashSpend: the value is a percentage"),
            subtitle: String(
                localized: "This can mean the market moved fast or the provider's price is wrong. If you're not sure, cancel and try again in a few minutes.",
                comment: "DashSpend"),
            backgroundColor: Color.dash.yellowAlpha10)
            .padding(8)
            .accessibilityElement(children: .combine)
    }

    /// Paying is the main action for a small increase; from the warning level on, cancelling is.
    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            if change.needsWarning {
                DashButton(text: String(localized: "Cancel purchase", comment: "DashSpend"), action: onCancel)

                DashButton(text: payButtonText,
                           trailingIcon: .custom("icon_dash_currency", maxHeight: 13),
                           style: .tintedBlue,
                           action: onPay)
                    .accessibilityLabel(payAccessibilityLabel)
            } else {
                DashButton(text: payButtonText,
                           trailingIcon: .custom("icon_dash_currency", maxHeight: 13),
                           action: onPay)
                    .accessibilityLabel(payAccessibilityLabel)

                DashButton(text: String(localized: "Cancel", comment: "DashSpend"), action: onCancel)
                    .overrideForegroundColor(.dash.primaryText)
                    .overrideBackgroundColor(.dash.gray300Alpha10)
            }
        }
    }

    private var payAccessibilityLabel: String {
        String(localized: "\(payButtonText) DASH", comment: "DashSpend: a Dash amount read by VoiceOver")
    }
}

#Preview("Below the warning level") {
    DashSpendPriceUpdatedDialog(
        change: GiftCardPaymentGuard.PriceChange(
            confirmedAmount: 493_700_000, confirmedFiat: 192.50,
            requestedAmount: 513_440_000, requestedFiat: 200.20, needsWarning: false),
        onPay: {}, onCancel: {})
        .background(Color.dash.primaryBackground)
}

#Preview("Warning") {
    DashSpendPriceUpdatedDialog(
        change: GiftCardPaymentGuard.PriceChange(
            confirmedAmount: 493_700_000, confirmedFiat: 192.50,
            requestedAmount: 552_940_000, requestedFiat: 215.60, needsWarning: true),
        onPay: {}, onCancel: {})
        .background(Color.dash.primaryBackground)
}
