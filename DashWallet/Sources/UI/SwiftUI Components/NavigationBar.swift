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

struct NavigationBar<Leading: View, Central: View, Trailing: View>: View {
    private let leading: Leading
    private let central: Central
    private let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder central: () -> Central,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.central = central()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack {
                leading
                
                Spacer()

                trailing
            }
            .padding(.horizontal, 20)

            central
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }
}

// MARK: - Convenience Initializers (2 elements)

extension NavigationBar where Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading, @ViewBuilder central: () -> Central) {
        self.init(leading: leading, central: central, trailing: { EmptyView() })
    }
}

extension NavigationBar where Central == EmptyView {
    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.init(leading: leading, central: { EmptyView() }, trailing: trailing)
    }
}

extension NavigationBar where Leading == EmptyView {
    init(@ViewBuilder central: () -> Central, @ViewBuilder trailing: () -> Trailing) {
        self.init(leading: { EmptyView() }, central: central, trailing: trailing)
    }
}

// MARK: - Convenience Initializers (1 element)

extension NavigationBar where Central == EmptyView, Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, central: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension NavigationBar where Leading == EmptyView, Trailing == EmptyView {
    init(@ViewBuilder central: () -> Central) {
        self.init(leading: { EmptyView() }, central: central, trailing: { EmptyView() })
    }
}

extension NavigationBar where Leading == EmptyView, Central == EmptyView {
    init(@ViewBuilder trailing: () -> Trailing) {
        self.init(leading: { EmptyView() }, central: { EmptyView() }, trailing: trailing)
    }
}

enum NavigationBarElement: String {
    case back = "navigationbar-back"
    case close = "navigationbar-close"
    case plus = "navigationbar-plus"
    case info = "navigationbar-info"

    var icon: some View {
        Icon(name: .custom(rawValue))
    }

    func button(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .fixedSize()
                .frame(width: 44, height: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(NavigationBarButtonStyle())
    }
}

private struct NavigationBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

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

// MARK: - NavBarBackPlus

/// Navigation bar with a back button on the left and an add button on the right.
///
/// Mirrors the styling of `NavBarBack` on both sides:
/// - 64pt height navigation container
/// - Circular back button (left) with chevron icon
/// - Circular add button (right) with "toolbar-plus" icon (11pt height)
/// - 34pt circular border with custom styling on both buttons
/// - Dark mode support
///
/// Usage:
/// ```swift
/// NavBarBackPlus(onBack: { dismiss() }, onAdd: { viewModel.addItem() })
/// ```
struct NavBarBackPlus: View {
   @Environment(\.colorScheme) private var colorScheme
   let onBack: () -> Void
   let onAdd: () -> Void

   var body: some View {
       HStack {
           // Back button (left)
           Button(action: onBack) {
               ZStack {
                   Color.clear
                       .frame(width: 44, height: 44)

                   Circle()
                       .stroke(borderColor, lineWidth: 1.5)
                       .frame(width: 34, height: 34)

                   Image(backIconName)
                       .resizable()
                       .aspectRatio(contentMode: .fit)
                       .frame(height: 12)
                       .offset(x: -1)
                       .foregroundColor(.primaryText)
               }
           }
           .padding(.leading, 20)

           Spacer()

           // Add button (right)
           Button(action: onAdd) {
               ZStack {
                   Color.clear
                       .frame(width: 44, height: 44)

                   Circle()
                       .stroke(borderColor, lineWidth: 1.5)
                       .frame(width: 34, height: 34)

                   Image("toolbar-plus")
                       .resizable()
                       .aspectRatio(contentMode: .fit)
                       .frame(height: 11)
                       .foregroundColor(.primaryText)
               }
           }
           .padding(.trailing, 20)
       }
       .frame(height: 64)
   }

   private var borderColor: Color {
       .gray300Alpha30
   }

   private var backIconName: String {
       colorScheme == .dark ? "controls-back-dark-mode" : "controls-back"
   }
}

// MARK: - NavBarClose

/// Navigation bar with only a close button on the right side.
///
/// Used for modal/sheet presentations where a dismiss action is needed:
/// - 64pt height navigation container
/// - Circular close button (right) with "toolbar-plus" X icon (11pt height)
/// - 34pt circular border with custom styling
/// - Dark mode support
///
/// Usage:
/// ```swift
/// NavBarClose {
///     dismiss()
/// }
/// ```
struct NavBarClose: View {
   let onClose: () -> Void

   var body: some View {
       HStack {
           Spacer()

           // Close button (right)
           Button(action: onClose) {
               ZStack {
                   Color.clear
                       .frame(width: 44, height: 44)

                   Circle()
                       .stroke(Color.gray300Alpha30, lineWidth: 1.5)
                       .frame(width: 34, height: 34)

                   Image("toolbar-close")
                       .resizable()
                       .aspectRatio(contentMode: .fit)
                       .frame(height: 11)
                       .foregroundColor(.primaryText)
               }
           }
           .padding(.trailing, 20)
       }
       .frame(height: 64)
   }
}

// MARK: - Previews

#Preview("NavBarBack") {
    NavigationBar(
        leading: { NavigationBarElement.back.button { } }
    )
}

#Preview("NavBarBackTitle") {
    NavigationBar(
        leading: { NavigationBarElement.back.button { } },
        central: { Text("Title").font(.subheadMedium) }
    )
}

#Preview("NavBarBackTitleInfo") {
    NavigationBar(
        leading: { NavigationBarElement.back.button { } },
        central: { Text("Title").font(.subheadMedium) },
        trailing: { NavigationBarElement.info.button { } }
    )
}

#Preview("NavBarBackInfo") {
    NavigationBar(
        leading: { NavigationBarElement.back.button { } },
        trailing: { NavigationBarElement.info.button { } }
    )
}

#Preview("NavBarTitleClose") {
    NavigationBar(
        central: { Text("Title").font(.subheadMedium) },
        trailing: { NavigationBarElement.close.button { } }
    )
}

#Preview("NavBarBackTitlePlus") {
    NavigationBar(
        leading: { NavigationBarElement.back.button { } },
        central: { Text("Title").font(.subheadMedium) },
        trailing: { NavigationBarElement.close.button { } }
    )
}

#Preview("NavBarBackPlus") {
    NavigationBar(
        leading: { NavigationBarElement.back.button { } },
        trailing: { NavigationBarElement.plus.button { } }
    )
}

#Preview("NavBarTitle") {
    NavigationBar(
        central: { Text("Title").font(.subheadMedium) }
    )
}

#Preview("NavBarClose") {
    NavigationBar(
        trailing: { NavigationBarElement.close.button { } }
    )
}

#Preview("NavBarTitleClose") {
    NavigationBar(
        central: { Text("Title").font(.subheadMedium) },
        trailing: { NavigationBarElement.close.button { } }
    )
}
