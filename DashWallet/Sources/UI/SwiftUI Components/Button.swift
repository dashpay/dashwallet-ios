//  
//  Created by Andrei Ashikhmin
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

private struct OverrideForegroundColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var overrideForegroundColor: Color? {
        get { self[OverrideForegroundColorKey.self] }
        set { self[OverrideForegroundColorKey.self] = newValue }
    }
}

extension View {
    func overrideForegroundColor(_ color: Color?) -> some View {
        environment(\.overrideForegroundColor, color)
    }
}

struct DashButton: View {
    enum Style {
        case plain
        case outlined
        case filled
    }
    
    enum Size {
        case large
        case medium
        case small
        case extraSmall
    }

    var text: String? = nil
    var leadingIcon: IconName? = nil
    var trailingIcon: IconName? = nil
    var action: () -> Void
    var style: Style = .filled
    var size: Size = .large
    
    @Environment(\.overrideForegroundColor) var overridenForegroundColor

    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                if let icon = leadingIcon {
                    Icon(name: icon)
                        .font(.system(size: iconSize))
                }
                
                if let text = text {
                    Text(text)
                        .font(.system(size: fontSize))
                        .fontWeight(.semibold)
                }
                
                if let icon = trailingIcon {
                    Icon(name: icon)
                        .font(.system(size: iconSize))
                }
            }
            .padding(.horizontal, paddingHorizontal)
            .padding(.vertical, paddingVertical)
            .background(backgroundColor)
            .foregroundColor(overridenForegroundColor ?? foregroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 2)
            )
            .cornerRadius(cornerRadius)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .filled:
            return Color.dashBlue
        default:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .filled:
            return Color.white
        default:
            return Color.primaryText
        }
    }

    private var borderColor: Color {
        switch style {
        case .outlined:
            return Color.tertiaryText.opacity(0.25)
        default:
            return Color.clear
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .large:
            return 16
        case .medium:
            return 14
        case .small:
            return 13
        case .extraSmall:
            return 12
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .large:
            return 22
        case .medium:
            return 20
        case .small:
            return 16
        case .extraSmall:
            return 13
        }
    }

    private var paddingHorizontal: CGFloat {
        switch size {
        case .large:
            return 20
        case .medium:
            return 16
        case .small:
            return 12
        case .extraSmall:
            return 8
        }
    }
    
    private var paddingVertical: CGFloat {
        switch size {
        case .large:
            return 12
        case .medium:
            return 10
        case .small:
            return 6
        case .extraSmall:
            return 4
        }
    }
    
    private var cornerRadius: CGFloat {
        switch size {
        case .large:
            return 12
        case .medium:
            return 10
        case .small:
            return 8
        case .extraSmall:
            return 6
        }
    }
}
