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

// MARK: - MayaAmountView

struct MayaAmountView: View {

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
        HStack(spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                amountText
                    .font(.largeTitle)
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .allowsTightening(true)
                    .layoutPriority(1)

                if showDashLogo {
                    Icon(name: .custom("dash-logo-black", maxHeight: 20))
                }
            }

            if showCurrencyButton {
                Button {
                    onCurrencyTap?()
                } label: {
                    Icon(name: .custom("chevron-down-icon", maxHeight: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var amountText: Text {
        let valueText = Text(amount.isEmpty ? "0" : amount)
        guard let sym = symbol, !sym.isEmpty else {
            return valueText
        }

        return Text(sym + " ") + valueText
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        MayaAmountView(
            amount: "1.5",
            symbol: "Ð",
            secondaryText: "$ 150.00",
            topText: "Enter amount",
            showDashLogo: true
        )
        MayaAmountView(
            amount: "100",
            symbol: "$",
            secondaryText: "Ð 1.0"
        )
    }
    .padding(20)
}
#endif
