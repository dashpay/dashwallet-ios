//
//  Created by Codex
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
import UIKit

struct ShortcutItemView: View {
    let title: String
    let iconName: String
    var textColor: Color = Color(uiColor: .dw_darkTitle())
    var alpha: CGFloat = 1.0

    init(title: String, iconName: String, textColor: Color = Color(uiColor: .dw_darkTitle()), alpha: CGFloat = 1.0) {
        self.title = title
        self.iconName = iconName
        self.textColor = textColor
        self.alpha = alpha
    }

    init(model: ShortcutAction) {
        self.title = model.title
        self.iconName = model.type.iconName
        self.textColor = Color(uiColor: model.textColor)
        self.alpha = model.alpha
    }

    var body: some View {
        VStack(spacing: 4) {
            Icon(name: .custom(iconName))
                .frame(width: 46, height: 46, alignment: .center)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .clipShape(.rect(cornerRadius: 16))
        .opacity(Double(alpha))
        .contentShape(.rect)
    }
}

#if DEBUG
private func shortcutItemGrid(_ alpha: CGFloat) -> some View {
    HStack(spacing: 4) {
        ShortcutItemView(model: .init(type: .receive))
        ShortcutItemView(model: .init(type: .send))
        ShortcutItemView(model: .init(type: .sendToContact))
        ShortcutItemView(
            title: ShortcutAction(type: .buySellDash).title,
            iconName: ShortcutActionType.buySellDash.iconName,
            alpha: alpha
        )
    }
    .padding(8)
    .background(Color.secondaryBackground)
}

#Preview("Enabled") {
    shortcutItemGrid(1.0)
}


#Preview("Disabled") {
    shortcutItemGrid(0.4)
}
#endif
