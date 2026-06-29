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

import DashUIKit
import SwiftUI

struct DashSpendAmountView: View {
    let currencySymbol: String
    let amount: String

    var body: some View {
        DashUIKit.SwapAmountView(amount: amount, symbol: currencySymbol)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
    }
}

#Preview {
    DashSpendAmountView(currencySymbol: "$", amount: "42.50")
        .frame(height: 80)
        .background(Color.gray.opacity(0.1))
}
