//
//  Created by Roman Chornyi
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import DashUIKit

private enum SegmentedControlLayout {
    static let containerPadding: CGFloat = 4
    static let containerCornerRadius: CGFloat = 20
    static let segmentCornerRadius: CGFloat = 16
    static let segmentVerticalPadding: CGFloat = 6
    static let height: CGFloat = 40
    static let shadowRadius: CGFloat = 10
    static let shadowY: CGFloat = 5
    static let springResponse: Double = 0.3
    static let springDamping: Double = 0.7

    // Icon variant (an SF Symbol stacked over the label). It sizes to its
    // content instead of `height`, which only fits a single text line.
    static let iconSize: CGFloat = 16
    static let iconLabelSpacing: CGFloat = 4
    static let iconSegmentVerticalPadding: CGFloat = 10
}

struct SegmentedControl<T: Hashable>: View {
    private typealias Layout = SegmentedControlLayout

    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    /// SF Symbol drawn above each label. `nil` (the default) keeps the
    /// text-only segment every existing caller uses.
    var icon: ((T) -> String)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var containerWidth: CGFloat = 0

    private var segmentWidth: CGFloat {
        guard options.count > 0 else { return 0 }
        return containerWidth / CGFloat(options.count)
    }

    private var indicatorOffset: CGFloat {
        let index = options.firstIndex(of: selection) ?? 0
        return CGFloat(index) * segmentWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Layout.segmentCornerRadius)
                .fill(colorScheme == .dark ? Color.dash.whiteAlpha20 : Color.dash.white)
                .shadow(color: .shadow, radius: Layout.shadowRadius, x: 0, y: Layout.shadowY)
                .frame(width: max(1, segmentWidth))
                .offset(x: indicatorOffset)
                .animation(.spring(response: Layout.springResponse, dampingFraction: Layout.springDamping), value: selection)
                .opacity(containerWidth > 0 ? 1 : 0)

            HStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        select(option)
                    }) {
                        segmentContent(option)
                            .foregroundColor(selection == option ? .dash.primaryText : .dash.primaryText.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, icon == nil
                                ? Layout.segmentVerticalPadding
                                : Layout.iconSegmentVerticalPadding)
                            .contentShape(Rectangle())
                            .animation(.spring(response: Layout.springResponse, dampingFraction: Layout.springDamping), value: selection)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(label(option)))
                    .accessibilityHint(Text(NSLocalizedString("Double tap to select", comment: "SegmentedControl")))
                    .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { newWidth in
                        containerWidth = newWidth
                    }
            }
        )
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard segmentWidth > 0 else { return }
                    updateSelection(at: value.location.x)
                }
        )
        .padding(Layout.containerPadding)
        // The icon variant is two lines tall, so it sizes to its content —
        // `height` is the single-line text measurement.
        .frame(height: icon == nil ? Layout.height : nil)
        .background(Color.dash.gray300Alpha20)
        .clipShape(RoundedRectangle(cornerRadius: Layout.containerCornerRadius))
    }

    @ViewBuilder
    private func segmentContent(_ option: T) -> some View {
        if let icon {
            VStack(spacing: Layout.iconLabelSpacing) {
                Image(systemName: icon(option))
                    .font(.system(size: Layout.iconSize, weight: .semibold))
                segmentLabel(option)
            }
        } else {
            segmentLabel(option)
        }
    }

    private func segmentLabel(_ option: T) -> some View {
        Text(label(option))
            .font(.footnoteMedium)
            .lineLimit(1)
    }

    private func updateSelection(at x: CGFloat) {
        let index = max(0, min(options.count - 1, Int(x / segmentWidth)))
        select(options[index])
    }

    private func select(_ option: T) {
        guard option != selection else { return }
        withAnimation(.spring(response: Layout.springResponse, dampingFraction: Layout.springDamping)) {
            selection = option
        }
    }
}

extension SegmentedControl where T == String {
    init(options: [T], selection: Binding<T>) {
        self.options = options
        self._selection = selection
        self.label = { $0 }
    }
}

#Preview {
    SegmentedControlPreview()
}

private struct SegmentedControlPreview: View {
    @State private var two = "Single"
    @State private var three = "Day"
    @State private var four = "1D"

    var body: some View {
        VStack(spacing: 24) {
            SegmentedControl(options: ["Single", "Multiple"], selection: $two)

            SegmentedControl(options: ["Day", "Week", "Month"], selection: $three)

            SegmentedControl(options: ["1D", "1W", "1M", "1Y"], selection: $four)
        }
        .padding()
    }
}

#Preview("Icon variant") {
    SegmentedControlIconPreview()
}

/// The icon variant next to the text-only one, so the two stay recognisably the
/// same control: same track, same pill, only the segment is two lines tall.
private struct SegmentedControlIconPreview: View {
    @State private var withIcons = "Internal"
    @State private var textOnly = "Internal"

    private let options = ["Receive", "Internal", "Send"]
    private let icons = [
        "Receive": "arrow.down",
        "Internal": "arrow.up.arrow.down",
        "Send": "arrow.up",
    ]

    var body: some View {
        VStack(spacing: 24) {
            SegmentedControl(
                options: options,
                selection: $withIcons,
                label: { $0 },
                icon: { icons[$0] ?? "questionmark" })

            SegmentedControl(options: options, selection: $textOnly)
        }
        .padding()
    }
}
