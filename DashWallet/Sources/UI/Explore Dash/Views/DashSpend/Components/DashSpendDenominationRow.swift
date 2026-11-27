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
import DashUIKit

struct DashSpendDenominationRow: View {
    /// The card value, formatted in the card currency.
    let label: String
    @Binding var count: Int
    var inventoryLimit: Int? = nil

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Icon(name: .custom("icon-gift_card-piggy_cards", maxHeight: 26))

                Text(label)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.dash.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashStepper(count: $count, maxCount: inventoryLimit)
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        DashSpendDenominationRowPreview(label: "$5")
        DashSpendDenominationRowPreview(label: "$25")
        DashSpendDenominationRowPreview(label: "$100")
    }
    .padding(20)
    .background(Color.dash.secondaryBackground)
    .cornerRadius(20)
    .padding(20)
}

private struct DashSpendDenominationRowPreview: View {
    let label: String
    @State private var count = 0

    var body: some View {
        DashSpendDenominationRow(
            label: label,
            count: $count
        )
    }
}
