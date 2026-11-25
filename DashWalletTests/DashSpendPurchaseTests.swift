//
//  DashSpendPurchaseTests.swift
//  DashWalletTests
//
//  A gift card purchase run end to end in `DashSpendPayViewModel`, for each provider, with
//  the provider's order response and the send service stubbed. These tests pin that the Dash
//  amount a provider asks for is compared with the price the buyer confirmed before anything
//  is paid: they fail when that comparison is left out of either provider's path.
//
//  The PiggyCards tests are not wrapped in `PIGGYCARDS_ENABLED`: the test target does not
//  define it, and the `dashpay` host app these tests import is built with it in every
//  configuration.
//

import Combine
import XCTest
@testable import dashpay

// MARK: - Stubs

@MainActor
private final class StubCTXRepository: CTXGiftCardOrdering {
    var isUserSignedIn = true
    var isUserSignedInPublisher: AnyPublisher<Bool, Never> { Just(isUserSignedIn).eraseToAnyPublisher() }

    static let orderId = "ctx-order-1"
    static let paymentURL = "dash:?r=https://provider.invalid/pay/ctx-order-1"

    private(set) var orders: [(merchantId: String, fiatAmount: String)] = []

    func getMerchant(merchantId: String) async throws -> MerchantResponse {
        throw DashSpendError.networkError
    }

    func purchaseGiftCard(merchantId: String, fiatAmount: String, fiatCurrency: String,
                          cryptoCurrency: String) async throws -> GiftCardResponse {
        orders.append((merchantId, fiatAmount))
        let json = """
        {"id": "\(Self.orderId)", "status": "unpaid", "paymentId": "payment-1",
         "paymentUrls": {"DASH.DASH": "\(Self.paymentURL)"}}
        """
        return try JSONDecoder().decode(GiftCardResponse.self, from: Data(json.utf8))
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
    private(set) var urlPayments: [(url: String, amount: UInt64)] = []
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
        urlPayments.append((paymentUrlString, amount))
        return Self.txidWire
    }

    func sendCoins(address: String, amount: UInt64, sessionAuthSufficient: Bool) async throws -> Data {
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

    private var merchant: ExplorePointOfUse {
        ExplorePointOfUse(
            id: 0, name: "Test Merchant",
            category: .merchant(ExplorePointOfUse.Merchant(
                merchantId: "merchant-1", paymentMethod: .giftCard, type: .online, deeplink: nil,
                savingsBasisPoints: 0, denominationsType: "range", denominations: [], redeemType: "online",
                giftCardProviders: [
                    .init(providerId: "ctx", savingsPercentage: 0, denominationsType: "range", sourceId: nil),
                    .init(providerId: "piggycards", savingsPercentage: 0, denominationsType: "range", sourceId: "1"),
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
            merchant: merchant, provider: provider, exchangeRate: { rate }, dependencies: dependencies)
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

    // MARK: CTX

    func testCTXPurchaseAtTheConfirmedPriceIsPaidAndRecorded() async throws {
        let (viewModel, snapshot) = try viewModelWithConfirmSheet(provider: .ctx)
        payments.requestedByURL = Self.confirmedDuffs

        let txid = try await finish(startPurchase(snapshot, on: viewModel), on: viewModel)

        XCTAssertEqual(txid, StubPayments.txidWire)
        XCTAssertEqual(ctx.orders.map(\.merchantId), ["merchant-1"])
        XCTAssertEqual(ctx.orders.map(\.fiatAmount), ["25.00"])
        XCTAssertEqual(payments.urlPayments.map(\.url), [StubCTXRepository.paymentURL])
        XCTAssertEqual(payments.urlPayments.map(\.amount), [Self.confirmedDuffs])
        XCTAssertTrue(payments.addressPayments.isEmpty)
        XCTAssertEqual(recorder.records, [GiftCardPurchaseRecord(
            txidWire: StubPayments.txidWire, provider: .ctx, merchantName: "Test Merchant", merchantUrl: nil,
            merchantIconUrl: "", price: 25, note: StubCTXRepository.orderId)])
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
        XCTAssertTrue(payments.isEmpty, "paid before the buyer answered")

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
}
