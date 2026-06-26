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

import Combine
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

struct LoadingSpinner: View {
    /// Default tint — Maya blue (#008DE4).
    static let defaultColor = Color(red: 0, green: 141 / 255, blue: 228 / 255)

    let size: CGFloat
    let color: Color
    let spokeCount: Int
    /// Seconds for the bright head to travel once around the ring.
    let duration: Double

    @State private var phase = 0
    private let timer: Publishers.Autoconnect<Timer.TimerPublisher>

    init(size: CGFloat = 61.73, color: Color = defaultColor, spokeCount: Int = 12, duration: Double = 1) {
        self.size = size
        self.color = color
        self.spokeCount = spokeCount
        self.duration = duration
        self.timer = Timer
            .publish(every: duration / Double(max(spokeCount, 1)), on: .main, in: .common)
            .autoconnect()
    }

    private var stepInterval: Double { duration / Double(max(spokeCount, 1)) }

    var body: some View {
        ZStack {
            ForEach(0..<spokeCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .opacity(opacity(for: index))
                    .frame(width: size * 0.083, height: size * 0.25)
                    .offset(y: -size * 0.375)
                    .rotationEffect(.degrees(Double(index) / Double(spokeCount) * 360))
            }
        }
        .frame(width: size, height: size)
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: stepInterval)) {
                phase = (phase + 1) % spokeCount
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        guard spokeCount > 1 else { return 0.75 }
        let distanceFromHead = (index - phase + spokeCount) % spokeCount
        return 0.2 + 0.55 * (1 - Double(distanceFromHead) / Double(spokeCount - 1))
    }
}

#Preview {
    VStack(spacing: 40) {
        LoadingIllustration()
        LoadingIllustration(size: 32, color: .red)
        LoadingSpinner(size: 24, color: .gray, spokeCount: 8, duration: 0.8)
    }
}
