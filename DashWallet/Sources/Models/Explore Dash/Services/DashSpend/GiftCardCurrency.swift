//
//  GiftCardCurrency.swift
//  DashWallet
//
//  Money rules for the currency a gift card is priced in.
//

import Foundation

/// Money rules for the currency a gift card is priced in: the merchant's, which is not always
/// USD. Amounts are `Decimal` throughout.
enum GiftCardCurrency {
    /// The currency of PiggyCards cards, of the merchants in the explore database, and of a
    /// saved card that records none.
    static let usd = "USD"

    private static let codesInUse = Set(Locale.commonISOCurrencyCodes)

    // ISO 4217 minor units where they are not 2. `NumberFormatter` cannot be asked: its
    // figures are CLDR's, which give HUF, IDR and PKR no decimals and IQD none instead of 3.
    private static let minorUnits: [String: Int] = [
        "BIF": 0, "CLP": 0, "DJF": 0, "GNF": 0, "ISK": 0, "JPY": 0, "KMF": 0, "KRW": 0, "PYG": 0,
        "RWF": 0, "UGX": 0, "UYI": 0, "VND": 0, "VUV": 0, "XAF": 0, "XOF": 0, "XPF": 0,
        "BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3,
        "CLF": 4, "UYW": 4,
    ]

    /// The upper-case ISO 4217 code of a currency in use, or nil when `code` is absent, blank
    /// or not one.
    static func normalize(_ code: String?) -> String? {
        guard let candidate = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              codesInUse.contains(candidate) else {
            return nil
        }
        return candidate
    }

    /// The decimals an amount in `currency` can have: 0 for JPY, 3 for KWD.
    static func fractionDigits(_ currency: String) -> Int {
        minorUnits[currency] ?? 2
    }

    /// The number a provider wrote as text, or nil unless the whole string is plain decimal
    /// digits with at most one decimal point ("1", "0.25"). `Decimal(string:)` alone reads a
    /// leading number and ignores what follows it, so the string is checked first. Signs,
    /// exponents, grouping separators and whitespace are refused, as is anything longer than
    /// `Decimal` can hold exactly.
    ///
    /// The check reads UTF-8 bytes, not `Character`s: a digit followed by a combining mark
    /// is one `Character` that sorts between "0" and "9".
    static func plainDecimal(_ string: String) -> Decimal? {
        let bytes = string.utf8
        guard bytes.count <= 30 else { return nil }

        let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
        let parts = bytes.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy { asciiDigits.contains($0) } }) else {
            return nil
        }

        return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// `false` when `amount` has more decimals than the currency has, e.g. 1000.5 JPY.
    static func isRepresentable(_ amount: Decimal, in currency: String) -> Bool {
        fits(amount, decimals: fractionDigits(currency))
    }

    private static func fits(_ amount: Decimal, decimals: Int) -> Bool {
        guard amount.isFinite else { return false }
        var source = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, decimals, .plain)
        return rounded == amount
    }

    /// The amount as a provider's API takes it, whatever the device locale: ASCII digits, "."
    /// and exactly the currency's decimals, with no grouping. Nil for an amount that is not
    /// above zero or that the currency cannot hold; the amount is never rounded.
    static func orderAmount(_ amount: Decimal, currency: String) -> String? {
        guard amount > 0, isRepresentable(amount, in: currency) else { return nil }

        let digits = fractionDigits(currency)
        var source = amount
        var scaled = Decimal()
        var units = Decimal()
        NSDecimalMultiplyByPowerOf10(&scaled, &source, Int16(digits), .plain)
        NSDecimalRound(&units, &scaled, 0, .plain)

        var text = NSDecimalNumber(decimal: units).stringValue
        let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
        guard units == scaled, text.utf8.allSatisfy({ asciiDigits.contains($0) }) else { return nil }
        guard digits > 0 else { return text }

        text = String(repeating: "0", count: max(0, digits + 1 - text.count)) + text
        return "\(text.dropLast(digits)).\(text.suffix(digits))"
    }

    /// Formats amounts for display in `locale`, with the currency's own number of decimals.
    static func formatter(for currency: String, locale: Locale = .current) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = fractionDigits(currency)
        formatter.maximumFractionDigits = fractionDigits(currency)
        return formatter
    }

    /// `amount` for display in `locale`, with the currency's symbol and decimals.
    ///
    /// - Parameter trimsWholeAmounts: a whole amount is written without decimals ("$25").
    static func string(_ amount: Decimal, currency: String, locale: Locale = .current,
                       trimsWholeAmounts: Bool = false) -> String {
        let formatter = formatter(for: currency, locale: locale)
        if trimsWholeAmounts, fits(amount, decimals: 0) {
            formatter.minimumFractionDigits = 0
        }
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? ""
    }

    /// `amount` as a bare number in `locale`: no symbol, no grouping, and no more decimals
    /// than the currency has.
    static func plainString(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits(currency)
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? ""
    }

    /// The currency's symbol as `locale` writes it.
    static func symbol(for currency: String, locale: Locale = .current) -> String {
        formatter(for: currency, locale: locale).currencySymbol
    }

    /// The currency of a saved card. One without a currency was bought when every card was USD.
    static func ofSavedCard(_ stored: String?) -> String {
        normalize(stored) ?? usd
    }

    /// The first currency a provider's answer names that is not the one ordered, or nil when
    /// every currency it names is. The Dash amount in the answer is paid as it stands, so it
    /// must be for the card that was ordered.
    static func mismatch(ordered: String, reported: [String?]) -> String? {
        reported
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.caseInsensitiveCompare(ordered) != .orderedSame }
    }
}
