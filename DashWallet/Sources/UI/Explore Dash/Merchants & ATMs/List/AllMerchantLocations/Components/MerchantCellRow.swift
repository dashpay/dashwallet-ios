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

struct MerchantCellRow: View {
    let pointOfUse: ExplorePointOfUse
    let distanceText: String?

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                if let distanceText {
                    HStack(spacing: 8) {
                        Icon(name: .custom("image.explore.dash.distance", maxHeight: 15))
                        Text(distanceText)
                            .font(.footnote)
                            .foregroundStyle(Color.gray500)
                    }
                }

                Text(pointOfUse.address)
                    .font(.subhead)
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Icon(name: .custom("list-chevron-right", maxHeight: 10))
                .frame(width: 10)
        }
        .padding(20)
        .background(Color.gray300Alpha10)
        .clipShape(.rect(cornerRadius: 16))
    }
}

#if DEBUG
#Preview("With distance") {
    MerchantCellRow(
        pointOfUse: .previewMockMerchant(
            name: "Walmart",
            address1: "301 Massachusetts Ave",
            city: "Lunenburg",
            territory: "Massachusetts"
        ),
        distanceText: "2.4 km"
    )
    .padding()
}

#Preview("No distance (online merchant)") {
    MerchantCellRow(
        pointOfUse: .previewMockMerchant(
            name: "Walmart",
            address1: nil,
            city: "Rindge",
            territory: "New Hampshire"
        ),
        distanceText: nil
    )
    .padding()
}
#endif
