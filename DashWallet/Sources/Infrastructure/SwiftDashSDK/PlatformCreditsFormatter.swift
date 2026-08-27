//
//  PlatformCreditsFormatter.swift
//  DashWallet
//

import Foundation

enum PlatformCreditsFormatter {
    static let creditsPerDash: UInt64 = 100_000_000_000

    static func dashString(_ credits: UInt64) -> String {
        if credits == 0 {
            return "0 DASH"
        }

        let dash = Double(credits) / Double(creditsPerDash)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 11
        formatter.groupingSeparator = ""

        let string = formatter.string(from: NSNumber(value: dash)) ?? "\(dash)"
        return "\(string) DASH"
    }
}
