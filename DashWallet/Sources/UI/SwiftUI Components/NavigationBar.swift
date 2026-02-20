//
//  NavigationBar.swift
//  DashWallet
//
//  Reusable navigation bar components for consistent navigation across the app.
//  Each variant provides a specific navigation pattern with consistent styling.
//
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

// MARK: - NavBarBack

/// Navigation bar with only a back button
///
/// A minimal navigation bar with just a back button on the left side.
/// Provides consistent styling and behavior across the app:
/// - 64pt height navigation container
/// - Circular back button with 44x44pt touch area
/// - 34pt circular border with custom styling
/// - Dark mode support with automatic icon switching
/// - Proper visual centering with -1pt offset
///
/// Usage:
/// ```swift
/// NavBarBack {
///     navigationController?.popViewController(animated: true)
/// }
/// ```
struct NavBarBack: View {
    @Environment(\.colorScheme) private var colorScheme
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                ZStack {
                    // Touch area (44x44)
                    Color.clear
                        .frame(width: 44, height: 44)

                    // Circular border (34x34)
                    Circle()
                        .stroke(borderColor, lineWidth: 1.5)
                        .frame(width: 34, height: 34)

                    // Chevron icon (12pt height, -1pt horizontal offset for visual centering)
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 12)
                        .offset(x: -1)
                        .foregroundColor(.primaryText)
                }
            }
            .padding(.leading, 20)

            Spacer()
        }
        .frame(height: 64)
    }

    private var borderColor: Color {
        .gray300Alpha30
    }

    private var iconName: String {
        colorScheme == .dark ? "controls-back-dark-mode" : "controls-back"
    }
}

// MARK: - Legacy Support

/// Legacy name for NavBarBack - use NavBarBack instead
@available(*, deprecated, renamed: "NavBarBack", message: "Use NavBarBack for clarity")
typealias NavigationBar = NavBarBack

// MARK: - Previews

struct NavigationBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            NavBarBack {
                print("Back tapped")
            }

            Spacer()
        }
        .previewDisplayName("NavBarBack - Light")

        VStack(spacing: 0) {
            NavBarBack {
                print("Back tapped")
            }

            Spacer()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("NavBarBack - Dark")
    }
}
