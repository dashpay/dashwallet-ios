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
