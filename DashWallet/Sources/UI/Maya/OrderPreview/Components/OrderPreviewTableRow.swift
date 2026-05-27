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

struct OrderPreviewTableRow: View {
    let leading: String
    let trailing: String
    var trailingSecondary: String? = nil
    let rowHPadding: CGFloat
    let rowVPadding: CGFloat
    let labelSpacing: CGFloat
    let rowMinHeight: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: labelSpacing) {
            Text(leading)
                .font(.subheadMedium)
                .foregroundColor(.tertiaryText)
                .fixedSize()

            VStack(alignment: .trailing, spacing: 2) {
                Text(trailing)
                    .font(.subhead)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if let secondary = trailingSecondary {
                    Text(secondary)
                        .font(.subhead)
                        .foregroundColor(.primaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, rowHPadding)
        .padding(.vertical, rowVPadding)
        .frame(minHeight: rowMinHeight)
    }
}

#if DEBUG
#Preview("OrderPreviewTableRow") {
    OrderPreviewTableRow(
        leading: "Destination address",
        trailing: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        rowHPadding: 10,
        rowVPadding: 12,
        labelSpacing: 20,
        rowMinHeight: 46
    )
    .padding()
    .background(Color.secondaryBackground)
}
#endif
