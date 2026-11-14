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

import Combine
@testable import dashpay
import SwiftDashSDK
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

    // DIP-0018 bech32m Platform (0xb0 + 20-byte hash) and Shielded (0x10 + 43 Orchard bytes), as in
    // DestinationParserTests.
    private var platformAddress: String {
        Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: false), data: Data([0xb0] + Array(repeating: 0x02, count: 20)))
            ?? ""
    }

    private var shieldedAddress: String {
        Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: false), data: Data([0x10] + Array(repeating: 0x07, count: 43)))
            ?? ""
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
        let identity: FakeCurrentIdentity
        let restoreSync: RestoreSyncState
        let finishes: FinishLog
    }

    /// What the restored wallet's initial-sync gate answers when read.
    private final class RestoreSyncState {
        var isRunning = false
    }

    private final class FinishLog {
        var all: [ExternalSendFlow.Finish] = []
    }

    private func makeHarness(
        balances: [SendSource: UInt64]? = nil, fetchResult: Result<PaymentRequestDetails, Error>? = nil,
        executor customExecutor: ExternalSendExecuting? = nil, lockResumer: HeldAssetLockResuming? = nil
    ) -> Harness {
        let table = balances ?? [.core: 5 * oneDash, .shielded: 3 * oneDash, .platform: 2 * oneDash]
        let fakeBalances = FakeBalances(values: table)
        let executor = FakeExecutor()
        let estimator = FakeEstimator()
        let lookup = FakeLookup()
        let fetcher = FakePaymentRequests()
        let clipboard = FakeClipboard()
        let identity = FakeCurrentIdentity()
        let restoreSync = RestoreSyncState()
        if let fetchResult { fetcher.result = fetchResult }
        let flow = ExternalSendFlow(
            network: network, identityLookup: lookup, executor: customExecutor ?? executor, balances: fakeBalances,
            feeEstimator: estimator, maxPlanner: FakeMaxPlanner(), converter: FakeConverter(),
            currentIdentity: identity, paymentRequests: fetcher, clipboard: clipboard,
            initialRestoreSync: Just(false).eraseToAnyPublisher(),
            initialRestoreSyncNow: { restoreSync.isRunning }, lockResumer: lockResumer ?? FakeLockResumer())
        let log = FinishLog()
        flow.onFinish = { log.all.append($0) }
        return Harness(flow: flow, executor: executor, estimator: estimator, lookup: lookup, fetcher: fetcher,
                       clipboard: clipboard, balances: fakeBalances, identity: identity, restoreSync: restoreSync,
                       finishes: log)
    }

    private func details(amount: UInt64? = nil, isSecure: Bool = false) -> PaymentRequestDetails {
        PaymentRequestDetails(address: coreAddress, confirmation: .fixture(
            address: coreAddress, amount: amount ?? oneDash * 3 / 2, isSecure: isSecure))
    }

    /// The real executor over a fake BIP70 send seam.
    private func executor(paymentRequestSend: FakePaymentRequestSend) -> ExternalSendExecutor {
        ExternalSendExecutor(
            paymentRequestSend: paymentRequestSend,
            balances: FakeBalances(values: [.core: 5 * oneDash]), logOutcome: { _ in })
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
        await send.proceed()
        return try XCTUnwrap(harness.flow.confirmViewModel)
    }

    private func confirmThroughTheFlow(_ harness: Harness) async throws -> ConfirmViewModel? {
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()
        await send.proceed()
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

    // dashpay/dashwallet-ios#1383: a payment request made by Receive on Platform, Shielded or Identity opens Send
    // with its recipient and its amount, scanned or opened by another app alike.

    func testAPlatformOrShieldedLinkOpensSendWithItsAmount() async throws {
        for (address, typeText) in [(platformAddress, "Platform address"), (shieldedAddress, "Shielded address")] {
            for openedByApp in [false, true] {
                let harness = makeHarness()

                let accepted = await harness.flow.start(scanned: "dash:\(address)?amount=1.5", openedByApp: openedByApp)
                let send = try XCTUnwrap(harness.flow.sendViewModel, typeText)
                await send.load()

                XCTAssertTrue(accepted)
                XCTAssertEqual(harness.flow.step, .send)
                XCTAssertEqual(send.destinationTypeText, typeText)
                XCTAssertEqual(send.amountDuffs, oneDash * 3 / 2, "\(typeText), opened by app: \(openedByApp)")
                XCTAssertFalse(send.isAmountLocked)
            }
        }
    }

    func testAnIdentityLinkIsCheckedAndOpensSendWithItsRecipientAndAmount() async throws {
        for openedByApp in [false, true] {
            let harness = makeHarness()
            harness.lookup.results = [.found(foundRecipient)]

            let accepted = await harness.flow.start(scanned: "dash:\(identityID)?amount=0.1", openedByApp: openedByApp)
            let send = try XCTUnwrap(harness.flow.sendViewModel)
            await send.load()

            XCTAssertTrue(accepted)
            XCTAssertEqual(harness.lookup.lookedUp, [identityID], "the recipient is checked as a typed Identity ID is")
            XCTAssertEqual(harness.flow.step, .send)
            XCTAssertEqual(send.destinationTypeText, "Identity")
            XCTAssertEqual(send.recipientName, alice)
            XCTAssertEqual(send.amountDuffs, oneDash / 10, "opened by app: \(openedByApp)")
        }
    }

    func testAnIdentityLinkWithoutAnAmountOpensSendWithNoAmount() async throws {
        let harness = makeHarness()
        harness.lookup.results = [.found(foundRecipient)]

        let accepted = await harness.flow.start(scanned: "dash:\(identityID)")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertTrue(accepted)
        XCTAssertEqual(harness.lookup.lookedUp, [identityID])
        XCTAssertEqual(send.amountDuffs, 0)
    }

    func testAnIdentityLinkTheHostChecksBeforePresentingIsAccepted() {
        let harness = makeHarness()

        let destination = harness.flow.scannedDestination("dash:\(identityID)?amount=0.1", openedByApp: true)

        XCTAssertEqual(destination?.type, .identityID)
        XCTAssertEqual(destination?.amountDuffs, oneDash / 10)
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

    /// The scanner's own fetch failed and it cleared the request: the flow opens the code's Core address with its
    /// amount, label and message, and does not fetch the request again.
    func testACodeWhoseRequestTheScannerClearedOpensItsCoreAddressWithoutFetching() async throws {
        let harness = makeHarness(fetchResult: .success(details()))
        let link = "dash:\(coreAddress)?amount=1&label=Coffee%20Shop&message=Table%204&r=\(requestURL.absoluteString)"

        let accepted = await harness.flow.start(scanned: link, requestCleared: true)
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()

        XCTAssertTrue(accepted)
        XCTAssertTrue(harness.fetcher.fetched.isEmpty, "the request is not fetched again")
        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertEqual(send.amountDuffs, oneDash)
        XCTAssertFalse(send.isAmountLocked)
        XCTAssertEqual(send.source, .core)
        XCTAssertEqual(send.destinationLabel, "Coffee Shop")
        XCTAssertEqual(send.destinationNote, "Table 4")
    }

    func testACodeWithOnlyARequestIsNotValidOnceTheRequestIsCleared() async {
        let harness = makeHarness(fetchResult: .success(details()))
        let link = "dash:?r=\(requestURL.absoluteString)"
        XCTAssertNil(harness.flow.scannedDestination(link, requestCleared: true))
        XCTAssertNotNil(harness.flow.scannedDestination(link))
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

    /// The request URL is dropped, the sender of a link another app opened is not: the standard send of the link's
    /// own address finishes with the payack callback.
    func testAFailedFetchOfALinkAnotherAppOpenedFinishesTheFallbackSendWithThePayAck() async throws {
        let standardSend = FakeStandardSend()
        let harness = makeHarness(
            fetchResult: .failure(FakeFetchError(message: "Request expired")),
            executor: ExternalSendExecutor(
                standardSend: standardSend, balances: FakeBalances(values: [.core: 5 * oneDash]), logOutcome: { _ in }))

        await harness.flow.start(
            scanned: "dash:\(coreAddress)?amount=1&r=\(requestURL.absoluteString)&sender=merchantapp",
            openedByApp: true)
        let confirmed = try await confirmThroughTheFlow(harness)
        let confirm = try XCTUnwrap(confirmed)
        await confirm.confirm()

        XCTAssertEqual(standardSend.broadcasts, 1)
        XCTAssertEqual(harness.finishes.all, [.success(
            .transactionDetails, txidWire: Data(repeating: 0xe9, count: 32),
            callbackURL: URL(string: "merchantapp://callback=payack&address=\(coreAddress)&txid="
                + String(repeating: "e9", count: 32)))])
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
        XCTAssertNil(harness.flow.sendViewModel?.recipientNotice, "someone else's identity has no notice")
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
        XCTAssertEqual(confirm.state, .ready, "Confirm opens with the send already prepared")
        XCTAssertEqual(confirm.fromText, "Core")
        XCTAssertEqual(confirm.amountDuffs, Int64(oneDash))
    }

    /// The PIN prompt and the Confirm sheet must never be presented at once: Continue authenticates and prepares
    /// while Send is on screen with Continue busy, and Confirm opens only afterwards.
    func testContinuePreparesWhileSendIsShownAndOpensConfirmWhenPrepared() async throws {
        let harness = makeHarness()
        let send = try await openSend(harness)
        var stepAtPrepare: ExternalSendFlow.Step?
        var continueBusyAtPrepare = false
        var continueEnabledAtPrepare = true
        harness.executor.onPrepare = { [unowned flow = harness.flow] in
            stepAtPrepare = flow.step
            continueBusyAtPrepare = send.isContinueLoading
            continueEnabledAtPrepare = send.isContinueEnabled
        }

        await send.proceed()

        XCTAssertEqual(stepAtPrepare, .send, "the send is prepared before Confirm opens")
        XCTAssertTrue(continueBusyAtPrepare, "Continue shows busy while it prepares")
        XCTAssertFalse(continueEnabledAtPrepare, "a second tap meanwhile starts nothing")
        XCTAssertEqual(harness.flow.step, .confirm)
        let confirm = try XCTUnwrap(harness.flow.confirmViewModel)
        XCTAssertEqual(confirm.state, .ready)
        XCTAssertEqual(confirm.feeText, (226 as UInt64).formattedDashAmount)
        XCTAssertFalse(send.isContinueLoading)
    }

    func testCancelledAuthenticationAtContinueNeverOpensConfirm() async throws {
        let harness = makeHarness()
        harness.executor.prepareResults = [.failure(.authenticationCancelled)]
        let send = try await openSend(harness)
        var steps: [ExternalSendFlow.Step?] = []
        let watch = harness.flow.$step.sink { steps.append($0) }
        defer { watch.cancel() }

        await send.proceed()

        XCTAssertEqual(harness.executor.preparedDestinations.count, 1, "Continue tried to prepare")
        XCTAssertFalse(steps.contains(.confirm), "Confirm never opened: \(steps)")
        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertNil(harness.flow.confirmViewModel)
        XCTAssertFalse(send.isContinueLoading)
        XCTAssertTrue(send.isContinueEnabled, "Continue can be tapped again")
    }

    func testCancellingConfirmReturnsToSendKeepingTheAmount() async throws {
        let harness = makeHarness()
        let send = try await openSend(harness)
        await send.proceed()

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

        await send.proceed()

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertEqual(send.amountDuffs, oneDash)
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    /// The executor refuses a Core-funded send during the restore sync even when Send has not yet seen the sync state
    /// change; back on Send, the holder sees the gate and Continue is off.
    func testARestoreSyncRefusalAtContinueShowsTheGateOnSend() async throws {
        let harness = makeHarness()
        harness.executor.prepareResults = [.failure(.initialRestoreSync)]
        let send = try await openSend(harness)
        XCTAssertTrue(send.isContinueEnabled)
        harness.restoreSync.isRunning = true

        await send.proceed()

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertNil(harness.flow.confirmViewModel)
        XCTAssertTrue(send.isBlockedBySync)
        XCTAssertFalse(send.isContinueEnabled)
    }

    /// Try again inside Confirm would authenticate over the open sheet, so a prepare that cannot read the fee or the
    /// balance stays on Send, which shows its own could-not-calculate message and Try again.
    func testAFeeFailureAtContinueStaysOnSendWithItsRetry() async throws {
        for failure in [ExternalSendError.feeUnavailable, .balanceUnavailable] {
            let harness = makeHarness()
            harness.executor.prepareResults = [.failure(failure)]
            let send = try await openSend(harness)
            var steps: [ExternalSendFlow.Step?] = []
            let watch = harness.flow.$step.sink { steps.append($0) }

            await send.proceed()
            watch.cancel()

            XCTAssertFalse(steps.contains(.confirm), "\(failure): Confirm never opened: \(steps)")
            XCTAssertEqual(harness.flow.step, .send, "\(failure)")
            XCTAssertNil(harness.flow.confirmViewModel, "\(failure)")
            XCTAssertEqual(send.state, .feeFailed, "\(failure)")
            XCTAssertEqual(send.feeFailureMessage, SendAmountViewModel.feeFailureText, "\(failure)")
            XCTAssertFalse(send.isContinueLoading, "\(failure)")

            await send.retryFee()

            XCTAssertEqual(send.state, .ready, "\(failure): Try again on Send estimates anew")
        }
    }

    // MARK: - Leaving Send while the send is prepared

    private final class RequestLog {
        var last: SendAmountRequest?
    }

    /// A Continue whose prepare is held: `proceeding` returns once the prepare does.
    private struct HeldContinue {
        let harness: Harness
        let send: SendAmountViewModel
        let proceeding: Task<Void, Never>
    }

    /// Opens Send for a payment request whose send is built by the real executor over `paymentRequests`, and starts
    /// Continue with the next prepare held. `requests` records what Continue hands to the flow.
    private func continueWithAHeldPaymentRequest(
        _ paymentRequests: FakePaymentRequestSend, requests: RequestLog = RequestLog()
    ) async throws -> HeldContinue {
        let harness = makeHarness(fetchResult: .success(details()),
                                  executor: executor(paymentRequestSend: paymentRequests))
        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()
        let toFlow = send.onContinue
        send.onContinue = { request in
            requests.last = request
            await toFlow?(request)
        }
        paymentRequests.holdsNextPrepare = true
        let proceeding = Task { await send.proceed() }
        await eventually(paymentRequests.isHoldingPrepare, "the prepare never started")
        return HeldContinue(harness: harness, send: send, proceeding: proceeding)
    }

    /// A send prepared after the holder opened Select source is discarded, which gives the request's single-use claim
    /// back, and never opens Confirm; the same request can then be prepared again.
    func testAPreparationFinishingAfterSelectSourceOpenedIsDiscardedAndNeverOpensConfirm() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let held = try await continueWithAHeldPaymentRequest(paymentRequests)
        let (harness, send, proceeding) = (held.harness, held.send, held.proceeding)

        await harness.flow.showSelectSource()
        paymentRequests.resumePrepare()
        await proceeding.value

        XCTAssertEqual(harness.flow.step, .selectSource, "the flow stays where the holder went")
        XCTAssertNil(harness.flow.confirmViewModel)
        XCTAssertEqual(paymentRequests.releases, 1, "the prepared send is discarded once")

        harness.flow.closeSelectSource()
        await send.proceed()

        XCTAssertEqual(harness.flow.step, .confirm, "the request can be prepared again")
        XCTAssertEqual(harness.flow.confirmViewModel?.state, .ready)
        XCTAssertEqual(paymentRequests.prepared.count, 2)
        XCTAssertEqual(paymentRequests.releases, 1)
    }

    /// Picking a source returns to the same Send, so the flow tells a send prepared before the pick by its own
    /// record, not by the screen.
    func testAPreparationFinishingAfterASourcePickIsDiscarded() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let held = try await continueWithAHeldPaymentRequest(paymentRequests)
        let (harness, proceeding) = (held.harness, held.proceeding)

        await harness.flow.showSelectSource()
        harness.flow.closeSelectSource()
        paymentRequests.resumePrepare()
        await proceeding.value

        XCTAssertEqual(harness.flow.step, .send)
        XCTAssertNil(harness.flow.confirmViewModel, "Confirm never opens for a send prepared before the change")
        XCTAssertEqual(paymentRequests.releases, 1)
    }

    func testAPreparationFinishingAfterBackFromSendIsDiscarded() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let held = try await continueWithAHeldPaymentRequest(paymentRequests)
        let (harness, proceeding) = (held.harness, held.proceeding)

        harness.flow.backFromSend()
        paymentRequests.resumePrepare()
        await proceeding.value

        XCTAssertEqual(harness.flow.step, .address)
        XCTAssertNil(harness.flow.confirmViewModel)
        XCTAssertEqual(paymentRequests.releases, 1)
    }

    func testAPreparationFailingAfterBackFromSendShowsNothing() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let held = try await continueWithAHeldPaymentRequest(paymentRequests)
        let (harness, proceeding) = (held.harness, held.proceeding)
        var steps: [ExternalSendFlow.Step?] = []
        let watch = harness.flow.$step.sink { steps.append($0) }
        defer { watch.cancel() }

        harness.flow.backFromSend()
        paymentRequests.resumePrepare(failing: FakeFetchError(message: "offline"))
        await proceeding.value

        XCTAssertEqual(steps.last, .address)
        XCTAssertFalse(steps.dropFirst().contains(.send), "the failure never brings Send back: \(steps)")
        XCTAssertNil(harness.flow.confirmViewModel)
        XCTAssertEqual(paymentRequests.releases, 0, "nothing was prepared, nothing to discard")
        XCTAssertTrue(harness.finishes.all.isEmpty)
    }

    /// Of two Continues only the latest opens Confirm, even when the earlier one finishes last, and the send that
    /// finishes is the one Confirm showed.
    func testOnlyTheLatestOfTwoContinuesOpensConfirm() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let requests = RequestLog()
        let held = try await continueWithAHeldPaymentRequest(paymentRequests, requests: requests)
        let (harness, send, proceeding) = (held.harness, held.send, held.proceeding)

        await send.onContinue?(try XCTUnwrap(requests.last))
        let latest = try XCTUnwrap(harness.flow.confirmViewModel)
        paymentRequests.resumePrepare()
        await proceeding.value

        XCTAssertIdentical(harness.flow.confirmViewModel, latest, "the earlier preparation never replaces it")
        XCTAssertEqual(harness.flow.step, .confirm)
        XCTAssertEqual(paymentRequests.releases, 1, "the earlier preparation is discarded")

        await latest.confirm()

        XCTAssertEqual(harness.finishes.all, [.success(
            .transactionDetails, txidWire: FakePaymentRequestSend.txidWire(ofPrepare: 2), callbackURL: nil)])
    }

    func testBalanceNoLongerCoveringTheFeeReturnsToSendAndEstimatesAgain() async throws {
        let harness = makeHarness()
        harness.executor.prepareResults = [.failure(.balanceNotEnough)]
        let send = try await openSend(harness)
        let estimatesBefore = harness.estimator.calls

        await send.proceed()

        XCTAssertEqual(harness.flow.step, .send)
        await eventually(harness.estimator.calls > estimatesBefore, "Send did not call confirmReportedNotEnough")
    }

    // MARK: - Outcomes (ADR-0040)

    func testSentCoreToCoreFinishesWithTheTransactionScreenAndItsTxid() async throws {
        let harness = makeHarness()
        let display = Data((0 ..< 32).map { UInt8($0) })
        harness.executor.coreTxHash = display
        let confirm = try await openConfirm(harness)

        await confirm.confirm()

        XCTAssertEqual(harness.finishes.all,
                       [.success(.transactionDetails, txidWire: Data(display.reversed()), callbackURL: nil)])
    }

    func testSentFromShieldedClosesTheSheetOnTheSentToast() async throws {
        let harness = makeHarness()
        let confirm = try await openConfirm(harness, pinned: .shielded)

        await confirm.confirm()

        XCTAssertEqual(harness.finishes.all, [.success(.toast(message: "Sent"), txidWire: nil, callbackURL: nil)])
        XCTAssertEqual(harness.flow.step, .sent(.toast(message: "Sent")))
        XCTAssertNil(harness.flow.confirmViewModel)
    }

    func testSentCoreToCoreWithoutATxidShowsTheSentToastNotAnInlineSent() async throws {
        let harness = makeHarness()
        harness.executor.coreHasTxid = false
        let confirm = try await openConfirm(harness)

        await confirm.confirm()

        XCTAssertEqual(harness.finishes.all, [.success(.toast(message: "Sent"), txidWire: nil, callbackURL: nil)])
    }

    func testInFlightShowsTheToastAndClosesTheFlow() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .inFlight
        let confirm = try await openConfirm(harness)

        await confirm.confirm()

        XCTAssertEqual(harness.finishes.all, [.toast(
            title: "Send in progress",
            message: "It will finish on its own. You don't need to send it again.")])
    }

    func testLockHeldOpensTheLockHeldSheetAndKeepsTheFlowOpen() async throws {
        let lock = HeldAssetLock(fundingTypeRaw: 4, txidWire: Data(repeating: 0x0C, count: 32), vout: 0)
        let harness = makeHarness()
        harness.executor.sendOutcome = .lockHeld(lock)
        let confirm = try await openConfirm(harness)

        await confirm.confirm()

        XCTAssertEqual(harness.flow.step, .lockHeld)
        XCTAssertEqual(harness.flow.lockHeldViewModel?.lock, lock)
        XCTAssertTrue(harness.finishes.all.isEmpty, "the flow stays open for Finish or Close")
    }

    func testFinishOnALockHeldSendResumesTheLockAndShowsTheSentToast() async throws {
        let lock = HeldAssetLock(fundingTypeRaw: 5, txidWire: Data(repeating: 0x0D, count: 32), vout: 3)
        let resumer = FakeLockResumer()
        let harness = makeHarness(lockResumer: resumer)
        harness.executor.sendOutcome = .lockHeld(lock)
        let confirm = try await openConfirm(harness)
        await confirm.confirm()

        await harness.flow.lockHeldViewModel?.finish()

        XCTAssertEqual(resumer.resumed, [lock])
        XCTAssertEqual(harness.finishes.all, [.success(.toast(message: "Sent"), txidWire: nil, callbackURL: nil)])
    }

    func testCloseOnALockHeldSendClosesWithoutResuming() async throws {
        let lock = HeldAssetLock(fundingTypeRaw: 4, txidWire: Data(repeating: 0x0E, count: 32), vout: 0)
        let resumer = FakeLockResumer()
        let harness = makeHarness(lockResumer: resumer)
        harness.executor.sendOutcome = .lockHeld(lock)
        let confirm = try await openConfirm(harness)
        await confirm.confirm()

        harness.flow.closeFromLockHeld()

        XCTAssertTrue(resumer.resumed.isEmpty)
        XCTAssertEqual(harness.finishes.all, [.closed])
    }

    func testNotSentOpensSendFailedWithTheReason() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .notSent(.offline)
        let confirm = try await openConfirm(harness)

        await confirm.confirm()

        guard case .sendFailed(let content) = harness.flow.step else {
            return XCTFail("expected sendFailed, got \(String(describing: harness.flow.step))")
        }
        XCTAssertEqual(content.reason, NotSentReason.offline.localizedMessage)
        XCTAssertEqual(content.info, "Nothing was sent. Your money is still in your Core balance.")
        XCTAssertTrue(harness.finishes.all.isEmpty, "the flow stays open for Retry or Close")
    }

    func testIdentityNotFoundOpensSendFailedNotTheInProgressToast() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .notSent(.identityNotFound)
        let confirm = try await openConfirm(harness)

        await confirm.confirm()

        guard case .sendFailed(let content) = harness.flow.step else {
            return XCTFail("expected sendFailed, got \(String(describing: harness.flow.step))")
        }
        XCTAssertEqual(content.reason, NotSentReason.identityNotFound.localizedMessage)
        XCTAssertTrue(harness.finishes.all.isEmpty, "no Send in progress Toast")
    }

    func testRetryOnSendFailedReturnsToTheSameSendWithTheSameRequest() async throws {
        let harness = makeHarness()
        harness.executor.sendOutcome = .notSent(.rejected)
        let send = try await openSend(harness)
        await send.proceed()
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
        XCTAssertNil(harness.executor.preparedDestinations.last?.callbackScheme)
    }

    func testTheCallbackSchemeOfALinkAnotherAppOpenedReachesTheFetchAndTheDestination() async throws {
        let harness = makeHarness(fetchResult: .success(details()))

        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)&sender=merchantapp", openedByApp: true)

        XCTAssertEqual(harness.fetcher.callbackSchemes, ["merchantapp"])
        let confirmed = try await confirmThroughTheFlow(harness)
        let confirm = try XCTUnwrap(confirmed)
        XCTAssertEqual(harness.executor.preparedDestinations.last?.callbackScheme, "merchantapp")
    }

    func testASuccessfulPaymentRequestSendFinishesWithTheMerchantCallbackURL() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let callback = URL(fileURLWithPath: "/callback/paid")
        paymentRequests.callbackURL = callback
        let fetched = details()
        let harness = makeHarness(fetchResult: .success(fetched),
                                  executor: executor(paymentRequestSend: paymentRequests))

        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)&sender=merchantapp", openedByApp: true)
        let send = try XCTUnwrap(harness.flow.sendViewModel)
        await send.load()
        await send.proceed()
        let confirm = try XCTUnwrap(harness.flow.confirmViewModel)
        await confirm.confirm()

        XCTAssertEqual(harness.fetcher.callbackSchemes, ["merchantapp"], "the fetched request carries the scheme")
        XCTAssertIdentical(paymentRequests.prepared.first, fetched.confirmation, "that request reaches the seam")
        XCTAssertEqual(paymentRequests.sentCount, 1)
        XCTAssertEqual(harness.finishes.all, [.success(
            .transactionDetails, txidWire: Data(repeating: 0xb2, count: 32), callbackURL: callback)])
    }

    // MARK: - Payment request: one fetch from open to broadcast

    /// Confirm and the send read the request fetched at open: it is not fetched again, and the outputs built and
    /// signed are the ones of the request Confirm shows.
    func testAPaymentRequestIsFetchedOnceAndTheSendBuildsTheRequestConfirmShows() async throws {
        let paymentRequests = FakePaymentRequestSend()
        let fetched = details()
        let harness = makeHarness(fetchResult: .success(fetched),
                                  executor: executor(paymentRequestSend: paymentRequests))

        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let confirmedConfirm = try await confirmThroughTheFlow(harness)
        let confirm = try XCTUnwrap(confirmedConfirm)
        await confirm.confirm()

        XCTAssertEqual(harness.fetcher.fetched, [requestURL], "one fetch from open to broadcast")
        XCTAssertEqual(paymentRequests.prepared.count, 1)
        let built = try XCTUnwrap(paymentRequests.prepared.first)
        XCTAssertIdentical(built, fetched.confirmation, "Confirm and the send read the same request")
        XCTAssertEqual(built.confirmation.recipients.map { $0.address }, [coreAddress])
        XCTAssertEqual(built.confirmation.recipients.map { $0.amount }, [oneDash * 3 / 2])
        XCTAssertEqual(paymentRequests.sentCount, 1)
    }

    /// The request's single-use claim stays taken once its broadcast was attempted, so Retry fetches the request
    /// again: Confirm shows and the send builds the new one, from the same source and for the same amount.
    func testARetryAfterNotSentFetchesTheRequestAgainAndBuildsTheNewOne() async throws {
        let paymentRequests = FakePaymentRequestSend()
        paymentRequests.sendError = SwiftDashSDKTransactionSender.SendError.transactionRejected(
            txid: "t", reason: "bad-txns")
        let attempted = details()
        let harness = makeHarness(fetchResult: .success(attempted),
                                  executor: executor(paymentRequestSend: paymentRequests))
        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let confirmedFirst = try await confirmThroughTheFlow(harness)
        let first = try XCTUnwrap(confirmedFirst)
        await first.confirm()
        guard case .sendFailed = harness.flow.step else {
            return XCTFail("expected sendFailed, got \(String(describing: harness.flow.step))")
        }
        let refetched = details()
        harness.fetcher.result = .success(refetched)
        paymentRequests.sendError = nil

        harness.flow.retryFromSendFailed()
        await eventually(harness.flow.step == .send, "Retry never returned to Send")
        let confirmedAgain = try await confirmThroughTheFlow(harness)
        let again = try XCTUnwrap(confirmedAgain)
        await again.confirm()

        XCTAssertEqual(harness.fetcher.fetched, [requestURL, requestURL], "Retry fetches the request again")
        XCTAssertEqual(paymentRequests.prepared.count, 2)
        XCTAssertIdentical(paymentRequests.prepared.last, refetched.confirmation,
                           "the new request, not the one already attempted")
        XCTAssertEqual(harness.flow.sendViewModel?.source, .core)
        XCTAssertEqual(harness.flow.sendViewModel?.amountDuffs, oneDash * 3 / 2)
        XCTAssertEqual(paymentRequests.sentCount, 2)
    }

    func testARetryWhoseFetchFailsFinishesWithRequestFailed() async throws {
        let paymentRequests = FakePaymentRequestSend()
        paymentRequests.sendError = SwiftDashSDKTransactionSender.SendError.transactionRejected(
            txid: "t", reason: "bad-txns")
        let harness = makeHarness(fetchResult: .success(details()),
                                  executor: executor(paymentRequestSend: paymentRequests))
        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let confirmed = try await confirmThroughTheFlow(harness)
        let confirm = try XCTUnwrap(confirmed)
        await confirm.confirm()
        harness.fetcher.result = .failure(FakeFetchError(message: "Request expired"))

        harness.flow.retryFromSendFailed()
        await eventually(!harness.finishes.all.isEmpty, "Retry never finished")

        XCTAssertEqual(harness.finishes.all, [
            .requestFailed(title: "Couldn't make payment", message: "Request expired"),
        ])
        XCTAssertEqual(paymentRequests.prepared.count, 1, "nothing is built from the attempted request")
    }

    /// While Retry fetches the request again the flow reports it, so Retry shows its progress; closing the sheet
    /// meanwhile cancels the fetch, and a fetch that returns afterwards opens nothing.
    func testARetryFetchIsReportedAndClosingDuringItOpensNothing() async throws {
        let paymentRequests = FakePaymentRequestSend()
        paymentRequests.sendError = SwiftDashSDKTransactionSender.SendError.transactionRejected(
            txid: "t", reason: "bad-txns")
        let harness = makeHarness(fetchResult: .success(details()),
                                  executor: executor(paymentRequestSend: paymentRequests))
        await harness.flow.start(scanned: "dash:?r=\(requestURL.absoluteString)")
        let confirmed = try await confirmThroughTheFlow(harness)
        let confirm = try XCTUnwrap(confirmed)
        await confirm.confirm()
        guard case .sendFailed = harness.flow.step else {
            return XCTFail("expected sendFailed, got \(String(describing: harness.flow.step))")
        }
        harness.fetcher.result = .success(details())
        harness.fetcher.holds = true

        harness.flow.retryFromSendFailed()
        await eventually(harness.fetcher.isHolding, "Retry never fetched")
        XCTAssertTrue(harness.flow.isRefetchingRequest)

        harness.flow.closeFromSendFailed()
        XCTAssertFalse(harness.flow.isRefetchingRequest)
        harness.fetcher.release()
        for _ in 0 ..< 50 { try? await Task.sleep(nanoseconds: 2_000_000) }

        XCTAssertNotEqual(harness.flow.step, .send, "a closed flow does not open Send")
        XCTAssertEqual(harness.finishes.all, [.closed])
    }

    func testAPlainSendHasNoCallbackURL() async throws {
        let harness = makeHarness()
        let confirm = try await openConfirm(harness)

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
        select.tap(.platform)

        await eventually(send.source == .platform, "the pick never reached Send")
        XCTAssertEqual(harness.flow.step, .send)
    }

    /// The sheet shows at once with its loading state and loads its rows once per From tap.
    func testSelectSourceIsShownAtOnceAndLoadsOncePerTap() async throws {
        let harness = makeHarness()
        _ = try await openSend(harness)
        harness.identity.holds = true
        let before = harness.identity.reads

        let showing = Task { await harness.flow.showSelectSource() }
        for _ in 0 ..< 200 where !harness.identity.isHolding { await Task.yield() }
        XCTAssertTrue(harness.identity.isHolding)
        XCTAssertEqual(harness.flow.step, .selectSource, "shown before its rows are read")
        XCTAssertEqual(harness.flow.selectSourceViewModel?.isLoading, true)

        harness.identity.release()
        await showing.value
        XCTAssertEqual(harness.flow.selectSourceViewModel?.isLoading, false)
        XCTAssertEqual(harness.flow.selectSourceViewModel?.rows.count, 3)
        XCTAssertEqual(harness.identity.reads - before, 1, "one identity read: one load")
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

    /// The request behind a resolved link is fetched in a task the flow keeps; leaving Address meanwhile cancels it,
    /// so a fetch that returns afterwards does not open Send on a finished flow.
    func testLeavingAddressWhileTheRequestIsFetchedOpensNothingWhenItReturns() async throws {
        let harness = makeHarness(fetchResult: .success(details()))
        harness.fetcher.holds = true
        harness.flow.start()
        harness.flow.addressViewModel?.setText("dash:?r=\(requestURL.absoluteString)")
        await harness.flow.addressViewModel?.continueTapped()
        await eventually(harness.fetcher.isHolding, "the request was never fetched")

        harness.flow.backFromAddress()
        harness.fetcher.release()
        for _ in 0 ..< 50 { try? await Task.sleep(nanoseconds: 2_000_000) }

        XCTAssertNil(harness.flow.sendViewModel, "a finished flow does not open Send")
        XCTAssertEqual(harness.finishes.all, [.backToMenu])
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

private final class FakeCurrentIdentity: CurrentIdentityReading {
    /// When set, the next read suspends until `release`.
    var holds = false
    private(set) var reads = 0
    private var held: CheckedContinuation<Void, Never>?

    var isHolding: Bool { held != nil }

    func currentIdentity() async -> SelectSourceIdentity? {
        reads += 1
        if holds {
            holds = false
            await withCheckedContinuation { held = $0 }
        }
        return nil
    }

    func release() {
        held?.resume()
        held = nil
    }
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
    func maxPlan(route: SendRoute) async -> SendMaxPlan? { nil }
    func canFund(route: SendRoute, amount: UInt64) async -> SendFundingCheck { .notChecked }
}

private struct FakeConverter: SendAmountConverting {
    func fiat(forDuffs duffs: UInt64) -> Decimal? { nil }
    func duffs(forFiat fiat: Decimal) -> UInt64? { nil }
    func fiatText(forDuffs duffs: UInt64) -> String? { nil }
}

/// The executor at its protocol. A Core to Core prepare carries a standard plan with `coreTxHash`, as the live one
/// does, so the flow can read the txid the success screen needs.
@MainActor
private final class FakeLockResumer: HeldAssetLockResuming {
    private(set) var resumed: [HeldAssetLock] = []

    func resume(_ lock: HeldAssetLock) async throws -> AssetLockRecoveryService.Outcome {
        resumed.append(lock)
        return .completed
    }
}

@MainActor
private final class FakeExecutor: ExternalSendExecuting {
    var prepareResults: [Result<UInt64, ExternalSendError>] = []
    var sendOutcome: SendOutcome = .sent
    var coreTxHash = Data(repeating: 7, count: 32)
    /// False: a Core to Core prepare carries no txid, as a routed plan does.
    var coreHasTxid = true
    private(set) var preparedDestinations: [Destination] = []
    /// Runs when `prepare` is called, before it answers.
    var onPrepare: (() -> Void)?

    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        preparedDestinations.append(destination)
        onPrepare?()
        let fee: UInt64
        if prepareResults.isEmpty {
            fee = 226
        } else {
            switch prepareResults.removeFirst() {
            case .success(let value): fee = value
            case .failure(let error): throw error
            }
        }
        guard route == .coreToCore, coreHasTxid else {
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

/// The standard send edge of the real executor: hands out a prepared transaction whose broadcast is accepted.
private final class FakeStandardSend: CoreStandardSending {
    private(set) var broadcasts = 0

    func prepareStandardSend(address: String, amount: UInt64) async throws -> PreparedStandardSend {
        PreparedStandardSend(
            txData: Data([0x01]), txHash: Data(repeating: 0xe9, count: 32), fee: 226, address: address, amount: amount,
            ensureOnlineAction: {},
            broadcastAction: { [unowned self] in
                broadcasts += 1
                return .accepted(txid: "")
            })
    }
}

/// The BIP70 send edge of the real executor: records the request it is given to build and, once sent, hands back
/// the merchant's callback URL.
@MainActor
private final class FakePaymentRequestSend: CorePaymentRequestSending {
    var callbackURL: URL?
    var sendError: Error?
    private(set) var prepared: [BIP70ConfirmationBox] = []
    private(set) var sentCount = 0

    /// When set, the next prepare suspends until `resumePrepare`.
    var holdsNextPrepare = false
    /// How many prepared sends gave the request's claim back.
    private(set) var releases = 0
    private var heldPrepare: CheckedContinuation<Void, Never>?
    private var heldFailure: Error?

    var isHoldingPrepare: Bool { heldPrepare != nil }

    /// The txid of the `index`-th prepare (from 1), so two prepared sends can be told apart.
    static func txidWire(ofPrepare index: Int) -> Data {
        Data(repeating: 0xb1 + UInt8(index), count: 32)
    }

    /// Lets the held prepare go on, or fail with `error`.
    func resumePrepare(failing error: Error? = nil) {
        heldFailure = error
        heldPrepare?.resume()
        heldPrepare = nil
    }

    func preparePaymentRequestSend(_ request: BIP70ConfirmationBox) async throws -> PreparedPaymentRequestSend {
        prepared.append(request)
        let txidWire = Self.txidWire(ofPrepare: prepared.count)
        if holdsNextPrepare {
            holdsNextPrepare = false
            await withCheckedContinuation { heldPrepare = $0 }
            if let heldFailure {
                self.heldFailure = nil
                throw heldFailure
            }
        }
        let txidDisplay = Data(txidWire.reversed())
        return PreparedPaymentRequestSend(
            txidWire: txidWire, fee: 226,
            sendAction: { [unowned self] in
                sentCount += 1
                if let sendError { throw sendError }
                return SendResult(
                    txidHexDisplay: String(repeating: "b2", count: 32), txHashDisplay: txidDisplay, fee: 226,
                    amount: request.amount, primaryAddress: nil, ackMemo: nil, callbackURL: callbackURL)
            },
            release: { [unowned self] in releases += 1 })
    }
}
