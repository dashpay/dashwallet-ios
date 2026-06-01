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

struct OrderPreviewFeeRow: View {
    let feeTitle: String
    let feeText: String
    var feeTextSecondary: String? = nil
    let rowHPadding: CGFloat
    let rowVPadding: CGFloat
    let labelSpacing: CGFloat
    let infoSpacing: CGFloat
    let rowMinHeight: CGFloat

    // Sheet state lives here: the row owns the info icon and is the natural
    // owner of its tap target. OrderPreviewView is not involved.
    @State private var showInfoSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: labelSpacing) {
            HStack(spacing: infoSpacing) {
                Text(feeTitle)
                    .font(.subheadMedium)
                    .foregroundColor(.tertiaryText)

                ZStack {
                    Circle()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Color.gray300)

                    Icon(name: .custom("info-icon", maxHeight: 8))
                }
                .contentShape(Circle())
                .onTapGesture { showInfoSheet = true }
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(feeText)
                    .font(.subhead)
                    .foregroundColor(.primaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if let secondary = feeTextSecondary {
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
        .sheet(isPresented: $showInfoSheet) {
            BottomSheet(showBackButton: .constant(false), fillsHeight: false) {
                MayaFeeInfoSheet(onDismiss: { showInfoSheet = false })
            }
            .selfSizingSheet(cornerRadius: 32)
        }
    }
}

#if DEBUG
#Preview("OrderPreviewFeeRow") {
    OrderPreviewFeeRow(
        feeTitle: "Maya fee",
        feeText: "BTC 0.00042",
        rowHPadding: 10,
        rowVPadding: 12,
        labelSpacing: 20,
        infoSpacing: 6,
        rowMinHeight: 46
    )
    .padding()
    .background(Color.secondaryBackground)
}
#endif
