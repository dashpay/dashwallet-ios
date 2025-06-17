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

/// A reusable radio button row component that displays an optional icon, title, and radio button indicator
struct RadioButtonRow: View {
    enum Style {
        case radio
        case checkbox
    }
    
    let title: String
    let icon: IconName?
    let isSelected: Bool
    let style: Style
    let action: () -> Void
    
    init(title: String, icon: IconName? = nil, isSelected: Bool, style: Style = .radio, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if let icon = icon {
                    Icon(name: icon)
                        .frame(width: 30, height: 30)
                }
                
                Text(title)
                    .font(.body2)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
                
                Spacer()
                
                switch style {
                case .radio:
                    Circle()
                        .stroke(isSelected ? Color.dashBlue : Color.gray300.opacity(0.5), lineWidth: isSelected ? 6 : 2)
                        .frame(width: isSelected ? 21 : 24, height: isSelected ? 21 : 24)
                        .padding(.trailing, isSelected ? 2 : 0)
                case .checkbox:
                    Image(isSelected ? "icon_checkbox_square_checked" : "icon_checkbox_square")
                        .resizable()
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .frame(minHeight: 54)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
