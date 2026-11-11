//
//  GiftCardPaymentGuard.swift
//  DashWallet
//
//  Acceptance check for a gift-card provider's payment quote (CTX, PiggyCards).
//

import Foundation

/// Checks a provider-quoted gift-card payment against the price the buyer approved.
///
/// The buyer approves a fiat price. The provider then quotes the Dash amount with its own
/// exchange rate, so the quote never equals the approved price converted at the wallet's rate.
enum GiftCardPaymentGuard {
    /// The most a quote may exceed the approved price converted at the wallet's rate, in
    /// basis points (500 = 5%). It covers the gap between the provider's rate source and the
    /// wallet's, and the time between the two readings. The value is a judgment call: it has
    /// not been calibrated against live provider quotes.
    static let maxOverchargeBasisPoints: UInt64 = 500

    /// The wallet's exchange rate as read when a purchase is approved.
    struct ExchangeRate {
        /// Fiat price of one Dash; nil when the wallet has no rate.
        let price: Decimal?
        /// Unix time the rate was retrieved; 0 when unknown.
        let retrievedAt: Int
    }

    /// The price a buyer approved, as the most Dash a provider may ask for it.
    struct Approval {
        /// The approved price in duffs at the wallet's rate, before the margin.
        let amount: UInt64

        /// Throws unless `requested` duffs is positive and within the margin above `amount`.
        func check(requested: UInt64) throws {
            guard GiftCardPaymentGuard.isWithinApprovedAmount(requested: requested, expected: amount) else {
                DWLogger.log("Gift card payment refused: requested \(requested) duffs, approved \(amount)")
                throw GiftCardPaymentGuard.amountAboveApprovedError
            }
        }
    }

    /// Turns the confirmed card value and discount into an `Approval`. Every provider's quote
    /// is checked through the `Approval` this returns.
    ///
    /// Throws `rateUnavailableError` when the rate is missing, not a positive number, or not
    /// fresh, and when the converted amount is not a positive duff count: a quote cannot be
    /// checked against such a rate. The amount is rounded down to a whole duff.
    static func approve(price: Decimal, discount: Decimal, rate: ExchangeRate,
                        now: Date = Date()) throws -> Approval {
        let fiatAmount = price * (1 - discount)
        guard fiatAmount.isFinite, fiatAmount > 0 else { throw DashSpendError.invalidAmount }

        guard let ratePrice = rate.price, ratePrice.isFinite, ratePrice > 0,
              isRateFresh(lastRetrieval: rate.retrievedAt, now: now) else {
            throw rateUnavailableError
        }

        let dashAmount = fiatAmount / ratePrice
        guard dashAmount.isFinite, dashAmount > 0 else { throw rateUnavailableError }

        var scaled = dashAmount * Decimal(100_000_000)
        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .down)
        guard whole.isFinite, whole > 0, whole <= Decimal(UInt64.max),
              let duffs = UInt64(NSDecimalNumber(decimal: whole).stringValue) else {
            throw rateUnavailableError
        }

        return Approval(amount: duffs)
    }

    /// `true` when `requested` is positive and at most `expected` plus the allowed margin.
    /// A quote below `expected` passes: the buyer pays less than they approved.
    static func isWithinApprovedAmount(requested: UInt64, expected: UInt64) -> Bool {
        guard requested > 0, expected > 0 else { return false }
        guard requested > expected else { return true }

        // floor(expected * basisPoints / 10_000), split so the product cannot overflow.
        let allowance = (expected / 10_000) * maxOverchargeBasisPoints
            + (expected % 10_000) * maxOverchargeBasisPoints / 10_000
        return requested - expected <= allowance
    }

    /// The Dash amount a provider wrote into its payment request, or nil unless the whole
    /// string is plain decimal digits with at most one decimal point ("1", "0.25").
    /// `Decimal(string:)` alone reads a leading number and ignores what follows it, so the
    /// string is checked first. Signs, exponents, grouping separators and whitespace are
    /// refused, as is anything longer than `Decimal` can hold exactly.
    ///
    /// The check reads UTF-8 bytes, not `Character`s: a digit followed by a combining mark
    /// is one `Character` that sorts between "0" and "9".
    static func dashAmount(fromQuotedString string: String) -> Decimal? {
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

    /// `true` when the wallet's exchange rate was retrieved within the app's stale-rate
    /// limit (`kStaleRatesDuration`, the limit behind the "Prices are at least 30 minutes
    /// old" warning). A rate with no recorded retrieval time, or one recorded after `now`
    /// (the clock moved back, so its age is unknown), is not fresh.
    static func isRateFresh(lastRetrieval: Int, now: Date = Date()) -> Bool {
        guard lastRetrieval > 0 else { return false }
        let age = now.timeIntervalSince1970 - TimeInterval(lastRetrieval)
        return age >= 0 && age <= kStaleRatesDuration
    }

    /// A Dash amount as duffs, or nil when it is not positive, is finer than one duff, or
    /// does not fit in `UInt64`. Exact: no rounding and no binary floating point.
    static func duffs(fromDashAmount amount: Decimal) -> UInt64? {
        guard amount.isFinite, amount > 0 else { return nil }

        var scaled = amount * Decimal(100_000_000)
        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .plain)
        guard whole == scaled, whole <= Decimal(UInt64.max) else { return nil }

        return UInt64(NSDecimalNumber(decimal: whole).stringValue)
    }

    static var amountAboveApprovedError: DashSpendError {
        .customError(NSLocalizedString(
            "The gift card provider requested more Dash than the price you approved. Nothing was sent. Please try again or contact support.",
            comment: "DashSpend"))
    }

    static var invalidPaymentAddressError: DashSpendError {
        .customError(NSLocalizedString(
            "The gift card provider returned an invalid payment address. Nothing was sent. Please try again or contact support.",
            comment: "DashSpend"))
    }

    static var rateUnavailableError: DashSpendError {
        .customError(NSLocalizedString(
            "The exchange rate is unavailable, so this payment could not be checked. Nothing was sent. Please try again in a moment.",
            comment: "DashSpend"))
    }
}
