//
//  GiftCardPaymentGuardTests.swift
//  DashWalletTests
//
//  A gift-card provider quotes the Dash amount for a price the buyer confirmed. These tests
//  pin when a quote is paid as confirmed, when the buyer is asked again and when that
//  question carries a warning, and the exact conversion of a quoted Dash amount to duffs.
//

import XCTest
@testable import dashpay

final class GiftCardPaymentGuardTests: XCTestCase {

    // MARK: - Approval.assess(requested:)

    /// 1 Dash confirmed at $40. Up to 0.5% more is paid without asking again; from 5% more
    /// the price change carries a warning.
    private let confirmed: UInt64 = 100_000_000
    private let silentLimit: UInt64 = 100_500_000
    private let warningFrom: UInt64 = 105_000_000

    private func approval(_ amount: UInt64 = 100_000_000) -> GiftCardPaymentGuard.Approval {
        GiftCardPaymentGuard.Approval(amount: amount, fiatAmount: 40, rate: 40, rateRetrievedAt: 1_800_000_000)
    }

    /// The price change a quote produces, or nil when it is paid as confirmed.
    private func change(_ requested: UInt64, confirmed amount: UInt64 = 100_000_000) throws
        -> GiftCardPaymentGuard.PriceChange? {
        switch try approval(amount).assess(requested: requested) {
        case .asConfirmed: return nil
        case .higher(let change): return change
        }
    }

    func testThresholdsAreHalfAPercentAndFivePercent() {
        XCTAssertEqual(GiftCardPaymentGuard.silentIncreaseBasisPoints, 50)
        XCTAssertEqual(GiftCardPaymentGuard.warningBasisPoints, 500)
    }

    func testQuoteEqualToConfirmedIsPaidAsConfirmed() throws {
        XCTAssertNil(try change(confirmed))
    }

    /// Paying less than confirmed cannot cost the buyer anything, so there is no lower bound.
    func testQuoteBelowConfirmedIsPaidAsConfirmed() throws {
        XCTAssertNil(try change(1))
        XCTAssertNil(try change(confirmed / 2))
        XCTAssertNil(try change(confirmed - 1))
    }

    func testIncreaseUpToTheSilentLimitIsPaidAsConfirmed() throws {
        XCTAssertNil(try change(confirmed + 1))
        XCTAssertNil(try change(silentLimit - 1))
        XCTAssertNil(try change(silentLimit))
    }

    func testIncreaseOneDuffOverTheSilentLimitIsPutToTheBuyer() throws {
        let priceChange = try XCTUnwrap(try change(silentLimit + 1))
        XCTAssertFalse(priceChange.needsWarning)
        XCTAssertEqual(priceChange.confirmedAmount, confirmed)
        XCTAssertEqual(priceChange.requestedAmount, silentLimit + 1)
    }

    func testIncreaseJustUnderFivePercentHasNoWarning() throws {
        XCTAssertEqual(try change(warningFrom - 1)?.needsWarning, false)
    }

    func testIncreaseOfFivePercentCarriesAWarning() throws {
        XCTAssertEqual(try change(warningFrom)?.needsWarning, true)
        XCTAssertEqual(try change(warningFrom + 1)?.needsWarning, true)
    }

    /// There is no upper limit: any higher quote is put to the buyer with the warning.
    func testIncreaseFarAboveConfirmedCarriesAWarning() throws {
        XCTAssertEqual(try change(confirmed * 10)?.needsWarning, true)
        XCTAssertEqual(try change(UInt64.max)?.needsWarning, true)
    }

    /// A request for no Dash is refused as an invalid amount; it is not a price change.
    func testZeroQuoteIsRefusedAsAnInvalidAmount() {
        XCTAssertThrowsError(try approval().assess(requested: 0)) { error in
            XCTAssertEqual((error as? DashSpendError)?.errorDescription,
                           GiftCardPaymentGuard.invalidAmountError.errorDescription)
        }
    }

    /// The silent margin rounds down and the warning level rounds up. 0.5% of 199 duffs is
    /// under one duff, so nothing above 199 is paid without asking; 5% of 199 is 9.95, so
    /// the warning starts at 10 duffs more.
    func testThresholdsRoundForSmallAmounts() throws {
        XCTAssertNil(try change(199, confirmed: 199))
        XCTAssertEqual(try change(200, confirmed: 199)?.needsWarning, false)
        XCTAssertEqual(try change(208, confirmed: 199)?.needsWarning, false)
        XCTAssertEqual(try change(209, confirmed: 199)?.needsWarning, true)

        XCTAssertNil(try change(201, confirmed: 200))
        XCTAssertEqual(try change(202, confirmed: 200)?.needsWarning, false)
        XCTAssertEqual(try change(209, confirmed: 200)?.needsWarning, false)
        XCTAssertEqual(try change(210, confirmed: 200)?.needsWarning, true)
    }

    func testValuesNearUInt64MaxDoNotOverflow() throws {
        let max = UInt64.max
        XCTAssertNil(try change(max, confirmed: max))
        XCTAssertNil(try change(max - 1, confirmed: max))
        XCTAssertEqual(try change(max, confirmed: 1)?.needsWarning, true)
        XCTAssertEqual(try change(max, confirmed: max / 2)?.needsWarning, true)

        // The largest confirmed amount whose 5% still fits below UInt64.max.
        let amount = max / 21 * 20
        let fivePercent = amount / 20
        XCTAssertEqual(try change(amount + fivePercent - 1, confirmed: amount)?.needsWarning, false)
        XCTAssertEqual(try change(amount + fivePercent, confirmed: amount)?.needsWarning, true)
        XCTAssertNil(try change(amount + amount / 200, confirmed: amount))
        XCTAssertNotNil(try change(amount + amount / 200 + 1, confirmed: amount))
    }

    /// 1 Dash confirmed for $40; the provider asks 1.04 Dash, which is $41.60 at the same rate.
    func testPriceChangeCarriesTheFiguresTheBuyerIsShown() throws {
        let priceChange = try XCTUnwrap(try change(104_000_000))
        XCTAssertEqual(priceChange.confirmedFiat, 40)
        XCTAssertEqual(priceChange.requestedFiat, dash("41.6"))
        XCTAssertEqual(priceChange.differenceAmount, 4_000_000)
        XCTAssertEqual(priceChange.differenceFiat, dash("1.6"))
        XCTAssertEqual(priceChange.increaseFraction, dash("0.04"))
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

    /// The approval keeps what the sheets show and what a later freshness check needs.
    func testApprovalKeepsTheFiatPriceAndTheRate() throws {
        let approval = try approve(price: "50", discount: "0.05", rate: rate("40", age: 120))
        XCTAssertEqual(approval.fiatAmount, dash("47.5"))
        XCTAssertEqual(approval.rate, 40)
        XCTAssertEqual(approval.rateRetrievedAt, 1_800_000_000 - 120)
    }

    /// An approval made with a fresh rate stops being usable once that rate is past the limit.
    func testApprovalRateGoesStale() throws {
        let approval = try approve(price: "50", discount: "0", rate: rate("40", age: 60))
        XCTAssertTrue(approval.isRateFresh(now: approvalTime))
        XCTAssertTrue(approval.isRateFresh(now: approvalTime.addingTimeInterval(kStaleRatesDuration - 60)))
        XCTAssertFalse(approval.isRateFresh(now: approvalTime.addingTimeInterval(kStaleRatesDuration)))
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

    // MARK: - GiftCardAmountText

    private let posix = Locale(identifier: "en_US_POSIX")

    func testApproximateDashAmountHasFourDecimals() {
        XCTAssertEqual(GiftCardAmountText.approximateDash(493_700_000, locale: posix), "≈ 4.9370")
        XCTAssertEqual(GiftCardAmountText.approximateDash(123_456_789, locale: posix), "≈ 1.2346")
        XCTAssertEqual(GiftCardAmountText.approximateDash(100_000_000, locale: posix), "≈ 1.0000")
    }

    /// The amount the buyer is asked to pay is written in full, never rounded.
    func testExactDashAmountKeepsEveryDecimal() {
        XCTAssertEqual(GiftCardAmountText.exactDash(513_440_000, locale: posix), "5.1344")
        XCTAssertEqual(GiftCardAmountText.exactDash(513_441_234, locale: posix), "5.13441234")
        XCTAssertEqual(GiftCardAmountText.exactDash(1, locale: posix), "0.00000001")
        XCTAssertEqual(GiftCardAmountText.exactDash(100_000_000, locale: posix), "1.0000")
    }

    func testDashAmountsFollowTheLocale() {
        let polish = Locale(identifier: "pl_PL")
        XCTAssertEqual(GiftCardAmountText.exactDash(513_440_000, locale: polish), "5,1344")
        XCTAssertEqual(GiftCardAmountText.exactDash(123_456_700_000_000, locale: polish), "1234567,0000")
    }

    /// An increase just under 5% has no warning, so it must not read as 5%.
    func testIncreasePercentRoundsDown() {
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.0499")), 4.9)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.04999999")), 4.9)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.05")), 5.0)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.0999")), 9.9)
    }

    /// One decimal below 10%, whole percent from there.
    func testIncreasePercentRounding() {
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.03")), 3.0)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.041")), 4.1)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.00637")), 0.6)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.1249")), 12)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("0.1299")), 12)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: dash("9")), 900)
        XCTAssertEqual(DashSpendPriceUpdatedDialog.percent(of: Decimal.nan), 0)
    }
}

/// The purchase sheet's states in the view model: the rate is read when the Confirm sheet
/// opens, and a provider's quote is compared with it before anything is authorized.
@MainActor
final class DashSpendPayApprovalTests: XCTestCase {

    private var merchant: ExplorePointOfUse {
        ExplorePointOfUse(
            id: 0, name: "Test Merchant", category: .unknown, active: true, city: nil, territory: nil,
            address1: nil, address2: nil, address3: nil, address4: nil, latitude: nil, longitude: nil,
            website: nil, phone: nil, logoLocation: nil, coverImage: nil, source: nil)
    }

    private var usableRate: GiftCardPaymentGuard.ExchangeRate {
        GiftCardPaymentGuard.ExchangeRate(price: 40, retrievedAt: Int(Date().timeIntervalSince1970))
    }

    private func makeViewModel(provider: GiftCardProvider = .ctx,
                               rate: GiftCardPaymentGuard.ExchangeRate? = nil) -> DashSpendPayViewModel {
        let rate = rate ?? usableRate
        let viewModel = DashSpendPayViewModel(merchant: merchant, provider: provider, exchangeRate: { rate })
        // No sheet is on screen in these tests, so nothing reports its dismissal.
        viewModel.sheetDismissalWait = 0.01
        return viewModel
    }

    /// A view model with the Confirm sheet open for a $25 card: 0.625 Dash at $40.
    private func viewModelWithConfirmSheet() throws -> (DashSpendPayViewModel, GiftCardPurchaseSnapshot) {
        let viewModel = makeViewModel()
        try viewModel.beginPurchase(price: 25)
        guard case .confirm(let snapshot)? = viewModel.purchaseSheet else {
            XCTFail("the Confirm sheet did not open")
            throw CancellationError()
        }
        return (viewModel, snapshot)
    }

    /// How long a test waits for the view model before it fails.
    private static let patience: TimeInterval = 2

    /// Starts `confirmQuote` for `requested` Dash.
    private func startQuote(_ requested: UInt64, on viewModel: DashSpendPayViewModel,
                            snapshot: GiftCardPurchaseSnapshot) -> Task<Void, Error> {
        Task { try await viewModel.confirmQuote(requested: requested, approval: snapshot.approval) }
    }

    /// Runs `confirmQuote` and returns once the "Price updated" sheet is up. Fails the test
    /// and returns no change when the sheet has not come up in time; callers unwrap the
    /// change before they answer it.
    private func quote(_ requested: UInt64, on viewModel: DashSpendPayViewModel,
                       snapshot: GiftCardPurchaseSnapshot,
                       file: StaticString = #filePath, line: UInt = #line) async
        -> (task: Task<Void, Error>, change: GiftCardPaymentGuard.PriceChange?) {
        let task = startQuote(requested, on: viewModel, snapshot: snapshot)
        let deadline = Date().addingTimeInterval(Self.patience)
        while Date() < deadline {
            if case .priceUpdated(let change)? = viewModel.purchaseSheet { return (task, change) }
            await Task.yield()
        }
        XCTFail("the \"Price updated\" sheet did not come up", file: file, line: line)
        return (task, nil)
    }

    /// Waits for `task` to end. A task still waiting after `patience` fails the test and is
    /// let go by declining whatever it waits for, so a regression fails here instead of
    /// hanging the suite.
    private func finish(_ task: Task<Void, Error>, on viewModel: DashSpendPayViewModel,
                        file: StaticString = #filePath, line: UInt = #line) async throws {
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.patience * 1_000_000_000))
            guard !Task.isCancelled else { return }
            XCTFail("the quote is still waiting for an answer", file: file, line: line)
            viewModel.resolvePriceChange(pay: false)
            viewModel.purchaseSheetDidDismiss()
        }
        defer { watchdog.cancel() }
        try await task.value
    }

    private func assertCancelled(_ task: Task<Void, Error>, on viewModel: DashSpendPayViewModel,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await finish(task, on: viewModel, file: file, line: line)
            XCTFail("the purchase went on", file: file, line: line)
        } catch DashSpendError.purchaseCancelled {
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }

    // MARK: Opening the Confirm sheet

    func testConfirmSheetDoesNotOpenWithoutAUsableRate() {
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
                let viewModel = makeViewModel(provider: provider, rate: rate)
                XCTAssertThrowsError(try viewModel.beginPurchase(price: 25)) { error in
                    XCTAssertEqual((error as? DashSpendError)?.errorDescription,
                                   GiftCardPaymentGuard.rateUnavailableError.errorDescription,
                                   "\(provider.displayName), \(name) rate: \(error)")
                }
                XCTAssertNil(viewModel.purchaseSheet, "\(provider.displayName), \(name) rate")
            }
        }
    }

    func testConfirmSheetOpensWithTheDashAmountAtTheWalletsRate() throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        XCTAssertEqual(snapshot.price, 25)
        XCTAssertEqual(snapshot.discount, viewModel.displaySavingsFraction)
        XCTAssertEqual(snapshot.approval.fiatAmount, 25 * (1 - snapshot.discount))
        XCTAssertEqual(snapshot.approval.rate, 40)
        XCTAssertEqual(snapshot.approval.amount, try GiftCardPaymentGuard.approve(
            price: 25, discount: snapshot.discount, rate: usableRate).amount)
    }

    func testCancelOnTheConfirmSheetClosesIt() throws {
        let (viewModel, _) = try viewModelWithConfirmSheet()
        viewModel.dismissPurchaseSheet()
        XCTAssertNil(viewModel.purchaseSheet)
    }

    // MARK: The purchase

    /// The sheet can stay open past the stale-rate limit. Confirm then stops the purchase
    /// before the provider is asked for an order.
    func testPurchaseStopsBeforeTheProviderWhenTheConfirmedRateWentStale() async throws {
        var clock = Date()
        let rate = GiftCardPaymentGuard.ExchangeRate(price: 40, retrievedAt: Int(clock.timeIntervalSince1970))
        let viewModel = DashSpendPayViewModel(merchant: merchant, provider: .ctx,
                                              exchangeRate: { rate }, now: { clock })
        try viewModel.beginPurchase(price: 25)
        guard case .confirm(let snapshot)? = viewModel.purchaseSheet else {
            return XCTFail("the Confirm sheet did not open")
        }

        clock = clock.addingTimeInterval(kStaleRatesDuration + 60)
        do {
            _ = try await viewModel.purchaseGiftCardAndPay(snapshot)
            XCTFail("the purchase went on")
        } catch {
            XCTAssertEqual((error as? DashSpendError)?.errorDescription,
                           GiftCardPaymentGuard.rateUnavailableError.errorDescription, "\(error)")
        }
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertFalse(viewModel.isProcessingPayment)
    }

    /// With a fresh rate the purchase moves on to the provider step. This merchant has no
    /// provider id, so that step refuses it without a network call, and the sheet closes.
    func testPurchaseWithAFreshRateReachesTheProviderStep() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()

        do {
            _ = try await viewModel.purchaseGiftCardAndPay(snapshot)
            XCTFail("the purchase went on")
        } catch DashSpendError.unauthorized {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertFalse(viewModel.isProcessingPayment)
    }

    // MARK: Starting once

    private func outcome(of purchase: Task<Data, Error>) async -> String {
        do {
            _ = try await purchase.value
            return "paid"
        } catch DashSpendError.purchaseCancelled {
            return "not started"
        } catch DashSpendError.unauthorized {
            return "provider step"
        } catch {
            return "\(error)"
        }
    }

    /// Confirm can be tapped again before the sheet has redrawn. Only one of the two starts
    /// reaches the provider step; the other ends with nothing ordered.
    func testSecondStartForTheSameConfirmationIsRefused() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()

        let first = Task { try await viewModel.purchaseGiftCardAndPay(snapshot) }
        let second = Task { try await viewModel.purchaseGiftCardAndPay(snapshot) }
        let outcomes = [await outcome(of: first), await outcome(of: second)].sorted()

        XCTAssertEqual(outcomes, ["not started", "provider step"])
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertFalse(viewModel.isProcessingPayment)
    }

    /// The sheet stays drawn while it animates away after Cancel. A Confirm tap in that time
    /// starts nothing.
    func testConfirmAfterCancelStartsNothing() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        viewModel.dismissPurchaseSheet()

        let result = await outcome(of: Task { try await viewModel.purchaseGiftCardAndPay(snapshot) })

        XCTAssertEqual(result, "not started")
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertFalse(viewModel.isProcessingPayment)
    }

    /// Only the confirmation on screen can be started: an earlier one is refused and the
    /// sheet that is open stays as it is.
    func testConfirmationThatIsNotOnScreenStartsNothing() async throws {
        let (viewModel, earlier) = try viewModelWithConfirmSheet()
        try viewModel.beginPurchase(price: 50)
        let shown = viewModel.purchaseSheet

        let result = await outcome(of: Task { try await viewModel.purchaseGiftCardAndPay(earlier) })

        XCTAssertEqual(result, "not started")
        XCTAssertEqual(viewModel.purchaseSheet, shown)
        XCTAssertNotEqual(shown, GiftCardPurchaseSheet.confirm(earlier))
    }

    // MARK: The provider's quote

    func testQuoteAsConfirmedClosesTheSheetWithoutAsking() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        try await finish(startQuote(snapshot.approval.amount, on: viewModel, snapshot: snapshot), on: viewModel)
        XCTAssertNil(viewModel.purchaseSheet)
    }

    /// 0.3% more than confirmed is inside the margin that is paid without asking again.
    func testSmallIncreaseClosesTheSheetWithoutAsking() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        let requested = snapshot.approval.amount + snapshot.approval.amount * 3 / 1_000
        try await finish(startQuote(requested, on: viewModel, snapshot: snapshot), on: viewModel)
        XCTAssertNil(viewModel.purchaseSheet)
    }

    func testHigherQuoteWaitsForTheBuyerAndGoesOnWhenTheyPay() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        let requested = snapshot.approval.amount + snapshot.approval.amount * 2 / 100

        let (task, shown) = await quote(requested, on: viewModel, snapshot: snapshot)
        let priceChange = try XCTUnwrap(shown)
        XCTAssertEqual(priceChange.requestedAmount, requested)
        XCTAssertEqual(priceChange.confirmedAmount, snapshot.approval.amount)
        XCTAssertFalse(priceChange.needsWarning)

        viewModel.resolvePriceChange(pay: true)
        XCTAssertNil(viewModel.purchaseSheet)
        viewModel.purchaseSheetDidDismiss()
        try await finish(task, on: viewModel)
    }

    func testQuoteFivePercentHigherIsShownWithAWarning() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        let requested = snapshot.approval.amount + snapshot.approval.amount * 5 / 100

        let (task, shown) = await quote(requested, on: viewModel, snapshot: snapshot)
        XCTAssertEqual(try XCTUnwrap(shown).needsWarning, true)

        viewModel.resolvePriceChange(pay: true)
        try await finish(task, on: viewModel)
    }

    func testDecliningAHigherQuoteCancelsThePurchase() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        let (task, shown) = await quote(snapshot.approval.amount * 2, on: viewModel, snapshot: snapshot)
        _ = try XCTUnwrap(shown)

        viewModel.resolvePriceChange(pay: false)
        await assertCancelled(task, on: viewModel)
        XCTAssertNil(viewModel.purchaseSheet)
    }

    /// Swiping the "Price updated" sheet away reaches the view model as a dismissal.
    func testDismissingThePriceSheetDeclinesTheQuote() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        let (task, shown) = await quote(snapshot.approval.amount * 2, on: viewModel, snapshot: snapshot)
        _ = try XCTUnwrap(shown)

        viewModel.dismissPurchaseSheet()
        await assertCancelled(task, on: viewModel)
        XCTAssertNil(viewModel.purchaseSheet)
    }

    // MARK: The screen going away

    /// The screen is closed (a sign-out does this) while a price change waits for an answer.
    func testClosingTheScreenDeclinesAPendingPriceChange() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        let (task, shown) = await quote(snapshot.approval.amount * 2, on: viewModel, snapshot: snapshot)
        _ = try XCTUnwrap(shown)

        viewModel.unsubscribeFromAll()
        await assertCancelled(task, on: viewModel)
        XCTAssertNil(viewModel.purchaseSheet)
    }

    /// A higher quote that arrives after the screen closed has no sheet to be shown on. It
    /// ends the purchase instead of waiting for an answer nobody can give.
    func testHigherQuoteAfterTheScreenClosedEndsThePurchaseWithoutWaiting() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        viewModel.unsubscribeFromAll()

        await assertCancelled(startQuote(snapshot.approval.amount * 2, on: viewModel, snapshot: snapshot), on: viewModel)
        if case .priceUpdated? = viewModel.purchaseSheet { XCTFail("a price change was shown with no screen") }
    }

    /// A quote as confirmed needs no answer, but with the screen closed nothing follows it:
    /// no PIN prompt is raised over whatever the buyer went on to.
    func testQuoteAsConfirmedAfterTheScreenClosedEndsThePurchase() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        viewModel.unsubscribeFromAll()

        await assertCancelled(startQuote(snapshot.approval.amount, on: viewModel, snapshot: snapshot), on: viewModel)
    }

    /// The screen closes in the moment the sheet is leaving after the quote was accepted.
    func testScreenClosingWhileTheSheetLeavesEndsThePurchase() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        viewModel.sheetDismissalWait = 5

        let task = startQuote(snapshot.approval.amount, on: viewModel, snapshot: snapshot)
        let deadline = Date().addingTimeInterval(Self.patience)
        while viewModel.purchaseSheet != nil, Date() < deadline { await Task.yield() }
        XCTAssertNil(viewModel.purchaseSheet, "the quote was not accepted")

        viewModel.unsubscribeFromAll()
        viewModel.purchaseSheetDidDismiss()
        await assertCancelled(task, on: viewModel)
    }

    /// Tapping Pay shows the screen is there, so a purchase begun after the screen was last
    /// reported gone goes on.
    func testAPurchaseBegunAfterTheScreenWasReportedGoneGoesOn() async throws {
        let viewModel = makeViewModel()
        viewModel.unsubscribeFromAll()
        try viewModel.beginPurchase(price: 25)
        guard case .confirm(let snapshot)? = viewModel.purchaseSheet else {
            return XCTFail("the Confirm sheet did not open")
        }

        try await finish(startQuote(snapshot.approval.amount, on: viewModel, snapshot: snapshot), on: viewModel)
        XCTAssertNil(viewModel.purchaseSheet)
    }

    /// The screen also disappears and comes back around a full-screen prompt. A price change
    /// is shown again once it is back.
    func testPriceChangeIsShownAgainOnceTheScreenIsBack() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        viewModel.unsubscribeFromAll()
        viewModel.subscribeToUpdates()
        defer { viewModel.unsubscribeFromAll() }

        let (task, shown) = await quote(snapshot.approval.amount * 2, on: viewModel, snapshot: snapshot)
        _ = try XCTUnwrap(shown)
        viewModel.resolvePriceChange(pay: true)
        try await finish(task, on: viewModel)
    }

    func testZeroQuoteIsRefusedWithoutAsking() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet()
        do {
            try await finish(startQuote(0, on: viewModel, snapshot: snapshot), on: viewModel)
            XCTFail("a quote for no Dash went on")
        } catch {
            XCTAssertEqual((error as? DashSpendError)?.errorDescription,
                           GiftCardPaymentGuard.invalidAmountError.errorDescription, "\(error)")
        }
        if case .priceUpdated? = viewModel.purchaseSheet { XCTFail("a quote for no Dash was put to the buyer") }
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
