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

/// A slider that snaps to evenly spaced stops: a track with a tick per stop
/// and a thumb on the selected one. Tap or drag picks the nearest stop.
/// VoiceOver reads it as an adjustable element valued by `valueText`.
private enum Layout {
    static let thumbDiameter: CGFloat = 30
    static let tickHeight: CGFloat = 10
    static let lineWidth: CGFloat = 1
    static let height: CGFloat = 44
}

struct SegmentSlider<Leading: View, Trailing: View>: View {
    let stopCount: Int
    /// The selected stop, `nil` when the current value isn't one of them.
    let selectedIndex: Int?
    let accessibilityLabel: String
    let valueText: (Int) -> String
    let onSelect: (Int) -> Void
    @ViewBuilder let leadingLabel: Leading
    @ViewBuilder let trailingLabel: Trailing

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

                    if let selectedIndex {
                        Circle()
                            .fill(Color.dash.blue)
                            .frame(width: Layout.thumbDiameter, height: Layout.thumbDiameter)
                            .offset(x: step * CGFloat(selectedIndex))
                            .animation(.easeInOut(duration: 0.15), value: selectedIndex)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let index = nearestStop(x: value.location.x - inset, step: step)
                            if index != selectedIndex { onSelect(index) }
                        })
            }
            .frame(height: Layout.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(selectedIndex.map(valueText) ?? ""))
        .accessibilityAdjustableAction { direction in
            let current = selectedIndex ?? 0
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

    private func nearestStop(x: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        let index = Int((x / step).rounded())
        return min(max(index, 0), stopCount - 1)
    }
}
