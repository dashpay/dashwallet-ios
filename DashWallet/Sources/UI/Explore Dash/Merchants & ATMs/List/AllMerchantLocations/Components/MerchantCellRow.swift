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

    private enum Layout {
        static let rowSpacing: CGFloat = 20
        static let textSpacing: CGFloat = 4
        static let distanceSpacing: CGFloat = 8
        static let distanceIconHeight: CGFloat = 15
        static let chevronHeight: CGFloat = 10
        static let chevronWidth: CGFloat = 10
        static let addressLineLimit = 2
        static let contentPadding: CGFloat = 20
        static let cornerRadius: CGFloat = 16
    }

    private enum Asset {
        static let distanceIcon = "image.explore.dash.distance"
        static let chevronIcon = "list-chevron-right"
    }

    var body: some View {
        HStack(spacing: Layout.rowSpacing) {
            contentStack
            .frame(maxWidth: .infinity, alignment: .leading)

            chevron
        }
        .padding(Layout.contentPadding)
        .background(Color.gray300Alpha10)
        .clipShape(.rect(cornerRadius: Layout.cornerRadius))
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: Layout.textSpacing) {
            distanceLabel
            addressLabel
        }
    }

    @ViewBuilder
    private var distanceLabel: some View {
        if let distanceText {
            HStack(spacing: Layout.distanceSpacing) {
                Icon(name: .custom(Asset.distanceIcon, maxHeight: Layout.distanceIconHeight))
                Text(distanceText)
                    .font(.footnote)
                    .foregroundStyle(Color.gray500)
            }
        }
    }

    private var addressLabel: some View {
        Text(pointOfUse.address)
            .font(.subhead)
            .foregroundStyle(Color.primaryText)
            .lineLimit(Layout.addressLineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chevron: some View {
        Icon(name: .custom(Asset.chevronIcon, maxHeight: Layout.chevronHeight))
            .frame(width: Layout.chevronWidth)
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
