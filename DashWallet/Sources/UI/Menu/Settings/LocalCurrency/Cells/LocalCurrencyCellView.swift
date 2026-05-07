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

struct LocalCurrencyCellView: View {

    private enum Layout {
        static let spacing: CGFloat = 16
        static let horizontalPadding: CGFloat = 10
        static let flagSize: CGFloat = 30
        static let checkboxSize: CGFloat = 22
        static let checkboxSelectedBorderWidth: CGFloat = 5
        static let checkboxDefaultBorderWidth: CGFloat = 1.5
        static let trailingSpacing: CGFloat = 10
        static let infoVerticalPadding: CGFloat = 10
        static let infoSpacing: CGFloat = 1
    }

    let item: CurrencyItem
    let isSelected: Bool
    let searchQuery: String

    var body: some View {
        HStack(spacing: Layout.spacing) {
            flagSection
            infoSection
            trailingSection
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .clipShape(.rect)
    }

    private var flagSection: some View {
        Group {
            if let flagName = item.flagName, UIImage(named: flagName) != nil {
                Image(flagName)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray200
            }
        }
        .frame(width: Layout.flagSize, height: Layout.flagSize)
        .clipShape(.circle)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: Layout.infoSpacing) {
            highlightedText(item.name, query: searchQuery)
                .font(.subhead.weight(.medium))
                .foregroundColor(.primaryText)
                .lineLimit(1)

            if let priceString = item.priceString {
                Text(priceString)
                    .font(.footnote)
                    .foregroundColor(.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Layout.infoVerticalPadding)
    }

    private var trailingSection: some View {
        HStack(spacing: Layout.trailingSpacing) {
            currencyCodeView
            checkboxView
        }
    }

    private var currencyCodeView: some View {
        highlightedText(item.code, query: searchQuery)
            .font(.caption1)
            .foregroundColor(.tertiaryText)
            .lineLimit(1)
    }

    private var checkboxView: some View {
        Circle()
            .strokeBorder(
                isSelected ? Color.dashBlue : Color.gray300,
                lineWidth: isSelected ? Layout.checkboxSelectedBorderWidth : Layout.checkboxDefaultBorderWidth
            )
            .frame(width: Layout.checkboxSize, height: Layout.checkboxSize)
    }

    /// Builds a SwiftUI Text with the first occurrence of `query` highlighted in dashBlue.
    private func highlightedText(_ text: String, query: String) -> Text {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let range = text.range(of: trimmed, options: .caseInsensitive) else {
            return Text(text)
        }
        let before = String(text[..<range.lowerBound])
        let match  = String(text[range])
        let after  = String(text[range.upperBound...])

        return Text("\(before)\(Text(match).foregroundColor(.dashBlue))\(after)")
    }
}

#Preview {
    VStack(spacing: 0) {
        // Selected
        LocalCurrencyCellView(
            item: CurrencyItem(code: "USD", name: "US Dollar", flagName: "united states", priceString: "38,01"),
            isSelected: true,
            searchQuery: ""
        )

        Divider()

        // Default
        LocalCurrencyCellView(
            item: CurrencyItem(code: "EUR", name: "Euro", flagName: "european union", priceString: "35,20"),
            isSelected: false,
            searchQuery: ""
        )

        Divider()

        // Search highlight
        LocalCurrencyCellView(
            item: CurrencyItem(code: "UAH", name: "Ukrainian Hryvnia", flagName: "algeria", priceString: "1 750,00"),
            isSelected: false,
            searchQuery: "ukr"
        )

        Divider()

        // No flag
        LocalCurrencyCellView(
            item: CurrencyItem(code: "XYZ", name: "Unknown Currency", flagName: nil, priceString: nil),
            isSelected: false,
            searchQuery: ""
        )
    }
    .padding(.horizontal)
}
