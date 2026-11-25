//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

extension Font {
    // MARK: - Titles

    /// Large Title: 34pt Bold (line height: 41pt)
    public static let largeTitle: Font = .system(size: 34, weight: .bold)

    /// Title 1: 28pt Bold (line height: 34pt)
    public static let title1: Font = .system(size: 28, weight: .bold)

    /// Title 2: 22pt Bold (line height: 28pt)
    public static let title2: Font = .system(size: 22, weight: .bold)

    /// Title 3: 20pt Bold (line height: 25pt)
    public static let title3: Font = .system(size: 20, weight: .bold)

    /// Title 3 Medium: 20pt Medium (line height: 25pt)
    public static let title3Medium: Font = .system(size: 20, weight: .medium)

    // MARK: - Text Styles

    /// Headline: 17pt Bold (line height: 22pt)
    public static let headline: Font = .system(size: 17, weight: .bold)

    /// Body: 17pt Regular (line height: 22pt)
    public static let body: Font = .system(size: 17, weight: .regular)

    /// Callout: 16pt Regular (line height: 21pt)
    public static let callout: Font = .system(size: 16, weight: .regular)

    /// Callout Medium: 16pt Semibold (line height: 21pt)
    public static let calloutMedium: Font = .system(size: 16, weight: .semibold)

    /// Subhead Regular: 15pt Regular (line height: 20pt)
    public static let subhead: Font = .system(size: 15, weight: .regular)

    /// Subhead Medium: 15pt Medium (line height: 20pt)
    public static let subheadMedium: Font = .system(size: 15, weight: .medium)

    /// Footnote Regular: 13pt Regular (line height: 18pt)
    public static let footnote: Font = .system(size: 13, weight: .regular)

    /// Footnote Medium: 13pt Medium (line height: 18pt)
    public static let footnoteMedium: Font = .system(size: 13, weight: .medium)

    /// Caption 1: 12pt Regular (line height: 16pt)
    public static let caption1: Font = .system(size: 12, weight: .regular)

    /// Caption 2: 11pt Regular (line height: 13pt)
    public static let caption2: Font = .system(size: 11, weight: .regular)
}

// MARK: - Dynamic Type

/// A system font that is `size` points at the default text size and scales
/// with the user's text size the way `textStyle` does. SwiftUI has no
/// `Font.system(size:relativeTo:)`; this is that, for designs whose sizes no
/// Apple text style has at the default setting (14pt, 18pt, …).
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` that follows Dynamic Type: `size`
    /// at the default text size, scaled like `textStyle` otherwise.
    func scaledSystemFont(size: CGFloat,
                          weight: Font.Weight = .regular,
                          design: Font.Design = .default,
                          relativeTo textStyle: Font.TextStyle) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}
