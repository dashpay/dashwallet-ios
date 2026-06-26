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

// MARK: - DashBalanceView

/// Trailing balance for the convert source row: a symbol-free Dash amount followed by the Dash
/// symbol, with the fiat value beneath. Both strings come from `MayaConvertViewModel`
/// (`dashBalanceFormatted` / `dashBalanceFiat`); pass `fiat: nil` to hide the fiat line.
struct DashBalanceView: View {
    /// Symbol-free formatted balance, e.g. "1.5".
    let balance: String
    /// Formatted fiat value; `nil` hides the line (e.g. zero balance).
    var fiat: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 6) {
                Text(balance)
                    .font(.subhead)
                    .lineLimit(1)

                dashSymbol
            }
            .foregroundStyle(Color.primaryText)

            if let fiat {
                Text(fiat)
                    .font(.caption)
                    .foregroundColor(.primaryText)
            }
        }
    }

    private var dashSymbol: some View {
        Image("icon_dash_currency")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 12, height: 10)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        DashBalanceView(balance: "1.5", fiat: "$ 150.00")
        DashBalanceView(balance: "0", fiat: nil)
    }
    .padding()
    .background(Color.secondaryBackground)
}
#endif
