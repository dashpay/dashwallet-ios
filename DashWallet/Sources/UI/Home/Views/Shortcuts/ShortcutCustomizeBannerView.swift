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
            Icon(name: .custom("menu-shortcuts"))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Customize shortcut bar", comment: "Shortcut banner"))
                    .font(.footnoteMedium)
                    .foregroundStyle(Color.primaryText)

                Text(NSLocalizedString("Hold any button above to replace it with the function you need", comment: "Shortcut banner"))
                    .font(.footnote)
                    .foregroundStyle(Color.gray500)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(.dw_secondaryText()))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NSLocalizedString("Close", comment: "Accessibility"))
            .accessibilityIdentifier("shortcut_banner_dismiss")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: Color.shadow, radius: 10, x: 0, y: 5)
    }
}

#if DEBUG
private func bannerPreview() -> some View {
    ShortcutCustomizeBannerView(onDismiss: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .background(Color.primaryBackground)
}

#Preview("Light") {
    bannerPreview()
}

#Preview("Dark") {
    bannerPreview()
        .preferredColorScheme(.dark)
}
#endif
