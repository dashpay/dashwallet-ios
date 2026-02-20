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
    var isLoading: Bool = false
    var action: () -> Void
    
    enum Style {
        case plain
        case outlined
        case filled
        case filledBlue
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
                
                if isLoading {
                    SwiftUI.ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                        .padding(.vertical, 2)
                } else if let text = text {
                    Text(text)
                        .font(.system(size: fontSize))
                        .fontWeight(.semibold)
                        .frame(height: lineHeight)
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
            .frame(height: minimumHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 2)
            )
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .buttonStyle(DashButtonStyle(cornerRadius: cornerRadius))
        .disabled(!isEnabled || isLoading)
        .background(Color.clear)
    }

    private var backgroundColor: Color {
        if !isEnabled {
            switch style {
            case .filledBlue:
                return Color.blackAlpha5
            default:
                return Color.black.opacity(0.2)
            }
        }

        switch style {
        case .filled:
            return overridenBackgroundColor ?? Color.dashBlue
        case .filledBlue:
            return Color.blue
        default:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            switch style {
            case .filledBlue:
                return Color.blackAlpha40
            default:
                return Color.black.opacity(0.6)
            }
        }

        switch style {
        case .filled:
            return Color.white
        case .filledBlue:
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

    private var lineHeight: CGFloat {
        switch size {
        case .large:
            return 22
        case .medium:
            return 20
        case .small:
            return 18
        case .extraSmall:
            return 16
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .large:
            return 22
        case .medium:
            return 20
        case .small:
            return 18
        case .extraSmall:
            return 16
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
            return 16
        case .medium:
            return 14
        case .small:
            return 11
        case .extraSmall:
            return 9
        }
    }

    private var minimumHeight: CGFloat {
        switch size {
        case .large:
            return 50
        case .medium:
            return 40
        case .small:
            return 30
        case .extraSmall:
            return 24
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

struct DashButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.2 : 0))
            )
    }
}
