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
import SDWebImageSwiftUI

struct DashSpendConfirmationDialog: View {
    let merchantName: String
    let merchantIconUrl: String
    let originalPrice: Decimal
    let discount: Decimal
    let quantities: [Decimal: Int]?
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
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(red: 0.69, green: 0.71, blue: 0.74).opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 13)

            Text(NSLocalizedString("Confirm", comment: "DashSpend"))
                .font(.calloutMedium)
                .foregroundColor(.primaryText)
                .frame(height: 44)

            VStack(spacing: 20) {
                DashSpendAmountView(
                    currencySymbol: fiatFormatter.currencySymbol,
                    amount: formattedPayAmount
                )
                .frame(height: 85)

                VStack(alignment: .leading, spacing: 2) {
                    detailsRow(title: NSLocalizedString("From", comment: "DashSpend")) {
                        HStack(spacing: 8) {
                            Image("image.explore.dash.wts.dash")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text(NSLocalizedString("Dash Wallet", comment: "DashSpend"))
                                .font(.subhead)
                                .foregroundColor(.primaryText)
                        }
                    }

                    detailsRow(title: NSLocalizedString("To", comment: "DashSpend")) {
                        HStack(spacing: 8) {
                            WebImage(url: URL(string: merchantIconUrl))
                                .resizable()
                                .indicator(.activity)
                                .transition(.fade(duration: 0.3))
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text(merchantName)
                                .font(.subhead)
                                .foregroundColor(.primaryText)
                        }
                    }

                    detailsRow(title: NSLocalizedString("Gift card", comment: "DashSpend")) {
                        Text(fiatFormatter.string(from: NSDecimalNumber(decimal: originalPrice)) ?? "")
                            .font(.subhead)
                            .foregroundColor(.primaryText)
                    }

                    if !quantityLines.isEmpty {
                        detailsRow(title: NSLocalizedString("Quantity", comment: "DashSpend")) {
                            VStack(alignment: .trailing, spacing: 2) {
                                ForEach(quantityLines, id: \.self) { line in
                                    Text(line)
                                        .font(.subhead)
                                        .foregroundColor(.primaryText)
                                }
                            }
                        }
                    }

                    detailsRow(title: NSLocalizedString("Discount", comment: "DashSpend")) {
                        Text(PercentageFormatter.format(percent: NSDecimalNumber(decimal: discount * 100).doubleValue))
                            .font(.subhead)
                            .foregroundColor(.primaryText)
                    }

                    detailsRow(title: NSLocalizedString("You pay", comment: "DashSpend")) {
                        Text(fiatFormatter.string(from: NSDecimalNumber(decimal: youPayAmount)) ?? "")
                            .font(.subhead)
                            .foregroundColor(.primaryText)
                    }
                }
                .padding(6)
                .background(Color.secondaryBackground)
                .cornerRadius(20)
                .shadow(color: Color(red: 0.72, green: 0.76, blue: 0.8).opacity(0.1), radius: 20, x: 0, y: 5)

                HStack(spacing: 20) {
                    DashButton(
                        text: NSLocalizedString("Cancel", comment: "DashSpend"),
                        action: onCancel
                    )
                    .overrideForegroundColor(.primaryText)
                    .overrideBackgroundColor(.gray300Alpha10)

                    DashButton(
                        text: NSLocalizedString("Confirm", comment: "DashSpend"),
                        action: onConfirm
                    )
                }
                .padding(.horizontal, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        // Publish the natural height so `.selfSizingSheet()` (which reads
        // `BottomSheetHeightPreferenceKey`) can size the sheet. This dialog is not a `BottomSheet`,
        // so without this the modifier never gets a measurement and falls back to `.medium`, which
        // is too short and lets the content overflow above the sheet. `.fixedSize(vertical:)` keeps
        // the measurement stable (decoupled from the offered height) like the BottomSheet does.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BottomSheetHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
    }

    private func detailsRow(title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subhead)
                .fontWeight(.medium)
                .foregroundColor(.tertiaryText)

            Spacer()

            value()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
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
            let content = DashSpendConfirmationDialog(
                merchantName: "Amazon",
                merchantIconUrl: "",
                originalPrice: 75.70,
                discount: 0.10,
                quantities: [50: 1, 25: 2],
                onConfirm: {},
                onCancel: {}
            )

            if #available(iOS 16.4, *) {
                content
                    .presentationBackground(Color.primaryBackground)
                    .selfSizingSheet()
                    .presentationCornerRadius(32)
                    .presentationDragIndicator(.hidden)
            } else if #available(iOS 16.0, *) {
                content
                    .selfSizingSheet()
                    .presentationDragIndicator(.hidden)
            } else {
                content
            }
        }
    }
}
