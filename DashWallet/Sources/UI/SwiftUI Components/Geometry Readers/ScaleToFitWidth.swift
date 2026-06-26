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

// MARK: - ScaleToFitWidth

private struct ScaleToFitContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 { value = next }
    }
}

/// Scales its content uniformly to fit the available width on a single line, shrinking the WHOLE
/// group (e.g. currency symbol + amount + logo) together — unlike `minimumScaleFactor`, which only
/// shrinks each `Text` independently. Content renders at full size when it fits and never scales
/// below `minScale`.
///
/// The modifier reserves the content's natural single-line height (constant) so it keeps the
/// surrounding vertical layout stable while only the horizontal scale changes.
struct ScaleToFitWidth: ViewModifier {
    var minScale: CGFloat = 0.35

    @State private var naturalSize: CGSize = .zero

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .fixedSize()  // natural, single-line size — the unit we scale
                .scaleEffect(scale(forAvailableWidth: proxy.size.width), anchor: .center)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        // Collapse the greedy GeometryReader to one content line so vertical layout is unaffected.
        .frame(height: naturalSize.height == 0 ? nil : naturalSize.height)
        .background(
            // Measure the content's natural (unconstrained) size off-screen.
            content
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScaleToFitContentSizeKey.self, value: proxy.size)
                    }
                )
        )
        .onPreferenceChange(ScaleToFitContentSizeKey.self) { naturalSize = $0 }
    }

    private func scale(forAvailableWidth available: CGFloat) -> CGFloat {
        guard naturalSize.width > 0, available > 0, available < naturalSize.width else { return 1 }
        return max(minScale, available / naturalSize.width)
    }
}

extension View {
    /// Scales the view uniformly to fit the available width on one line, down to `minScale`.
    func scaleToFitWidth(minScale: CGFloat = 0.35) -> some View {
        modifier(ScaleToFitWidth(minScale: minScale))
    }
}
