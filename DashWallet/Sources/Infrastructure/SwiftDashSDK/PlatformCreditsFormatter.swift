//
//  PlatformCreditsFormatter.swift
//  DashWallet
//

import Foundation

enum PlatformCreditsFormatter {
    static let creditsPerDash: UInt64 = 100_000_000_000

    /// Credits rendered as DASH at full credit precision, with no grouping and
    /// trailing zeros trimmed.
    ///
    /// Integer arithmetic, not `Double`: a `Double` cannot represent every
    /// `UInt64` credit amount above 2^53, so a large amount rendered through
    /// it came out rounded while the exact integer was the one spent.
    static func dashString(_ credits: UInt64) -> String {
        dashString(credits, locale: .current)
    }

    /// The same, with an explicit locale for the decimal separator. A separate
    /// overload rather than a defaulted parameter: the sync screens pass
    /// `dashString` as a `(UInt64) -> String` function value, which a defaulted
    /// second parameter does not satisfy.
    static func dashString(_ credits: UInt64, locale: Locale) -> String {
        let whole = credits / creditsPerDash
        let fraction = credits % creditsPerDash
        guard fraction > 0 else {
            return "\(whole) DASH"
        }

        let fractionDigits = String(creditsPerDash).count - 1
        var digits = String(fraction)
        digits = String(repeating: "0", count: fractionDigits - digits.count) + digits
        while digits.hasSuffix("0") {
            digits.removeLast()
        }
        let separator = locale.decimalSeparator ?? "."
        return "\(whole)\(separator)\(digits) DASH"
    }
}
