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
}
