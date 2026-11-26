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
                merchantIconUrl: "", price: price, note: note))
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
            merchantIconUrl: "", price: 25, note: StubCTXRepository.orderId)])
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
