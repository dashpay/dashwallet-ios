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
import UIKit

// MARK: - ExclamationIcon

/// A code-drawn warning icon that mirrors the source SVG (18x17 viewBox):
/// a yellow rounded triangle with an exclamation mark inside. Scales cleanly
/// to any `size` without needing raster assets.
struct ExclamationIcon: View {
    var size: CGSize = CGSize(width: 18, height: 17)
    var fillColor: Color = Color(uiColor: UIColor(red: 1.0, green: 192.0 / 255.0, blue: 67.0 / 255.0, alpha: 1.0))
    var strokeColor: Color = Color(uiColor: UIColor(red: 1.0, green: 192.0 / 255.0, blue: 67.0 / 255.0, alpha: 1.0))
    var symbolColor: Color = Color(uiColor: UIColor(red: 10.0 / 255.0, green: 11.0 / 255.0, blue: 13.0 / 255.0, alpha: 1.0))
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            WarningTriangleShape()
                .fill(fillColor)

            WarningTriangleShape()
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            ExclamationMarkShape()
                .stroke(symbolColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - WarningTriangleShape

/// Triangle path normalized from the source SVG 18x17 viewBox.
private struct WarningTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * (x / 18.0),
                y: rect.minY + rect.height * (y / 17.0)
            )
        }

        var path = Path()
        path.move(to: point(13.7031, 15.75))
        path.addLine(to: point(3.32148, 15.75))
        path.addCurve(
            to: point(1.04863, 11.9904),
            control1: point(1.3904, 15.75),
            control2: point(0.15145, 13.6993)
        )
        path.addLine(to: point(6.24373, 2.1214))
        path.addCurve(
            to: point(10.7894, 2.1214),
            control1: point(7.20927, 0.292865),
            control2: point(9.8239, 0.292865)
        )
        path.addLine(to: point(15.9845, 11.9904))
        path.addCurve(
            to: point(13.7117, 15.75),
            control1: point(16.8817, 13.6993),
            control2: point(15.6428, 15.75)
        )
        path.addLine(to: point(13.7031, 15.75))
        path.closeSubpath()
        return path
    }
}

// MARK: - ExclamationMarkShape

/// Exclamation mark path normalized from the source SVG 18x17 viewBox.
private struct ExclamationMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * (x / 18.0),
                y: rect.minY + rect.height * (y / 17.0)
            )
        }

        var path = Path()
        path.move(to: point(8.50806, 9.1023))
        path.addLine(to: point(8.50806, 6.11169))

        path.move(to: point(8.50806, 12.0923))
        path.addLine(to: point(8.50806, 12.0844))
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        ExclamationIcon()
        ExclamationIcon(size: CGSize(width: 28, height: 26.5))
        ExclamationIcon(size: CGSize(width: 44, height: 41.5))
    }
    .padding()
}
