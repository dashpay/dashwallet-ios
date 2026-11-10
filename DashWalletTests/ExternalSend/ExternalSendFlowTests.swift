//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

@testable import dashpay
import XCTest

/// The coordinator behind every external-send entry point (AC-14, AC-15, AC-20): which screen each entry point opens
/// first, how the screens hand over to one another, and where each outcome leads. The flow, the ViewModels, the
/// parser, the pair policy and the outcome router are the real ones; only the edges are fakes (executor, fee
/// estimator, balances, identity lookup, payment-request fetch, clipboard). The UIKit host and the call sites in
/// PaymentsLanding, MainTabbarController and the ObjC scanner are not covered here.
/// TODO(maestro-flows): cover the UIKit host and those call sites with Maestro UI flows.
@MainActor
final class ExternalSendFlowTests: XCTestCase {
    private typealias Network = WalletEnvironment.NetworkKind

    private let network: Network = .testnet
    private let oneDash: UInt64 = 100_000_000
    private let requestURL = URL(string: "https://merchant.example/pay/abc") ?? URL(fileURLWithPath: "/")

    // MARK: - Fixtures

    private static let hash20 = Data((1 ... 20).map { UInt8($0) })
    private static let p2pkhScript = Data([0x76, 0xa9, 0x14] + hash20 + [0x88, 0xac])

    private var coreAddress: String {
        ScriptAddressCodec.address(forScript: Self.p2pkhScript, network: .testnet) ?? ""
    }

    private var mainnetCoreAddress: String {
        ScriptAddressCodec.address(forScript: Self.p2pkhScript, network: .mainnet) ?? ""
    }

    private var identityID: String {
        ScriptAddressCodec.base58Encode(Data((1 ... 32).map { UInt8($0 * 3) })) ?? ""
    }

    private let alice = "alice"

    private var foundRecipient: IdentityRecipient {
        IdentityRecipient(id: identityID, username: alice, isOwnCurrentIdentity: false)
    }

    private func coreDestination(amountDuffs: UInt64? = nil, requestURL: URL? = nil) -> Destination {
        Destination(type: .coreAddress, text: coreAddress, amountDuffs: amountDuffs, paymentRequestURL: requestURL)
    }

    private var paymentRequestDestination: Destination {
        Destination(type: .paymentRequest, text: "", paymentRequestURL: requestURL)
    }

    private struct Harness {
        let flow: ExternalSendFlow
        let executor: FakeExecutor
        let estimator: FakeEstimator
        let lookup: FakeLookup
        let fetcher: FakePaymentRequests
        let clipboard: FakeClipboard
        let balances: FakeBalances
        let finishes: FinishLog
    }

    private final class FinishLog {
        var all: [ExternalSendFlow.Finish] = []
    }

    private func makeHarness(
        balances: [SendSource: UInt64]? = nil, fetchResult: Result<PaymentRequestDetails, Error>? = nil,
        executor customExecutor: ExternalSendExecuting? = nil
    ) -> Harness {
        let table = balances ?? [.core: 5 * oneDash, .shielded: 3 * oneDash, .platform: 2 * oneDash]
        let fakeBalances = FakeBalances(values: table)
        let executor = FakeExecutor()
        let estimator = FakeEstimator()
        let lookup = FakeLookup()
        let fetcher = FakePaymentRequests()
        let clipboard = FakeClipboard()
        if let fetchResult { fetcher.result = fetchResult }
        let flow = ExternalSendFlow(
            network: network, identityLookup: lookup, executor: customExecutor ?? executor, balances: fakeBalances,
            feeEstimator: estimator, maxPlanner: FakeMaxPlanner(), converter: FakeConverter(),
            currentIdentity: FakeCurrentIdentity(), paymentRequests: fetcher, clipboard: clipboard)
        let log = FinishLog()
        flow.onFinish = { log.all.append($0) }
        return Harness(flow: flow, executor: executor, estimator: estimator, lookup: lookup, fetcher: fetcher,
                       clipboard: clipboard, balances: fakeBalances, finishes: log)
    }

    private func details(amount: UInt64? = nil, isSecure: Bool = false) -> PaymentRequestDetails {
        PaymentRequestDetails(address: coreAddress, amountDuffs: amount ?? oneDash * 3 / 2,
                              merchantName: "Merchant", memo: "Order 7", isSecure: isSecure)
    }

    /// Opens Send for a Core address and enters `amount` duffs, so Continue is enabled.
    private func openSend(_ harness: Harness, pinned: SendSource? = nil,
                          amount: String = "1") async throws -> SendAmountViewModel {
        if let pinned { harness.flow.start(pinned: pinned) } else { harness.flow.start() }
        harness.flow.addressViewModel?.setText(coreAddress)
        await harness.flow.addressViewModel?.continueTapped()
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()
        await send.setAmountText(amount)
        return send
    }

    private func openConfirm(_ harness: Harness, pinned: SendSource? = nil) async throws -> ConfirmViewModel {
        let send = try await openSend(harness, pinned: pinned)
        send.proceed()
        return try XCTUnwrap(harness.flow.confirmViewModel)
    }

    private func confirmThroughTheFlow(_ harness: Harness) async throws -> ConfirmViewModel? {
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()
        send.proceed()
        return harness.flow.confirmViewModel
    }

    private func eventually(_ condition: @autoclosure () -> Bool, _ message: String = "condition not met",
                            file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail(message, file: file, line: line)
    }

    // MARK: - Entry points: first screen

    func testStartOpensTheAddressScreenWithNothingPinned() {
        let harness = makeHarness()

        harness.flow.start()

        XCTAssertEqual(harness.flow.step, .address)
        XCTAssertNotNil(harness.flow.addressViewModel)
        XCTAssertNil(harness.flow.sendViewModel)
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    func testStartNeverReadsTheClipboard() async throws {
        let harness = makeHarness()

        _ = try await openSend(harness)

        XCTAssertEqual(harness.clipboard.readCount, 0, "the clipboard is read only on the Show clipboard tap")
    }

    func testStartPinnedOpensAddressAndCarriesThePinIntoSend() async throws {
        let harness = makeHarness()

        let send = try await openSend(harness, pinned: .platform)

        XCTAssertEqual(send.source, .platform)
        XCTAssertNil(send.sourceChangedNotice)
        XCTAssertEqual(harness.flow.step, .send)
    }

    func testStartPinnedShowsAddressFirst() {
        let harness = makeHarness()

        harness.flow.start(pinned: .shielded)

        XCTAssertEqual(harness.flow.step, .address)
        XCTAssertNil(harness.flow.sendViewModel)
    }

    func testPinnedSourceThatCannotPayIsReplacedWithTheStartingSourceAndANote() async throws {
        let harness = makeHarness(fetchResult: .success(details()))

        harness.flow.start(pinned: .platform)
        await harness.flow.start(destination: paymentRequestDestination)
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertEqual(send.source, .core, "a payment request is payable from Core only")
        XCTAssertNotNil(send.sourceChangedNotice)
    }

    func testStartWithAScannedCoreDestinationOpensSendDirectly() async throws {
        let harness = makeHarness()

        await harness.flow.start(destination: coreDestination())

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertNotNil(harness.flow.sendViewModel)
        XCTAssertEqual(harness.fetcher.fetched, [])
    }

    func testStartWithAnIdentityIDOpensAddressCheckingBeforeSend() async throws {
        let harness = makeHarness()
        harness.lookup.suspends = true
        let destination = Destination(type: .identityID, text: identityID)

        let opening = Task { await harness.flow.start(destination: destination) }
        await eventually(harness.flow.addressViewModel?.state == .checking, "Address never reached checking")

        XCTAssertEqual(harness.flow.step, .address)
        XCTAssertNil(harness.flow.sendViewModel)

        harness.lookup.resume(.found(foundRecipient))
        await opening.value
        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertEqual(harness.flow.sendViewModel?.recipientName, alice)
    }

    func testAnIdentityIDThatIsNotFoundStaysOnAddress() async throws {
        let harness = makeHarness()
        harness.lookup.results = [.notFound]

        await harness.flow.start(destination: Destination(type: .identityID, text: identityID))

        XCTAssertEqual(harness.flow.step, .address)
        XCTAssertEqual(harness.flow.addressViewModel?.state, .notFound)
        XCTAssertNil(harness.flow.sendViewModel)
    }

    // MARK: - Scan and dash: link (AC-02, AC-15)

    func testAScannedTextThatIsNotValidHereNeverOpensTheFlow() async {
        let harness = makeHarness()

        let accepted = await harness.flow.start(scanned: "not an address")

        XCTAssertFalse(accepted, "the scanner stays open to scan again")
        XCTAssertNil(harness.flow.step)
        XCTAssertNil(harness.flow.sendViewModel)
    }

    /// The host checks a scan or link before it is presented, so an invalid one never shows an empty Address that
    /// a dismiss during the presentation would leave behind; the check is the same acceptance handleScanned uses.
    func testTheScanCheckBeforePresentingAcceptsWhatHandleScannedAccepts() {
        let harness = makeHarness()

        XCTAssertNil(harness.flow.scannedDestination("not an address"))
        XCTAssertNil(harness.flow.scannedDestination(mainnetCoreAddress))
        XCTAssertNil(harness.flow.scannedDestination("ftp://merchant.example/pay/1"))
        XCTAssertEqual(harness.flow.scannedDestination(coreAddress)?.type, .coreAddress)
        XCTAssertEqual(harness.flow.scannedDestination("dash:\(coreAddress)?amount=1")?.amountDuffs, oneDash)
        let request = harness.flow.scannedDestination(requestURL.absoluteString)
        XCTAssertEqual(request?.type, .paymentRequest)
        XCTAssertEqual(request?.paymentRequestURL, requestURL)
        XCTAssertNil(harness.flow.step, "checking opens nothing")
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    func testAScannedAddressOfAnotherNetworkNeverOpensSend() async {
        let harness = makeHarness()

        let accepted = await harness.flow.start(scanned: mainnetCoreAddress)
        let linkAccepted = await harness.flow.start(scanned: "dash:\(mainnetCoreAddress)?amount=1")

        XCTAssertFalse(accepted)
        XCTAssertFalse(linkAccepted)
        XCTAssertNil(harness.flow.step)
        XCTAssertNil(harness.flow.sendViewModel)
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    func testAScannedCoreAddressOpensSend() async {
        let harness = makeHarness()

        let accepted = await harness.flow.start(scanned: coreAddress)

        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.flow.step, .send)
    }

    func testAScannedDashLinkFillsInTheAddressAndItsAmount() async throws {
        let harness = makeHarness()

        let accepted = await harness.flow.start(scanned: "dash:\(coreAddress)?amount=1.5")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertEqual(send.amountDuffs, oneDash * 3 / 2)
        XCTAssertFalse(send.isAmountLocked, "a plain link's amount can be edited")
    }

    func testAScannedIdentityIDGoesThroughAddressChecking() async {
        let harness = makeHarness()
        harness.lookup.results = [.found(foundRecipient)]

        let accepted = await harness.flow.start(scanned: identityID)

        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.lookup.lookedUp, [identityID])
        XCTAssertEqual(harness.flow.step, .send)
    }

    // MARK: - Payment request (the existing BIP70 fetch)

    func testAPaymentRequestIsFetchedAndSendOpensLockedToTheFetchedAmount() async throws {
        let harness = makeHarness(fetchResult: .success(details()))

        let accepted = await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.fetcher.fetched, [requestURL])
        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertTrue(send.isAmountLocked)
        XCTAssertEqual(send.amountDuffs, oneDash * 3 / 2)
        XCTAssertEqual(send.source, .core)
        XCTAssertEqual(send.shortAddress, SendAmountViewModel.shortAddress(of: coreDestination()))
    }

    /// The old Send showed the merchant with 🔒 when the request's signature verified, and the memo (AC-15).
    func testAVerifiedPaymentRequestShowsTheMerchantWithTheLockAndTheMemo() async throws {
        let harness = makeHarness(fetchResult: .success(details(isSecure: true)))
        _ = await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertEqual(send.destinationLabel, "🔒 Merchant")
        XCTAssertEqual(send.destinationNote, "Order 7")
    }

    func testAnUnverifiedPaymentRequestShowsTheMerchantWithoutTheLock() async throws {
        let harness = makeHarness(fetchResult: .success(details(isSecure: false)))
        _ = await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertEqual(send.destinationLabel, "Merchant")
    }

    func testALinksLabelAndMessageAreShownOnSend() async throws {
        let harness = makeHarness()
        _ = await harness.flow.start(scanned: "dash:\(coreAddress)?amount=1&label=Coffee%20Shop&message=Table%204")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertEqual(send.destinationLabel, "Coffee Shop")
        XCTAssertEqual(send.destinationNote, "Table 4")
    }

    /// An unsigned link cannot pass itself off as a verified merchant: its label and message are sanitized the way
    /// the old Send does, so a leading 🔒 shows as its name and only a verified request gets the lock.
    func testALinksLabelStartingWithTheLockIsSanitizedAndNeverLooksVerified() async throws {
        let harness = makeHarness()
        _ = await harness.flow.start(
            scanned: "dash:\(coreAddress)?amount=1&label=%F0%9F%94%92%20Amazon&message=%F0%9F%94%92%20Paid")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertEqual(send.destinationLabel, "\\N{LOCK} Amazon")
        XCTAssertEqual(send.destinationNote, "\\N{LOCK} Paid")
    }

    // MARK: - One scan acceptance

    func testTheAddressScannerAcceptsABIP73PaymentRequestURL() async throws {
        let harness = makeHarness(fetchResult: .success(details()))
        harness.flow.start()

        let accepted = await harness.flow.handleScanned(requestURL.absoluteString)

        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.fetcher.fetched, [requestURL])
        XCTAssertEqual(harness.flow.step, .send)
    }

    func testTheAddressScannerAcceptsADashwalletPayLink() async throws {
        let harness = makeHarness()
        harness.flow.start()

        let accepted = await harness.flow.handleScanned("dashwallet://pay=\(coreAddress)&amount=1&sender=shop.app")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertTrue(accepted)
        XCTAssertEqual(send.shortAddress, SendAmountViewModel.shortAddress(of: coreDestination()))
        XCTAssertEqual(send.amountDuffs, oneDash)
    }

    func testARequestTheScannerAlreadyFetchedIsNotFetchedAgain() async throws {
        let harness = makeHarness()

        let accepted = await harness.flow.handleScanned(
            "dash:?r=\(requestURL.absoluteString)", prefetched: details(isSecure: true))
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertTrue(accepted)
        XCTAssertTrue(harness.fetcher.fetched.isEmpty)
        XCTAssertTrue(send.isAmountLocked)
        XCTAssertEqual(send.amountDuffs, oneDash * 3 / 2)
        XCTAssertEqual(send.destinationLabel, "🔒 Merchant")
    }

    func testAddressShowsCheckingWhileARequestIsFetchedAndASecondScanStartsNothing() async throws {
        let harness = makeHarness(fetchResult: .success(details()))
        harness.fetcher.holds = true
        harness.flow.start()

        let first = Task { await harness.flow.handleScanned("dash:?r=\(requestURL.absoluteString)") }
        for _ in 0 ..< 200 where !harness.fetcher.isHolding { await Task.yield() }
        XCTAssertTrue(harness.fetcher.isHolding)
        XCTAssertEqual(harness.flow.addressViewModel?.state, .checking)

        let second = await harness.flow.handleScanned("dash:?r=\(requestURL.absoluteString)")
        XCTAssertTrue(second, "ignored, not refused: no invalid-address alert for it")
        XCTAssertEqual(harness.fetcher.fetched.count, 1, "a scan while one is starting starts nothing")

        harness.fetcher.release()
        let accepted = await first.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.fetcher.fetched, [requestURL], "fetched once")
        XCTAssertEqual(harness.flow.step, .send)
    }

    /// BIP73: the current scanner fetches a payment-request URL scanned whole; only the scan path accepts it.
    func testAScannedBarePaymentRequestURLIsFetchedLikeADashLink() async throws {
        let harness = makeHarness(fetchResult: .success(details()))

        let accepted = await harness.flow.start(scanned: " \(requestURL.absoluteString)\n")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.fetcher.fetched, [requestURL])
        XCTAssertTrue(send.isAmountLocked)
        XCTAssertEqual(send.amountDuffs, oneDash * 3 / 2)
    }

    func testAScannedURLThatIsNotHTTPIsRejected() async {
        let harness = makeHarness(fetchResult: .success(details()))

        let accepted = await harness.flow.start(scanned: "ftp://merchant.example/pr")

        XCTAssertFalse(accepted)
        XCTAssertTrue(harness.fetcher.fetched.isEmpty)
        XCTAssertNil(harness.flow.sendViewModel)
    }

    func testACoreLinkWithARequestURLIsFetchedToo() async throws {
        let harness = makeHarness(fetchResult: .success(details(amount: 2 * oneDash)))

        await harness.flow.start(destination: coreDestination(amountDuffs: oneDash, requestURL: requestURL))
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertEqual(harness.fetcher.fetched, [requestURL])
        XCTAssertTrue(send.isAmountLocked)
        XCTAssertEqual(send.amountDuffs, 2 * oneDash, "the merchant's amount wins over the link's")
    }

    func testAFailedFetchWithoutAFallbackAddressShowsTheErrorAndNeverOpensSend() async {
        let harness = makeHarness(fetchResult: .failure(FakeFetchError(message: "Request expired")))

        await harness.flow.start(destination: paymentRequestDestination)

        XCTAssertNil(harness.flow.sendViewModel)
        XCTAssertNotEqual(harness.flow.step, .send)
        XCTAssertEqual(harness.finishes.all,
                       [.requestFailed(title: "Couldn't make payment", message: "Request expired")])
    }

    func testAFailedFetchWithAValidFallbackAddressSendsToThatAddressUnlocked() async throws {
        let harness = makeHarness(fetchResult: .failure(FakeFetchError(message: "Request expired")))

        await harness.flow.start(destination: coreDestination(amountDuffs: oneDash, requestURL: requestURL))
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertFalse(send.isAmountLocked, "the request URL is dropped, as in the current Send")
        XCTAssertEqual(send.amountDuffs, oneDash)
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    // MARK: - Address to Send

    func testAResolvedAddressOpensSendWithTheIdentityRecipient() async throws {
        let harness = makeHarness()
        harness.lookup.results = [.found(foundRecipient)]

        harness.flow.start()
        harness.flow.addressViewModel?.setText(identityID)
        await harness.flow.addressViewModel?.continueTapped()

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertEqual(harness.flow.sendViewModel?.recipientName, alice)
        XCTAssertNotNil(harness.flow.sendViewModel?.recipientNotice)
    }

    func testAnInvalidAddressNeverOpensSend() async {
        let harness = makeHarness()

        harness.flow.start()
        harness.flow.addressViewModel?.setText("garbage")
        await harness.flow.addressViewModel?.continueTapped()

        XCTAssertEqual(harness.flow.step, .address)
        XCTAssertNil(harness.flow.sendViewModel)
    }

    // MARK: - Send to Confirm and back

    func testSendContinueOpensConfirmForTheEnteredRequest() async throws {
        let harness = makeHarness()

        let confirm = try await openConfirm(harness)

        XCTAssertEqual(harness.flow.step, .confirm)
        XCTAssertEqual(confirm.fromText, "Core")
        XCTAssertEqual(confirm.amountDuffs, Int64(oneDash))
    }

    func testCancellingConfirmReturnsToSendKeepingTheAmount() async throws {
        let harness = makeHarness()
        let send = try await openSend(harness)
        send.proceed()

        harness.flow.confirmViewModel?.cancel()

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertIdentical(harness.flow.sendViewModel, send)
        XCTAssertEqual(send.amountDuffs, oneDash)
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    func testAuthenticationNotCompletedReturnsToSendWithoutAnError() async throws {
        let harness = makeHarness()
        harness.executor.prepareResults = [.failure(.authenticationCancelled)]
        let send = try await openSend(harness)
        send.proceed()

        await harness.flow.confirmViewModel?.start()

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertEqual(send.amountDuffs, oneDash)
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    func testBalanceNoLongerCoveringTheFeeReturnsToSendAndEstimatesAgain() async throws {
        let harness = makeHarness()
        harness.executor.prepareResults = [.failure(.balanceNotEnough)]
        let send = try await openSend(harness)
        send.proceed()
        let estimatesBefore = harness.estimator.calls

        await harness.flow.confirmViewModel?.start()

        XCTAssertEqual(harness.flow.step, .send)
        await eventually(harness.estimator.calls > estimatesBefore, "Send did not call confirmReportedNotEnough")
    }

    // MARK: - Outcomes (ADR-0040)

    func testSentCoreToCoreFinishesWithTheTransactionScreenAndItsTxid() async throws {
        let harness = makeHarness()
        let display = Data((0 ..< 32).map { UInt8($0) })
        harness.executor.coreTxHash = display
        let confirm = try await openConfirm(harness)
        await confirm.start()

        await confirm.confirm()

        XCTAssertEqual(harness.finishes.all,
                       [.success(.transactionDetails, txidWire: Data(display.reversed()), callbackURL: nil)])
    }

    func testSentOnAnotherRouteFinishesWithTheSentSheetAndNoTxid() async throws {
        let harness = makeHarness()
        let confirm = try await openConfirm(harness, pinned: .shielded)
        await confirm.start()

        await confirm.confirm()

        XCTAssertEqual(harness.finishes.all, [.success(.sentSheet, txidWire: nil, callbackURL: nil)])
    }

    func testInFlightShowsTheToastAndClosesTheFlow() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .inFlight
        let confirm = try await openConfirm(harness)
        await confirm.start()

        await confirm.confirm()

        XCTAssertEqual(harness.finishes.all, [.toast(
            title: "Send in progress",
            message: "It will finish on its own. You don't need to send it again.")])
    }

    func testNotSentOpensSendFailedWithTheReason() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .notSent(.offline)
        let confirm = try await openConfirm(harness)
        await confirm.start()

        await confirm.confirm()

        guard case .sendFailed(let content) = harness.flow.step else {
            return XCTFail("expected sendFailed, got \(String(describing: harness.flow.step))")
        }
        XCTAssertEqual(content.reason, NotSentReason.offline.localizedMessage)
        XCTAssertEqual(content.info, "Nothing was sent. Your money is still in your Core balance.")
        XCTAssertTrue(harness.finishes.all.isEmpty, "the flow stays open for Retry or Close")
    }

    func testRetryOnSendFailedReturnsToTheSameSendWithTheSameRequest() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .notSent(.rejected)
        let send = try await openSend(harness)
        send.proceed()
        await harness.flow.confirmViewModel?.start()
        await harness.flow.confirmViewModel?.confirm()

        harness.flow.retryFromSendFailed()

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertIdentical(harness.flow.sendViewModel, send)
        XCTAssertEqual(send.amountDuffs, oneDash)
        XCTAssertEqual(send.source, .core)
        XCTAssertTrue(send.isContinueEnabled, "Continue authenticates again")
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    func testCloseOnSendFailedClosesTheFlow() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .notSent(.failed)
        let confirm = try await openConfirm(harness)
        await confirm.start()
        await confirm.confirm()

        harness.flow.closeFromSendFailed()

        XCTAssertEqual(harness.finishes.all, [.closed])
    }

    // MARK: - Payment request callback (the link's sender=)

    func testAScannedLinksSenderReachesNeitherTheFetchNorTheDestination() async throws {
        let harness = makeHarness(fetchResult: .success(details()))

        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)&sender=merchantapp")

        XCTAssertEqual(harness.fetcher.callbackSchemes, [nil])
        let confirmed = try await confirmThroughTheFlow(harness)
        let confirm = try XCTUnwrap(confirmed)
        await confirm.start()
        XCTAssertNil(harness.executor.preparedDestinations.last?.callbackScheme)
    }

    func testTheCallbackSchemeOfALinkAnotherAppOpenedReachesTheFetchAndTheDestination() async throws {
        let harness = makeHarness(fetchResult: .success(details()))

        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)&sender=merchantapp", openedByApp: true)

        XCTAssertEqual(harness.fetcher.callbackSchemes, ["merchantapp"])
        let confirmed = try await confirmThroughTheFlow(harness)
        let confirm = try XCTUnwrap(confirmed)
        await confirm.start()
        XCTAssertEqual(harness.executor.preparedDestinations.last?.callbackScheme, "merchantapp")
    }

    func testASuccessfulPaymentRequestSendFinishesWithTheMerchantCallbackURL() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let callback = URL(fileURLWithPath: "/callback/paid")
        paymentRequests.callbackURL = callback
        let executor = ExternalSendExecutor(
            paymentRequestSend: paymentRequests,
            balances: FakeBalances(values: [.core: 5 * oneDash]), logOutcome: { _ in })
        let harness = makeHarness(fetchResult: .success(details()), executor: executor)

        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)&sender=merchantapp", openedByApp: true)
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()
        send.proceed()
        let confirm = try XCTUnwrap(harness.flow.confirmViewModel)
        await confirm.start()
        await confirm.confirm()

        XCTAssertEqual(paymentRequests.callbackSchemes, ["merchantapp"], "the scheme reaches the executor's seam")
        XCTAssertEqual(paymentRequests.sentCount, 1)
        XCTAssertEqual(harness.finishes.all, [.success(
            .transactionDetails, txidWire: Data(repeating: 0xb2, count: 32), callbackURL: callback)])
    }

    func testAPlainSendHasNoCallbackURL() async throws {
        let harness = makeHarness()
        let confirm = try await openConfirm(harness)
        await confirm.start()

        await confirm.confirm()

        guard case .success(_, _, let callback)? = harness.finishes.all.first else {
            return XCTFail("expected success, got \(harness.finishes.all)")
        }
        XCTAssertNil(callback)
    }

    // MARK: - Select source

    func testPickingASourceInSelectSourceChangesTheSourceOnSend() async throws {
        let harness = makeHarness()
        let send = try await openSend(harness)
        XCTAssertEqual(send.source, .core)

        await harness.flow.showSelectSource()
        let select = try XCTUnwrap(harness.flow.selectSourceViewModel)
        XCTAssertEqual(harness.flow.step, .selectSource)
        select.select(.platform)

        await eventually(send.source == .platform, "the pick never reached Send")
        XCTAssertEqual(harness.flow.step, .send)
    }

    /// The sheet shows at once with its loading state and loads its rows once per From tap.
    func testSelectSourceIsShownAtOnceAndLoadsOncePerTap() async throws {
        let harness = makeHarness()
        _ = try await openSend(harness)
        harness.balances.holds = true
        let before = harness.balances.reads

        let showing = Task { await harness.flow.showSelectSource() }
        for _ in 0 ..< 200 where !harness.balances.isHolding { await Task.yield() }
        XCTAssertTrue(harness.balances.isHolding)
        XCTAssertEqual(harness.flow.step, .selectSource, "shown before its rows are read")
        XCTAssertEqual(harness.flow.selectSourceViewModel?.isLoading, true)

        harness.balances.release()
        await showing.value
        XCTAssertEqual(harness.flow.selectSourceViewModel?.isLoading, false)
        XCTAssertEqual(harness.flow.selectSourceViewModel?.rows.count, 3)
        XCTAssertEqual(harness.balances.reads - before, 3, "one read per row: one load")
    }

    func testSelectSourceOffersNothingTheDestinationCannotUse() async throws {
        let harness = makeHarness(fetchResult: .success(details()))
        harness.flow.start()
        await harness.flow.start(destination: paymentRequestDestination)
        _ = try XCTUnwrap(harness.flow.sendViewModel)

        await harness.flow.showSelectSource()

        let rows = try XCTUnwrap(harness.flow.selectSourceViewModel?.rows)
        XCTAssertEqual(rows.filter(\.isSelectable).map(\.source), [.core])
    }

    /// Address is a step of the Payments sheet: back returns to the Send menu, not out of Payments (SCR-02).
    func testBackFromAddressReturnsToTheSendMenu() {
        let harness = makeHarness()
        harness.flow.start()

        harness.flow.backFromAddress()

        XCTAssertEqual(harness.finishes.all, [.backToMenu])
    }

    func testBackFromSendStillReturnsToAddress() async throws {
        let harness = makeHarness()
        _ = try await openSend(harness)

        harness.flow.backFromSend()

        XCTAssertEqual(harness.flow.step, .address)
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    func testClosingTheFlowFromAddressFinishesWithClosed() {
        let harness = makeHarness()
        harness.flow.start()

        harness.flow.close()

        XCTAssertEqual(harness.finishes.all, [.closed])
    }
}

// MARK: - Fakes

private struct FakeFetchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private final class FakePaymentRequests: PaymentRequestFetching {
    var result: Result<PaymentRequestDetails, Error> = .failure(FakeFetchError(message: "no request queued"))
    /// When set, a fetch suspends until `release`, so what shows during it can be observed.
    var holds = false
    private(set) var fetched: [URL] = []
    private(set) var callbackSchemes: [String?] = []
    private var held: CheckedContinuation<Void, Never>?

    var isHolding: Bool { held != nil }

    func fetch(url: URL, callbackScheme: String?) async throws -> PaymentRequestDetails {
        fetched.append(url)
        callbackSchemes.append(callbackScheme)
        if holds { await withCheckedContinuation { held = $0 } }
        return try result.get()
    }

    func release() {
        held?.resume()
        held = nil
    }
}

private final class FakeClipboard: ClipboardReading {
    private(set) var readCount = 0

    func readString() -> String? {
        readCount += 1
        return nil
    }
}

private final class FakeLookup: IdentityLooking {
    var results: [IdentityLookupResult] = []
    var suspends = false
    private(set) var lookedUp: [String] = []
    private var pending: CheckedContinuation<IdentityLookupResult, Never>?

    func lookup(id: String, network: WalletEnvironment.NetworkKind) async -> IdentityLookupResult {
        lookedUp.append(id)
        if suspends { return await withCheckedContinuation { pending = $0 } }
        return results.isEmpty ? .couldNotCheck : results.removeFirst()
    }

    func resume(_ result: IdentityLookupResult) {
        pending?.resume(returning: result)
        pending = nil
    }
}

private final class FakeBalances: ExternalSendBalanceReading {
    let values: [SendSource: UInt64]
    /// When set, the next read suspends until `release`.
    var holds = false
    private(set) var reads = 0
    private var held: CheckedContinuation<Void, Never>?

    init(values: [SendSource: UInt64]) {
        self.values = values
    }

    var isHolding: Bool { held != nil }

    func spendableBalance(of source: SendSource) async -> UInt64? {
        reads += 1
        if holds {
            holds = false
            await withCheckedContinuation { held = $0 }
        }
        return values[source]
    }

    func release() {
        held?.resume()
        held = nil
    }
}

private struct FakeCurrentIdentity: CurrentIdentityReading {
    func currentIdentity() async -> SelectSourceIdentity? { nil }
}

@MainActor
private final class FakeEstimator: SendFeeEstimating {
    private(set) var calls = 0

    func estimate(route: SendRoute, amount: UInt64) async -> SendFeeEstimate {
        calls += 1
        return .fee(1_000)
    }
}

private struct FakeMaxPlanner: SendMaxPlanning {
    func maxDuffs(route: SendRoute) async -> UInt64? { nil }
}

private struct FakeConverter: SendAmountConverting {
    func fiat(forDuffs duffs: UInt64) -> Decimal? { nil }
    func duffs(forFiat fiat: Decimal) -> UInt64? { nil }
    func fiatText(forDuffs duffs: UInt64) -> String? { nil }
}

/// The executor at its protocol. A Core to Core prepare carries a standard plan with `coreTxHash`, as the live one
/// does, so the flow can read the txid the success screen needs.
@MainActor
private final class FakeExecutor: ExternalSendExecuting {
    var prepareResults: [Result<UInt64, ExternalSendError>] = []
    var sendOutcome: SendOutcome = .sent
    var coreTxHash = Data(repeating: 7, count: 32)
    private(set) var preparedDestinations: [Destination] = []

    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool
    ) async throws -> PreparedExternalSend {
        preparedDestinations.append(destination)
        let fee: UInt64
        if prepareResults.isEmpty {
            fee = 226
        } else {
            switch prepareResults.removeFirst() {
            case .success(let value): fee = value
            case .failure(let error): throw error
            }
        }
        guard route == .coreToCore else {
            return PreparedExternalSend(
                route: route, amount: amount, fee: fee, isMax: isMax, plan: .routed(destination: destination))
        }
        let standard = PreparedStandardSend(
            txData: Data([0x01]), txHash: coreTxHash, fee: fee, address: destination.text, amount: amount,
            ensureOnlineAction: {}, broadcastAction: { .accepted(txid: "") })
        return PreparedExternalSend(route: route, amount: amount, fee: fee, isMax: isMax, plan: .standard(standard))
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome { sendOutcome }

    func discard(_ prepared: PreparedExternalSend) {}
}

/// The BIP70 send edge of the real executor: records the scheme it is given and, once sent, hands back the
/// merchant's callback URL.
@MainActor
private final class FakePaymentRequestSend: CorePaymentRequestSending {
    var callbackURL: URL?
    private(set) var callbackSchemes: [String?] = []
    private(set) var sentCount = 0

    func preparePaymentRequestSend(
        requestURL: URL, callbackScheme: String?, amount: UInt64
    ) async throws -> PreparedPaymentRequestSend {
        callbackSchemes.append(callbackScheme)
        let txidDisplay = Data(repeating: 0xb2, count: 32)
        return PreparedPaymentRequestSend(
            txidWire: Data(txidDisplay.reversed()), fee: 226,
            sendAction: { [unowned self] in
                sentCount += 1
                return SendResult(
                    txidHexDisplay: String(repeating: "b2", count: 32), txHashDisplay: txidDisplay, fee: 226,
                    amount: amount, primaryAddress: nil, ackMemo: nil, callbackURL: callbackURL)
            })
    }
}
