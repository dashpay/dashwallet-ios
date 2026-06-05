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

// Self-sizing sheet: the sheet hugs its content height instead of using a fixed
// detent. Measures the content via GeometryReader and feeds the height into a
// single `.height` presentation detent.
//
// Notes:
// - A single detent (no .large) means the sheet cannot be dragged to full screen,
//   and iOS does not show the system drag indicator.
// - Until a real measurement arrives, .medium is used as a placeholder so the
//   sheet doesn't collapse (a height of 0 would make iOS fall back to full screen).
// - The measured view must have a finite intrinsic height (no greedy Spacers /
//   maxHeight: .infinity), otherwise it expands to fill the offered space and the
//   measurement is wrong. See BottomSheet(fillsHeight: false).

@available(iOS 16.0, *)
private struct SelfSizingSheetModifier: ViewModifier {
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { update(geo.size.height) }
                        .onChange(of: geo.size.height) { update($0) }
                }
            )
            .presentationDetents(detents)
            .presentationDragIndicator(.hidden)
    }

    private var detents: Set<PresentationDetent> {
        guard let height, height > 0 else { return [.medium] }
        return [.height(height)]
    }

    private func update(_ newHeight: CGFloat) {
        guard newHeight > 0, newHeight != height else { return }
        height = newHeight
    }
}

extension View {
    /// Applies a self-sizing sheet detent so the sheet fits its content automatically.
    ///
    /// - Parameter cornerRadius: Optional corner radius applied via `presentationCornerRadius`
    ///   on iOS 16.4..<26 only. Pass `nil` (default) to skip. iOS 26+ uses the system sheet
    ///   corner styling, so the custom radius is intentionally not applied there.
    ///
    /// The iOS 16 guard is built-in; callers do NOT need their own `#available` check.
    @ViewBuilder
    func selfSizingSheet(cornerRadius: CGFloat? = nil) -> some View {
        if #available(iOS 16.0, *) {
            let modified = modifier(SelfSizingSheetModifier())
            if #available(iOS 16.4, *), let r = cornerRadius {
                if #unavailable(iOS 26.0) {
                    // iOS 16.4..<26: apply the custom corner radius.
                    modified
                        .presentationCornerRadius(r)
                        .presentationBackground(Color.primaryBackground)
                } else {
                    // iOS 26+: keep the system corner styling, skip the custom radius.
                    modified
                        .presentationBackground(Color.primaryBackground)
                }
            } else {
                modified
            }
        } else {
            self
        }
    }
}
