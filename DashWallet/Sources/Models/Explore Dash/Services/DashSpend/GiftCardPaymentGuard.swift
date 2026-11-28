//
//  GiftCardPaymentGuard.swift
//  DashWallet
//
//  Acceptance check for a gift-card provider's payment quote (CTX, PiggyCards).
//

import Foundation

/// Compares a provider-quoted gift-card payment with the price the buyer confirmed.
///
/// The buyer confirms a fiat price and the Dash amount it comes to at the wallet's rate. The
/// provider then quotes the Dash amount with its own exchange rate, so the quote rarely equals
/// the confirmed amount. A quote that is higher by more than a small margin is put to the
/// buyer again before anything is signed.
enum GiftCardPaymentGuard {
    /// The largest increase over the confirmed amount that is paid without asking the buyer
    /// again, in basis points (50 = 0.5%). It covers the gap between the provider's rate
    /// source and the wallet's, and the time between the two readings. The value is a
    /// judgment call: it has not been calibrated against live provider quotes.
    static let silentIncreaseBasisPoints: UInt64 = 50

    /// The increase from which the price change is shown with a warning, in basis points
    /// (500 = 5%).
    static let warningBasisPoints: UInt64 = 500

    /// How long the buyer has to accept a higher price when the provider's order states no
    /// expiry of its own. Two minutes is the PIN prompt's own timeout, which was the longest
    /// such an order waited for its payment before the price was put to the buyer. The value
    /// is not taken from a provider: how long an unpaid order stays open is not known here.
    static let priceAnswerLimit: TimeInterval = 120

    /// The time allowed for accepting a higher price on a payment request.
    ///
    /// - Parameter requestExpires: the request's `expires` time; 0 when it states none, which
    ///   is also how an omitted field decodes.
    /// - Returns: `priceAnswerLimit` for a request with no expiry, `nil` for one that states
    ///   an expiry: `BIP70PaymentService.authorizeAndSend` checks that expiry again once the
    ///   buyer has answered.
    static func priceAnswerLimit(requestExpires: UInt64) -> TimeInterval? {
        requestExpires == 0 ? priceAnswerLimit : nil
    }

    /// The wallet's exchange rate as read when a purchase is approved.
    struct ExchangeRate {
        /// Fiat price of one Dash; nil when the wallet has no rate.
        let price: Decimal?
        /// Unix time the rate was retrieved; 0 when unknown.
        let retrievedAt: Int
    }

    /// The price a buyer confirmed: the fiat amount, and the Dash amount it comes to at the
    /// wallet's rate.
    struct Approval: Equatable {
        /// The confirmed price in duffs at `rate`.
        let amount: UInt64
        /// The confirmed price in fiat: the card value less the discount. For CTX it is
        /// rounded up to the card currency's decimals, and is the figure the buyer is shown.
        let fiatAmount: Decimal
        /// Fiat price of one Dash that `amount` was computed with.
        let rate: Decimal
        /// Unix time `rate` was retrieved.
        let rateRetrievedAt: Int

        /// `false` once `rate` is older than the app's stale-rate limit.
        func isRateFresh(now: Date = Date()) -> Bool {
            GiftCardPaymentGuard.isRateFresh(lastRetrieval: rateRetrievedAt, now: now)
        }

        /// Compares the duffs a provider requested with the confirmed amount.
        ///
        /// A request at or below the confirmed amount, or above it by no more than
        /// `silentIncreaseBasisPoints`, is `.asConfirmed`. Anything higher is `.higher`, for
        /// the buyer to accept or decline. A request for no Dash throws `invalidAmountError`.
        func assess(requested: UInt64) throws -> Assessment {
            guard requested > 0 else {
                DWLogger.log("Gift card payment refused: the provider requested no Dash")
                throw GiftCardPaymentGuard.invalidAmountError
            }
            guard requested > amount,
                  requested - amount > GiftCardPaymentGuard.share(
                      of: amount, basisPoints: GiftCardPaymentGuard.silentIncreaseBasisPoints, roundingUp: false) else {
                return .asConfirmed
            }

            let warningFrom = GiftCardPaymentGuard.share(
                of: amount, basisPoints: GiftCardPaymentGuard.warningBasisPoints, roundingUp: true)
            return .higher(PriceChange(confirmedAmount: amount,
                                       confirmedFiat: fiatAmount,
                                       requestedAmount: requested,
                                       requestedFiat: Decimal(requested) / Decimal(100_000_000) * rate,
                                       needsWarning: requested - amount >= warningFrom))
        }
    }

    /// What a provider's quote is against the confirmed price.
    enum Assessment: Equatable {
        /// The buyer pays what they confirmed, less, or more by a margin too small to ask about.
        case asConfirmed
        /// The provider asks for more than the buyer confirmed.
        case higher(PriceChange)
    }

    /// A provider's quote that is higher than the confirmed price, as the figures the buyer
    /// is shown before deciding.
    struct PriceChange: Equatable {
        /// The confirmed price in duffs.
        let confirmedAmount: UInt64
        /// The confirmed price in fiat.
        let confirmedFiat: Decimal
        /// The duffs the provider requested.
        let requestedAmount: UInt64
        /// `requestedAmount` in fiat at the rate the buyer confirmed with.
        let requestedFiat: Decimal
        /// `true` when the increase is `warningBasisPoints` or more.
        let needsWarning: Bool

        var differenceAmount: UInt64 { requestedAmount - confirmedAmount }
        var differenceFiat: Decimal { requestedFiat - confirmedFiat }
        /// The increase as a fraction of the confirmed amount (0.04 = 4%).
        var increaseFraction: Decimal { Decimal(differenceAmount) / Decimal(confirmedAmount) }
    }

    /// Turns the confirmed card value and discount into an `Approval`. Every provider's quote
    /// is compared through the `Approval` this returns.
    ///
    /// Throws `rateUnavailableError` when the rate is missing, not a positive number, or not
    /// fresh, and when the converted amount is not a positive duff count: a quote cannot be
    /// compared against such a rate. The amount is rounded down to a whole duff.
    ///
    /// - Parameter currency: the card currency whose decimals the discounted price is rounded
    ///   up to; `nil` holds the price less the discount as it is, which is what a PiggyCards
    ///   purchase is approved at.
    static func approve(price: Decimal, discount: Decimal, currency: String?, rate: ExchangeRate,
                        now: Date = Date()) throws -> Approval {
        let fiatAmount = currency.map { GiftCardCurrency.discounted(price, by: discount, currency: $0) }
            ?? price * (1 - discount)
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

        return Approval(amount: duffs, fiatAmount: fiatAmount, rate: ratePrice,
                        rateRetrievedAt: rate.retrievedAt)
    }

    /// `amount * basisPoints / 10_000`, rounded down or up to a whole duff. Split so the
    /// product cannot overflow.
    static func share(of amount: UInt64, basisPoints: UInt64, roundingUp: Bool) -> UInt64 {
        let remainder = (amount % 10_000) * basisPoints
        return (amount / 10_000) * basisPoints + (remainder + (roundingUp ? 9_999 : 0)) / 10_000
    }

    /// The Dash amount a provider wrote into its payment request, or nil unless the whole
    /// string is a plain decimal number (`GiftCardCurrency.plainDecimal`).
    static func dashAmount(fromQuotedString string: String) -> Decimal? {
        GiftCardCurrency.plainDecimal(string)
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

    /// A provider amount that is zero or cannot be read as a duff count.
    static var invalidAmountError: DashSpendError {
        .paymentProcessingError(String(localized: "Invalid gift card amount", comment: "DashSpend"))
    }

    static var invalidPaymentAddressError: DashSpendError {
        .customError(String(
            localized: "The gift card provider returned an invalid payment address. Nothing was sent. Please try again or contact support.",
            comment: "DashSpend"))
    }

    /// A higher price that was accepted after `priceAnswerLimit`.
    static var quoteExpiredError: DashSpendError {
        .customError(String(localized: "This quote expired. Please go back and try again.", comment: "DashSpend"))
    }

    static var rateUnavailableError: DashSpendError {
        .customError(String(
            localized: "The exchange rate is unavailable, so this payment could not be checked. Nothing was sent. Please try again in a moment.",
            comment: "DashSpend"))
    }
}
