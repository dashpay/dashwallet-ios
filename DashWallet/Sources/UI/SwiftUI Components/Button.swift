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

struct DashButton: View {
    var text: String? = nil
    var leadingIcon: IconName? = nil
    var trailingIcon: IconName? = nil
    var style: Style = .filled
    var size: Size = .large
    var stretch: Bool = true
    var isEnabled: Bool = true
    var action: () -> Void
    
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
    
    @Environment(\.overrideForegroundColor) var overridenForegroundColor
    @Environment(\.overrideBackgroundColor) var overridenBackgroundColor

    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                if let icon = leadingIcon {
                    Icon(name: icon)
                        .frame(width: iconSize, height: iconSize)
                        .font(.system(size: iconSize))
                }
                
                if let text = text {
                    Text(text)
                        .font(.system(size: fontSize))
                        .fontWeight(.semibold)
                        .padding(.vertical, 2)
                }
                
                if let icon = trailingIcon {
                    Icon(name: icon)
                        .frame(width: iconSize, height: iconSize)
                        .font(.system(size: iconSize))
                }
            }
            .padding(.horizontal, paddingHorizontal)
            .padding(.vertical, paddingVertical)
            .foregroundColor(overridenForegroundColor ?? foregroundColor)
            .if(stretch) { view in
                view.frame(maxWidth: .infinity)
            }
            .frame(minHeight: minimumHeight)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 2)
            )
            .cornerRadius(cornerRadius)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled)
        .background(GeometryReader { geometry in
            Color.clear
        })
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return Color.black.opacity(0.2)
        }
        
        switch style {
        case .filled:
            return overridenBackgroundColor ?? Color.dashBlue
        default:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return Color.black.opacity(0.6)
        }
        
        switch style {
        case .filled:
            return Color.white
        default:
            return Color.primaryText
        }
    }

    private var borderColor: Color {
        if !isEnabled {
            return Color.clear
        }
        
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

    private var minimumHeight: CGFloat {
        switch size {
        case .large:
            return 48
        case .medium:
            return 42
        case .small:
            return 32
        default:
            return 28
        }
    }
}

private struct OverrideForegroundColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

private struct OverrideBackgroundColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var overrideForegroundColor: Color? {
        get { self[OverrideForegroundColorKey.self] }
        set { self[OverrideForegroundColorKey.self] = newValue }
    }
    
    var overrideBackgroundColor: Color? {
        get { self[OverrideBackgroundColorKey.self] }
        set { self[OverrideBackgroundColorKey.self] = newValue }
    }
}

extension View {
    func overrideForegroundColor(_ color: Color?) -> some View {
        environment(\.overrideForegroundColor, color)
    }
    
    func overrideBackgroundColor(_ color: Color?) -> some View {
        environment(\.overrideBackgroundColor, color)
    }
}
