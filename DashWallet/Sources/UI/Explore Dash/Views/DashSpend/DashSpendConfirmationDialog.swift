//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import SDWebImageSwiftUI

struct DashSpendConfirmationDialog: View {
    /// Detent used before `selfSizingSheet` has measured the sheet, so it doesn't
    /// present short and then jump. Covers this dialog's own natural height plus
    /// `DashUIKit.BottomSheet`'s chrome — an 18pt grabber and a 74pt header.
    /// Both presenters share this value; keep it here so they can't drift apart.
    static let sheetFallbackHeight: CGFloat = 690

    let merchantName: String
    let merchantIconUrl: String
    let originalPrice: Decimal
    let discount: Decimal
    /// What the buyer pays, in duffs at the wallet's rate.
    let dashAmount: UInt64
    let quantities: [Decimal: Int]?
    /// `true` once the buyer confirmed and the provider's answer is awaited.
    let isWaiting: Bool
    /// The most height the dialog may take; `nil` for its natural height. When the content
    /// is taller, the details scroll and the buttons stay in place below them.
    var maxHeight: CGFloat? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: kDefaultCurrencyCode)
    private var youPayAmount: Decimal { originalPrice * (1 - discount) }

    private var formattedPayAmount: String {
        let hasCents = youPayAmount != Decimal(Int(truncating: NSDecimalNumber(decimal: youPayAmount)))
        let formatter = NumberFormatter.fiatFormatter(currencyCode: kDefaultCurrencyCode)
        if !hasCents {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        }
        return formatter.string(from: NSDecimalNumber(decimal: youPayAmount))?.strippingCurrencySymbol(formatter) ?? ""
    }

    private var quantityLines: [String] {
        guard let quantities = quantities else { return [] }
        return quantities
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { denomination, count in
                let amount = fiatFormatter.string(from: NSDecimalNumber(decimal: denomination)) ?? "$\(denomination)"
                return "\(count) x \(amount)"
            }
    }

    var body: some View {
        DashSpendSheetBody(maxHeight: maxHeight) {
            VStack(spacing: 0) {
                DashSpendAmountView(
                    currencySymbol: fiatFormatter.currencySymbol,
                    amount: formattedPayAmount
                )
                .frame(height: 70)

                DashSpendDashFigure(text: GiftCardAmountText.approximateDash(dashAmount))
            }

            details
        } buttons: {
            VStack(spacing: 10) {
                DashButton(
                    text: NSLocalizedString("Confirm", comment: "DashSpend"),
                    isLoading: isWaiting,
                    action: onConfirm
                )

                DashButton(
                    text: NSLocalizedString("Cancel", comment: "DashSpend"),
                    isEnabled: !isWaiting,
                    action: onCancel
                )
                .overrideForegroundColor(.dash.primaryText)
                .overrideBackgroundColor(.dash.gray300Alpha10)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            detailsRow(title: NSLocalizedString("From", comment: "DashSpend")) {
                HStack(spacing: 8) {
                    Image("image.explore.dash.wts.dash")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("Dash Wallet", comment: "DashSpend"))
                        .font(.subhead)
                        .foregroundColor(.dash.primaryText)
                }
            }

            detailsRow(title: NSLocalizedString("To", comment: "DashSpend")) {
                HStack(spacing: 8) {
                    // The placeholder stands in while loading and on failure, so a
                    // missing or broken icon URL still shows the merchant's initials.
                    WebImage(url: URL(string: merchantIconUrl)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        // Rounded-rect clip (below), so the text may fill almost the
                        // whole box. Initials rather than the full name — at 20pt the
                        // name style hits the 6pt font floor and clips.
                        MerchantLogoPlaceholder(merchantName: merchantName,
                                                style: .initials,
                                                usableFraction: 0.84)
                    }
                    .transition(.fade(duration: 0.3))
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(merchantName)
                        .font(.subhead)
                        .foregroundColor(.dash.primaryText)
                }
            }

            detailsRow(title: NSLocalizedString("Gift card total", comment: "DashSpend")) {
                Text(fiatFormatter.string(from: NSDecimalNumber(decimal: originalPrice)) ?? "")
                    .font(.subhead)
                    .foregroundColor(.dash.primaryText)
            }

            if !quantityLines.isEmpty {
                detailsRow(title: NSLocalizedString("Quantity", comment: "DashSpend")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(quantityLines, id: \.self) { line in
                            Text(line)
                                .font(.subhead)
                                .foregroundColor(.dash.primaryText)
                        }
                    }
                }
            }

            detailsRow(title: NSLocalizedString("Discount", comment: "DashSpend")) {
                Text(PercentageFormatter.format(percent: NSDecimalNumber(decimal: discount * 100).doubleValue))
                    .font(.subhead)
                    .foregroundColor(.dash.primaryText)
            }

            detailsRow(title: NSLocalizedString("You pay", comment: "DashSpend")) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fiatFormatter.string(from: NSDecimalNumber(decimal: youPayAmount)) ?? "")
                        .font(.subhead)
                        .foregroundColor(.dash.primaryText)
                    DashSpendDashFigure(text: GiftCardAmountText.approximateDash(dashAmount),
                                        font: .footnote, symbolSize: 10, color: .dash.secondaryText)
                }
            }
        }
        .padding(6)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(20)
        .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
    }

    private func detailsRow(title: String, @ViewBuilder value: () -> some View) -> some View {
        DashSpendDetailsRow(title: title, value: value)
    }
}

/// The body of a DashSpend purchase sheet: content that scrolls when the sheet cannot be made
/// tall enough for it, above buttons that stay in place.
struct DashSpendSheetBody<Content: View, Buttons: View>: View {
    /// The most height the body may take; `nil` for its natural height.
    let maxHeight: CGFloat?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20, content: content)
                    .padding(.horizontal, 20)
                    // Room for the details card's shadow, which the scroll view would
                    // otherwise cut off.
                    .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            buttons()
                .padding(.horizontal, 30)
        }
        .padding(.bottom, 20)
        .frame(maxHeight: maxHeight)
        // Keep the height independent of the offered detent so DashUIKit's
        // `.selfSizingSheet()` can measure a stable one: the natural height, or `maxHeight`
        // when that is less.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One titled row of a DashSpend purchase sheet's details card.
struct DashSpendDetailsRow<Value: View>: View {
    let title: String
    let value: Value

    init(title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subhead)
                .fontWeight(.medium)
                .foregroundColor(.dash.tertiaryText)

            Spacer()

            value
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 46)
    }
}

/// A Dash amount followed by the Dash symbol, read by VoiceOver as one amount.
struct DashSpendDashFigure: View {
    /// The amount as shown, with any "≈" or "+" in front.
    let text: String
    var font: Font = .subhead
    var symbolSize: CGFloat = 12
    var color: Color = .dash.primaryText

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
                .font(font)
            Image("icon_dash_currency")
                .resizable()
                .scaledToFit()
                .frame(width: symbolSize, height: symbolSize)
        }
        .foregroundColor(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("%@ DASH", comment: "DashSpend: a Dash amount read by VoiceOver"), text))
    }
}

/// Dash amounts as the purchase sheets write them.
enum GiftCardAmountText {
    /// A Dash amount rounded to four decimals with "≈" in front: the price at the wallet's
    /// rate, which the provider's own quote will differ from.
    static func approximateDash(_ duffs: UInt64, locale: Locale = .current) -> String {
        "≈ " + dash(duffs, minimumFractionDigits: 4, maximumFractionDigits: 4, locale: locale)
    }

    /// A Dash amount in full: every decimal it has, and at least four.
    static func exactDash(_ duffs: UInt64, locale: Locale = .current) -> String {
        dash(duffs, minimumFractionDigits: 4, maximumFractionDigits: 8, locale: locale)
    }

    private static func dash(_ duffs: UInt64, minimumFractionDigits: Int, maximumFractionDigits: Int,
                             locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfEven
        let amount = Decimal(duffs) / Decimal(100_000_000)
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}

private extension String {
    func strippingCurrencySymbol(_ formatter: NumberFormatter) -> String {
        replacingOccurrences(of: formatter.currencySymbol, with: "").trimmingCharacters(in: .whitespaces)
    }
}

#Preview {
    DashSpendConfirmationDialogPreview()
}

private struct DashSpendConfirmationDialogPreview: View {
    @State private var isPresented = true

    var body: some View {
        VStack {
            Text("Tap to open")
                .onTapGesture { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            DashUIKit.BottomSheet.selfSizing(
                title: NSLocalizedString("Confirm", comment: "DashSpend"),
                showBackButton: .constant(false),
                fallback: DashSpendConfirmationDialog.sheetFallbackHeight,
                cornerRadius: 32
            ) {
                DashSpendConfirmationDialog(
                    merchantName: "Amazon",
                    merchantIconUrl: "",
                    originalPrice: 75.70,
                    discount: 0.10,
                    dashAmount: 174_690_000,
                    quantities: [50: 1, 25: 2],
                    isWaiting: false,
                    onConfirm: {},
                    onCancel: {}
                )
            }
        }
    }
}
