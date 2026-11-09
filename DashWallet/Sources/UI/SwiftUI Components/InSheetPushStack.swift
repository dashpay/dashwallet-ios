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

import DashUIKit
import SwiftUI

/// A two-level route inside a sheet that moves like a navigation push: the pushed level
/// slides in from the trailing edge while the root shifts toward the leading edge, and
/// going back reverses it. Under Reduce Motion the pushed level fades in and out over
/// the root instead.
///
/// The root stays in the hierarchy under the pushed level, so its scroll position
/// survives the round trip; while covered it takes no taps and is hidden from VoiceOver.
/// The pushed level is backed by an opaque `primaryBackground` run through the safe areas,
/// the bottom one included, so the root never shows through it, mid-slide or at rest; content that
/// paints its own background draws over that fill.
struct InSheetPushStack<Item, Root: View, Pushed: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// The item shown on the pushed level; `nil` shows the root.
    let pushed: Item?
    @ViewBuilder let root: () -> Root
    @ViewBuilder let pushedContent: (Item) -> Pushed
    
    /// How far the covered root shifts toward the leading edge, as a share of its width.
    private static var coveredRootShift: CGFloat { 0.3 }
    
    var body: some View {
        let isPushed = pushed != nil
        // Negative x is the leading side; SwiftUI mirrors the offset in right-to-left
        // layouts, as it does `.move(edge: .trailing)`.
        let rootShift = isPushed && !reduceMotion ? -Self.coveredRootShift : 0
        
        ZStack {
            root()
                .visualEffect { content, proxy in
                    content.offset(x: proxy.size.width * rootShift)
                }
                .allowsHitTesting(!isPushed)
                .accessibilityHidden(isPushed)
            
            if let pushed {
                pushedContent(pushed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dash.primaryBackground, ignoresSafeAreaEdges: .all)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            }
        }
        .animation(.inSheetPush(reduceMotion: reduceMotion), value: isPushed)
    }
}

extension Animation {
    /// The timing of an `InSheetPushStack` push or pop, for views outside the stack that
    /// change with it, such as the sheet header's Back button.
    static func inSheetPush(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.35)
    }
}
