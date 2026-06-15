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

// MARK: - CurrencyOption

enum CurrencyOption: Hashable {
    case fiat(String)
    case dash
    case coin(String)

    var isFiat: Bool {
        if case .fiat = self { return true }
        return false
    }

    var isCoinInput: Bool {
        if case .coin = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .fiat(let code): return code
        case .dash: return "DASH"
        case .coin(let code): return code
        }
    }

    var symbol: String? {
        switch self {
        case .fiat(let code):
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = code
            return formatter.currencySymbol
        case .dash: return nil
        case .coin(let code): return code
        }
    }
}

// MARK: - EnterAmountView

struct EnterAmountView: View {

    @Binding var value: String
    @Binding var selectedCurrency: CurrencyOption
    var options: [CurrencyOption]
    var onMax: (() -> Void)?
    var onCurrencyTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            maxButton
            amountView
            currencyPickerView
        }
    }

    private var maxButton: some View {
        Button {
            onMax?()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.blueAlpha5)
                    .frame(width: 40, height: 40)

                Text(NSLocalizedString("Max", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(Color.blue)
            }
        }
    }

    private var amountView: some View {
        MayaAmountView(
            amount: value,
            symbol: selectedCurrency.symbol,
            showDashLogo: selectedCurrency == .dash,
            showCurrencyButton: selectedCurrency.isFiat,
            onCurrencyTap: onCurrencyTap
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currencyPickerView: some View {
        DashPickerView(
            options: options,
            title: { $0.displayName },
            selected: $selectedCurrency
        )
    }

}

#if DEBUG
#Preview {
    EnterAmountView(
        value: .constant("12.5"),
        selectedCurrency: .constant(.dash),
        options: [.fiat("USD"), .dash, .coin("BTC")]
    )
    .frame(height: 110)
    .background(.red.opacity(0.3))
    .padding(20)
}
#endif
