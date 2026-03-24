//
//  Created by Claude
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

struct ShortcutCustomizeBannerView: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image("shortcut_customize_banner")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Customize shortcut bar", comment: "Shortcut banner"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(.dw_darkTitle()))
                Text(NSLocalizedString("Hold any button above to replace it with the function you need", comment: "Shortcut banner"))
                    .font(.system(size: 13))
                    .foregroundColor(Color(.dw_secondaryText()))
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(.dw_secondaryText()))
            }
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.dw_background()))
                .shadow(color: Color(red: 0.72, green: 0.76, blue: 0.80).opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 20)
    }
}
