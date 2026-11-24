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

    private struct WaitTimedOut: Error {}

    /// Spins the main run loop until `condition` holds or 2 s pass. A timeout
    /// fails and throws, so the test stops before it completes a request
    /// that was never made.
    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out: \(message)", file: file, line: line)
                throw WaitTimedOut()
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Lets queued main-actor work run, for asserting that nothing changes.
    private func settle() async {
        for _ in 0..<20 { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testSessionShowsNoAddressWhileDerivingThenTheFreshOne() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)

        viewModel.beginReceiveSession()
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)
        XCTAssertNil(viewModel.currentAddress, "no address while deriving; Copy and Share disabled")

        try await waitUntil("request sent") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        try await waitUntil("fresh applied") { viewModel.currentAddress == "tdash1fresh-a" }
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.fresh("tdash1fresh-a")))
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
    }

    func testEachSessionShowsItsOwnAddress() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)

        viewModel.beginReceiveSession()
        try await waitUntil("first request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        try await waitUntil("first applied") { viewModel.currentAddress == "tdash1fresh-a" }

        viewModel.beginReceiveSession()
        XCTAssertNil(viewModel.currentAddress, "a new session never shows the previous address")
        try await waitUntil("second request") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-b"))
        try await waitUntil("second applied") { viewModel.currentAddress == "tdash1fresh-b" }
    }

    func testLateResultOfAnEndedSessionIsDropped() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)

        viewModel.beginReceiveSession()
        try await waitUntil("first request") { source.callCount == 1 }
        viewModel.beginReceiveSession()
        try await waitUntil("second request") { source.callCount == 2 }

        source.complete(1, with: .fresh("tdash1fresh-new"))
        try await waitUntil("new applied") { viewModel.currentAddress == "tdash1fresh-new" }
        source.complete(0, with: .fresh("tdash1fresh-old"))
        await settle()
        XCTAssertEqual(viewModel.currentAddress, "tdash1fresh-new", "the ended session's result never replaces it")
    }

    func testAppAndSettingsTicksNeverReplaceTheAddress() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        try await waitUntil("applied") { viewModel.currentAddress == "tdash1fresh-a" }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.post(name: .advancedModeDidChange, object: nil)
        viewModel.setReceiveSurfaceVisible(true)
        viewModel.setReceiptWatchingObscured(false)
        await settle()

        XCTAssertEqual(source.callCount, 1, "no derivation outside a session start")
        XCTAssertEqual(viewModel.currentAddress, "tdash1fresh-a")
    }

    func testFallbackIsOnlyEverShownWithTheWarning() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fallback("tdash1default"))
        try await waitUntil("fallback applied") { viewModel.currentAddress == "tdash1default" }
        XCTAssertTrue(viewModel.isShowingShieldedFallback, "the default address is never shown without the warning")

        // The next session tries for a fresh address again and drops the warning.
        viewModel.beginReceiveSession()
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
        try await waitUntil("retry request") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-a"))
        try await waitUntil("fresh applied") { viewModel.currentAddress == "tdash1fresh-a" }
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
    }

    func testUnavailableShowsNoAddress() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .unavailable)
        try await waitUntil("unavailable applied") { viewModel.shieldedReceiveState == .ready(.unavailable) }
        XCTAssertNil(viewModel.currentAddress)
        XCTAssertFalse(viewModel.isShowingShieldedFallback)
    }

    func testNoWalletMeansUnavailableWithoutAskingTheSource() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source, walletId: nil)
        viewModel.beginReceiveSession()
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.unavailable))
        await settle()
        XCTAssertEqual(source.callCount, 0)
    }

    func testCoreSelectedDerivesNoShieldedAddress() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(network: .core, source: source)
        viewModel.beginReceiveSession()
        await settle()
        XCTAssertEqual(source.callCount, 0)
    }

    /// The live source answers on the main actor at once: the switch itself
    /// carries the fresh address, so the card slides in with its QR.
    func testSwitchingToShieldedWithAnImmediateSourceShowsTheAddressInTheSameCall() {
        final class ImmediateSource: ImmediateShieldedReceiveAddressSource {
            var calls = 0
            func receiveAddress(walletId: Data) async -> ShieldedReceiveAddress { .unavailable }
            func receiveAddressNow(walletId: Data) -> ShieldedReceiveAddress {
                calls += 1
                return .fresh("tdash1fresh\(calls)")
            }
        }
        let source = ImmediateSource()
        let viewModel = PaymentsLandingViewModel(
            activeTab: .receive,
            network: .core,
            shieldedAddressSource: source,
            activeWalletId: { Self.walletId },
            receiptSources: .live,
            shieldedRunning: Empty().eraseToAnyPublisher())

        viewModel.network = .shielded

        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.fresh("tdash1fresh1")))
        XCTAssertEqual(viewModel.currentAddress, "tdash1fresh1")
        XCTAssertEqual(source.calls, 1)
    }

    func testSwitchingToShieldedBeginsASession() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(network: .core, source: source)
        viewModel.network = .shielded
        try await waitUntil("switch began a session") { source.callCount == 1 }
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)
    }

    func testWalletOrNetworkChangeBeginsANewSession() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        try await waitUntil("applied") { viewModel.currentAddress == "tdash1fresh-a" }

        viewModel.handleWalletOrEnvironmentChange()
        XCTAssertNil(viewModel.currentAddress, "the old network's address is gone")
        try await waitUntil("new session") { source.callCount == 2 }
    }

    // MARK: - Receipt window (AC-01 paragraph 2, AC-10)

    private static let receipt = ReceiveReceipt(
        id: "shielded-receipt", rail: .shielded, amountDuffs: 1_000,
        receivedAt: Date(timeIntervalSince1970: 1_800_000_000), memo: nil, transactionId: nil, coreStatus: nil)

    private func viewModelShowingAddress(
        _ source: ControlledShieldedAddressSource
    ) async throws -> PaymentsLandingViewModel {
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        try await waitUntil("applied") { viewModel.currentAddress == "tdash1fresh-a" }
        return viewModel
    }

    func testGainOfFocusWhileAReceiptIsShownChangesNothing() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = try await viewModelShowingAddress(source)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.beginReceiveSession()
        await settle()

        XCTAssertEqual(viewModel.receipt, Self.receipt, "the receipt stays")
        XCTAssertEqual(source.callCount, 1, "no new session, no new address")
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.fresh("tdash1fresh-a")))
    }

    func testReceiveAnotherClearsTheReceiptAndBeginsASession() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = try await viewModelShowingAddress(source)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.receiveAnother()

        XCTAssertNil(viewModel.receipt)
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)
        try await waitUntil("new session") { source.callCount == 2 }
    }

    func testDoneEndsTheReceiptWithoutANewSession() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = try await viewModelShowingAddress(source)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.finishReceiving()
        await settle()

        XCTAssertNil(viewModel.receipt)
        XCTAssertEqual(source.callCount, 1, "Done begins no session; returning to Receive does")
    }

    func testLateResultAfterLeavingReceiveIsDropped() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }

        viewModel.receiveDidDisappear(pushingReceiveStep: false)
        source.complete(0, with: .fresh("tdash1fresh-late"))
        await settle()

        XCTAssertEqual(viewModel.shieldedReceiveState, .idle, "an ended session's result is never applied")
        XCTAssertNil(viewModel.currentAddress)
    }

    func testPushingAReceiveStepKeepsTheDerivation() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(source: source)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }

        viewModel.receiveDidDisappear(pushingReceiveStep: true)
        source.complete(0, with: .fresh("tdash1fresh-a"))
        try await waitUntil("applied") { viewModel.currentAddress == "tdash1fresh-a" }
    }

    func testLateResultAfterDoneIsDropped() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = try await viewModelShowingAddress(source)
        // A derivation started before the receipt, still in flight at Done.
        viewModel.beginReceiveSession()
        try await waitUntil("second request") { source.callCount == 2 }
        viewModel.acceptReceipt(Self.receipt)
        viewModel.finishReceiving()
        source.complete(1, with: .fresh("tdash1fresh-late"))
        await settle()

        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving, "Done drops a result still in flight")
        XCTAssertNotEqual(viewModel.currentAddress, "tdash1fresh-late")
    }

    func testShieldedWalletStartingAfterLeavingDerivesNothing() async throws {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .notReady)
        try await waitUntil("placeholder") { viewModel.shieldedReceiveState == .ready(.notReady) }

        viewModel.receiveDidDisappear(pushingReceiveStep: false)
        running.send(true)
        await settle()

        XCTAssertEqual(source.callCount, 1, "no address is derived while Receive is away")
    }

    // MARK: - Gains of focus inside the landing

    func testNoShieldedDerivationOffTheReceiveTab() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(activeTab: .send, source: source)
        viewModel.beginReceiveSession()
        await settle()
        XCTAssertEqual(source.callCount, 0)
    }

    func testOpeningTheReceiveTabBeginsASession() async throws {
        let source = ControlledShieldedAddressSource()
        let viewModel = makeViewModel(activeTab: .send, source: source)
        viewModel.activeTab = .receive
        try await waitUntil("opening Receive began a session") { source.callCount == 1 }
    }

    // MARK: - Receipt window (AC-10)

    /// Receive on screen with a fresh address, the receipt window open and
    /// watching the faked shielded rail.
    private func watchingViewModel(
        _ source: ControlledShieldedAddressSource,
        _ wallet: FakeReceiptSources
    ) async throws -> PaymentsLandingViewModel {
        let viewModel = makeViewModel(source: source, receiptSources: wallet.sources(walletId: Self.walletId))
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        viewModel.setReceiveSurfaceVisible(true)
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fresh("tdash1fresh-a"))
        try await waitUntil("watching") { viewModel.isWatchingForReceipt }
        return viewModel
    }

    /// Ends focus, lets a payment land, and returns focus with a new address.
    private func paymentWhileUnfocused(
        _ viewModel: PaymentsLandingViewModel,
        _ source: ControlledShieldedAddressSource,
        _ wallet: FakeReceiptSources,
        leaving: Bool
    ) async throws {
        viewModel.setReceiveSurfaceVisible(false)
        if leaving { viewModel.receiveDidDisappear(pushingReceiveStep: false) }
        wallet.receive(FakeReceiptSources.receivedItem(2))
        viewModel.beginReceiveSession()
        try await waitUntil("second request") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-b"))
        try await waitUntil("new address") { viewModel.currentAddress == "tdash1fresh-b" }
        viewModel.setReceiveSurfaceVisible(true)
    }

    func testPaymentWhileUnfocusedRaisesItsReceiptWhenFocusReturns() async throws {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        wallet.receive(FakeReceiptSources.receivedItem(1))
        let viewModel = try await watchingViewModel(source, wallet)
        await settle()
        XCTAssertNil(viewModel.receipt, "a row that existed when Receive opened is not new")

        try await paymentWhileUnfocused(viewModel, source, wallet, leaving: false)

        try await waitUntil("receipt raised") { viewModel.receipt != nil }
        XCTAssertEqual(viewModel.receipt?.id, FakeReceiptSources.receivedItem(2).id)
        XCTAssertEqual(viewModel.currentAddress, "tdash1fresh-b", "the address changed")
    }

    func testGainOfFocusDoesNotMoveTheReceiptWindowStart() async throws {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = try await watchingViewModel(source, wallet)
        XCTAssertEqual(wallet.baselineReads, 1)

        try await paymentWhileUnfocused(viewModel, source, wallet, leaving: false)
        try await waitUntil("receipt raised") { viewModel.receipt != nil }

        XCTAssertEqual(wallet.baselineReads, 1, "the window kept the baseline read when Receive opened")
    }

    func testLeavingReceiveEndsTheReceiptWindow() async throws {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = try await watchingViewModel(source, wallet)

        try await paymentWhileUnfocused(viewModel, source, wallet, leaving: true)
        try await waitUntil("a new window is watching") { viewModel.isWatchingForReceipt }
        await settle()

        XCTAssertNil(viewModel.receipt, "a payment that landed while the owner was away is not new")
        XCTAssertEqual(wallet.baselineReads, 2, "returning opened a new window")
    }

    func testLeavingReceiveClearsAShownReceipt() async throws {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = try await watchingViewModel(source, wallet)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.setReceiveSurfaceVisible(false)
        viewModel.receiveDidDisappear(pushingReceiveStep: false)

        XCTAssertNil(viewModel.receipt)
    }

    func testPushingAReceiveStepKeepsTheReceiptAndTheWindow() async throws {
        let source = ControlledShieldedAddressSource()
        let wallet = FakeReceiptSources()
        let viewModel = try await watchingViewModel(source, wallet)
        viewModel.acceptReceipt(Self.receipt)

        viewModel.setReceiveSurfaceVisible(false)
        viewModel.receiveDidDisappear(pushingReceiveStep: true)
        viewModel.setReceiveSurfaceVisible(true)
        await settle()

        XCTAssertEqual(viewModel.receipt, Self.receipt, "a pushed receive step is not a leave")
        XCTAssertEqual(wallet.baselineReads, 1, "the window kept its baseline")
    }

    // MARK: - Placeholder retry

    func testNotReadyPlaceholderRetriesWhenShieldedStartsRunning() async throws {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .notReady)
        try await waitUntil("placeholder") { viewModel.shieldedReceiveState == .ready(.notReady) }

        running.send(true)

        try await waitUntil("retried") { source.callCount == 2 }
        source.complete(1, with: .fresh("tdash1fresh-a"))
        try await waitUntil("address") { viewModel.currentAddress == "tdash1fresh-a" }
    }

    func testUnavailablePlaceholderRetriesWhenShieldedStartsRunning() async throws {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .unavailable)
        try await waitUntil("placeholder") { viewModel.shieldedReceiveState == .ready(.unavailable) }

        running.send(true)

        try await waitUntil("retried") { source.callCount == 2 }
    }

    /// Shielded sync starts after the source answered «not ready» but before
    /// that answer is applied: the session must not stay on the placeholder.
    func testShieldedStartingWhileDerivingRetries() async throws {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        XCTAssertEqual(viewModel.shieldedReceiveState, .deriving)

        running.send(true)
        try await waitUntil("retried") { source.callCount == 2 }
        source.complete(0, with: .notReady)
        source.complete(1, with: .fresh("tdash1fresh-a"))

        try await waitUntil("address") { viewModel.currentAddress == "tdash1fresh-a" }
        await settle()
        XCTAssertEqual(viewModel.shieldedReceiveState, .ready(.fresh("tdash1fresh-a")), "the stale answer is dropped")
    }

    func testShieldedStartingNeverReplacesAShownAddress() async throws {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .fallback("tdash1default"))
        try await waitUntil("address") { viewModel.currentAddress == "tdash1default" }

        running.send(true)
        await settle()

        XCTAssertEqual(source.callCount, 1, "the session keeps its address")
        XCTAssertEqual(viewModel.currentAddress, "tdash1default")
    }

    func testShieldedStoppingDoesNotRetry() async throws {
        let source = ControlledShieldedAddressSource()
        let running = PassthroughSubject<Bool, Never>()
        let viewModel = makeViewModel(source: source, shieldedRunning: running.eraseToAnyPublisher())
        viewModel.beginReceiveSession()
        try await waitUntil("request") { source.callCount == 1 }
        source.complete(0, with: .notReady)
        try await waitUntil("placeholder") { viewModel.shieldedReceiveState == .ready(.notReady) }

        running.send(false)
        await settle()

        XCTAssertEqual(source.callCount, 1)
    }
}
