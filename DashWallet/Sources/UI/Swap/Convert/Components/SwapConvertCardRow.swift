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

// MARK: - Card row height preference

/// Identifies the two cards of the conversion card stack so the parent can position the arrow
/// badge between them.
enum SwapConvertRowSlot {
    case top
    case bottom
}

/// Reports each row's measured height up to `SwapConvertView`, which centers the arrow badge
/// between the two cards. Kept here next to the row that writes it; the parent owns the read.
struct SwapConvertRowHeightKey: PreferenceKey {
    static var defaultValue: [SwapConvertRowSlot: CGFloat] = [:]

    static func reduce(value: inout [SwapConvertRowSlot: CGFloat], nextValue: () -> [SwapConvertRowSlot: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - SwapConvertCardRow

/// One card in the conversion stack: wraps arbitrary content with the shared, non-interactive
/// card chrome and reports its height via `SwapConvertRowHeightKey` for its `slot`.
struct SwapConvertCardRow<Content: View>: View {
    let slot: SwapConvertRowSlot
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .allowsHitTesting(false)   // rows are display-only
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(.rect(cornerRadius: 20))
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SwapConvertRowHeightKey.self, value: [slot: proxy.size.height])
                }
            )
    }
}
