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

// MARK: - LoadingIllustration

/// Wrapper that centers the loading spinner inside a fixed-size frame, matching the
/// Maya design (Figma node 6:254 — a 90×90 frame containing a 61.73 spinner).
struct LoadingIllustration: View {
    /// Diameter of the spinner.
    var size: CGFloat = 61.73
    /// Spinner tint.
    var color: Color = LoadingSpinner.defaultColor
    /// Size of the surrounding square frame (the spinner is centered within it).
    var containerSize: CGFloat = 90

    var body: some View {
        ZStack {
            LoadingSpinner(size: size, color: color)
        }
        .frame(width: containerSize, height: containerSize)
    }
}

// MARK: - LoadingSpinner

/// A spinner built from `spokeCount` capsules arranged in a ring with a graduated
/// "comet-tail" opacity. The spokes are static; the whole ring rotates continuously.
struct LoadingSpinner: View {
    /// Default tint — Maya blue (#008DE4).
    static let defaultColor = Color(red: 0, green: 141 / 255, blue: 228 / 255)

    /// Diameter of the spinner.
    var size: CGFloat = 61.73
    /// Spoke tint.
    var color: Color = defaultColor
    /// Number of spokes in the ring.
    var spokeCount: Int = 12
    /// Seconds for one full rotation.
    var duration: Double = 1

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<spokeCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .opacity(opacity(for: index))
                    // Proportions taken from the Figma SVG (viewBox 61.73):
                    // width 0.083·size, height 0.25·size, outer edge at radius 0.5·size.
                    .frame(width: size * 0.083, height: size * 0.25)
                    .offset(y: -size * 0.375)
                    .rotationEffect(.degrees(Double(index) / Double(spokeCount) * 360))
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(isAnimating ? 360 : 0))
        .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: isAnimating)
        .onAppear { isAnimating = true }
    }

    private func opacity(for index: Int) -> Double {
        guard spokeCount > 1 else { return 0.75 }
        return 0.2 + 0.55 * Double(index) / Double(spokeCount - 1)
    }
}

#Preview {
    VStack(spacing: 40) {
        LoadingIllustration()
        LoadingIllustration(size: 32, color: .red)
        LoadingSpinner(size: 24, color: .gray, spokeCount: 8, duration: 0.8)
    }
}
