//
//  Created by Roman Chornyi
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

struct DashSpendDenominationRow: View {
    let denomination: Decimal
    @Binding var count: Int
    var inventoryLimit: Int? = nil

    private let fiatFormatter: NumberFormatter = {
        let formatter = NumberFormatter.fiatFormatter(currencyCode: kDefaultCurrencyCode)
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Icon(name: .custom("icon-gift_card-piggy_cards", maxHeight: 26))

                Text(fiatFormatter.string(from: NSDecimalNumber(decimal: denomination)) ?? "")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashStepper(count: $count, maxCount: inventoryLimit)
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        DashSpendDenominationRowPreview(denomination: 5)
        DashSpendDenominationRowPreview(denomination: 25)
        DashSpendDenominationRowPreview(denomination: 100)
    }
    .padding(20)
    .background(Color.secondaryBackground)
    .cornerRadius(20)
    .padding(20)
}

private struct DashSpendDenominationRowPreview: View {
    let denomination: Decimal
    @State private var count = 0

    var body: some View {
        DashSpendDenominationRow(
            denomination: denomination,
            count: $count
        )
    }
}
