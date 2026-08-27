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

import SwiftUI
import UIKit

/// A generated fallback icon for a merchant that has no logo: the merchant's name (or
/// initials) in white on a circle/rounded square whose colour is derived deterministically
/// from the name, so the same merchant always looks the same.
///
/// Mirrors the Android implementation (`MerchantInitialIcon.kt`, dash-wallet #1506):
/// HSV with fixed 30% saturation / 60% brightness, hue spread over a hash of the name.
/// The hash replicates Java's `String.hashCode()` so a merchant gets the same colour on
/// both platforms.
struct MerchantLogoPlaceholder: View {
    enum Style {
        /// Full name, one word per line ("Home Depot" -> "Home" / "Depot").
        case name
        /// Initials of up to the first two words ("Home Depot" -> "HD").
        case initials
    }

    let merchantName: String
    var style: Style = .name
    /// Fraction of the box the text may use. A circle only exposes its inscribed square
    /// (~0.66 of the diameter); a rounded square exposes almost the whole box (~0.84).
    var usableFraction: CGFloat = 0.66

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                MerchantLogoPlaceholder.color(for: merchantName)
                text(side: side)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(style == .name ? max(words.count, 1) : 1)
                    .padding(side * (1 - usableFraction) / 2)
            }
        }
    }

    @ViewBuilder
    private func text(side: CGFloat) -> some View {
        switch style {
        case .initials:
            Text(MerchantLogoPlaceholder.initials(merchantName))
                .font(.system(size: side * 0.4, weight: .semibold))
        case .name:
            Text(words.joined(separator: "\n"))
                .font(.system(size: fittedFontSize(side: side), weight: .semibold))
        }
    }

    private var words: [String] {
        merchantName.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Estimate-based fit (no measurement pass): constrained by line count (height) and the
    /// longest word (width) against the usable area, then capped so short names aren't oversized.
    private func fittedFontSize(side: CGFloat) -> CGFloat {
        MerchantLogoPlaceholder.fittedFontSize(words: words, side: side, usableFraction: usableFraction)
    }

    // MARK: - Deterministic name → colour / initials (shared logic, matches Android)

    /// Deterministic background colour for a merchant name. HSV(hue, 0.3, 0.6) where the hue
    /// is spread over a Java-compatible hash of the lowercased name.
    static func color(for name: String) -> Color {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hue = key.isEmpty ? 0 : ((javaHashCode(key) % 360) + 360) % 360
        return Color(hue: Double(hue) / 360.0, saturation: 0.3, brightness: 0.6)
    }

    /// Initials: first letter of up to the first two words. "Home Depot" -> "HD", "Brinker" -> "B".
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        switch words.count {
        case 0: return ""
        case 1: return words[0].prefix(1).uppercased()
        default: return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
    }

    /// Replicates `java.lang.String.hashCode()`: `h = 31*h + c` over UTF-16 code units, with
    /// 32-bit wrapping overflow. Kept in sync with Android so colours match across platforms.
    private static func javaHashCode(_ s: String) -> Int {
        var hash: Int32 = 0
        for unit in s.utf16 {
            hash = 31 &* hash &+ Int32(unit)
        }
        return Int(hash)
    }
}

// MARK: - UIKit rendering

extension MerchantLogoPlaceholder {
    /// `UIColor` counterpart of `color(for:)` for UIKit call sites.
    static func uiColor(for name: String) -> UIColor {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hue = key.isEmpty ? 0 : ((javaHashCode(key) % 360) + 360) % 360
        return UIColor(hue: CGFloat(hue) / 360.0, saturation: 0.3, brightness: 0.6, alpha: 1)
    }

    /// Renders the full-name placeholder as a `UIImage`, for UIKit spots (list cell, map marker).
    /// Mirrors the SwiftUI `.name` style: white words (one per line, auto-fitted) on the
    /// deterministic colour, clipped to a circle or rounded square.
    static func image(merchantName: String, size: CGSize, cornerRadius: CGFloat) -> UIImage {
        let side = min(size.width, size.height)
        // A circle only exposes its inscribed square (~0.66); a rounded square exposes ~0.84.
        let isCircle = cornerRadius >= side / 2
        let usableFraction: CGFloat = isCircle ? 0.66 : 0.84

        let words = merchantName.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let fontSize = fittedFontSize(words: words, side: side, usableFraction: usableFraction)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: min(cornerRadius, side / 2))
            uiColor(for: merchantName).setFill()
            path.fill()

            guard !words.isEmpty else { return }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byClipping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let text = words.joined(separator: "\n") as NSString
            let usable = side * usableFraction
            let bounding = CGSize(width: usable, height: side)
            let textRect = text.boundingRect(with: bounding,
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: attrs, context: nil)
            let drawRect = CGRect(x: (size.width - textRect.width) / 2,
                                  y: (size.height - textRect.height) / 2,
                                  width: textRect.width, height: textRect.height)
            text.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                      attributes: attrs, context: nil)
        }
    }

    /// Shared with the SwiftUI view: estimate-based font fit (no measurement pass).
    fileprivate static func fittedFontSize(words: [String], side: CGFloat, usableFraction: CGFloat) -> CGFloat {
        guard !words.isEmpty else { return 1 }
        let usable = side * usableFraction
        let longestWord = CGFloat(words.map(\.count).max() ?? 1)
        let byHeight = usable / (CGFloat(words.count) * 1.15)
        let byWidth = usable / (longestWord * 0.58)
        let maxFont = side * 0.4
        return max(min(byHeight, byWidth, maxFont), 6)
    }
}

#if DEBUG
struct MerchantLogoPlaceholder_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            MerchantLogoPlaceholder(merchantName: "Home Depot")
                .frame(width: 50, height: 50).clipShape(Circle())
            MerchantLogoPlaceholder(merchantName: "Brinker")
                .frame(width: 50, height: 50).clipShape(Circle())
            MerchantLogoPlaceholder(merchantName: "Mortons The Steak House", usableFraction: 0.84)
                .frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 8))
            MerchantLogoPlaceholder(merchantName: "Amazon", style: .initials)
                .frame(width: 50, height: 50).clipShape(Circle())
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
