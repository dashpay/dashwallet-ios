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

// MARK: - SwapAmountView

struct SwapAmountView: View {

    let amount: String
    var symbol: String? = nil
    var secondaryText: String? = nil
    var topText: String? = nil
    var bottomText: String? = nil
    var showDashLogo: Bool = false
    var showCurrencyButton: Bool = false
    var onCurrencyTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 2) {
            if let top = topText {
                Text(top)
                    .font(.caption1)
                    .foregroundStyle(Color.tertiaryText)
            }

            VStack(spacing: 0) {
                primaryRow

                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.subhead)
                        .foregroundStyle(Color.tertiaryText)
                }
            }

            if let bottom = bottomText {
                Text(bottom)
                    .font(.caption1)
                    .foregroundStyle(Color.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryRow: some View {
        // Amount (symbol + number + logo) and the currency chevron scale down together as ONE
        // centered unit, so the chevron stays right next to the amount instead of being pushed to
        // the far edge (scaleToFitWidth fills the width, so it must wrap the whole group, not just
        // the amount). Renders full-size when it fits; shrinks uniformly when it doesn't.
        HStack(spacing: 6) {
            amountView
                .foregroundStyle(Color.primaryText)

            if showCurrencyButton {
                Button {
                    onCurrencyTap?()
                } label: {
                    Image("chevron-down-currency-select")
                        .frame(width: 10, height: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .scaleToFitWidth()
        .frame(maxWidth: .infinity)
    }

    /// The numeric string as shown to the user. Pure display transform:
    /// - empty → "0"
    /// - bare-decimal input gets a leading zero: ".34" → "0.34", "." → "0." (same for ",")
    /// Does NOT trim, reformat, or cap precision — that happens upstream in `sanitize`.
    private var displayAmount: String {
        guard !amount.isEmpty else { return "0" }
        if let first = amount.first, first == "." || first == "," {
            return "0" + amount
        }
        return amount
    }

    private var amountView: some View {
        HStack(spacing: 4) {
            if let sym = symbol, !sym.isEmpty {
                Text(sym)
                    .font(.largeTitle)
            }

            Text(displayAmount)
                .font(.largeTitle)

            if showDashLogo {
                Image("enter-amount-dash")
            }
        }
    }
}

#if DEBUG
#Preview("Normal amounts") {
    VStack(spacing: 20) {
        SwapAmountView(
            amount: "1.5",
            secondaryText: "$ 150.00",
            topText: "Enter amount",
            showDashLogo: true
        )
        SwapAmountView(
            amount: "100",
            symbol: "$",
            secondaryText: "Ð 1.0",
            showCurrencyButton: true
        )
    }
    .padding(20)
}

#Preview("Edge cases — scaling") {
    VStack(spacing: 20) {
        // Long Dash amount: icon + text must both shrink
        SwapAmountView(
            amount: "99999.99999999",
            topText: "Dash — very long",
            showDashLogo: true
        )
        // Long fiat — currency button must stay visible
        SwapAmountView(
            amount: "123456.78",
            symbol: "$",
            topText: "Fiat — long with button",
            showCurrencyButton: true
        )
        // Long crypto
        SwapAmountView(
            amount: "0.00012345",
            symbol: "BTC",
            topText: "Crypto — small value"
        )
    }
    .padding(20)
}

#Preview("Edge cases — precision") {
    VStack(spacing: 20) {
        // Fiat: 2 dp is the max; "0.1344255" sanitizes to "0.13"
        SwapAmountView(
            amount: "0.13",
            symbol: "$",
            topText: "Fiat 0.13 (max 2 dp)",
            showCurrencyButton: true
        )
        // Leading-zero normalized: "01" → "1"
        SwapAmountView(
            amount: "1",
            topText: "Normalized from 01 → 1",
            showDashLogo: true
        )
        // In-progress decimal "0." — preserved
        SwapAmountView(
            amount: "0.",
            symbol: "$",
            topText: "In-progress: 0.",
            showCurrencyButton: true
        )
    }
    .padding(20)
}

#Preview("Leading zero — bare decimal") {
    VStack(spacing: 20) {
        // Bare decimal: ".34" renders as "0.34"
        SwapAmountView(
            amount: ".34",
            topText: "Bare decimal: .34 → 0.34",
            showDashLogo: true
        )
        // In-progress: just the decimal key tapped — "." renders as "0."
        SwapAmountView(
            amount: ".",
            symbol: "$",
            topText: "In-progress: . → 0.",
            showCurrencyButton: true
        )
    }
    .padding(20)
}
#endif
