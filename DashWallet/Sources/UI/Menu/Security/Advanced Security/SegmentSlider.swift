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

import DashUIKit
import SwiftUI

private enum Layout {
    static let thumbDiameter: CGFloat = 30
    static let tickHeight: CGFloat = 10
    static let lineWidth: CGFloat = 1
    static let height: CGFloat = 44
    /// How far a touch moves before it counts as a drag.
    static let dragThreshold: CGFloat = 10
}

/// A slider that snaps to evenly spaced stops: a track with a tick per stop
/// and a thumb on the selected one.
///
/// A tap picks the nearest stop. A horizontal drag moves the thumb and picks
/// the stop it is released on, so `onSelect` runs once per drag. A drag that
/// moves more down than across scrolls the screen and picks nothing.
/// VoiceOver reads it as an adjustable element valued by `valueText`.
struct SegmentSlider<Leading: View, Trailing: View>: View {
    let stopCount: Int
    /// The selected stop, `nil` when the current value isn't one of them.
    let selectedIndex: Int?
    let accessibilityLabel: String
    /// What VoiceOver reads while `selectedIndex` is `nil`.
    let unselectedValueText: String
    let valueText: (Int) -> String
    let onSelect: (Int) -> Void
    @ViewBuilder let leadingLabel: Leading
    @ViewBuilder let trailingLabel: Trailing

    /// The stop under a horizontal drag in progress, shown before it is
    /// picked. Resets by itself when the scroll view takes the touch.
    @GestureState private var dragIndex: Int?

    private var displayedIndex: Int? { dragIndex ?? selectedIndex }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                leadingLabel
                Spacer(minLength: 8)
                trailingLabel
            }
            .font(.system(.footnote))
            .foregroundColor(.dash.tertiaryText)

            GeometryReader { geometry in
                let inset = Layout.thumbDiameter / 2
                let width = max(geometry.size.width - inset * 2, 1)
                let step = stopCount > 1 ? width / CGFloat(stopCount - 1) : 0

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.dash.gray300)
                        .frame(width: width, height: Layout.lineWidth)
                        .offset(x: inset)

                    ForEach(0..<stopCount, id: \.self) { index in
                        Rectangle()
                            .fill(Color.dash.gray300)
                            .frame(width: Layout.lineWidth, height: Layout.tickHeight)
                            .offset(x: inset + step * CGFloat(index) - Layout.lineWidth / 2)
                    }

                    if let displayedIndex {
                        Circle()
                            .fill(Color.dash.blue)
                            .frame(width: Layout.thumbDiameter, height: Layout.thumbDiameter)
                            .offset(x: step * CGFloat(displayedIndex))
                            .animation(.easeInOut(duration: 0.15), value: displayedIndex)
                    }
                }
                // Full width, so the hit area reaches the last stop: the track
                // is inset, and offsets don't widen the layout.
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                .contentShape(Rectangle())
                // a11y-ignore: A11Y012 the slider is one adjustable VoiceOver element, labeled below
                .onTapGesture(coordinateSpace: .local) { location in
                    select(nearestStop(x: location.x - inset, step: step))
                }
                // Simultaneous, so a vertical swipe that starts on the track
                // still scrolls the screen.
                .simultaneousGesture(
                    DragGesture(minimumDistance: Layout.dragThreshold)
                        .updating($dragIndex) { value, state, _ in
                            state = isHorizontal(value) ? nearestStop(x: value.location.x - inset, step: step) : nil
                        }
                        .onEnded { value in
                            guard isHorizontal(value) else { return }
                            select(nearestStop(x: value.location.x - inset, step: step))
                        })
            }
            .frame(height: Layout.height)
        }
        .sensoryFeedback(.selection, trigger: dragIndex) { old, new in
            new != nil && new != (old ?? selectedIndex)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(verbatim: selectedIndex.map(valueText) ?? unselectedValueText))
        .accessibilityAdjustableAction { direction in
            guard let current = selectedIndex else {
                // Nothing selected yet: either direction lands on the first stop.
                onSelect(0)
                return
            }
            switch direction {
            case .increment where current < stopCount - 1:
                onSelect(current + 1)
            case .decrement where current > 0:
                onSelect(current - 1)
            default:
                break
            }
        }
    }

    private func select(_ index: Int) {
        if index != selectedIndex { onSelect(index) }
    }

    private func isHorizontal(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height)
    }

    private func nearestStop(x: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        let index = Int((x / step).rounded())
        return min(max(index, 0), stopCount - 1)
    }
}
