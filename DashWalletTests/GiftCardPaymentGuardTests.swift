//
//  GiftCardPaymentGuardTests.swift
//  DashWalletTests
//
//  A gift-card provider quotes the Dash amount for a price the buyer approved in fiat.
//  These tests pin where a quote stops being acceptable, and the exact conversion of a
//  quoted Dash amount to duffs.
//

import XCTest
@testable import dashpay

final class GiftCardPaymentGuardTests: XCTestCase {

    // MARK: - isWithinApprovedAmount

    /// 1 DASH approved: the margin is 5%, so 1.05 DASH is the last accepted quote.
    private let approved: UInt64 = 100_000_000
    private let cap: UInt64 = 105_000_000

    func testMarginIsFivePercent() {
        XCTAssertEqual(GiftCardPaymentGuard.maxOverchargeBasisPoints, 500)
    }

    func testQuoteEqualToApprovedPasses() {
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: approved, expected: approved))
    }

    func testQuoteJustUnderTheMarginPasses() {
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: cap - 1, expected: approved))
    }

    func testQuoteAtTheMarginPasses() {
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: cap, expected: approved))
    }

    func testQuoteOneDuffOverTheMarginIsRefused() {
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: cap + 1, expected: approved))
    }

    func testQuoteFarAboveApprovedIsRefused() {
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: approved * 10, expected: approved))
    }

    /// Paying less than approved cannot cost the buyer anything, so there is no lower bound.
    func testQuoteBelowApprovedPasses() {
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: 1, expected: approved))
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: approved / 2, expected: approved))
    }

    func testZeroQuoteIsRefused() {
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: 0, expected: approved))
    }

    /// Without an approved amount there is nothing to compare against.
    func testZeroApprovedAmountIsRefused() {
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: approved, expected: 0))
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: 0, expected: 0))
    }

    /// The allowance rounds down: 5% of 19 duffs is 0.95, so nothing above 19 is accepted.
    func testAllowanceRoundsDownForSmallAmounts() {
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: 19, expected: 19))
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: 20, expected: 19))
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: 21, expected: 20))
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: 22, expected: 20))
    }

    func testValuesNearUInt64MaxDoNotOverflow() {
        let max = UInt64.max
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: max, expected: max))
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: max - 1, expected: max))
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: max, expected: 1))
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: max, expected: max / 2))

        // The largest approved amount whose 5% margin still fits below UInt64.max.
        let expected = max / 21 * 20
        let allowance = expected / 20
        XCTAssertTrue(GiftCardPaymentGuard.isWithinApprovedAmount(requested: expected + allowance, expected: expected))
        XCTAssertFalse(GiftCardPaymentGuard.isWithinApprovedAmount(requested: expected + allowance + 1, expected: expected))
    }

    // MARK: - duffs(fromDashAmount:)

    private func dash(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    func testExactAmountsConvert() {
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("1")), 100_000_000)
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("1.234")), 123_400_000)
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("0.00000001")), 1)
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("21000000")), 2_100_000_000_000_000)
    }

    /// Amounts that a binary double cannot hold exactly still convert to the exact duff count.
    func testEightDecimalAmountsConvertExactly() {
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("0.12345678")), 12_345_678)
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("0.1")), 10_000_000)
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("0.29")), 29_000_000)
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("1.15")), 115_000_000)
    }

    func testSubDuffAmountIsRefused() {
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: dash("0.123456789")))
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: dash("0.000000001")))
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: dash("1.000000005")))
    }

    func testZeroAndNegativeAmountsAreRefused() {
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: 0))
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: dash("-1")))
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: dash("-0.00000001")))
    }

    func testNotANumberIsRefused() {
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: Decimal.nan))
    }

    func testAmountTooLargeForUInt64IsRefused() {
        // UInt64.max duffs is 184467440737.09551615 DASH.
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: dash("184467440737.09551615")), UInt64.max)
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: dash("184467440737.09551616")))
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: dash("1000000000000")))
    }

    // MARK: - dashAmount(fromQuotedString:)

    func testPlainDecimalStringsParse() {
        XCTAssertEqual(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1"), dash("1"))
        XCTAssertEqual(GiftCardPaymentGuard.dashAmount(fromQuotedString: "0.25"), dash("0.25"))
        XCTAssertEqual(GiftCardPaymentGuard.dashAmount(fromQuotedString: "12.34567891"), dash("12.34567891"))
        XCTAssertEqual(GiftCardPaymentGuard.dashAmount(fromQuotedString: "007.50"), dash("7.5"))
    }

    /// The whole string has to be a number: a leading number followed by anything else is refused.
    func testTrailingTextIsRefused() {
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1.25invalid"))
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1.25 "))
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1.25&x"))
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1.25DASH"))
    }

    func testRepeatedDecimalSeparatorsAreRefused() {
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1.2.3"))
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1..2"))
    }

    func testCommaFormattedAmountsAreRefused() {
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1,234.5"))
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: "1,25"))
    }

    func testSignsExponentsAndBareSeparatorsAreRefused() {
        for string in ["-1", "+1", "1e-3", "1E3", ".5", "1.", ".", "", " 1.5", "abc", "0x10", "１.５"] {
            XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: string), "accepted \"\(string)\"")
        }
    }

    /// A digit that carries a combining mark, a variation selector or a joiner is one
    /// `Character`, and `Decimal(string:)` reads the digits in front of it.
    func testDigitsWithCombiningMarksAreRefused() {
        for string in ["1\u{0301}25", "1\u{0301}", "0.5\u{0301}", "1\u{FE0F}\u{20E3}", "12\u{200D}3", "1.\u{0301}5", "\u{0661}"] {
            let scalars = string.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
            XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: string), "accepted scalars \(scalars)")
        }
    }

    /// A string too long for `Decimal` to hold exactly is refused instead of being cut short.
    func testOverlongAmountIsRefused() {
        let overlong = "0.12345678" + String(repeating: "0", count: 40) + "1"
        XCTAssertNil(GiftCardPaymentGuard.dashAmount(fromQuotedString: overlong))
    }

    // MARK: - isRateFresh

    func testRateWithinTheStaleLimitIsFresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let limit = Int(kStaleRatesDuration)
        XCTAssertTrue(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 1_800_000_000, now: now))
        XCTAssertTrue(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 1_800_000_000 - 60, now: now))
        XCTAssertTrue(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 1_800_000_000 - limit, now: now))
    }

    func testRatePastTheStaleLimitIsNotFresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let limit = Int(kStaleRatesDuration)
        XCTAssertFalse(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 1_800_000_000 - limit - 1, now: now))
        XCTAssertFalse(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 1_800_000_000 - 86_400, now: now))
    }

    /// No recorded retrieval time means the rate's age is unknown, so it does not count as fresh.
    func testRateWithNoRetrievalTimeIsNotFresh() {
        XCTAssertFalse(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 0))
    }

    /// A retrieval time after `now` means the clock moved back, so the age is unknown.
    func testRateRetrievedInTheFutureIsNotFresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 1_800_000_001, now: now))
        XCTAssertFalse(GiftCardPaymentGuard.isRateFresh(lastRetrieval: 1_800_086_400, now: now))
    }

    // MARK: - approve(price:discount:rate:)

    private let approvalTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func rate(_ price: String?, age: Int = 60) -> GiftCardPaymentGuard.ExchangeRate {
        GiftCardPaymentGuard.ExchangeRate(price: price.map(dash), retrievedAt: 1_800_000_000 - age)
    }

    private func approve(price: String, discount: String,
                         rate: GiftCardPaymentGuard.ExchangeRate) throws -> GiftCardPaymentGuard.Approval {
        try GiftCardPaymentGuard.approve(price: dash(price), discount: dash(discount), rate: rate, now: approvalTime)
    }

    private func assertRateUnavailable(_ rate: GiftCardPaymentGuard.ExchangeRate,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try approve(price: "50", discount: "0.05", rate: rate), file: file, line: line) { error in
            XCTAssertEqual((error as? DashSpendError)?.errorDescription,
                           GiftCardPaymentGuard.rateUnavailableError.errorDescription,
                           "unexpected error: \(error)", file: file, line: line)
        }
    }

    /// $50 card at 5% off is $47.50; at $40 per Dash that is 1.1875 Dash.
    func testApprovedAmountIsTheDiscountedPriceAtTheRate() throws {
        XCTAssertEqual(try approve(price: "50", discount: "0.05", rate: rate("40")).amount, 118_750_000)
        XCTAssertEqual(try approve(price: "25", discount: "0", rate: rate("25")).amount, 100_000_000)
    }

    /// $10 at $30 per Dash is 0.3333… Dash: the ceiling rounds down to a whole duff.
    func testApprovedAmountRoundsDownToAWholeDuff() throws {
        XCTAssertEqual(try approve(price: "10", discount: "0", rate: rate("30")).amount, 33_333_333)
        XCTAssertEqual(try approve(price: "20", discount: "0", rate: rate("30")).amount, 66_666_666)
    }

    func testMissingRateIsRefused() {
        assertRateUnavailable(rate(nil))
    }

    /// A rate that is not a positive number cannot price anything, so it gives no ceiling.
    func testZeroNegativeOrNotANumberRateIsRefused() {
        assertRateUnavailable(rate("0"))
        assertRateUnavailable(rate("-40"))
        assertRateUnavailable(GiftCardPaymentGuard.ExchangeRate(price: Decimal.nan, retrievedAt: 1_800_000_000 - 60))
    }

    func testStaleRateIsRefused() {
        assertRateUnavailable(rate("40", age: Int(kStaleRatesDuration) + 1))
        assertRateUnavailable(rate("40", age: -60))
        assertRateUnavailable(GiftCardPaymentGuard.ExchangeRate(price: 40, retrievedAt: 0))
    }

    /// A rate so small that the amount no longer fits in duffs gives no ceiling.
    func testRateThatOverflowsTheDuffRangeIsRefused() {
        assertRateUnavailable(rate("0.000000000000000000000001"))
    }

    /// A rate so large that the price is less than one duff gives no ceiling.
    func testRateThatRoundsTheAmountToZeroIsRefused() {
        assertRateUnavailable(rate("100000000000000"))
    }

    func testNonPositivePriceIsRefusedAsAnInvalidAmount() {
        for (price, discount) in [("0", "0"), ("-5", "0"), ("50", "1"), ("50", "1.5")] {
            XCTAssertThrowsError(try approve(price: price, discount: discount, rate: rate("40"))) { error in
                guard case DashSpendError.invalidAmount = error else {
                    return XCTFail("price \(price) discount \(discount): unexpected error \(error)")
                }
            }
        }
    }

    func testApprovalAcceptsAQuoteUpToTheMarginAndRefusesOneAbove() throws {
        let approval = GiftCardPaymentGuard.Approval(amount: 100_000_000)
        XCTAssertNoThrow(try approval.check(requested: 100_000_000))
        XCTAssertNoThrow(try approval.check(requested: 105_000_000))
        XCTAssertNoThrow(try approval.check(requested: 1))

        for requested in [UInt64(105_000_001), 0, UInt64.max] {
            XCTAssertThrowsError(try approval.check(requested: requested)) { error in
                XCTAssertEqual((error as? DashSpendError)?.errorDescription,
                               GiftCardPaymentGuard.amountAboveApprovedError.errorDescription)
            }
        }
    }
}

/// The purchase reads the exchange rate and builds its approval before it asks a provider
/// for an order. These tests pin that order for every provider.
@MainActor
final class DashSpendPayApprovalTests: XCTestCase {

    private var merchant: ExplorePointOfUse {
        ExplorePointOfUse(
            id: 0, name: "Test Merchant", category: .unknown, active: true, city: nil, territory: nil,
            address1: nil, address2: nil, address3: nil, address4: nil, latitude: nil, longitude: nil,
            website: nil, phone: nil, logoLocation: nil, coverImage: nil, source: nil)
    }

    private func purchase(provider: GiftCardProvider,
                          rate: GiftCardPaymentGuard.ExchangeRate) async -> Error? {
        let viewModel = DashSpendPayViewModel(merchant: merchant, provider: provider, exchangeRate: { rate })
        do {
            _ = try await viewModel.purchaseGiftCardAndPay(confirmedPrice: 25, confirmedDiscount: 0)
            return nil
        } catch {
            return error
        }
    }

    func testPurchaseStopsBeforeTheProviderIsAskedWithoutAUsableRate() async {
        let now = Int(Date().timeIntervalSince1970)
        let unusable: [(name: String, rate: GiftCardPaymentGuard.ExchangeRate)] = [
            ("missing", .init(price: nil, retrievedAt: now)),
            ("zero", .init(price: 0, retrievedAt: now)),
            ("negative", .init(price: -40, retrievedAt: now)),
            ("stale", .init(price: 40, retrievedAt: now - Int(kStaleRatesDuration) - 60)),
            ("no retrieval time", .init(price: 40, retrievedAt: 0)),
        ]

        for provider in GiftCardProvider.allCases {
            for (name, rate) in unusable {
                let error = await purchase(provider: provider, rate: rate)
                XCTAssertEqual((error as? DashSpendError)?.errorDescription,
                               GiftCardPaymentGuard.rateUnavailableError.errorDescription,
                               "\(provider.displayName), \(name) rate: \(String(describing: error))")
            }
        }
    }

    /// With a usable rate the purchase moves on to the provider step. This merchant has no
    /// provider id, so that step refuses it without a network call.
    func testPurchaseWithAUsableRateReachesTheProviderStep() async {
        let usable = GiftCardPaymentGuard.ExchangeRate(price: 40, retrievedAt: Int(Date().timeIntervalSince1970))
        let error = await purchase(provider: .ctx, rate: usable)
        guard case DashSpendError.unauthorized? = error else {
            return XCTFail("unexpected result: \(String(describing: error))")
        }
    }
}

/// The PiggyCards order response carries the payment as a `dash:` URI. These tests pin what
/// the parser accepts from it.
@MainActor
final class PiggyCardsPaymentURITests: XCTestCase {

    private static let testnetAddress = "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr"

    private func isValid(on network: PaymentNetwork) -> (String) -> Bool {
        { ScriptAddressCodec.scriptPubKey(forAddress: $0, network: network) != nil }
    }

    private func parse(_ uri: String, network: PaymentNetwork = .testnet) throws -> (address: String, amount: Decimal) {
        try PiggyCardsRepository.parsePaymentURI(uri, message: nil, isValidAddress: isValid(on: network))
    }

    private func assertRefused(_ uri: String, network: PaymentNetwork = .testnet,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parse(uri, network: network), "accepted \(uri)", file: file, line: line)
    }

    func testAddressAndAmountAreRead() throws {
        let payment = try parse("dash:\(Self.testnetAddress)?amount=0.12345678")
        XCTAssertEqual(payment.address, Self.testnetAddress)
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: payment.amount), 12_345_678)
    }

    func testAmountIsReadAmongOtherParameters() throws {
        let payment = try parse("dash:\(Self.testnetAddress)?label=order&amount=1.5&message=x")
        XCTAssertEqual(GiftCardPaymentGuard.duffs(fromDashAmount: payment.amount), 150_000_000)
    }

    func testMalformedAmountsAreRefused() {
        for amount in ["1.25invalid", "1.2.3", "1,234.5", "1e-3", "-1", "abc", ""] {
            assertRefused("dash:\(Self.testnetAddress)?amount=\(amount)")
        }
    }

    func testAmountDigitsWithCombiningMarksAreRefused() {
        for amount in ["1\u{0301}25", "0.5\u{0301}", "1\u{FE0F}\u{20E3}", "12\u{200D}3"] {
            assertRefused("dash:\(Self.testnetAddress)?amount=\(amount)")
        }
    }

    func testMissingOrZeroAmountIsRefused() {
        assertRefused("dash:\(Self.testnetAddress)")
        assertRefused("dash:\(Self.testnetAddress)?label=order")
        assertRefused("dash:\(Self.testnetAddress)?amount=0")
        assertRefused("dash:\(Self.testnetAddress)?amount=0.00000000")
    }

    /// The parser keeps a sub-duff amount as written; the duff conversion is what refuses it.
    func testSubDuffAmountDoesNotConvertToDuffs() throws {
        let payment = try parse("dash:\(Self.testnetAddress)?amount=0.123456789")
        XCTAssertNil(GiftCardPaymentGuard.duffs(fromDashAmount: payment.amount))
    }

    func testAddressForAnotherNetworkIsRefused() {
        XCTAssertNoThrow(try parse("dash:\(Self.testnetAddress)?amount=1", network: .testnet))
        assertRefused("dash:\(Self.testnetAddress)?amount=1", network: .mainnet)
    }

    func testInvalidOrMissingAddressIsRefused() {
        assertRefused("dash:notAnAddress?amount=1")
        assertRefused("dash:?amount=1")
        assertRefused("dash:\(Self.testnetAddress.dropLast())?amount=1")
    }

    func testOtherSchemesAndEmptyInputAreRefused() {
        assertRefused("bitcoin:\(Self.testnetAddress)?amount=1")
        assertRefused("\(Self.testnetAddress)?amount=1")
        assertRefused("")
    }
}
