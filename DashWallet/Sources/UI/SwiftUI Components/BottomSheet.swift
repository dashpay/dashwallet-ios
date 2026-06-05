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

struct BottomSheet<Content: View>: View {
    @Environment(\.presentationMode) private var presentationMode

    var title: String = ""
    @Binding var showBackButton: Bool
    var onBackButtonPressed: (() -> Void)? = nil
    /// `true` (default) — greedy: content fills the sheet (use with an explicit detent or a
    /// `.large`/`.medium` detent). `false` — natural height: pair with `.selfSizingSheet()` so
    /// the sheet snaps to its content.
    var fillsHeight: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        let sheet = VStack(spacing: 0) {
            grabber
                .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .center)

            header

            contentSection
        }
        .background(Color.primaryBackground)

        if fillsHeight {
            sheet.edgesIgnoringSafeArea(.bottom)
        } else {
            // Publish the natural content height for `.selfSizingSheet()`. The bottom safe area is
            // intentionally NOT ignored here, so the measured height excludes the home-indicator
            // inset — `.presentationDetents([.height])` adds that inset itself.
            sheet.background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: BottomSheetHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
    }

    private var grabber: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: 36, height: 5)
            .background(Color.gray300Alpha50)
            .cornerRadius(5)
    }

    private var header: some View {
        // Reuse the shared NavigationBar (absolutely-centered title, own 64pt height +
        // horizontal padding). Title styling preserved; back/close use NavigationBarElement.
        NavigationBar(
            leading: {
                if showBackButton {
                    NavigationBarElement.back.button { onBackButtonPressed?() }
                }
            },
            central: {
                Text(title)
                    .font(.calloutMedium)
                    .foregroundColor(.primaryText)
            },
            trailing: {
                NavigationBarElement.close.button { presentationMode.wrappedValue.dismiss() }
            }
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        if fillsHeight {
            NavigationView {
                content()
                    .navigationBarHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primaryBackground)
            }
        } else {
            // Natural height — no greedy NavigationView / maxHeight so the sheet can self-size.
            content()
                .frame(maxWidth: .infinity)
                .background(Color.primaryBackground)
        }
    }
}

// MARK: - Auto-sizing

/// Bubbles a `BottomSheet`'s measured natural height up to `.selfSizingSheet()`.
struct BottomSheetHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Sizes a `BottomSheet` (built with `fillsHeight: false`) to its content's natural height —
    /// no hardcoded `.height(...)` needed. On iOS < 16 it is a no-op.
    @ViewBuilder
    func selfSizingSheet(fallback: CGFloat = 0, maxHeightFraction: CGFloat = 0.95) -> some View {
        if #available(iOS 16.0, *) {
            modifier(SelfSizingSheetModifier(fallback: fallback, maxHeightFraction: maxHeightFraction))
        } else {
            self
        }
    }
}

@available(iOS 16.0, *)
private struct SelfSizingSheetModifier: ViewModifier {
    let fallback: CGFloat
    let maxHeightFraction: CGFloat
    @State private var measured: CGFloat = 0

    func body(content: Content) -> some View {
        let cap = UIScreen.main.bounds.height * maxHeightFraction
        let resolved = min(measured > 0 ? measured : fallback, cap)
        content
            .onPreferenceChange(BottomSheetHeightPreferenceKey.self) { measured = $0 }
            // Before the first measurement (and when nothing is provided) fall back to .medium so
            // the sheet is never given an invalid 0-height detent.
            .presentationDetents(resolved > 0 ? [.height(resolved)] : [.medium])
    }
}
