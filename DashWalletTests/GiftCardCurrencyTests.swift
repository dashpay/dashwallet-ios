//
//  GiftCardCurrencyTests.swift
//  DashWalletTests
//
//  A CTX gift card is priced in its merchant's currency and paid in Dash. These tests pin the
//  money rules of that currency: which codes are usable, how amounts are written for display
//  and for an order, which merchant load names the currency, and what a CTX order may be.
//

import XCTest
@testable import dashpay

final class GiftCardCurrencyTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US")
    private let enGB = Locale(identifier: "en_GB")
    private let deDE = Locale(identifier: "de_DE")
    private let arSA = Locale(identifier: "ar_SA")

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    // MARK: - The currency code

    func testACodeInUseIsNormalizedToUpperCase() {
        XCTAssertEqual(GiftCardCurrency.normalize("USD"), "USD")
        XCTAssertEqual(GiftCardCurrency.normalize(" gbp\n"), "GBP")
        for code in ["EUR", "CAD", "AED", "INR", "JPY", "KWD", "MXN", "SAR", "AUD", "TRY", "QAR", "HUF"] {
            XCTAssertEqual(GiftCardCurrency.normalize(code), code)
        }
    }

    func testAnAbsentBlankOrUnknownCodeIsNoCurrency() {
        for code in [nil, "", "   ", "US", "USDX", "ZZZ", "XXX", "XAU", "DEM", "$", "U S D"] {
            XCTAssertNil(GiftCardCurrency.normalize(code), code ?? "nil")
        }
    }

    func testFractionDigitsAreTheCurrencysOwn() {
        XCTAssertEqual(GiftCardCurrency.fractionDigits("USD"), 2)
        XCTAssertEqual(GiftCardCurrency.fractionDigits("GBP"), 2)
        XCTAssertEqual(GiftCardCurrency.fractionDigits("JPY"), 0)
        XCTAssertEqual(GiftCardCurrency.fractionDigits("KRW"), 0)
        XCTAssertEqual(GiftCardCurrency.fractionDigits("KWD"), 3)
        XCTAssertEqual(GiftCardCurrency.fractionDigits("BHD"), 3)
        // ISO 4217, not the cash rounding `NumberFormatter` uses for these.
        XCTAssertEqual(GiftCardCurrency.fractionDigits("HUF"), 2)
        XCTAssertEqual(GiftCardCurrency.fractionDigits("IDR"), 2)
        XCTAssertEqual(GiftCardCurrency.fractionDigits("IQD"), 3)
    }

    // MARK: - Amounts a provider writes

    func testOnlyAPlainDecimalNumberIsRead() {
        XCTAssertEqual(GiftCardCurrency.plainDecimal("25"), 25)
        XCTAssertEqual(GiftCardCurrency.plainDecimal("10.50"), decimal("10.5"))
        XCTAssertEqual(GiftCardCurrency.plainDecimal("0.001"), decimal("0.001"))
        for text in ["", " 25", "25 ", "1,000", "10,50", "1e3", "-5", "+5", "5.", ".5", "5.0.0", "٢٥", "25USD"] {
            XCTAssertNil(GiftCardCurrency.plainDecimal(text), text)
        }
    }

    // MARK: - The amount in an order

    func testOrderAmountHasExactlyTheCurrencysDecimals() {
        XCTAssertEqual(GiftCardCurrency.orderAmount(25, currency: "USD"), "25.00")
        XCTAssertEqual(GiftCardCurrency.orderAmount(decimal("10.5"), currency: "GBP"), "10.50")
        XCTAssertEqual(GiftCardCurrency.orderAmount(decimal("0.05"), currency: "EUR"), "0.05")
        XCTAssertEqual(GiftCardCurrency.orderAmount(1000, currency: "JPY"), "1000")
        XCTAssertEqual(GiftCardCurrency.orderAmount(decimal("1.5"), currency: "KWD"), "1.500")
        XCTAssertEqual(GiftCardCurrency.orderAmount(decimal("0.001"), currency: "KWD"), "0.001")
    }

    func testOrderAmountIsNeverGrouped() {
        XCTAssertEqual(GiftCardCurrency.orderAmount(1000, currency: "USD"), "1000.00")
        XCTAssertEqual(GiftCardCurrency.orderAmount(decimal("1234567.89"), currency: "USD"), "1234567.89")
        XCTAssertEqual(GiftCardCurrency.orderAmount(25000, currency: "JPY"), "25000")
    }

    func testAnAmountTheCurrencyCannotHoldIsRefusedNotRounded() {
        XCTAssertNil(GiftCardCurrency.orderAmount(decimal("1000.5"), currency: "JPY"))
        XCTAssertNil(GiftCardCurrency.orderAmount(decimal("10.505"), currency: "USD"))
        XCTAssertNil(GiftCardCurrency.orderAmount(decimal("10.999"), currency: "GBP"))
        XCTAssertNil(GiftCardCurrency.orderAmount(decimal("1.0005"), currency: "KWD"))
        XCTAssertFalse(GiftCardCurrency.isRepresentable(decimal("1000.5"), in: "JPY"))
        XCTAssertTrue(GiftCardCurrency.isRepresentable(decimal("1000.50"), in: "USD"))
    }

    func testAnAmountThatIsNotAboveZeroIsRefused() {
        XCTAssertNil(GiftCardCurrency.orderAmount(0, currency: "USD"))
        XCTAssertNil(GiftCardCurrency.orderAmount(-25, currency: "USD"))
        XCTAssertNil(GiftCardCurrency.orderAmount(Decimal.nan, currency: "USD"))
    }

    /// The order string uses no locale. The display string of the same amount does, which
    /// is how the two differ on a device set to German or Arabic.
    func testOrderAmountIsAsciiWhateverTheDisplayLocaleWrites() {
        let amount = decimal("1234.5")
        let order = GiftCardCurrency.orderAmount(amount, currency: "USD")
        XCTAssertEqual(order, "1234.50")

        let german = GiftCardCurrency.string(amount, currency: "USD", locale: deDE)
        XCTAssertTrue(german.contains("1.234,50"), german)
        let arabic = GiftCardCurrency.string(amount, currency: "USD", locale: arSA)
        XCTAssertNotEqual(arabic, GiftCardCurrency.string(amount, currency: "USD", locale: enUS))

        let allowed = Set("0123456789.".utf8)
        XCTAssertTrue(order?.utf8.allSatisfy { allowed.contains($0) } ?? false)
    }

    // MARK: - Amounts on screen

    func testDisplayUsesTheCardCurrencyAndItsDecimals() {
        XCTAssertEqual(GiftCardCurrency.string(25, currency: "USD", locale: enUS), "$25.00")
        XCTAssertEqual(GiftCardCurrency.string(25, currency: "GBP", locale: enGB), "£25.00")
        XCTAssertEqual(GiftCardCurrency.string(decimal("10.5"), currency: "GBP", locale: enUS), "£10.50")

        let yen = GiftCardCurrency.string(1000, currency: "JPY", locale: enUS)
        XCTAssertTrue(yen.contains("1,000"), yen)
        XCTAssertFalse(yen.contains("."), yen)

        let dinar = GiftCardCurrency.string(decimal("1.5"), currency: "KWD", locale: enUS)
        XCTAssertTrue(dinar.contains("1.500"), dinar)

        let forint = GiftCardCurrency.string(5000, currency: "HUF", locale: enUS)
        XCTAssertTrue(forint.contains("5,000.00"), forint)
    }

    func testDisplayFollowsTheLocale() {
        let german = GiftCardCurrency.string(decimal("1234.5"), currency: "GBP", locale: deDE)
        XCTAssertTrue(german.contains("1.234,50"), german)
        XCTAssertTrue(german.contains("£"), german)
    }

    func testAWholeAmountCanBeWrittenWithoutDecimals() {
        XCTAssertEqual(GiftCardCurrency.string(25, currency: "USD", locale: enUS, trimsWholeAmounts: true), "$25")
        XCTAssertEqual(GiftCardCurrency.string(decimal("25.5"), currency: "USD", locale: enUS, trimsWholeAmounts: true),
                       "$25.50")
        XCTAssertEqual(GiftCardCurrency.string(decimal("1.5"), currency: "KWD", locale: enUS, trimsWholeAmounts: true)
            .contains("1.500"), true)
    }

    func testPlainAmountHasNoSymbolOrGrouping() {
        XCTAssertEqual(GiftCardCurrency.plainString(1500, currency: "USD", locale: enUS), "1500")
        XCTAssertEqual(GiftCardCurrency.plainString(decimal("12.5"), currency: "USD", locale: enUS), "12.5")
        XCTAssertEqual(GiftCardCurrency.plainString(decimal("12.5"), currency: "USD", locale: deDE), "12,5")
        XCTAssertEqual(GiftCardCurrency.plainString(decimal("1.125"), currency: "KWD", locale: enUS), "1.125")
        XCTAssertEqual(GiftCardCurrency.plainString(3000, currency: "JPY", locale: enUS), "3000")
    }

    func testSymbolIsTheCardCurrencys() {
        XCTAssertEqual(GiftCardCurrency.symbol(for: "USD", locale: enUS), "$")
        XCTAssertEqual(GiftCardCurrency.symbol(for: "GBP", locale: enUS), "£")
        XCTAssertEqual(GiftCardCurrency.symbol(for: "EUR", locale: enUS), "€")
    }

    // MARK: - What a merchant sells

    func testARangeMerchantsLimitsAreReadInItsCurrency() {
        let terms = CTXMerchantTerms(currency: "GBP", isRange: true, denominations: ["5", "250.50"])
        XCTAssertEqual(terms?.currency, "GBP")
        XCTAssertEqual(terms?.isFixed, false)
        XCTAssertEqual(terms?.minimum, 5)
        XCTAssertEqual(terms?.maximum, decimal("250.5"))
        XCTAssertEqual(terms?.denominations, [])
    }

    func testAFixedMerchantKeepsFractionalCardValues() {
        let terms = CTXMerchantTerms(currency: "eur", isRange: false, denominations: ["10", "12.50", " 25 "])
        XCTAssertEqual(terms?.currency, "EUR")
        XCTAssertEqual(terms?.isFixed, true)
        XCTAssertEqual(terms?.denominations, [10, decimal("12.5"), 25])
        XCTAssertNil(terms?.minimum)
        XCTAssertNil(terms?.maximum)
    }

    func testKuwaitiDinarCardValuesKeepThreeDecimals() {
        let terms = CTXMerchantTerms(currency: "KWD", isRange: false, denominations: ["1.125", "5"])
        XCTAssertEqual(terms?.denominations, [decimal("1.125"), 5])
    }

    func testAnAnswerWithoutAUsableCurrencyIsUnusable() {
        XCTAssertNil(CTXMerchantTerms(currency: nil, isRange: true, denominations: ["5", "100"]))
        XCTAssertNil(CTXMerchantTerms(currency: "", isRange: true, denominations: ["5", "100"]))
        XCTAssertNil(CTXMerchantTerms(currency: "  ", isRange: false, denominations: ["5"]))
        XCTAssertNil(CTXMerchantTerms(currency: "ZZZ", isRange: false, denominations: ["5"]))
    }

    func testAnAnswerWithAnAmountThatIsNotANumberOfTheCurrencyIsUnusable() {
        XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: false, denominations: ["10", "abc"]))
        XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: false, denominations: ["1,000"]))
        XCTAssertNil(CTXMerchantTerms(currency: "JPY", isRange: false, denominations: ["1000.5"]))
        XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: true, denominations: ["5", "10.005"]))
    }

    func testARangeWithoutRoomIsUnusable() {
        XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: true, denominations: ["5", "0"]))
        XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: true, denominations: ["0", "0"]))
        XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: true, denominations: ["100", "5"]))
        XCTAssertNotNil(CTXMerchantTerms(currency: "USD", isRange: true, denominations: ["5", "5"]))
    }

    func testAmountsThatAreNotFiniteOrAreNegativeAreUnusable() {
        for text in ["NaN", "nan", "inf", "Infinity", "-5", "-0.01", "1e400", String(repeating: "9", count: 60)] {
            XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: true, denominations: ["5", text]), text)
            XCTAssertNil(CTXMerchantTerms(currency: "USD", isRange: false, denominations: [text]), text)
        }
    }

    func testMissingLimitsAndZeroCardValuesAreLeftOut() {
        let range = CTXMerchantTerms(currency: "USD", isRange: true, denominations: ["0"])
        XCTAssertNotNil(range)
        XCTAssertNil(range?.minimum)
        XCTAssertNil(range?.maximum)

        let fixed = CTXMerchantTerms(currency: "USD", isRange: false, denominations: ["0", "25"])
        XCTAssertEqual(fixed?.denominations, [25])
    }

    // MARK: - Which load names the currency

    func testTheFirstAnswerConfirmsTheCurrency() {
        var loads = CardCurrencyLoads()
        XCTAssertEqual(loads.state, .loading)
        XCTAssertNil(loads.confirmed)
        // The explore database's amounts, which are in USD, are on screen until then.
        XCTAssertEqual(loads.shown, "USD")

        let load = loads.begin()
        XCTAssertEqual(loads.finish(load, .currency("USD")), .applied(clearsSelection: false))
        XCTAssertEqual(loads.state, .known("USD"))
        XCTAssertEqual(loads.confirmed, "USD")
    }

    func testAnotherCurrencyThanTheOneOnScreenClearsTheSelection() {
        var loads = CardCurrencyLoads()
        let load = loads.begin()
        XCTAssertEqual(loads.finish(load, .currency("GBP")), .applied(clearsSelection: true))
        XCTAssertEqual(loads.shown, "GBP")
    }

    func testAFirstLoadWithoutAnAnswerLeavesTheCurrencyUnknown() {
        var loads = CardCurrencyLoads()
        let load = loads.begin()
        XCTAssertEqual(loads.finish(load, .noAnswer), .applied(clearsSelection: true))
        XCTAssertEqual(loads.state, .unknown)
        XCTAssertNil(loads.confirmed)
        XCTAssertNil(loads.shown)
    }

    func testAnUnusableAnswerLeavesTheCurrencyUnknown() {
        var loads = CardCurrencyLoads()
        let load = loads.begin()
        XCTAssertEqual(loads.finish(load, .unusable), .applied(clearsSelection: true))
        XCTAssertEqual(loads.state, .unknown)
    }

    func testARefreshWithoutAnAnswerKeepsAConfirmedCurrency() {
        var loads = CardCurrencyLoads(confirmed: "GBP")
        let load = loads.begin()
        XCTAssertEqual(loads.state, .known("GBP"))
        XCTAssertEqual(loads.finish(load, .noAnswer), .kept)
        XCTAssertEqual(loads.confirmed, "GBP")
    }

    func testARefreshAnsweredWithTheSameCurrencyKeepsTheSelection() {
        var loads = CardCurrencyLoads(confirmed: "GBP")
        let load = loads.begin()
        XCTAssertEqual(loads.finish(load, .currency("GBP")), .applied(clearsSelection: false))
    }

    func testARefreshAnsweredWithAnotherCurrencyChangesItAndClearsTheSelection() {
        var loads = CardCurrencyLoads(confirmed: "GBP")
        let load = loads.begin()
        XCTAssertEqual(loads.finish(load, .currency("EUR")), .applied(clearsSelection: true))
        XCTAssertEqual(loads.confirmed, "EUR")
    }

    func testARefreshAnsweredWithoutAUsableCurrencyUnconfirmsItAndClearsTheSelection() {
        var loads = CardCurrencyLoads(confirmed: "GBP")
        let load = loads.begin()
        XCTAssertEqual(loads.finish(load, .unusable), .applied(clearsSelection: true))
        XCTAssertEqual(loads.state, .unknown)
        XCTAssertNil(loads.confirmed)
    }

    func testASupersededLoadNamesNothing() {
        var loads = CardCurrencyLoads()
        let older = loads.begin()
        let newer = loads.begin()

        XCTAssertEqual(loads.finish(newer, .currency("GBP")), .applied(clearsSelection: true))
        XCTAssertEqual(loads.finish(older, .currency("USD")), .superseded)
        XCTAssertEqual(loads.finish(older, .unusable), .superseded)
        XCTAssertEqual(loads.confirmed, "GBP")
    }

    func testASupersededLoadNamesNothingEvenWhenItEndsFirst() {
        var loads = CardCurrencyLoads()
        let older = loads.begin()
        let newer = loads.begin()

        XCTAssertEqual(loads.finish(older, .currency("USD")), .superseded)
        XCTAssertEqual(loads.state, .loading)
        XCTAssertEqual(loads.finish(newer, .currency("GBP")), .applied(clearsSelection: true))
    }

    /// Only the first load shows USD provisionally. A retry after an unknown currency shows
    /// none until CTX names one.
    func testTryingAgainAfterAnUnknownCurrencyShowsNoCurrencyWhileItLoads() {
        var loads = CardCurrencyLoads()
        XCTAssertEqual(loads.finish(loads.begin(), .noAnswer), .applied(clearsSelection: true))

        let retry = loads.begin()
        XCTAssertEqual(loads.state, .unknown)
        XCTAssertNil(loads.shown)
        XCTAssertNil(loads.confirmed)
        XCTAssertEqual(GiftCardPurchaseBlock.check(currency: loads.shown, rate: { _ in 40 }), .currencyUnconfirmed)

        XCTAssertEqual(loads.finish(retry, .currency("USD")), .applied(clearsSelection: true))
        XCTAssertEqual(loads.confirmed, "USD")
    }

    func testARetryWithoutAnAnswerLeavesTheCurrencyUnknown() {
        var loads = CardCurrencyLoads()
        XCTAssertEqual(loads.finish(loads.begin(), .unusable), .applied(clearsSelection: true))

        XCTAssertEqual(loads.finish(loads.begin(), .noAnswer), .applied(clearsSelection: false))
        XCTAssertEqual(loads.state, .unknown)
        XCTAssertNil(loads.shown)
    }

    // MARK: - What blocks every purchase

    func testAnUnconfirmedCurrencyBlocks() {
        XCTAssertEqual(GiftCardPurchaseBlock.check(currency: nil, rate: { _ in 40 }), .currencyUnconfirmed)
    }

    func testAMissingRateForTheCardCurrencyBlocks() {
        let rates: [String: Decimal] = ["USD": 40]
        XCTAssertNil(GiftCardPurchaseBlock.check(currency: "USD", rate: { rates[$0] }))
        XCTAssertEqual(GiftCardPurchaseBlock.check(currency: "GBP", rate: { rates[$0] }), .rateMissing)
        XCTAssertEqual(GiftCardPurchaseBlock.check(currency: "USD", rate: { _ in nil }), .rateMissing)
        XCTAssertEqual(GiftCardPurchaseBlock.check(currency: "USD", rate: { _ in 0 }), .rateMissing)
        XCTAssertEqual(GiftCardPurchaseBlock.check(currency: "USD", rate: { _ in -1 }), .rateMissing)
    }

    func testTheRateIsAskedForTheCardCurrency() {
        var asked: [String] = []
        _ = GiftCardPurchaseBlock.check(currency: "GBP", rate: { asked.append($0); return 30 })
        XCTAssertEqual(asked, ["GBP"])
    }

    // MARK: - A CTX order

    func testATypedAmountIsOrderedAsOneCardInTheCardCurrency() throws {
        let order = try CTXGiftCardOrder(price: decimal("25.5"), quantities: [:], currency: "GBP")
        XCTAssertEqual(order.fiatCurrency, "GBP")
        XCTAssertEqual(order.fiatAmount, "25.50")
    }

    func testOneFixedCardIsOrderedForItsValue() throws {
        let order = try CTXGiftCardOrder(price: 5000, quantities: [5000: 1, 1000: 0], currency: "JPY")
        XCTAssertEqual(order.fiatCurrency, "JPY")
        XCTAssertEqual(order.fiatAmount, "5000")
    }

    func testSeveralCardsAreRefused() {
        XCTAssertThrowsError(try CTXGiftCardOrder(price: 50, quantities: [25: 2], currency: "USD")) {
            XCTAssertEqual($0 as? CTXGiftCardOrder.Refusal, .notOneCard)
        }
        XCTAssertThrowsError(try CTXGiftCardOrder(price: 75, quantities: [25: 1, 50: 1], currency: "USD")) {
            XCTAssertEqual($0 as? CTXGiftCardOrder.Refusal, .notOneCard)
        }
    }

    func testACardThatIsNotTheConfirmedPriceIsRefused() {
        XCTAssertThrowsError(try CTXGiftCardOrder(price: 50, quantities: [25: 1], currency: "USD")) {
            XCTAssertEqual($0 as? CTXGiftCardOrder.Refusal, .notOneCard)
        }
    }

    func testAnAmountOfZeroOrOneTheCurrencyCannotHoldIsRefused() {
        XCTAssertThrowsError(try CTXGiftCardOrder(price: 0, quantities: [:], currency: "USD")) {
            XCTAssertEqual($0 as? CTXGiftCardOrder.Refusal, .amountNotInCurrency)
        }
        XCTAssertThrowsError(try CTXGiftCardOrder(price: decimal("1000.5"), quantities: [:], currency: "JPY")) {
            XCTAssertEqual($0 as? CTXGiftCardOrder.Refusal, .amountNotInCurrency)
        }
    }

    func testAFixedSelectionIsHeldToOneCard() {
        XCTAssertEqual(CTXGiftCardOrder.singleCard(from: [:], to: [25: 1]), [25: 1])
        XCTAssertEqual(CTXGiftCardOrder.singleCard(from: [25: 1], to: [25: 2]), [25: 1])
        XCTAssertEqual(CTXGiftCardOrder.singleCard(from: [25: 1], to: [25: 1, 50: 1]), [50: 1])
        XCTAssertEqual(CTXGiftCardOrder.singleCard(from: [25: 1], to: [:]), [:])
    }

    // MARK: - The provider's answer and the saved card

    func testAnAnswerInTheOrderedCurrencyConfirmsTheOrder() {
        XCTAssertTrue(GiftCardCurrency.answerConfirms(ordered: "GBP", reported: ["GBP", "gbp"]))
        XCTAssertTrue(GiftCardCurrency.answerConfirms(ordered: "GBP", reported: [nil, " GBP "]))
        XCTAssertTrue(GiftCardCurrency.answerConfirms(ordered: "USD", reported: ["USD", nil]))
    }

    func testAnAnswerThatNamesAnotherCurrencyDoesNotConfirmTheOrder() {
        XCTAssertFalse(GiftCardCurrency.answerConfirms(ordered: "GBP", reported: ["USD", "GBP"]))
        XCTAssertFalse(GiftCardCurrency.answerConfirms(ordered: "GBP", reported: ["GBP", "EUR"]))
        XCTAssertFalse(GiftCardCurrency.answerConfirms(ordered: "GBP", reported: [nil, "USD"]))
        XCTAssertFalse(GiftCardCurrency.answerConfirms(ordered: "USD", reported: ["GBP", nil]))
    }

    /// Answers named no currency while every order was USD, so one that names none still
    /// confirms a USD order. It confirms no other.
    func testAnAnswerThatNamesNoCurrencyConfirmsOnlyAUSDOrder() {
        for reported in [[], [nil, nil], ["", "  "]] as [[String?]] {
            XCTAssertTrue(GiftCardCurrency.answerConfirms(ordered: "USD", reported: reported))
            XCTAssertFalse(GiftCardCurrency.answerConfirms(ordered: "GBP", reported: reported))
            XCTAssertFalse(GiftCardCurrency.answerConfirms(ordered: "JPY", reported: reported))
        }
    }

    // MARK: - The discounted price

    func testTheDiscountedPriceIsExactInDecimal() {
        XCTAssertEqual(GiftCardCurrency.discounted(decimal("1.1"), by: decimal("0.1"), currency: "KWD"), decimal("0.99"))
        XCTAssertEqual(GiftCardCurrency.string(
            GiftCardCurrency.discounted(decimal("1.1"), by: decimal("0.1"), currency: "KWD"),
            currency: "KWD", locale: enUS).contains("0.990"), true)
        XCTAssertEqual(GiftCardCurrency.discounted(100, by: decimal("0.1"), currency: "USD"), 90)
        XCTAssertEqual(GiftCardCurrency.discounted(25, by: 0, currency: "USD"), 25)
    }

    func testTheDiscountedPriceIsRoundedUpOnceAtTheCurrencysDecimals() {
        // 24.0625, 974.025 and 1.108875
        XCTAssertEqual(GiftCardCurrency.discounted(25, by: decimal("0.0375"), currency: "USD"), decimal("24.07"))
        XCTAssertEqual(GiftCardCurrency.discounted(999, by: decimal("0.025"), currency: "JPY"), 975)
        XCTAssertEqual(GiftCardCurrency.discounted(decimal("1.125"), by: decimal("0.0143"), currency: "KWD"),
                       decimal("1.109"))
    }

    // MARK: - A confirmation and the selection behind it

    func testAConfirmationShowsTheSelectionItWasOpenedFor() {
        XCTAssertTrue(CTXGiftCardOrder.confirmationShows(price: 25, quantities: [:], amount: 25, cart: nil))
        XCTAssertTrue(CTXGiftCardOrder.confirmationShows(price: 50, quantities: [25: 2], amount: 50, cart: [25: 2]))
        XCTAssertTrue(CTXGiftCardOrder.confirmationShows(price: 25, quantities: [25: 1], amount: 25,
                                                         cart: [25: 1, 50: 0]))
    }

    func testAConfirmationNoLongerShowsAChangedAmountOrCart() {
        XCTAssertFalse(CTXGiftCardOrder.confirmationShows(price: 25, quantities: [:], amount: 30, cart: nil))
        XCTAssertFalse(CTXGiftCardOrder.confirmationShows(price: 25, quantities: [:], amount: 0, cart: nil))
        XCTAssertFalse(CTXGiftCardOrder.confirmationShows(price: 50, quantities: [25: 2], amount: 50, cart: [50: 1]))
        XCTAssertFalse(CTXGiftCardOrder.confirmationShows(price: 50, quantities: [25: 2], amount: 50, cart: [:]))
    }

    func testASavedCardWithoutACurrencyIsInDollars() {
        XCTAssertEqual(GiftCardCurrency.ofSavedCard(nil), "USD")
        XCTAssertEqual(GiftCardCurrency.ofSavedCard(""), "USD")
        XCTAssertEqual(GiftCardCurrency.ofSavedCard("GBP"), "GBP")
        XCTAssertEqual(GiftCardCurrency.ofSavedCard("JPY"), "JPY")
    }
}
