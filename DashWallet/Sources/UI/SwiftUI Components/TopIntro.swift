//
//  Created by Andrei Ashikhmin
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

struct TopIntro: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title1)
                .foregroundColor(.primaryText)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.subhead)
                    .foregroundColor(.secondaryText)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 60)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
