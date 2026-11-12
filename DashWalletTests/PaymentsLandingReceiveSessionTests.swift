//
//  PaymentsLandingReceiveSessionTests.swift
//  DashWalletTests
//

import Combine
@testable import dashpay
import SwiftDashSDK
import SwiftData
import XCTest

/// A source whose every request stays pending until the test completes it,
/// so the tests decide the order in which derivations finish.
final class ControlledShieldedAddressSource: ShieldedReceiveAddressSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<ShieldedReceiveAddress, Never>?] = []

    var callCount: Int { lock.withLock { continuations.count } }

    func receiveAddress(walletId: Data) async -> ShieldedReceiveAddress {
        await withCheckedContinuation { continuation in
            lock.withLock { continuations.append(continuation) }
        }
    }

    /// Completes the `index`-th request (0-based) with `result`.
    func complete(_ index: Int, with result: ShieldedReceiveAddress) {
        let continuation = lock.withLock { () -> CheckedContinuation<ShieldedReceiveAddress, Never>? in
            let pending = continuations[index]
            continuations[index] = nil
            return pending
        }
        continuation?.resume(returning: result)
    }
}

/// The wallet the receipt watchers read, faked: a running testnet wallet
/// whose persisted and projected shielded rows the test sets.
final class FakeReceiptSources: @unchecked Sendable {
    private let lock = NSLock()
    private var persisted: Set<String> = []
    private var projected: [ShieldedActivityItem] = []
    private(set) var baselineReads = 0
    let syncResults = PassthroughSubject<Void, Never>()

    /// A shielded payment lands: persisted and projected from now on.
    func receive(_ item: ShieldedActivityItem) {
        lock.withLock {
            persisted.insert(item.id)
            projected.append(item)
        }
    }

    func sources(walletId: Data) -> ReceiptWatchingSources {
        ReceiptWatchingSources(
            walletContext: { ReceiptWalletContext(walletId: walletId, environment: .testnet, isRunning: true) },
            persistedShieldedActivityIds: { [self] in
                lock.withLock {
                    baselineReads += 1
                    return persisted
                }
            },
            projectedShieldedActivity: { [self] in lock.withLock { projected } },
            shieldedSyncResults: { [syncResults] _ in syncResults.eraseToAnyPublisher() },
            requestShieldedRefresh: {})
    }

    static func receivedItem(_ id: UInt8) -> ShieldedActivityItem {
        ShieldedActivityItem(row: PersistentShieldedActivity(
            walletId: Data(repeating: 9, count: 32), accountIndex: 0, entryId: Data(repeating: id, count: 32),
            kindTag: ShieldedActivityItem.Kind.received.rawValue, direction: 0, status: 1, amount: 5_000_000,
            fee: 0, hasFee: false, blockHeight: 1, hasBlockHeight: true, createdAtMs: 1_800_000_000_000,
            identityId: Data(), counterparty: Data(), memo: Data(), noteCmxs: Data(), spentNullifiers: Data()))
    }
}

@MainActor
final class PaymentsLandingReceiveSessionTests: XCTestCase {
    private static let walletId = Data(repeating: 9, count: 32)

    private func makeViewModel(
        activeTab: PaymentsLandingTab = .receive,
        network: ChainNetwork = .shielded,
        source: ControlledShieldedAddressSource,
        walletId: Data? = PaymentsLandingReceiveSessionTests.walletId,
        receiptSources: ReceiptWatchingSources = .live,
        shieldedRunning: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()
    ) -> PaymentsLandingViewModel {
        PaymentsLandingViewModel(
            activeTab: activeTab,
            network: network,
            shieldedAddressSource: source,
            activeWalletId: { walletId },
            receiptSources: receiptSources,
            shieldedRunning: shieldedRunning)
    }

    /// Spins the main run loop until `condition` holds or 2 s pass.
    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline {
                return XCTFail("timed out: \(message)", file: file, line: line)
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Lets queued main-actor work run, for asserting that nothing changes.
    private func settle() async {
        for _ in 0..<20 { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testSessionShowsNoAddressWhileDerivingThenTheFreshOne() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)

        viewModel.beginReceiveSession()
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)
        XCTAssertNil(viewModel.currentAddress, "no address while deriving; Copy and Share disabled")

        await waitUntil("request sent") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        await waitUntil("fresh applied") { viewModel.currentAddress == "tdash1fresh-a" }
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.fresh("tdash1fresh-a")))
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
    }

    func testEachSessionShowsItsOwnAddress() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)

        viewModel.beginReceiveSession()
        await waitUntil("first request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        await waitUntil("first applied") { viewModel.currentAddress == "tdash1fresh-a" }

        viewModel.beginReceiveSession()
        XCTAssertNil(viewModel.currentAddress, "a new session never shows the previous address")
        await waitUntil("second request") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-b"))
        await waitUntil("second applied") { viewModel.currentAddress == "tdash1fresh-b" }
    }

    func testLateResultOfAnEndedSessionIsDropped() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)

        viewModel.beginReceiveSession()
        await waitUntil("first request") { source.callCount == 1 }
        viewModel.beginReceiveSession()
        await waitUntil("second request") { source.callCount == 2 }

        source.complete(1, with: .fresh("tdash1fresh-new"))
        await waitUntil("new applied") { viewModel.currentAddress == "tdash1fresh-new" }
        source.complete(0, with: .fresh("tdash1fresh-old"))
        await settle()
        XCTAssertEqual(viewModel.currentAddress, "tdash1fresh-new", "the ended session's result never replaces it")
    }

    func testAppAndSettingsTicksNeverReplaceTheAddress() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        await waitUntil("applied") { viewModel.currentAddress == "tdash1fresh-a" }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.post(name: .advancedModeDidChange, object: nil)
        viewModel.setReceiveSurfaceVisible(true)
        viewModel.setReceiptWatchingObscured(false)
        await settle()

        XCTAssertEqual(source.callCount, 1, "no derivation outside a session start")
        XCTAssertEqual(viewModel.currentAddress, "tdash1fresh-a")
    }

    func testFallbackIsOnlyEverShownWithTheWarning() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fallback("tdash1default"))
        await waitUntil("fallback applied") { viewModel.currentAddress == "tdash1default" }
        XCTAssertTrue(viewModel.isShowingShieldedFallback, "the default address is never shown without the warning")

        // The next session tries for a fresh address again and drops the warning.
        viewModel.beginReceiveSession()
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
        await waitUntil("retry request") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-a"))
        await waitUntil("fresh applied") { viewModel.currentAddress == "tdash1fresh-a" }
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
    }

    func testUnavailableShowsNoAddress() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .unavailable)
        await waitUntil("unavailable applied") { viewModel.shieldedReceiveState == .ready(.unavailable) }
        XCTAssertNil(viewModel.currentAddress)
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
    }

    func testNoWalletMeansUnavailableWithoutAskingTheSource() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source, walletId: nil)
        viewModel.beginReceiveSession()
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.unavailable))
        await settle()
        XCTAssertEqual(source.callCount, 0)
    }

    func testCoreSelectedDerivesNoShieldedAddress() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(network: .core, source: source)
        viewModel.beginReceiveSession()
        await settle()
        XCTAssertEqual(source.callCount, 0)
    }

    func testSwitchingToShieldedBeginsASession() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(network: .core, source: source)
        viewModel.network = .shielded
        await waitUntil("switch began a session") { source.callCount == 1 }
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)
    }

    func testWalletOrNetworkChangeBeginsANewSession() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        await waitUntil("applied") { viewModel.currentAddress == "tdash1fresh-a" }

        viewModel.handleWalletOrEnvironmentChange()
        XCTAssertNil(viewModel.currentAddress, "the old network's address is gone")
        await waitUntil("new session") { source.callCount == 2 }
    }

    // MARK: - Receipt window (AC-01 paragraph 2, AC-10)

    private static let receipt = ReceiveReceipt(
        id: "shielded-receipt", rail: .shielded, amountDuffs: 1_000,
        receivedAt: Date(timeIntervalSince1970: 1_800_000_000), memo: nil, transactionId: nil, coreStatus: nil)

    private func viewModelShowingAddress(
        _ source: ControlledShieldedAddressSource
    ) async -> PaymentsLandingViewModel {
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        await waitUntil("applied") { viewModel.currentAddress == "tdash1fresh-a" }
        return viewModel
    }

    func testGainOfFocusWhileAReceiptIsShownChangesNothing() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = await viewModelShowingAddress(source)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.beginReceiveSession()
        await settle()

        XCTAssertEqual(viewModel.receipt, Self.receipt, "the receipt stays")
        XCTAssertEqual(source.callCount, 1, "no new session, no new address")
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.fresh("tdash1fresh-a")))
    }

    func testReceiveAnotherClearsTheReceiptAndBeginsASession() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = await viewModelShowingAddress(source)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.receiveAnother()

        XCTAssertNil(viewModel.receipt)
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)
        await waitUntil("new session") { source.callCount == 2 }
    }

    func testDoneEndsTheReceiptWithoutANewSession() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = await viewModelShowingAddress(source)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.finishReceiving()
        await settle()

        XCTAssertNil(viewModel.receipt)
        XCTAssertEqual(source.callCount, 1, "Done begins no session; returning to Receive does")
    }

    // MARK: - Gains of focus inside the landing

    func testNoShieldedDerivationOffTheReceiveTab() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(activeTab: .send, source: source)
        viewModel.beginReceiveSession()
        await settle()
        XCTAssertEqual(source.callCount, 0)
    }

    func testOpeningTheReceiveTabBeginsASession() async {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(activeTab: .send, source: source)
        viewModel.activeTab = .receive
        await waitUntil("opening Receive began a session") { source.callCount == 1 }
    }

    // MARK: - Receipt window (AC-10)

    /// Receive on screen with a fresh address, the receipt window open and
    /// watching the faked shielded rail.
    private func watchingViewModel(
        _ source: ControlledShieldedAddressSource,
        _ wallet: FakeReceiptSources
    ) async -> PaymentsLandingViewModel {
        let viewModel = makeViewModel(source: source, receiptSources: wallet.sources(walletId: Self.walletId))
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        viewModel.setReceiveSurfaceVisible(true)
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        await waitUntil("watching") { viewModel.isWatchingForReceipt }
        return viewModel
    }

    /// Ends focus, lets a payment land, and returns focus with a new address.
    private func paymentWhileUnfocused(
        _ viewModel: PaymentsLandingViewModel,
        _ source: ControlledShieldedAddressSource,
        _ wallet: FakeReceiptSources,
        leaving: Bool
    ) async {
        viewModel.setReceiveSurfaceVisible(false)
        if leaving { viewModel.receiveDidDisappear(pushingReceiveStep: false) }
        wallet.receive(FakeReceiptSources.receivedItem(2))
        viewModel.beginReceiveSession()
        await waitUntil("second request") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-b"))
        await waitUntil("new address") { viewModel.currentAddress == "tdash1fresh-b" }
        viewModel.setReceiveSurfaceVisible(true)
    }

    func testPaymentWhileUnfocusedRaisesItsReceiptWhenFocusReturns() async {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        wallet.receive(FakeReceiptSources.receivedItem(1))
        let viewModel = await watchingViewModel(source, wallet)
        await settle()
        XCTAssertNil(viewModel.receipt, "a row that existed when Receive opened is not new")

        await paymentWhileUnfocused(viewModel, source, wallet, leaving: false)

        await waitUntil("receipt raised") { viewModel.receipt != nil }
        XCTAssertEqual(viewModel.receipt?.id, FakeReceiptSources.receivedItem(2).id)
        XCTAssertEqual(viewModel.currentAddress, "tdash1fresh-b", "the address changed")
    }

    func testGainOfFocusDoesNotMoveTheReceiptWindowStart() async {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = await watchingViewModel(source, wallet)
        XCTAssertEqual(wallet.baselineReads, 1)

        await paymentWhileUnfocused(viewModel, source, wallet, leaving: false)
        await waitUntil("receipt raised") { viewModel.receipt != nil }

        XCTAssertEqual(wallet.baselineReads, 1, "the window kept the baseline read when Receive opened")
    }

    func testLeavingReceiveEndsTheReceiptWindow() async {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = await watchingViewModel(source, wallet)

        await paymentWhileUnfocused(viewModel, source, wallet, leaving: true)
        await waitUntil("a new window is watching") { viewModel.isWatchingForReceipt }
        await settle()

        XCTAssertNil(viewModel.receipt, "a payment that landed while the owner was away is not new")
        XCTAssertEqual(wallet.baselineReads, 2, "returning opened a new window")
    }

    func testLeavingReceiveClearsAShownReceipt() async {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = await watchingViewModel(source, wallet)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.setReceiveSurfaceVisible(false)
        viewModel.receiveDidDisappear(pushingReceiveStep: false)

        XCTAssertNil(viewModel.receipt)
    }

    func testPushingAReceiveStepKeepsTheReceiptAndTheWindow() async {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = await watchingViewModel(source, wallet)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.setReceiveSurfaceVisible(false)
        viewModel.receiveDidDisappear(pushingReceiveStep: true)
        viewModel.setReceiveSurfaceVisible(true)
        await settle()

        XCTAssertEqual(viewModel.receipt, Self.receipt, "a pushed receive step is not a leave")
        XCTAssertEqual(wallet.baselineReads, 1, "the window kept its baseline")
    }

    // MARK: - Placeholder retry

    func testNotReadyPlaceholderRetriesWhenShieldedStartsRunning() async {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .notReady)
        await waitUntil("placeholder") { viewModel.shieldedReceiveState == .ready(.notReady) }

        running.send(true)

        await waitUntil("retried") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-a"))
        await waitUntil("address") { viewModel.currentAddress == "tdash1fresh-a" }
    }

    func testUnavailablePlaceholderRetriesWhenShieldedStartsRunning() async {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .unavailable)
        await waitUntil("placeholder") { viewModel.shieldedReceiveState == .ready(.unavailable) }

        running.send(true)

        await waitUntil("retried") { source.callCount == 2 }
    }

    /// Shielded sync starts after the source answered «not ready» but before
    /// that answer is applied: the session must not stay on the placeholder.
    func testShieldedStartingWhileDerivingRetries() async {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)

        running.send(true)
        await waitUntil("retried") { source.callCount == 2 }
        source.complete(0, with: .notReady)
        source.complete(1, with: .fresh("tdash1fresh-a"))

        await waitUntil("address") { viewModel.currentAddress == "tdash1fresh-a" }
        await settle()
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.fresh("tdash1fresh-a")), "the stale answer is dropped")
    }

    func testShieldedStartingNeverReplacesAShownAddress() async {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fallback("tdash1default"))
        await waitUntil("address") { viewModel.currentAddress == "tdash1default" }

        running.send(true)
        await settle()

        XCTAssertEqual(source.callCount, 1, "the session keeps its address")
        XCTAssertEqual(viewModel.currentAddress, "tdash1default")
    }

    func testShieldedStoppingDoesNotRetry() async {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .notReady)
        await waitUntil("placeholder") { viewModel.shieldedReceiveState == .ready(.notReady) }

        running.send(false)
        await settle()

        XCTAssertEqual(source.callCount, 1)
    }
}
