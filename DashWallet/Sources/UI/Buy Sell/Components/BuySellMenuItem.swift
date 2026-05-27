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

struct BuySellMenuItem: View {

    private enum Layout {
        static let iconSize: CGFloat = 30
        static let hSpacing: CGFloat = 10
        static let textSpacing: CGFloat = 1
        static let padding: CGFloat = 10
    }

    private let iconName: String
    private let title: String
    private let description: String

    init(iconName: String, title: String, description: String) {
        self.iconName = iconName
        self.title = title
        self.description = description
    }

    var body: some View {
        HStack(spacing: Layout.hSpacing) {
            Icon(name: .custom(iconName))
                .frame(width: Layout.iconSize, height: Layout.iconSize)

            VStack(alignment: .leading, spacing: Layout.textSpacing) {
                Text(title)
                    .font(Font.subheadMedium)

                Text(description)
                    .font(Font.footnote)
                    .foregroundStyle(Color.tertiaryText)
            }
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

#Preview {
    BuySellMenuItem(
        iconName: "uphold_logo",
        title: "Uphold",
        description: "Click to connect your account"
    )
}
