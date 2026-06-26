//
//  Created by Roman Chornyi
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

// NOTE: `ShortcutsActionDelegate` is still declared in the legacy `ShortcutsView.swift` (same
// module), so this bar reuses it for now. When `ShortcutsView.swift` is deleted, move the
// protocol declaration here.

// MARK: - ShortcutsBarView

/// Home-screen shortcut bar — a pure-SwiftUI replacement for the UIKit `ShortcutsView`
/// (`ShortcutsView.swift` + `ShortcutsView.xib`). Always shows one row of 4 shortcut buttons.
///
/// Layered back-to-front, matching the old xib:
///   1. grey content background  (`Color.primaryBackground`, #F7F7F7),
///   2. a 30pt blue strip at the top (`Color.navigationBarColor`) so the navigation-bar blue
///      continues down behind the top of the card and merges with the balance view above,
///   3. a white rounded card (`Color.secondaryBackground`, #FFFFFF) inset 20pt on the sides,
///      holding the 4 evenly-spaced shortcut buttons.
///
/// Data comes straight from `HomeViewModel.shortcutItems` (`@Published`), so the bar updates
/// itself — no manual reload. Taps and long-presses are reported through plain closures, which
/// `HomeHeaderView` adapts to the `ShortcutsActionDelegate` used by `HomeViewController`.
struct ShortcutsBarView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onSelect: (ShortcutAction) -> Void
    let onLongPress: (_ position: Int, _ action: ShortcutAction) -> Void

    // Layout values taken 1:1 from ShortcutsView.xib / ShortcutsView.swift.
    private let cardCornerRadius: CGFloat = 20     // ShortcutsView.commonInit
    private let cardHorizontalInset: CGFloat = 20  // xib leading/trailing 20
    private let cardVerticalInset: CGFloat = 4     // xib top/bottom 4
    private let itemSpacing: CGFloat = 4           // xib flow layout spacing

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Grey content background, full bleed.
            Color.primaryBackground

            // 2. Blue fills the top half of the block, reaching the vertical middle of the card
            //    (the card is centred by its equal 4pt top/bottom insets). The card's upper half
            //    then sits on the navigation blue, the lower half on the grey content background.
            VStack(spacing: 0) {
                Color.navigationBarColor
                Color.clear
            }

            // 3. White card with the shortcut row, drawn over the strip.
            card
                .padding(.horizontal, cardHorizontalInset)
                .padding(.vertical, cardVerticalInset)
        }
    }

    private var card: some View {
        HStack(spacing: itemSpacing) {
            ForEach(Array(viewModel.shortcutItems.enumerated()), id: \.offset) { index, action in
                ShortcutCellButton(
                    action: action,
                    onSelect: { onSelect(action) },
                    onLongPress: { onLongPress(index, action) }
                )
            }
        }
        .padding(4)
        .background(Color.secondaryBackground)
        .clipShape(.rect(cornerRadius: cardCornerRadius))
    }
}

// MARK: - Cell

/// A single shortcut cell. Uses explicit tap + long-press gestures (not a `Button` with
/// `.onLongPressGesture`, whose button gesture swallows the touch so the long-press never fires —
/// the old UIKit bar used a dedicated `UILongPressGestureRecognizer`). A quick tap selects; a
/// ≥0.5s hold opens customization. The press-scale (`dw_pressedAnimation(.heavy)`) is driven by the
/// long-press `pressing:` callback.
private struct ShortcutCellButton: View {
    let action: ShortcutAction
    let onSelect: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false

    var body: some View {
        ShortcutItemView(model: action)
            .frame(maxWidth: .infinity)            // 4 equal columns
            .scaleEffect(isPressed ? 0.93 : 1.0)   // matches dw_pressedAnimation(.heavy)
            .animation(.spring(response: 0.4, dampingFraction: 0.5), value: isPressed)
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .onLongPressGesture(
                minimumDuration: 0.5,
                pressing: { pressing in isPressed = pressing },
                perform: { onLongPress() }
            )
            .opacity(action.enabled ? 1 : 0.4)
            .disabled(!action.enabled)             // also disables the gestures
            .modifier(ShortcutSnapshotIdentifier(action: action))
    }
}

// MARK: - Snapshot hook

/// Mirrors the `#if SNAPSHOT` accessibility identifier the old `ShortcutsView` set on the
/// "secure wallet" cell, so UI snapshot tests keep working.
private struct ShortcutSnapshotIdentifier: ViewModifier {
    let action: ShortcutAction

    func body(content: Content) -> some View {
        #if SNAPSHOT
        if action.type == .secureWallet {
            content.accessibilityIdentifier("shortcut_secure_wallet")
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Previews

#if DEBUG
private let previewBackupNeededZero: [ShortcutAction] = [ // zero balance + backup needed
    .init(type: .secureWallet), .init(type: .receive), .init(type: .buySellDash), .init(type: .spend),
]
private let previewVerifiedZero: [ShortcutAction] = [ // zero balance + verified
    .init(type: .receive), .init(type: .send), .init(type: .buySellDash), .init(type: .spend),
]
private let previewVerifiedFunded: [ShortcutAction] = [ // has balance + verified
    .init(type: .receive), .init(type: .send), .init(type: .scanToPay), .init(type: .spend),
]

private func previewBar(_ items: [ShortcutAction]) -> some View {
    ShortcutsBarView(
        viewModel: .makeForPreview(shortcuts: items),
        onSelect: { _ in },
        onLongPress: { _, _ in }
    )
}

/// Blue backdrop so the 30pt strip visibly merges with the navigation blue.
private func previewStack() -> some View {
    VStack(spacing: 0) {
        previewBar(previewBackupNeededZero)
        previewBar(previewVerifiedZero)
        previewBar(previewVerifiedFunded)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.navigationBarColor)
}

#Preview("Light") {
    previewStack()
}

#Preview("Dark") {
    previewStack()
        .preferredColorScheme(.dark)
}

#Preview("Large Dynamic Type") {
    previewBar(previewVerifiedFunded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.navigationBarColor)
        .environment(\.sizeCategory, .accessibilityExtraLarge)
}
#endif
