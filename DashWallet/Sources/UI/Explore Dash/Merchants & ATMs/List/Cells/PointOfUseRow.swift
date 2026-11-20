//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import SDWebImageSwiftUI
import SwiftUI

// MARK: - PointOfUseRow

/// One row of the ATM or Where to Spend list: logo, name, distance, and the
/// merchant's discount and payment method or the ATM's operations.
/// `PointOfUseListViewModel.rowModel(for:)` decides what it shows.
struct PointOfUseRow: View {
    let model: PointOfUseRowModel

    /// The row's height at the default text size; it grows with larger text.
    static let minHeight: CGFloat = 56

    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var subtitleSize: CGFloat = 11

    private enum Layout {
        static let spacing: CGFloat = 15
        static let textSpacing: CGFloat = 2
        static let logoSide: CGFloat = 36
        static let logoCornerRadius: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
    }

    var body: some View {
        HStack(spacing: Layout.spacing) {
            logo

            VStack(alignment: .leading, spacing: Layout.textSpacing) {
                Text(model.title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundColor(Color(UIColor.dw_label()))
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: subtitleSize))
                        .foregroundColor(Color(UIColor.dw_secondaryText()))
                }
            }

            Spacer(minLength: 0)

            accessory
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: Self.minHeight)
        // Hosted in a table cell, the separator would start at the text; the
        // list draws it 20pt from the edge.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 20 }
        .accessibilityElement(children: .combine)
    }

    private var logo: some View {
        WebImage(url: model.logoURL) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            // The same rendered placeholder the UIKit cell used, so its text
            // fits the 36pt logo the same way.
            Image(uiImage: MerchantLogoPlaceholder.image(merchantName: model.title,
                                                         size: CGSize(width: Layout.logoSide, height: Layout.logoSide),
                                                         cornerRadius: Layout.logoCornerRadius))
        }
        .frame(width: Layout.logoSide, height: Layout.logoSide)
        .clipShape(RoundedRectangle(cornerRadius: Layout.logoCornerRadius))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var accessory: some View {
        switch model.accessory {
        case .merchant(let savings, let paymentMethod):
            if let savings {
                Text(savings)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundColor(Color(UIColor.dw_secondaryText()))
            }
            Image(paymentMethod == .giftCard ? "image.explore.dash.wts.payment.gift-card"
                                             : "image.explore.dash.wts.payment.dash")
                .frame(width: 24, height: 24)
                .accessibilityLabel(paymentMethod == .giftCard
                    ? NSLocalizedString("Gift card", comment: "Explore Dash")
                    : NSLocalizedString("Pay with Dash", comment: "Explore Dash"))
        case .atm(let buy, let sell):
            HStack(spacing: 5) {
                if buy { AtmOperationTag(operation: .buy) }
                if sell { AtmOperationTag(operation: .sell) }
            }
        case .none:
            EmptyView()
        }
    }
}

// MARK: - AtmOperationTag

private struct AtmOperationTag: View {
    enum Operation {
        case buy
        case sell
    }

    let operation: Operation

    @ScaledMetric(relativeTo: .caption2) private var fontSize: CGFloat = 10

    var body: some View {
        Text(operation == .buy ? NSLocalizedString("Buy", comment: "Buy")
                               : NSLocalizedString("Sell", comment: "Sell"))
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .frame(minHeight: 20)
            .background(Color(operation == .buy ? UIColor.dw_green() : UIColor.dw_dashBlue()))
            .clipShape(Capsule())
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Merchant rows") {
    VStack(spacing: 0) {
        PointOfUseRow(model: .init(title: "Starbucks", logoURL: nil, subtitle: "52 m",
                                   accessory: .merchant(savings: "~2%", paymentMethod: .giftCard)))
        PointOfUseRow(model: .init(title: "Blue Tulip", logoURL: nil, subtitle: "9,068 km",
                                   accessory: .merchant(savings: nil, paymentMethod: .dash)))
        PointOfUseRow(model: .init(title: "Grubhub", logoURL: nil, subtitle: nil,
                                   accessory: .merchant(savings: nil, paymentMethod: .giftCard)))
    }
    .background(Color(UIColor.dw_secondaryBackground()))
}

#Preview("ATM rows") {
    VStack(spacing: 0) {
        PointOfUseRow(model: .init(title: "Bitcoin Depot", logoURL: nil, subtitle: "1.2 km • CoinFlip",
                                   accessory: .atm(buy: true, sell: true)))
        PointOfUseRow(model: .init(title: "Athena Bitcoin", logoURL: nil, subtitle: "Athena",
                                   accessory: .atm(buy: false, sell: true)))
    }
    .background(Color(UIColor.dw_secondaryBackground()))
}
#endif
