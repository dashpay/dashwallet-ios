//
//  DashSpendPurchaseTests.swift
//  DashWalletTests
//
//  A gift card purchase run end to end in `DashSpendPayViewModel`, for each provider, with
//  the provider's order response and the send service stubbed. These tests pin that the Dash
//  amount a provider asks for is compared with the price the buyer confirmed before anything
//  is paid: they fail when that comparison is left out of either provider's path. They also
//  pin that a payment whose outcome is unknown is recorded as a purchase, for both providers.
//
//  The PiggyCards tests are not wrapped in `PIGGYCARDS_ENABLED`: the test target does not
//  define it, and the `dashpay` host app these tests import is built with it in every
//  configuration.
//

import Combine
import SwiftDashSDK
import XCTest
@testable import dashpay

// MARK: - Stubs

@MainActor
private final class StubCTXRepository: CTXGiftCardOrdering {
    var isUserSignedIn = true
    var isUserSignedInPublisher: AnyPublisher<Bool, Never> { Just(isUserSignedIn).eraseToAnyPublisher() }

    static let orderId = "ctx-order-1"
    static let paymentURL = "dash:?r=https://provider.invalid/pay/ctx-order-1"

    private(set) var orders: [(merchantId: String, fiatAmount: String, fiatCurrency: String)] = []

    /// What `getMerchant` answers: the response body, or the error it throws.
    var merchantAnswer: Result<String, Error> = .failure(DashSpendError.networkError)
    /// While `true`, a `getMerchant` call waits until the test answers it.
    var holdsMerchantCalls = false
    private(set) var heldMerchantCalls: [CheckedContinuation<String, Error>] = []
    /// The currencies the order response names; `nil` for a field it leaves out.
    var answeredCurrencies: (payment: String?, card: String?) = (nil, nil)
    /// The card value the order is answered with, given the amount ordered; nil for none.
    var answeredCardAmount: (String) -> String? = { $0 }

    /// A `GET merchants/{id}` body; `currency` nil leaves the field out.
    static func merchantJSON(currency: String?, type: String = "min-max",
                             denominations: [Any] = ["5", "500"], savings: Int = 0) -> String {
        var body: [String: Any] = [
            "id": "merchant-1", "denominationsType": type, "denominations": denominations,
            "savingsPercentage": savings,
        ]
        body["currency"] = currency
        return String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }

    func getMerchant(merchantId: String) async throws -> MerchantResponse {
        let json: String
        if holdsMerchantCalls {
            json = try await withCheckedThrowingContinuation { heldMerchantCalls.append($0) }
        } else {
            json = try merchantAnswer.get()
        }
        return try JSONDecoder().decode(MerchantResponse.self, from: Data(json.utf8))
    }

    func answerMerchantCall(_ index: Int, with json: String) {
        heldMerchantCalls[index].resume(returning: json)
    }

    func purchaseGiftCard(merchantId: String, fiatAmount: String, fiatCurrency: String,
                          cryptoCurrency: String) async throws -> GiftCardResponse {
        orders.append((merchantId, fiatAmount, fiatCurrency))
        var body: [String: Any] = [
            "id": Self.orderId, "status": "unpaid", "paymentId": "payment-1",
            "paymentUrls": ["DASH.DASH": Self.paymentURL],
        ]
        body["paymentFiatCurrency"] = answeredCurrencies.payment
        body["cardFiatCurrency"] = answeredCurrencies.card
        body["cardFiatAmount"] = answeredCardAmount(fiatAmount)
        return try JSONDecoder().decode(GiftCardResponse.self, from: JSONSerialization.data(withJSONObject: body))
    }
}

@MainActor
private final class StubPiggyCardsRepository: PiggyCardsGiftCardOrdering {
    var isUserSignedIn = true
    var isUserSignedInPublisher: AnyPublisher<Bool, Never> { Just(isUserSignedIn).eraseToAnyPublisher() }

    static let orderId = "piggy-order-1"
    static let paymentAddress = "yTestPaymentAddress"

    /// The Dash amount the order response asks for.
    var quotedDash: Decimal = 0
    private(set) var orders: [[PiggyCardsRepository.OrderLineItem]] = []

    func getGiftCards(country: String, sourceId: String, merchantId: String) async throws -> [PiggyCardsGiftcard] {
        throw DashSpendError.networkError
    }

    func orderGiftCards(merchantId: String, lineItems: [PiggyCardsRepository.OrderLineItem],
                        fiatCurrency: String, cryptoCurrency: String) async throws -> GiftCardInfo {
        orders.append(lineItems)
        return GiftCardInfo(
            orderId: Self.orderId, paymentAddress: Self.paymentAddress, amount: quotedDash,
            merchantName: "Test Merchant", discountPercentage: 0, exchangeRate: 40, status: "pending")
    }
}

/// Stands in for `SendCoinsService`. Like the real service, it hands the amount of the
/// payment request to the caller's `validate` before it pays; `PaymentProtocolTests` pins
/// that the real one does so before the PIN prompt.
@MainActor
private final class StubPayments: GiftCardPaying {
    static let txidWire = Data(repeating: 0xAB, count: 32)

    /// The Dash amount the payment request behind a payment URL asks for.
    var requestedByURL: UInt64 = 0
    /// Thrown in place of paying, once the amount has passed the caller's check.
    var failure: Error?
    private(set) var urlPayments: [(url: String, amount: UInt64, awaitAcceptance: Bool)] = []
    private(set) var addressPayments: [(address: String, amount: UInt64)] = []

    var isEmpty: Bool { urlPayments.isEmpty && addressPayments.isEmpty }

    func payWithDashUrl(url paymentUrlString: String, awaitAcceptance: Bool,
                        validate: @escaping (Confirmation) async throws -> Void) async throws -> Data {
        let amount = requestedByURL
        try await validate(Confirmation(
            merchantName: nil, isSecure: true, recipients: [(address: "yTestRecipient", amount: amount)],
            amount: amount, estimatedFee: 0, network: .testnet, paymentURL: nil, scheme: "dash",
            merchantData: nil, memo: nil, callbackScheme: nil,
            request: PaymentRequest(serializedDetails: Data())))
        if let failure { throw failure }
        urlPayments.append((paymentUrlString, amount, awaitAcceptance))
        return Self.txidWire
    }

    func payGiftCardOrder(address: String, amount: UInt64) async throws -> Data {
        if let failure { throw failure }
        addressPayments.append((address, amount))
        return Self.txidWire
    }
}

@MainActor
private final class StubPurchaseRecorder: GiftCardPurchaseRecording {
    private(set) var records: [GiftCardPurchaseRecord] = []

    func record(_ purchase: GiftCardPurchaseRecord) {
        records.append(purchase)
    }
}

/// The pay view model with the network taken as reachable, so the message it shows does not
/// depend on the reachability of the machine the tests run on.
@MainActor
private final class OnlineDashSpendPayViewModel: DashSpendPayViewModel {
    /// The most the wallet can send; `nil` to ask the wallet.
    var sendableDuffs: UInt64?

    override var isNetworkAvailable: Bool { true }

    override func fundsRefusal(requestedDuffs: UInt64) -> SendAmountError? {
        guard let sendableDuffs else { return super.fundsRefusal(requestedDuffs: requestedDuffs) }
        return requestedDuffs > sendableDuffs ? .insufficientFunds : nil
    }
}

/// The wallet's rates, which a test changes while a view model reads them.
private final class Rates {
    var prices: [String: Decimal]
    var areFetching = false
    init(_ prices: [String: Decimal]) { self.prices = prices }
}

/// The stores the production purchase recorder writes to, kept in memory.
private final class StubTransactionMetadataDAO: TransactionMetadataDAO {
    func create(dto: TransactionMetadata) {}
    func get(by hash: Data, ignoreCache: Bool) -> TransactionMetadata? { nil }
    func update(dto: TransactionMetadata) {}
    func delete(dto: TransactionMetadata) {}
    func deleteAll() {}
}

private final class StubIconUpdater: GiftCardIconUpdating {
    func updateIcon(txId: Data, iconUrl: String) {}
}

/// `create` runs off the main actor, so the rows it keeps are read under a lock.
private final class StubGiftCardsDAO: GiftCardsDAO, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [GiftCard] = []
    var created: [GiftCard] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    var giftCardTxIdPublisher: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    func create(dto: GiftCard) async {
        lock.lock()
        rows.append(dto)
        lock.unlock()
    }
    func get(byTxId txId: Data) async -> GiftCard? { nil }
    func observeAll() -> AnyPublisher<[GiftCard], Never> { Empty().eraseToAnyPublisher() }
    func update(dto: GiftCard) async {}
    func updateCardDetails(txId: Data, number: String, pin: String?) async {}
    func updateBarcode(txId: Data, value: String, format: String) async {}
    func updateRedeemUrl(txId: Data, url: String, challenge: String?) async {}
    func backfillCurrency(txId: Data, currency: String) async {}
    func delete(byTxId txId: Data) async {}
    func all() async -> [GiftCard] { [] }
}

// MARK: - Tests

@MainActor
final class DashSpendPurchaseTests: XCTestCase {

    /// A $25 card with no discount at $40 per Dash: 0.625 Dash.
    private static let confirmedDuffs: UInt64 = 62_500_000
    /// 10% above the confirmed amount: 0.6875 Dash.
    private static let higherDuffs: UInt64 = 68_750_000
    /// How long a test waits for the view model before it fails.
    private static let patience: TimeInterval = 2

    private var ctx: StubCTXRepository!
    private var payments: StubPayments!
    private var recorder: StubPurchaseRecorder!
    private var piggyCards: StubPiggyCardsRepository!

    override func setUp() async throws {
        try await super.setUp()
        ctx = StubCTXRepository()
        payments = StubPayments()
        recorder = StubPurchaseRecorder()
        piggyCards = StubPiggyCardsRepository()
    }

    private var merchant: ExplorePointOfUse { merchant(piggyCardsSavings: 0) }

    /// - Parameter withLocalLimits: whether the merchant comes with limits of 5 to 500, as
    ///   one from the explore database does before CTX has answered.
    private func merchant(piggyCardsSavings: Int, withLocalLimits: Bool = false) -> ExplorePointOfUse {
        ExplorePointOfUse(
            id: 0, name: "Test Merchant",
            category: .merchant(ExplorePointOfUse.Merchant(
                merchantId: "merchant-1", paymentMethod: .giftCard, type: .online, deeplink: nil,
                savingsBasisPoints: 0,
                denominationsType: withLocalLimits ? DenominationType.Range.rawValue : "range",
                denominations: withLocalLimits ? [5, 500] : [],
                redeemType: "online",
                giftCardProviders: [
                    .init(providerId: "ctx", savingsPercentage: 0, denominationsType: "range", sourceId: nil),
                    .init(providerId: "piggycards", savingsPercentage: piggyCardsSavings,
                          denominationsType: "range", sourceId: "1"),
                ])),
            active: true, city: nil, territory: nil,
            address1: nil, address2: nil, address3: nil, address4: nil, latitude: nil, longitude: nil,
            website: nil, phone: nil, logoLocation: nil, coverImage: nil, source: nil)
    }

    /// A view model on the stubs, with the Confirm sheet open for a $25 card.
    private func viewModelWithConfirmSheet(provider: GiftCardProvider) throws
        -> (DashSpendPayViewModel, GiftCardPurchaseSnapshot) {
        let rate = GiftCardPaymentGuard.ExchangeRate(price: 40, retrievedAt: Int(Date().timeIntervalSince1970))
        let dependencies = DashSpendPayViewModel.Dependencies(
            ctx: ctx, piggyCards: piggyCards, payments: payments, purchases: recorder)
        let viewModel = DashSpendPayViewModel(
            merchant: merchant, provider: provider,
            confirmedTerms: CTXMerchantTerms(currency: "USD", denominationsType: "min-max", denominations: ["1", "1000"]),
            exchangeRate: { _ in rate },
            dependencies: dependencies)
        // No sheet is on screen in these tests, so nothing reports its dismissal.
        viewModel.sheetDismissalWait = 0.01

        try viewModel.beginPurchase(price: 25)
        guard case .confirm(let snapshot)? = viewModel.purchaseSheet else {
            XCTFail("the Confirm sheet did not open")
            throw CancellationError()
        }
        XCTAssertEqual(snapshot.approval.amount, Self.confirmedDuffs)
        return (viewModel, snapshot)
    }

    /// The rates the card currency tests give the wallet: the fiat price of one Dash.
    private static let rates: [String: Decimal] = ["USD": 40, "GBP": 50, "EUR": 45, "JPY": 5000, "KWD": 12]

    /// A CTX view model on the stubs whose merchant is still to be loaded.
    private func ctxViewModel(rates: [String: Decimal] = DashSpendPurchaseTests.rates,
                              onRate: @escaping (String) -> Void = { _ in }) -> OnlineDashSpendPayViewModel {
        ctxViewModel(live: Rates(rates), onRate: onRate)
    }

    private func ctxViewModel(live rates: Rates, withLocalLimits: Bool = false,
                              onRate: @escaping (String) -> Void = { _ in }) -> OnlineDashSpendPayViewModel {
        let retrievedAt = Int(Date().timeIntervalSince1970)
        let dependencies = DashSpendPayViewModel.Dependencies(
            ctx: ctx, piggyCards: piggyCards, payments: payments, purchases: recorder)
        let viewModel = OnlineDashSpendPayViewModel(
            merchant: merchant(piggyCardsSavings: 0, withLocalLimits: withLocalLimits), provider: .ctx,
            exchangeRate: { currency in
                onRate(currency)
                return GiftCardPaymentGuard.ExchangeRate(price: rates.prices[currency], retrievedAt: retrievedAt)
            },
            ratesAreFetching: { rates.areFetching },
            dependencies: dependencies)
        viewModel.sheetDismissalWait = 0.01
        return viewModel
    }

    /// A CTX view model that has loaded a merchant with `json` as CTX's answer.
    private func ctxViewModel(loading json: String) async -> OnlineDashSpendPayViewModel {
        let viewModel = ctxViewModel()
        ctx.merchantAnswer = .success(json)
        await viewModel.updateMerchantInfo()
        return viewModel
    }

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    /// Opens the Confirm sheet and returns what it shows.
    private func confirmation(of price: Decimal, quantities: [Decimal: Int] = [:],
                              on viewModel: DashSpendPayViewModel) throws -> GiftCardPurchaseSnapshot {
        try viewModel.beginPurchase(price: price, quantities: quantities)
        guard case .confirm(let snapshot)? = viewModel.purchaseSheet else {
            XCTFail("the Confirm sheet did not open")
            throw CancellationError()
        }
        return snapshot
    }

    private func assertNothingOrdered(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ctx.orders.isEmpty, "an order was made", file: file, line: line)
        XCTAssertTrue(payments.isEmpty, "a payment was made", file: file, line: line)
        XCTAssertTrue(recorder.records.isEmpty, "a purchase was recorded", file: file, line: line)
    }

    // MARK: CTX, the card currency

    /// Before CTX has named the merchant's currency nothing can be bought, although the
    /// explore database's USD amounts are on screen.
    func testNothingIsBoughtBeforeTheCurrencyIsConfirmed() {
        let viewModel = ctxViewModel()

        XCTAssertNil(viewModel.cardCurrency)
        XCTAssertEqual(viewModel.currencySymbol, "")
        XCTAssertNil(viewModel.error)
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 25))
        XCTAssertNil(viewModel.purchaseSheet)
        assertNothingOrdered()
    }

    func testAUSDMerchantLoadsWithItsLimitsAndKeepsTheSelection() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD"))

        XCTAssertEqual(viewModel.cardCurrency, "USD")
        XCTAssertFalse(viewModel.canRetryMerchantLoad)
        XCTAssertEqual(viewModel.selectionResets, 0)
        XCTAssertEqual(viewModel.minimumAmount, 5)
        XCTAssertEqual(viewModel.maximumAmount, 500)
        XCTAssertEqual(viewModel.amountFractionDigits, 2)
        XCTAssertEqual(try confirmation(of: 25, on: viewModel).currency, "USD")
    }

    func testAMerchantThatCannotBeLoadedBlocksThePurchaseUntilARetryConfirmsTheCurrency() async throws {
        let viewModel = ctxViewModel()
        await viewModel.updateMerchantInfo()

        XCTAssertNil(viewModel.cardCurrency)
        XCTAssertTrue(viewModel.canRetryMerchantLoad)
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 25))
        XCTAssertNil(viewModel.purchaseSheet)
        assertNothingOrdered()

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "USD"))
        await viewModel.updateMerchantInfo()

        XCTAssertEqual(viewModel.cardCurrency, "USD")
        XCTAssertFalse(viewModel.canRetryMerchantLoad)
        XCTAssertEqual(try confirmation(of: 25, on: viewModel).currency, "USD")
    }

    func testAnAnswerWithoutAUsableCurrencyBlocksThePurchase() async {
        let answers: [Result<String, Error>] = [
            .success(StubCTXRepository.merchantJSON(currency: nil)),
            .success(StubCTXRepository.merchantJSON(currency: "")),
            .success(StubCTXRepository.merchantJSON(currency: "ZZZ")),
            .success(StubCTXRepository.merchantJSON(currency: "USD", denominations: ["5", "five hundred"])),
            .failure(DashSpendError.parsingError),
        ]
        for answer in answers {
            let viewModel = ctxViewModel()
            ctx.merchantAnswer = answer
            await viewModel.updateMerchantInfo()

            XCTAssertNil(viewModel.cardCurrency, "\(answer)")
            XCTAssertTrue(viewModel.canRetryMerchantLoad, "\(answer)")
            XCTAssertEqual(viewModel.minimumAmount, 0, "\(answer)")
            XCTAssertEqual(viewModel.maximumAmount, 0, "\(answer)")
            XCTAssertThrowsError(try viewModel.beginPurchase(price: 25), "\(answer)")
        }
        assertNothingOrdered()
    }

    /// £25.50 at £50 per Dash is 0.51 Dash. The order names pounds, the wallet pays the Dash
    /// the payment request asks for, and the saved card keeps the currency.
    func testAPoundCardIsOrderedPaidAndRecordedInPounds() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "GBP"))
        XCTAssertEqual(viewModel.cardCurrency, "GBP")
        XCTAssertEqual(viewModel.selectionResets, 0)
        XCTAssertEqual(viewModel.minimumAmount, 5)
        XCTAssertEqual(viewModel.maximumAmount, 500)

        let snapshot = try confirmation(of: decimal("25.5"), on: viewModel)
        XCTAssertEqual(snapshot.currency, "GBP")
        XCTAssertEqual(snapshot.approval.rate, 50)
        XCTAssertEqual(snapshot.approval.amount, 51_000_000)

        ctx.answeredCurrencies = (payment: "GBP", card: "gbp")
        payments.requestedByURL = 51_100_000
        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(ctx.orders.map(\.fiatCurrency), ["GBP"])
        XCTAssertEqual(ctx.orders.map(\.fiatAmount), ["25.50"])
        XCTAssertEqual(payments.urlPayments.map(\.amount), [51_100_000])
        XCTAssertEqual(recorder.records.map(\.currency), ["GBP"])
        XCTAssertEqual(recorder.records.map(\.price), [decimal("25.5")])
    }

    func testAYenCardIsOrderedWithoutDecimals() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
            currency: "JPY", type: "fixed", denominations: ["1000", "5000"]))
        XCTAssertTrue(viewModel.isFixedDenomination)
        XCTAssertEqual(viewModel.denominations, [1000, 5000])
        XCTAssertEqual(viewModel.amountFractionDigits, 0)

        let snapshot = try confirmation(of: 5000, quantities: [5000: 1], on: viewModel)
        ctx.answeredCurrencies = (payment: "JPY", card: "JPY")
        payments.requestedByURL = snapshot.approval.amount
        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(ctx.orders.map(\.fiatCurrency), ["JPY"])
        XCTAssertEqual(ctx.orders.map(\.fiatAmount), ["5000"])
        XCTAssertEqual(recorder.records.map(\.currency), ["JPY"])
    }

    func testADinarCardKeepsItsThreeDecimals() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
            currency: "KWD", type: "fixed", denominations: ["1.125", "5"]))
        XCTAssertEqual(viewModel.denominations, [decimal("1.125"), 5])
        XCTAssertEqual(viewModel.amountFractionDigits, 3)

        let snapshot = try confirmation(of: decimal("1.125"), quantities: [decimal("1.125"): 1], on: viewModel)
        ctx.answeredCurrencies = (payment: nil, card: "KWD")
        payments.requestedByURL = snapshot.approval.amount
        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(ctx.orders.map(\.fiatCurrency), ["KWD"])
        XCTAssertEqual(ctx.orders.map(\.fiatAmount), ["1.125"])
    }

    func testAFractionalCardValueIsKeptAsItIs() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
            currency: "USD", type: "fixed", denominations: ["10", "12.50"]))

        XCTAssertEqual(viewModel.denominations, [10, decimal("12.5")])
    }

    func testAnAmountTheCurrencyCannotHoldIsRefusedBeforeAnOrder() async {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "JPY"))

        XCTAssertThrowsError(try viewModel.beginPurchase(price: decimal("1000.5")))
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 0))
        XCTAssertNil(viewModel.purchaseSheet)
        assertNothingOrdered()
    }

    /// CTX is asked for one card. Two cards of 25 are not ordered as one card of 50.
    func testSeveralCTXCardsAreRefusedBeforeAnOrder() async {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
            currency: "USD", type: "fixed", denominations: ["25", "50"]))

        XCTAssertThrowsError(try viewModel.beginPurchase(price: 50, quantities: [25: 2]))
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 75, quantities: [25: 1, 50: 1]))
        XCTAssertNil(viewModel.purchaseSheet)
        assertNothingOrdered()
    }

    func testAMissingRateForTheCardCurrencyBlocksThePurchase() async {
        let viewModel = ctxViewModel(rates: ["USD": 40])
        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "GBP"))
        await viewModel.updateMerchantInfo()

        XCTAssertEqual(viewModel.cardCurrency, "GBP")
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 25))
        XCTAssertNil(viewModel.purchaseSheet)
        assertNothingOrdered()
    }

    func testAMissingDollarRateBlocksADollarPurchase() async {
        let viewModel = ctxViewModel(rates: [:])
        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "USD"))
        await viewModel.updateMerchantInfo()

        XCTAssertThrowsError(try viewModel.beginPurchase(price: 25))
        assertNothingOrdered()
    }

    func testTheConfirmationUsesTheRateOfTheCardCurrency() async throws {
        var asked: [String] = []
        let viewModel = ctxViewModel(onRate: { asked.append($0) })
        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "EUR"))
        await viewModel.updateMerchantInfo()
        asked.removeAll()

        let snapshot = try confirmation(of: 45, on: viewModel)

        XCTAssertEqual(asked, ["EUR"])
        XCTAssertEqual(snapshot.approval.rate, 45)
        XCTAssertEqual(snapshot.approval.amount, 100_000_000)
    }

    func testAnOrderAnsweredInAnotherCurrencyIsNotPaid() async throws {
        // The last answer names no currency at all, which only a USD order accepts.
        let answers: [(payment: String?, card: String?)] = [
            (payment: "USD", card: "GBP"), (payment: "GBP", card: "USD"), (payment: nil, card: "EUR"),
            (payment: nil, card: nil), (payment: "GBP", card: nil),
        ]
        for answered in answers {
            let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "GBP"))
            let snapshot = try confirmation(of: 25, on: viewModel)
            ctx.answeredCurrencies = answered
            payments.requestedByURL = snapshot.approval.amount

            do {
                _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)
                XCTFail("the order was paid: \(answered)")
            } catch {}

            XCTAssertTrue(payments.isEmpty, "\(answered)")
            XCTAssertTrue(recorder.records.isEmpty, "\(answered)")
            XCTAssertNil(viewModel.purchaseSheet, "\(answered)")
        }
    }

    func testAUSDOrderAnsweredWithoutACurrencyIsPaid() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD"))
        let snapshot = try confirmation(of: 25, on: viewModel)
        payments.requestedByURL = snapshot.approval.amount

        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(ctx.orders.map(\.fiatCurrency), ["USD"])
        XCTAssertEqual(payments.urlPayments.count, 1)
    }

    /// The Dash amount of an answer is paid as it stands, so an answer for another card
    /// value than the one confirmed, or for none that can be read, is not paid.
    func testAnOrderAnsweredForAnotherCardValueIsNotPaid() async throws {
        for answered in ["20.00", "24.99", "25.01", "30.00", "", "25,00", nil] as [String?] {
            let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD"))
            let snapshot = try confirmation(of: 25, on: viewModel)
            payments.requestedByURL = snapshot.approval.amount
            ctx.answeredCardAmount = { _ in answered }

            do {
                _ = try await viewModel.purchaseGiftCardAndPay(snapshot)
                XCTFail("the order was paid: \(answered ?? "nil")")
            } catch {}

            XCTAssertTrue(payments.isEmpty, answered ?? "nil")
            XCTAssertTrue(recorder.records.isEmpty, answered ?? "nil")
            XCTAssertNil(viewModel.purchaseSheet, answered ?? "nil")
        }
    }

    func testAnOrderAnsweredForTheSameCardValueInAnotherScaleIsPaidAndRecorded() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD"))
        let snapshot = try confirmation(of: 25, on: viewModel)
        payments.requestedByURL = snapshot.approval.amount
        ctx.answeredCardAmount = { _ in "25" }

        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(ctx.orders.map(\.fiatAmount), ["25.00"])
        XCTAssertEqual(payments.urlPayments.count, 1)
        XCTAssertEqual(recorder.records.map(\.price), [25])
    }

    /// Clearing the selection sets `selectedDenomination`, whose observer puts the typed text
    /// back to "0". A currency change relies on that: "10.50" typed while the first load
    /// still showed dollars is not an amount of yen, and yen has no decimal key to edit it.
    func testClearingTheSelectionForAnotherCurrencyResetsTheTypedText() async {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "GBP"))
        let separator = Locale.current.decimalSeparator ?? "."
        viewModel.input = "10\(separator)50"
        XCTAssertEqual(viewModel.amount, decimal("10.5"))

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "JPY"))
        await viewModel.updateMerchantInfo()

        XCTAssertEqual(viewModel.input, "0")
        XCTAssertEqual(viewModel.amount, 0)
        viewModel.input = "05"
        XCTAssertEqual(viewModel.input, "5")
        viewModel.input = "5\(separator)5"
        XCTAssertEqual(viewModel.input, "5")
    }

    /// The first load shows the explore database's dollars. A retry after a failed load
    /// shows no currency, and typing during it does not clear the message.
    func testARetryShowsNoCurrencyAndKeepsItsMessage() async {
        let viewModel = ctxViewModel()
        await viewModel.updateMerchantInfo()
        XCTAssertEqual(viewModel.error as? GiftCardPurchaseBlock, .currencyUnconfirmed)

        ctx.holdsMerchantCalls = true
        let retry = Task { await viewModel.updateMerchantInfo() }
        await waitForHeldMerchantCalls(1)
        guard ctx.heldMerchantCalls.count == 1 else { return XCTFail("the retry did not start") }

        XCTAssertNil(viewModel.cardCurrency)
        XCTAssertEqual(viewModel.currencySymbol, "")
        viewModel.input = "7"
        XCTAssertEqual(viewModel.error as? GiftCardPurchaseBlock, .currencyUnconfirmed)
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 7))

        ctx.answerMerchantCall(0, with: StubCTXRepository.merchantJSON(currency: "USD"))
        await retry.value
        XCTAssertEqual(viewModel.cardCurrency, "USD")
        XCTAssertEqual(viewModel.currencySymbol, GiftCardCurrency.symbol(for: "USD"))
    }

    /// Confirm orders what the sheet shows. A selection that changes behind an open
    /// confirmation closes it, and the old confirmation orders nothing.
    func testAChangedAmountClosesTheConfirmationAndItOrdersNothing() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD"))
        viewModel.updateTotalAmount(25)
        let snapshot = try confirmation(of: 25, on: viewModel)

        viewModel.updateTotalAmount(25)
        XCTAssertEqual(viewModel.purchaseSheet, .confirm(snapshot))

        viewModel.updateTotalAmount(30)
        XCTAssertNil(viewModel.purchaseSheet)
        await assertCancelled(startPurchase(snapshot, on: viewModel), on: viewModel)
        assertNothingOrdered()
    }

    func testAMerchantWhoseRangeHasNoRoomBlocksThePurchase() async {
        for denominations in [["5", "0"], ["100", "5"], ["5", "-1"], ["5", "NaN"]] {
            let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
                currency: "USD", denominations: denominations))

            XCTAssertNil(viewModel.cardCurrency, "\(denominations)")
            XCTAssertThrowsError(try viewModel.beginPurchase(price: 25), "\(denominations)")
        }
        assertNothingOrdered()
    }

    // MARK: CTX, the price confirmed and the funds for it

    /// $25 at 3.75% off is $0.94 off as CTX rounds it. The buyer is shown $24.06, the price CTX
    /// charges, and that is the price the
    /// approval holds, the Dash is computed from and a higher quote is compared with.
    func testThePriceShownIsThePriceApprovedAndPaid() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD", savings: 375))
        let snapshot = try confirmation(of: 25, on: viewModel)

        XCTAssertEqual(snapshot.approval.fiatAmount, decimal("24.06"))
        XCTAssertEqual(snapshot.approval.amount, 60_150_000)

        payments.requestedByURL = 60_150_000
        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)
        XCTAssertEqual(payments.urlPayments.map(\.amount), [60_150_000])
    }

    /// 100 yen at 3.75% off is 4 yen off, shown as 96. A quote for 96 yen of Dash is the price
    /// shown, so the buyer is not asked about it again.
    func testAQuoteForThePriceShownInYenIsNotAskedAboutAgain() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
            currency: "JPY", denominations: ["100", "5000"], savings: 375))
        let snapshot = try confirmation(of: 100, on: viewModel)
        XCTAssertEqual(snapshot.approval.fiatAmount, 96)
        XCTAssertEqual(snapshot.approval.amount, 1_920_000)

        ctx.answeredCurrencies = (payment: "JPY", card: "JPY")
        payments.requestedByURL = 1_920_000
        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)
        XCTAssertEqual(payments.urlPayments.map(\.amount), [1_920_000])
    }

    /// A 100 pound card at 10% off costs 90 pounds: 1.8 Dash at 50 pounds per Dash, not the
    /// 2 Dash of its face value.
    func testTheFundsCheckIsForThePricePaidNotTheFaceValue() async {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "GBP", savings: 1000))

        viewModel.sendableDuffs = 190_000_000
        viewModel.input = "100"
        XCTAssertNil(viewModel.error)

        viewModel.sendableDuffs = 179_999_999
        viewModel.input = "100"
        XCTAssertEqual(viewModel.error as? SendAmountError, .insufficientFunds)

        viewModel.sendableDuffs = 180_000_000
        viewModel.input = "100"
        XCTAssertNil(viewModel.error)
    }

    /// While the first load runs there is no currency, so the price line, which would read
    /// "a 25 gift card for 25", stays hidden.
    func testThePriceLineIsHiddenUntilTheCurrencyIsConfirmed() async {
        let viewModel = ctxViewModel(live: Rates(Self.rates), withLocalLimits: true)
        XCTAssertEqual(viewModel.minimumAmount, 5)
        XCTAssertEqual(viewModel.maximumAmount, 500)
        viewModel.input = "25"
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.showCost)

        XCTAssertFalse(viewModel.canShowCost)

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "USD"))
        await viewModel.updateMerchantInfo()
        viewModel.sendableDuffs = .max
        viewModel.input = "25"
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.showCost)
        XCTAssertTrue(viewModel.canShowCost)
    }

    /// A merchant that could not be loaded is loaded again when the network is back.
    func testAMerchantThatCouldNotBeLoadedIsLoadedAgainWhenTheNetworkIsBack() async {
        let viewModel = ctxViewModel()
        await viewModel.updateMerchantInfo()
        XCTAssertTrue(viewModel.canRetryMerchantLoad)

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "USD"))
        viewModel.networkStatusDidChange?(.offline)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertNil(viewModel.cardCurrency)

        viewModel.networkStatusDidChange?(.online)
        for _ in 0..<1000 where viewModel.cardCurrency == nil { await Task.yield() }
        XCTAssertEqual(viewModel.cardCurrency, "USD")
        XCTAssertFalse(viewModel.canRetryMerchantLoad)
    }

    /// The network coming back while a load that began without it is still running starts a
    /// load of its own, which is the one that counts.
    func testTheNetworkComingBackDuringALoadLoadsTheMerchantAgain() async {
        let viewModel = ctxViewModel()
        ctx.holdsMerchantCalls = true

        let first = Task { await viewModel.updateMerchantInfo() }
        await waitForHeldMerchantCalls(1)
        viewModel.networkStatusDidChange?(.online)
        await waitForHeldMerchantCalls(2)
        guard ctx.heldMerchantCalls.count == 2 else { return XCTFail("no load followed the network coming back") }

        ctx.answerMerchantCall(0, with: StubCTXRepository.merchantJSON(currency: nil))
        await first.value
        ctx.answerMerchantCall(1, with: StubCTXRepository.merchantJSON(currency: "USD"))
        let deadline = Date().addingTimeInterval(Self.patience)
        while viewModel.cardCurrency == nil || viewModel.isLoading, Date() < deadline { await Task.yield() }
        XCTAssertEqual(viewModel.cardCurrency, "USD")
        XCTAssertFalse(viewModel.isLoading)

        viewModel.networkStatusDidChange?(.online)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(ctx.heldMerchantCalls.count, 2)
    }

    /// Just after launch the wallet has no rates yet: that is said as such, and goes when
    /// they arrive.
    func testRatesStillBeingFetchedAreNotCalledAMissingRate() async {
        let rates = Rates([:])
        rates.areFetching = true
        let viewModel = ctxViewModel(live: rates)
        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "USD"))
        await viewModel.updateMerchantInfo()

        viewModel.input = "25"
        XCTAssertEqual(viewModel.error as? GiftCardPurchaseBlock, .ratesFetching)
        XCTAssertEqual(viewModel.error?.localizedDescription, String(localized: "Fetching rates…", comment: "Balance"))

        rates.prices = Self.rates
        rates.areFetching = false
        viewModel.sendableDuffs = .max
        viewModel.exchangeRatesDidChange()
        XCTAssertNil(viewModel.error)
    }

    // MARK: PiggyCards, as before

    /// A PiggyCards cart keeps the figures it had before card currencies: 2.7% off
    /// $25 is $24.325, shown as the formatter rounds it, approved unrounded, and the funds
    /// check is for the $25 face value. The expected values are worked out here, not taken
    /// from the code under test.
    func testAPiggyCardsCartKeepsItsFiguresFromBeforeCardCurrencies() throws {
        let rate = GiftCardPaymentGuard.ExchangeRate(price: 40, retrievedAt: Int(Date().timeIntervalSince1970))
        let viewModel = OnlineDashSpendPayViewModel(
            merchant: merchant(piggyCardsSavings: 270), provider: .piggyCards,
            exchangeRate: { _ in rate },
            dependencies: .init(ctx: ctx, piggyCards: piggyCards, payments: payments, purchases: recorder))
        let unrounded = decimal("24.325")
        let shown = try XCTUnwrap(NumberFormatter.fiatFormatter(currencyCode: "USD").string(for: unrounded))

        viewModel.sendableDuffs = 62_500_000
        viewModel.input = "25"
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.costMessage.contains(shown), viewModel.costMessage)

        viewModel.sendableDuffs = 62_499_999
        viewModel.input = "25"
        XCTAssertEqual(viewModel.error as? SendAmountError, .insufficientFunds)

        viewModel.sendableDuffs = 62_500_000
        try viewModel.beginPurchase(price: 25)
        guard case .confirm(let snapshot)? = viewModel.purchaseSheet else { return XCTFail("the Confirm sheet did not open") }
        XCTAssertEqual(snapshot.approval.fiatAmount, unrounded)
        XCTAssertEqual(snapshot.approval.amount, 60_812_500)
    }

    // MARK: CTX, a change of the rate

    func testAFundsVerdictIsJudgedAgainWhenTheRateChanges() async {
        let rates = Rates(Self.rates)
        let viewModel = ctxViewModel(live: rates)
        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "GBP"))
        await viewModel.updateMerchantInfo()
        viewModel.sendableDuffs = 150_000_000
        viewModel.input = "100"
        XCTAssertEqual(viewModel.error as? SendAmountError, .insufficientFunds)

        rates.prices["GBP"] = 100
        viewModel.exchangeRatesDidChange()
        XCTAssertNil(viewModel.error)
    }

    func testARateThatGoesMissingBlocksAFormWithoutAnError() async {
        let rates = Rates(Self.rates)
        let viewModel = ctxViewModel(live: rates)
        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "GBP"))
        await viewModel.updateMerchantInfo()
        viewModel.sendableDuffs = .max
        viewModel.input = "100"
        XCTAssertNil(viewModel.error)

        rates.prices["GBP"] = nil
        viewModel.exchangeRatesDidChange()
        XCTAssertEqual(viewModel.error as? GiftCardPurchaseBlock, .rateMissing)

        rates.prices["GBP"] = 50
        viewModel.exchangeRatesDidChange()
        XCTAssertNil(viewModel.error)
    }

    func testARateChangeLeavesAnErrorItDoesNotOwn() async {
        let rates = Rates(Self.rates)
        let viewModel = ctxViewModel(live: rates)
        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "GBP"))
        await viewModel.updateMerchantInfo()
        viewModel.error = DashSpendError.networkError

        rates.prices["GBP"] = nil
        viewModel.exchangeRatesDidChange()
        guard case .networkError? = viewModel.error as? DashSpendError else {
            return XCTFail("the error was replaced: \(String(describing: viewModel.error))")
        }
    }

    // MARK: CTX, what the merchant sells

    /// A card chosen from the list on screen while the merchant loads is dropped when CTX
    /// no longer sells that value, and cannot be ordered.
    func testACardCTXNoLongerSellsIsDroppedAndCannotBeOrdered() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
            currency: "USD", type: "fixed", denominations: ["25", "50"]))
        let resets = viewModel.selectionResets
        viewModel.updateTotalAmount(25, quantities: [25: 1])
        let snapshot = try confirmation(of: 25, quantities: [25: 1], on: viewModel)

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(
            currency: "USD", type: "fixed", denominations: ["50", "100"]))
        await viewModel.updateMerchantInfo()

        XCTAssertEqual(viewModel.selectionResets, resets + 1)
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 25, quantities: [25: 1]))
        await assertCancelled(startPurchase(snapshot, on: viewModel), on: viewModel)
        assertNothingOrdered()
    }

    func testARefreshWithTheSameCardsKeepsTheSelection() async throws {
        let json = StubCTXRepository.merchantJSON(currency: "USD", type: "fixed", denominations: ["25", "50"])
        let viewModel = await ctxViewModel(loading: json)
        let resets = viewModel.selectionResets
        let snapshot = try confirmation(of: 25, quantities: [25: 1], on: viewModel)

        await viewModel.updateMerchantInfo()

        XCTAssertEqual(viewModel.selectionResets, resets)
        XCTAssertEqual(viewModel.purchaseSheet, .confirm(snapshot))
    }

    func testAnAmountOutsideTheConfirmedLimitsIsRefusedBeforeAnOrder() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD"))
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 4))
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 501))
        XCTAssertNoThrow(try viewModel.beginPurchase(price: 500))

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "USD", denominations: ["5", "100"]))
        await viewModel.updateMerchantInfo()
        XCTAssertNil(viewModel.purchaseSheet)
        assertNothingOrdered()
    }

    /// CTX's own JSON, through the response model: a list the model cannot read, a list that
    /// is missing and a list too short for its type all leave the merchant unusable, with
    /// Try Again, and never with limits or cards from before.
    func testDenominationsThatCannotBeReadOrAreIncompleteLeaveTheMerchantUnusable() async throws {
        let answers: [String] = [
            StubCTXRepository.merchantJSON(currency: "USD", denominations: [5, NSNull()]),
            StubCTXRepository.merchantJSON(currency: "USD", denominations: ["5", 500]),
            StubCTXRepository.merchantJSON(currency: "USD", denominations: []),
            StubCTXRepository.merchantJSON(currency: "USD", denominations: ["5"]),
            StubCTXRepository.merchantJSON(currency: "USD", type: "fixed", denominations: []),
            StubCTXRepository.merchantJSON(currency: "USD", type: "fixed", denominations: [NSNull()]),
            #"{"id": "merchant-1", "denominationsType": "min-max", "currency": "USD"}"#,
            StubCTXRepository.merchantJSON(currency: "USD", type: "something-new"),
        ]
        for answer in answers {
            let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "USD"))
            _ = try confirmation(of: 25, on: viewModel)

            ctx.merchantAnswer = .success(answer)
            await viewModel.updateMerchantInfo()

            XCTAssertNil(viewModel.cardCurrency, answer)
            XCTAssertTrue(viewModel.canRetryMerchantLoad, answer)
            XCTAssertEqual(viewModel.minimumAmount, 0, answer)
            XCTAssertEqual(viewModel.maximumAmount, 0, answer)
            XCTAssertEqual(viewModel.denominations, [], answer)
            XCTAssertNil(viewModel.purchaseSheet, answer)
            XCTAssertThrowsError(try viewModel.beginPurchase(price: 25), answer)
        }
        assertNothingOrdered()
    }

    /// `min-max-major` with the two values the server sends is a range of whole amounts,
    /// not a card of 1 and a card of 500: no decimals can be typed, a fractional amount is
    /// refused, and a whole one is ordered as "25.00".
    func testAMajorRangeMerchantIsARangeOfWholeAmounts() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(
            currency: "USD", type: "min-max-major", denominations: ["1", "500"]))

        XCTAssertFalse(viewModel.isFixedDenomination)
        XCTAssertEqual(viewModel.denominations, [])
        XCTAssertEqual(viewModel.minimumAmount, 1)
        XCTAssertEqual(viewModel.maximumAmount, 500)
        XCTAssertEqual(viewModel.amountFractionDigits, 0)
        viewModel.input = "25"
        viewModel.input = "25\(Locale.current.decimalSeparator ?? ".")5"
        XCTAssertEqual(viewModel.input, "25")
        XCTAssertThrowsError(try viewModel.beginPurchase(price: decimal("25.5")))
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 501))

        let snapshot = try confirmation(of: 25, on: viewModel)
        payments.requestedByURL = snapshot.approval.amount
        _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)
        XCTAssertEqual(ctx.orders.map(\.fiatAmount), ["25.00"])
        XCTAssertEqual(ctx.orders.map(\.fiatCurrency), ["USD"])
    }

    func testARefreshWithoutAnAnswerKeepsTheConfirmedCurrency() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "GBP"))
        let resets = viewModel.selectionResets
        let snapshot = try confirmation(of: 25, on: viewModel)

        ctx.merchantAnswer = .failure(DashSpendError.networkError)
        await viewModel.updateMerchantInfo()

        XCTAssertEqual(viewModel.cardCurrency, "GBP")
        XCTAssertFalse(viewModel.canRetryMerchantLoad)
        XCTAssertEqual(viewModel.minimumAmount, 5)
        XCTAssertEqual(viewModel.maximumAmount, 500)
        XCTAssertEqual(viewModel.selectionResets, resets)
        XCTAssertEqual(viewModel.purchaseSheet, .confirm(snapshot))
    }

    /// The confirmation showed pounds. Once CTX names euros it is closed, the selection is
    /// dropped, and the old confirmation cannot be used to order.
    func testARefreshAnsweredInAnotherCurrencyDropsTheSelectionAndTheConfirmation() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "GBP"))
        let resets = viewModel.selectionResets
        let snapshot = try confirmation(of: 25, on: viewModel)

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: "EUR", denominations: ["10", "100"]))
        await viewModel.updateMerchantInfo()

        XCTAssertEqual(viewModel.cardCurrency, "EUR")
        XCTAssertEqual(viewModel.minimumAmount, 10)
        XCTAssertEqual(viewModel.maximumAmount, 100)
        XCTAssertEqual(viewModel.selectionResets, resets + 1)
        XCTAssertEqual(viewModel.amount, 0)
        XCTAssertNil(viewModel.purchaseSheet)

        await assertCancelled(startPurchase(snapshot, on: viewModel), on: viewModel)
        assertNothingOrdered()
    }

    func testARefreshAnsweredWithoutACurrencyUnconfirmsIt() async throws {
        let viewModel = await ctxViewModel(loading: StubCTXRepository.merchantJSON(currency: "GBP"))
        let resets = viewModel.selectionResets
        _ = try confirmation(of: 25, on: viewModel)

        ctx.merchantAnswer = .success(StubCTXRepository.merchantJSON(currency: ""))
        await viewModel.updateMerchantInfo()

        XCTAssertNil(viewModel.cardCurrency)
        XCTAssertTrue(viewModel.canRetryMerchantLoad)
        XCTAssertEqual(viewModel.minimumAmount, 0)
        XCTAssertEqual(viewModel.maximumAmount, 0)
        XCTAssertEqual(viewModel.selectionResets, resets + 1)
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertThrowsError(try viewModel.beginPurchase(price: 25))
    }

    /// Two loads of the merchant overlap and the older one ends last. Its currency, its
    /// limits and its kind of merchant are all left out.
    func testAnOlderLoadThatEndsLastChangesNothing() async {
        let viewModel = ctxViewModel()
        ctx.holdsMerchantCalls = true

        let older = Task { await viewModel.updateMerchantInfo() }
        await waitForHeldMerchantCalls(1)
        let newer = Task { await viewModel.updateMerchantInfo() }
        await waitForHeldMerchantCalls(2)
        guard ctx.heldMerchantCalls.count == 2 else { return XCTFail("the two loads did not start") }

        ctx.answerMerchantCall(1, with: StubCTXRepository.merchantJSON(
            currency: "GBP", type: "fixed", denominations: ["20", "40"]))
        await newer.value
        ctx.answerMerchantCall(0, with: StubCTXRepository.merchantJSON(currency: "USD"))
        await older.value

        XCTAssertEqual(viewModel.cardCurrency, "GBP")
        XCTAssertTrue(viewModel.isFixedDenomination)
        XCTAssertEqual(viewModel.denominations, [20, 40])
        XCTAssertEqual(viewModel.minimumAmount, 0)
        XCTAssertEqual(viewModel.maximumAmount, 0)
    }

    /// The older of two overlapping loads ends first. The screen keeps loading for the newer.
    func testAnOlderLoadThatEndsFirstLeavesTheScreenLoading() async {
        let viewModel = ctxViewModel()
        ctx.holdsMerchantCalls = true

        let older = Task { await viewModel.updateMerchantInfo() }
        await waitForHeldMerchantCalls(1)
        let newer = Task { await viewModel.updateMerchantInfo() }
        await waitForHeldMerchantCalls(2)
        guard ctx.heldMerchantCalls.count == 2 else { return XCTFail("the two loads did not start") }

        ctx.answerMerchantCall(0, with: StubCTXRepository.merchantJSON(currency: "GBP"))
        await older.value
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.cardCurrency)
        XCTAssertEqual(viewModel.selectionResets, 0)

        ctx.answerMerchantCall(1, with: StubCTXRepository.merchantJSON(currency: "USD"))
        await newer.value
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.cardCurrency, "USD")
    }

    private func waitForHeldMerchantCalls(_ count: Int) async {
        let deadline = Date().addingTimeInterval(Self.patience)
        while ctx.heldMerchantCalls.count < count, Date() < deadline {
            await Task.yield()
        }
    }

    private func startPurchase(_ snapshot: GiftCardPurchaseSnapshot,
                               on viewModel: DashSpendPayViewModel) -> Task<Data, Error> {
        Task { try await viewModel.purchaseGiftCardAndPay(snapshot) }
    }

    /// Thrown by `finish` when the purchase has not ended in time.
    private struct StillWaiting: Error {}

    /// Waits for the purchase to end, for at most `patience`. One still waiting then fails
    /// the test; whatever it may wait for is declined, and this throws `StillWaiting`
    /// without waiting for the purchase again, so a regression fails here instead of
    /// hanging the suite.
    private func finish(_ purchase: Task<Data, Error>, on viewModel: DashSpendPayViewModel,
                        file: StaticString = #filePath, line: UInt = #line) async throws -> Data {
        let waiter = Waiter()
        return try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            let watchdog = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.patience * 1_000_000_000))
                guard !Task.isCancelled, waiter.continuation != nil else { return }
                XCTFail("the purchase is still waiting", file: file, line: line)
                viewModel.resolvePriceChange(pay: false)
                viewModel.purchaseSheetDidDismiss()
                waiter.resume(.failure(StillWaiting()))
            }
            Task { @MainActor in
                let result = await purchase.result
                watchdog.cancel()
                waiter.resume(result)
            }
        }
    }

    /// Holds the continuation `finish` waits on, so it is resumed once: by the purchase
    /// ending or by the timeout, whichever comes first.
    @MainActor
    private final class Waiter {
        var continuation: CheckedContinuation<Data, Error>?

        func resume(_ result: Result<Data, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    /// Returns the price change once the "Price updated" sheet is up, or nil, failing the
    /// test, when the sheet has not come up in time or the purchase ended without it.
    private func priceChange(on viewModel: DashSpendPayViewModel,
                             file: StaticString = #filePath, line: UInt = #line) async
        -> GiftCardPaymentGuard.PriceChange? {
        let deadline = Date().addingTimeInterval(Self.patience)
        while Date() < deadline {
            if case .priceUpdated(let change)? = viewModel.purchaseSheet { return change }
            if !viewModel.isProcessingPayment, viewModel.purchaseSheet == nil { break }
            await Task.yield()
        }
        XCTFail("the higher price was not put to the buyer", file: file, line: line)
        return nil
    }

    private func assertCancelled(_ purchase: Task<Data, Error>, on viewModel: DashSpendPayViewModel,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await finish(purchase, on: viewModel, file: file, line: line)
            XCTFail("the purchase went on", file: file, line: line)
        } catch DashSpendError.purchaseCancelled {
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }

    // MARK: CTX, the price

    func testCTXPurchaseAtTheConfirmedPriceIsPaidAndRecorded() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: .ctx)
        payments.requestedByURL = Self.confirmedDuffs

        let txid = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(txid, StubPayments.txidWire)
        XCTAssertEqual(ctx.orders.map(\.merchantId), ["merchant-1"])
        XCTAssertEqual(ctx.orders.map(\.fiatAmount), ["25.00"])
        XCTAssertEqual(payments.urlPayments.map(\.url), [StubCTXRepository.paymentURL])
        XCTAssertEqual(payments.urlPayments.map(\.amount), [Self.confirmedDuffs])
        // CTX fulfils the order from the payment it acknowledged; the verdict is not awaited.
        XCTAssertEqual(payments.urlPayments.map(\.awaitAcceptance), [false])
        XCTAssertTrue(payments.addressPayments.isEmpty)
        XCTAssertEqual(recorder.records, [GiftCardPurchaseRecord(
            txidWire: StubPayments.txidWire, provider: .ctx, merchantName: "Test Merchant", merchantUrl: nil,
            merchantIconUrl: "", price: 25, currency: "USD", note: StubCTXRepository.orderId)])
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertFalse(viewModel.isProcessingPayment)
    }

    /// Fails when the CTX path pays a payment request without comparing its amount.
    func testCTXHigherPriceIsPutToTheBuyerBeforeAnythingIsPaid() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: .ctx)
        payments.requestedByURL = Self.higherDuffs

        let purchase = startPurchase(snapshot, on: viewModel)
        let change = await priceChange(on: viewModel)

        XCTAssertEqual(change?.confirmedAmount, Self.confirmedDuffs)
        XCTAssertEqual(change?.requestedAmount, Self.higherDuffs)
        // Not asserted here that nothing is paid yet: the stub pays only once the check has
        // returned, so that would hold whatever the view model did.

        viewModel.resolvePriceChange(pay: false)
        await assertCancelled(purchase, on: viewModel)
        XCTAssertTrue(payments.isEmpty)
        XCTAssertTrue(recorder.records.isEmpty)
    }

    func testCTXHigherPriceTheBuyerAcceptsIsPaid() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: .ctx)
        payments.requestedByURL = Self.higherDuffs

        let purchase = startPurchase(snapshot, on: viewModel)
        guard await priceChange(on: viewModel) != nil else {
            _ = try? await finish(purchase, on: viewModel)
            return
        }
        viewModel.resolvePriceChange(pay: true)
        _ = try await finish(purchase, on: viewModel)

        XCTAssertEqual(payments.urlPayments.map(\.amount), [Self.higherDuffs])
        XCTAssertEqual(recorder.records.map(\.price), [25])
    }

    // MARK: The log of a higher price

    /// Runs a purchase whose provider asks more than the buyer confirmed, answers the
    /// "Price updated" sheet with `pay`, and returns every log message written meanwhile,
    /// through any logger that reaches the exported file.
    private func logOfHigherPrice(provider: GiftCardProvider, pay: Bool,
                                  file: StaticString = #filePath, line: UInt = #line) async throws -> [String] {
        let capture = CapturingLogger()
        DDLog.add(capture, with: .all)
        defer { DDLog.remove(capture) }

        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: provider)
        payments.requestedByURL = Self.higherDuffs
        piggyCards.quotedDash = try XCTUnwrap(Decimal(string: "0.6875"))
        let purchase = startPurchase(snapshot, on: viewModel)
        if await priceChange(on: viewModel, file: file, line: line) != nil {
            viewModel.resolvePriceChange(pay: pay)
        }
        _ = try? await finish(purchase, on: viewModel, file: file, line: line)
        DDLog.flushLog()
        return capture.texts
    }

    /// The price change is logged on both answers, its acceptance only when the buyer pays,
    /// and neither the confirmed nor the asked amount, nor the order note, is in any line.
    private func assertHigherPriceLog(provider: GiftCardProvider, pay: Bool,
                                      file: StaticString = #filePath, line: UInt = #line) async throws {
        let log = try await logOfHigherPrice(provider: provider, pay: pay, file: file, line: line)
        XCTAssertTrue(log.contains { $0.contains("Gift card price changed") }, "\(log)", file: file, line: line)
        XCTAssertEqual(log.contains { $0.contains("Gift card price change accepted") }, pay, "\(log)",
                       file: file, line: line)
        assertNoAmount(in: log, file: file, line: line)
    }

    /// No message holds the confirmed or the asked amount, in duffs or Dash, the card's $25 as
    /// the order sends it, or the order note's card amounts. An order id alone is an
    /// identifier the log may carry, like a txid. A bare "25" is not checked: the capture also
    /// holds the app's other lines, with durations and counts.
    private func assertNoAmount(in log: [String], file: StaticString = #filePath, line: UInt = #line) {
        let amounts = ["62500000", "62,500,000", "0.625", "68750000", "68,750,000", "0.6875",
                       "25.00", "$25", "cardAmounts"]
        for message in log where amounts.contains(where: { message.contains($0) }) {
            XCTFail("an amount in the log: \(message)", file: file, line: line)
        }
    }

    func testPurchaseAtTheConfirmedPriceIsLoggedWithoutAmounts() async throws {
        for provider in [GiftCardProvider.ctx, .piggyCards] {
            let capture = CapturingLogger()
            DDLog.add(capture, with: .all)
            defer { DDLog.remove(capture) }
            let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: provider)
            payments.requestedByURL = Self.confirmedDuffs
            piggyCards.quotedDash = try XCTUnwrap(Decimal(string: "0.625"))
            _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)
            DDLog.flushLog()
            assertNoAmount(in: capture.texts)
        }
    }

    /// The production recorder, on in-memory stores: the save is logged, its price and its
    /// note are not, for either provider's note.
    func testRecordedPurchaseIsLoggedWithoutItsPriceOrNote() async throws {
        let price = try XCTUnwrap(Decimal(string: "37.13"))
        let piggyNote = #"{"orderId":"piggy-order-7","cardAmounts":["37.13"]}"#
        for (provider, note) in [(GiftCardProvider.ctx, "ctx-order-7"), (.piggyCards, piggyNote)] {
            let giftCards = StubGiftCardsDAO()
            let store = GiftCardPurchaseStore(
                txMetadata: { StubTransactionMetadataDAO() }, icons: { StubIconUpdater() }, giftCards: { giftCards })
            let capture = CapturingLogger()
            DDLog.add(capture, with: .all)
            defer { DDLog.remove(capture) }

            store.record(GiftCardPurchaseRecord(
                txidWire: StubPayments.txidWire, provider: provider, merchantName: "Test Merchant", merchantUrl: nil,
                merchantIconUrl: "", price: price, currency: "USD", note: note))
            let deadline = Date().addingTimeInterval(Self.patience)
            while giftCards.created.isEmpty, Date() < deadline { await Task.yield() }
            DDLog.flushLog()

            XCTAssertEqual(giftCards.created.map(\.note), [note], "\(provider)")
            XCTAssertTrue(capture.texts.contains { $0.contains("Gift card saved") }, "\(provider): \(capture.texts)")
            for message in capture.texts
            where ["37.13", "ctx-order-7", "piggy-order-7", "cardAmounts"].contains(where: { message.contains($0) }) {
                XCTFail("\(provider): the price or the note in the log: \(message)")
            }
        }
    }

    func testCTXDeclinedHigherPriceIsLoggedWithoutAmounts() async throws {
        try await assertHigherPriceLog(provider: .ctx, pay: false)
    }

    func testCTXAcceptedHigherPriceIsLoggedWithoutAmounts() async throws {
        try await assertHigherPriceLog(provider: .ctx, pay: true)
    }

    func testPiggyCardsDeclinedHigherPriceIsLoggedWithoutAmounts() async throws {
        try await assertHigherPriceLog(provider: .piggyCards, pay: false)
    }

    func testPiggyCardsAcceptedHigherPriceIsLoggedWithoutAmounts() async throws {
        try await assertHigherPriceLog(provider: .piggyCards, pay: true)
    }

    // MARK: CTX, outcome unknown

    private static let unknownTxid = Data(repeating: 0xC3, count: 32)

    /// Runs a purchase at the confirmed price whose payment ends with `failure`, and returns
    /// the error the purchase ended with.
    private func purchase(provider: GiftCardProvider, endingWith failure: Error,
                          file: StaticString = #filePath, line: UInt = #line) async throws -> Error? {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: provider)
        payments.requestedByURL = Self.confirmedDuffs
        piggyCards.quotedDash = try XCTUnwrap(Decimal(string: "0.625"))
        payments.failure = failure

        var thrown: Error?
        do {
            _ = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel, file: file, line: line)
            XCTFail("the purchase reported a payment", file: file, line: line)
        } catch {
            thrown = error
        }
        XCTAssertNil(viewModel.purchaseSheet, file: file, line: line)
        XCTAssertFalse(viewModel.isProcessingPayment, file: file, line: line)
        return thrown
    }

    /// The payment left the device and its acceptance was not seen. The order is recorded
    /// against the transaction, and the error still says the outcome is unknown.
    func testCTXPaymentWithAnUnknownOutcomeIsRecorded() async throws {
        let thrown = try await purchase(
            provider: .ctx,
            endingWith: DashSpendError.paymentStatusUnknown(txIdWire: Self.unknownTxid, reason: "timeout"))

        guard case DashSpendError.paymentStatusUnknown(let txid, _)? = thrown else {
            return XCTFail("unexpected error: \(String(describing: thrown))")
        }
        XCTAssertEqual(txid, Self.unknownTxid)
        XCTAssertEqual(recorder.records, [GiftCardPurchaseRecord(
            txidWire: Self.unknownTxid, provider: .ctx, merchantName: "Test Merchant", merchantUrl: nil,
            merchantIconUrl: "", price: 25, currency: "USD", note: StubCTXRepository.orderId)])
    }

    /// The payment was posted to CTX and the connection was lost before its acknowledgement
    /// was read. CTX may be fulfilling the order, so it is recorded against the transaction.
    /// The error does not yet tell this apart from a post that never reached CTX (#1468).
    func testCTXUnacknowledgedPaymentIsRecorded() async throws {
        let thrown = try await purchase(
            provider: .ctx,
            endingWith: DashSpendError.paymentNotAcknowledged(
                txIdWire: Self.unknownTxid, reason: "the connection was lost after the request was sent"))

        guard case DashSpendError.paymentNotAcknowledged(let txid, _)? = thrown else {
            return XCTFail("unexpected error: \(String(describing: thrown))")
        }
        XCTAssertEqual(txid, Self.unknownTxid)
        XCTAssertEqual(recorder.records.map(\.txidWire), [Self.unknownTxid])
        XCTAssertEqual(recorder.records.map(\.note), [StubCTXRepository.orderId])
    }

    func testCTXPaymentThatFailedIsNotRecorded() async throws {
        let thrown = try await purchase(provider: .ctx, endingWith: DashSpendError.transactionRejected)

        guard case DashSpendError.transactionRejected? = thrown else {
            return XCTFail("unexpected error: \(String(describing: thrown))")
        }
        XCTAssertTrue(recorder.records.isEmpty)
    }

    // MARK: PiggyCards

    private func orderNote(_ note: String?) throws -> (orderId: String?, cardAmounts: [String]?) {
        let object = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(note).utf8)) as? [String: Any]
        return (object?["orderId"] as? String, object?["cardAmounts"] as? [String])
    }

    func testPiggyCardsPurchaseAtTheConfirmedPriceIsPaidAndRecorded() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: .piggyCards)
        piggyCards.quotedDash = try XCTUnwrap(Decimal(string: "0.625"))

        let txid = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(txid, StubPayments.txidWire)
        XCTAssertEqual(piggyCards.orders.count, 1)
        XCTAssertEqual(piggyCards.orders.first?.map(\.denomination), [25])
        XCTAssertEqual(piggyCards.orders.first?.map(\.quantity), [1])
        XCTAssertEqual(payments.addressPayments.map(\.address), [StubPiggyCardsRepository.paymentAddress])
        XCTAssertEqual(payments.addressPayments.map(\.amount), [Self.confirmedDuffs])
        XCTAssertTrue(payments.urlPayments.isEmpty)

        XCTAssertEqual(recorder.records.count, 1)
        let record = try XCTUnwrap(recorder.records.first)
        XCTAssertEqual(record.txidWire, StubPayments.txidWire)
        XCTAssertEqual(record.provider, .piggyCards)
        XCTAssertEqual(record.merchantName, "Test Merchant")
        XCTAssertEqual(record.price, 25)
        let note = try orderNote(record.note)
        XCTAssertEqual(note.orderId, StubPiggyCardsRepository.orderId)
        XCTAssertEqual(note.cardAmounts, ["25"])
        XCTAssertNil(viewModel.purchaseSheet)
        XCTAssertFalse(viewModel.isProcessingPayment)
    }

    /// Fails when the PiggyCards path pays an order without comparing its amount.
    func testPiggyCardsHigherPriceIsPutToTheBuyerBeforeAnythingIsPaid() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: .piggyCards)
        piggyCards.quotedDash = try XCTUnwrap(Decimal(string: "0.6875"))

        let purchase = startPurchase(snapshot, on: viewModel)
        let change = await priceChange(on: viewModel)

        XCTAssertEqual(change?.confirmedAmount, Self.confirmedDuffs)
        XCTAssertEqual(change?.requestedAmount, Self.higherDuffs)
        XCTAssertTrue(payments.isEmpty, "paid before the buyer answered")

        viewModel.resolvePriceChange(pay: false)
        await assertCancelled(purchase, on: viewModel)
        XCTAssertTrue(payments.isEmpty)
        XCTAssertTrue(recorder.records.isEmpty)
    }

    func testPiggyCardsHigherPriceTheBuyerAcceptsIsPaid() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: .piggyCards)
        piggyCards.quotedDash = try XCTUnwrap(Decimal(string: "0.6875"))

        let purchase = startPurchase(snapshot, on: viewModel)
        guard await priceChange(on: viewModel) != nil else {
            _ = try? await finish(purchase, on: viewModel)
            return
        }
        viewModel.resolvePriceChange(pay: true)
        _ = try await finish(purchase, on: viewModel)

        XCTAssertEqual(payments.addressPayments.map(\.amount), [Self.higherDuffs])
        XCTAssertEqual(recorder.records.map(\.price), [25])
    }

    /// The transaction was handed to the network and its acceptance was not seen. The order
    /// is recorded against it, so a payment that goes through does not leave the buyer with
    /// no card, and the error still says the outcome is unknown.
    func testPiggyCardsPaymentWithAnUnknownOutcomeIsRecorded() async throws {
        let thrown = try await purchase(
            provider: .piggyCards,
            endingWith: DashSpendError.paymentStatusUnknown(txIdWire: Self.unknownTxid, reason: "timeout"))

        guard case DashSpendError.paymentStatusUnknown(let txid, _)? = thrown else {
            return XCTFail("unexpected error: \(String(describing: thrown))")
        }
        XCTAssertEqual(txid, Self.unknownTxid)
        XCTAssertEqual(recorder.records.count, 1)
        let record = try XCTUnwrap(recorder.records.first)
        XCTAssertEqual(record.txidWire, Self.unknownTxid)
        XCTAssertEqual(record.provider, .piggyCards)
        XCTAssertEqual(record.price, 25)
        let note = try orderNote(record.note)
        XCTAssertEqual(note.orderId, StubPiggyCardsRepository.orderId)
        XCTAssertEqual(note.cardAmounts, ["25"])
    }

    /// A broadcast the network rejected: the error `WalletSendService` throws for it.
    private func rejectedSendError() throws -> NSError {
        let send = PreparedStandardSend(
            txData: Data([0x01]), txHash: Data(repeating: 0xe1, count: 32), fee: 226,
            address: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr", amount: 100_000,
            broadcastAction: { .rejected(txid: String(repeating: "e1", count: 32), reason: "not started") })
        var thrown: Error?
        XCTAssertThrowsError(try send.broadcast()) { thrown = $0 }
        return try XCTUnwrap(thrown) as NSError
    }

    func testPiggyCardsPaymentThatWasRejectedIsNotRecorded() async throws {
        let thrown = try await purchase(provider: .piggyCards, endingWith: try rejectedSendError())

        XCTAssertTrue(WalletSendService.isBroadcastRejectedError(try XCTUnwrap(thrown) as NSError))
        XCTAssertTrue(recorder.records.isEmpty)
    }

    // MARK: What the buyer is told

    /// PiggyCards does not hold the signed transaction: the wallet is the only one that can
    /// broadcast it, and only while the app is open. The buyer is told what every other send
    /// with an unknown outcome tells them, before the card details.
    func testPiggyCardsUnknownOutcomeCarriesTheDoNotSendAgainNotice() throws {
        let (viewModel, _) = try viewModelWithConfirmSheet(provider: .piggyCards)

        XCTAssertEqual(viewModel.unknownOutcomeNotice, WalletSendService.unknownBroadcastOutcomeNotice)
        XCTAssertFalse(WalletSendService.unknownBroadcastOutcomeNotice.isEmpty)
    }

    /// The notice is the description of the error a send with this outcome throws.
    func testTheNoticeIsTheCopyOfTheUnknownSendError() {
        let send = PreparedStandardSend(
            txData: Data([0x01]), txHash: Data(repeating: 0xe2, count: 32), fee: 226,
            address: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr", amount: 100_000,
            broadcastAction: { .unknown(txid: String(repeating: "e2", count: 32), reason: "timeout") })

        XCTAssertThrowsError(try send.broadcast()) {
            XCTAssertEqual(($0 as NSError).localizedDescription, WalletSendService.unknownBroadcastOutcomeNotice)
        }
    }

    func testCTXUnknownOutcomeGoesToTheCardWithoutANotice() throws {
        let (viewModel, _) = try viewModelWithConfirmSheet(provider: .ctx)

        XCTAssertNil(viewModel.unknownOutcomeNotice)
    }
}

// MARK: - The txid of a send whose outcome is unknown

/// `WalletSendService.send` reports an unknown broadcast outcome without a txid. The gift
/// card payment goes through the variant that carries it, and `SendCoinsService` turns that
/// into the gift card error a purchase is recorded from.
final class GiftCardUnknownOutcomeTests: XCTestCase {
    private func prepared(hashByte: UInt8,
                          action: @escaping () throws -> CoreTransactionBroadcastOutcome) -> PreparedStandardSend {
        PreparedStandardSend(
            txData: Data([0x01]), txHash: Data(repeating: hashByte, count: 32), fee: 226,
            address: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr", amount: 100_000, broadcastAction: action)
    }

    func testAcceptedBroadcastReturnsTheTxid() throws {
        let send = prepared(hashByte: 0xd1) { .accepted(txid: String(repeating: "d1", count: 32)) }

        XCTAssertEqual(try WalletSendService.broadcastCarryingUnknownOutcome(send), send.txidWire)
    }

    func testUnknownOutcomeCarriesTheTxidAndTheSendError() {
        let send = prepared(hashByte: 0xd2) {
            .unknown(txid: String(repeating: "d2", count: 32), reason: "no acceptance signal")
        }

        var thrown: Error?
        XCTAssertThrowsError(try WalletSendService.broadcastCarryingUnknownOutcome(send)) { thrown = $0 }
        guard let unknown = thrown as? WalletSendService.BroadcastOutcomeUnknown else {
            return XCTFail("unexpected error: \(String(describing: thrown))")
        }
        XCTAssertEqual(unknown.txidWire, send.txidWire)
        XCTAssertTrue(WalletSendService.isBroadcastUnknownError(unknown.underlying))

        // The error `send` rethrows is the one the prepared send keeps for this outcome.
        var kept: Error?
        XCTAssertThrowsError(try send.broadcast()) { kept = $0 }
        XCTAssertEqual(kept as NSError?, unknown.underlying)
    }

    func testRejectedBroadcastIsThrownAsBefore() {
        let send = prepared(hashByte: 0xd3) {
            .rejected(txid: String(repeating: "d3", count: 32), reason: "not started")
        }

        XCTAssertThrowsError(try WalletSendService.broadcastCarryingUnknownOutcome(send)) { error in
            XCTAssertFalse(error is WalletSendService.BroadcastOutcomeUnknown)
            XCTAssertTrue(WalletSendService.isBroadcastRejectedError(error as NSError))
        }
    }

    /// The gift card payment itself: an unknown outcome of the send it goes through comes
    /// out as the gift card error a purchase is recorded from.
    func testGiftCardPaymentReportsAnUnknownOutcomeWithTheTxid() async {
        let send = prepared(hashByte: 0xd5) {
            .unknown(txid: String(repeating: "d5", count: 32), reason: "no acceptance signal")
        }
        var paid: [(address: String, amount: UInt64, sessionAuthSufficient: Bool)] = []
        let service = SendCoinsService(sendToAddress: { address, amount, sessionAuthSufficient in
            paid.append((address, amount, sessionAuthSufficient))
            return try WalletSendService.broadcastCarryingUnknownOutcome(send)
        })

        do {
            _ = try await service.payGiftCardOrder(address: "yTestPaymentAddress", amount: 100_000)
            XCTFail("the payment reported an accepted broadcast")
        } catch DashSpendError.paymentStatusUnknown(let txid, let reason) {
            XCTAssertEqual(txid, send.txidWire)
            XCTAssertEqual(reason, "no acceptance signal")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(paid.map(\.address), ["yTestPaymentAddress"])
        XCTAssertEqual(paid.map(\.amount), [100_000])
    }

    /// An unlocked app is not enough to pay for a gift card: the send is asked to prompt.
    func testGiftCardPaymentAsksForThePIN() async throws {
        let send = prepared(hashByte: 0xd7) { .accepted(txid: String(repeating: "d7", count: 32)) }
        var sessionAuthSufficient: [Bool] = []
        let service = SendCoinsService(sendToAddress: { _, _, flag in
            sessionAuthSufficient.append(flag)
            return try WalletSendService.broadcastCarryingUnknownOutcome(send)
        })

        let txid = try await service.payGiftCardOrder(address: "yTestPaymentAddress", amount: 100_000)

        XCTAssertEqual(txid, send.txidWire)
        XCTAssertEqual(sessionAuthSufficient, [false])
    }

    func testGiftCardPaymentThrowsARejectedSendAsItIs() async {
        let send = prepared(hashByte: 0xd6) {
            .rejected(txid: String(repeating: "d6", count: 32), reason: "not started")
        }
        let service = SendCoinsService(sendToAddress: { _, _, _ in
            try WalletSendService.broadcastCarryingUnknownOutcome(send)
        })

        do {
            _ = try await service.payGiftCardOrder(address: "yTestPaymentAddress", amount: 100_000)
            XCTFail("the payment reported an accepted broadcast")
        } catch {
            XCTAssertTrue(WalletSendService.isBroadcastRejectedError(error as NSError), "\(error)")
        }
    }

    func testUnknownOutcomeBecomesTheGiftCardErrorWithTheTxidAndTheDiagnostic() {
        let send = prepared(hashByte: 0xd4) {
            .unknown(txid: String(repeating: "d4", count: 32), reason: "no acceptance signal")
        }

        XCTAssertThrowsError(try WalletSendService.broadcastCarryingUnknownOutcome(send)) { error in
            guard let unknown = error as? WalletSendService.BroadcastOutcomeUnknown,
                  case .paymentStatusUnknown(let txid, let reason) = SendCoinsService.paymentStatusUnknown(from: unknown)
            else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(txid, send.txidWire)
            XCTAssertEqual(reason, "no acceptance signal")
        }
    }
}
