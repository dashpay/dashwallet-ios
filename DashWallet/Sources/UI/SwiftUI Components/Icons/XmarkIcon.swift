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

// MARK: - XmarkIcon

/// A code-drawn "✕" (close) icon. Mirrors the source SVG (9×9 viewBox, two diagonals
/// inset from 0.75 to 7.75, round caps/joins). Scales cleanly to any `size`.
struct XmarkIcon: View {
    var size: CGFloat = 9
    var color: Color = .primaryText
    var lineWidth: CGFloat = 1.5

    var body: some View {
        XmarkShape()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

// MARK: - XmarkShape

/// Two diagonal strokes forming an "✕". Endpoints are normalized from the 9-unit
/// source viewBox (inset 0.75 → 7.75) so the cross keeps its proportions at any size.
private struct XmarkShape: Shape {
    private let insetRatio: CGFloat = 0.75 / 9
    private let extentRatio: CGFloat = 7.75 / 9

    func path(in rect: CGRect) -> Path {
        let minX = rect.minX + rect.width * insetRatio
        let maxX = rect.minX + rect.width * extentRatio
        let minY = rect.minY + rect.height * insetRatio
        let maxY = rect.minY + rect.height * extentRatio

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        path.move(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        XmarkIcon()
        XmarkIcon(size: 24, color: .white, lineWidth: 2)
            .padding(20)
            .background(Color.dashBlue, in: .circle)
        XmarkIcon(size: 40, color: .red, lineWidth: 3)
    }
    .padding()
}
