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

// MARK: - ArrowDownIcon

/// A code-drawn downward arrow matching the source SVG (9x13 viewBox):
/// a vertical shaft and a chevron arrowhead. Scales cleanly to any `size`.
struct ArrowDownIcon: View {
    var size: CGSize = CGSize(width: 9, height: 13)
    var color: Color = .dashBlue
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ArrowDownShape()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - ArrowDownShape

/// Arrow path normalized from the source SVG 9x13 viewBox.
private struct ArrowDownShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * (x / 9.0),
                y: rect.minY + rect.height * (y / 13.0)
            )
        }

        var path = Path()
        path.move(to: point(4.0498, 0.75))
        path.addLine(to: point(4.0498, 11.75))

        path.move(to: point(0.75, 8.44995))
        path.addLine(to: point(4.05, 11.75))
        path.addLine(to: point(7.35, 8.44995))

        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        ArrowDownIcon()
        ArrowDownIcon(size: CGSize(width: 16, height: 24))
        ArrowDownIcon(size: CGSize(width: 24, height: 34), color: .white, lineWidth: 2)
            .padding(20)
            .background(Color.dashBlue, in: RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}
