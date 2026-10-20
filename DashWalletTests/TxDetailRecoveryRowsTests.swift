//
//  TxDetailRecoveryRowsTests.swift
//  DashWalletTests
//
//  What makes an already-open transaction detail screen rebuild its
//  recovery rows, and when those rows offer the local removal (#1042 /
//  PR #1212): a transfer that just completed must not keep offering to
//  finish it, and a failed attempt must offer it again.
//

import Combine
import XCTest
@testable import dashpay

/// Counts row rebuilds: `reloadDataSource()` starts each one by assigning an
/// empty snapshot.
private final class CountingDetailViewController: TXDetailViewController {
    private(set) var rebuilds = 0

    override var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>! {
        didSet {
            if currentSnapshot?.numberOfSections == 0 { rebuilds += 1 }
        }
    }
}

final class TxDetailRecoveryRowsTests: XCTestCase {

    private typealias Input = TxDetailModel.RecoveryInput
    private typealias Retry = TxDetailModel.StuckAssetLockRetry

    private let txidWire = Data((0..<32).map { UInt8(0x40 + $0) })

    /// Records what the registry and the lookup emit through
    /// `recoveryInputChanges`; they publish on main, where the tests read.
    /// App-wide projection changes, which the host may post from any
    /// thread, are left out.
    private final class Recorder {
        private(set) var inputs: [Input] = []
        private var subscription: AnyCancellable?

        init(_ publisher: AnyPublisher<Input, Never>) {
            subscription = publisher
                .filter { $0 != .projection }
                .sink { [unowned self] in inputs.append($0) }
        }

        func count(of input: Input) -> Int { inputs.filter { $0 == input }.count }
    }

    // MARK: - Triggers

    @MainActor
    func testTheScreensLookupAnnouncesACompletedTransfer() {
        let lookup = ShieldedTxLookup()
        let recorder = Recorder(TxDetailModel.recoveryInputChanges(
            lookup: lookup, registry: ShieldedAssetLocksInFlight()))

        lookup.markConsumed(txidWire: txidWire)
        XCTAssertEqual(recorder.count(of: .lockLookup), 1)

        // Another lookup's changes are not this screen's.
        ShieldedTxLookup().markConsumed(txidWire: txidWire)
        XCTAssertEqual(recorder.count(of: .lockLookup), 1)
    }

    @MainActor
    func testAClaimAndItsReleaseAreAnnounced() {
        let registry = ShieldedAssetLocksInFlight()
        let recorder = Recorder(TxDetailModel.recoveryInputChanges(
            lookup: ShieldedTxLookup(), registry: registry))
        let lock = ShieldedAssetLocksInFlight.OutPoint(txidWire: txidWire, vout: 0)

        registry.claim(lock)
        XCTAssertEqual(recorder.count(of: .inFlightLocks), 1, "an attempt started")
        registry.release(lock)
        XCTAssertEqual(recorder.count(of: .inFlightLocks), 2, "the attempt ended")
    }

    @MainActor
    func testALockClaimedOnTheFFIThreadIsAnnouncedOnMain() {
        // A fresh transfer's lock is claimed from the SDK's worker thread,
        // and the registry publishes that claim on the main queue.
        let registry = ShieldedAssetLocksInFlight()
        let announced = expectation(description: "the built lock's claim is announced")
        // App-wide projection changes may arrive meanwhile; only the
        // registry's emission is this test's.
        let subscription = TxDetailModel.recoveryInputChanges(
            lookup: ShieldedTxLookup(), registry: registry
        )
        .filter { $0 == .inFlightLocks }
        .sink { _ in
            XCTAssertTrue(Thread.isMainThread)
            announced.fulfill()
        }
        let lock = ShieldedAssetLocksInFlight.OutPoint(txidWire: txidWire, vout: 0)
        DispatchQueue.global().async { registry.claimBuiltLock(lock) }

        wait(for: [announced], timeout: 2)
        subscription.cancel()
        registry.release(lock)
    }

    @MainActor
    func testAFundingCallStartingAndEndingIsAnnounced() {
        // A fresh transfer counts as active before any lock exists, which
        // hides the removal row.
        let registry = ShieldedAssetLocksInFlight()
        let recorder = Recorder(TxDetailModel.recoveryInputChanges(
            lookup: ShieldedTxLookup(), registry: registry))

        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertEqual(recorder.count(of: .inFlightLocks), 1)
        registry.endFundingCall()
        XCTAssertEqual(recorder.count(of: .inFlightLocks), 2)
    }

    // MARK: - Open screen

    /// Runs the main queue until `controller` has rebuilt its rows `count`
    /// times, or ten seconds pass (the swap-order lookup reads a database).
    @MainActor
    private func waitForRebuilds(_ count: Int, of controller: CountingDetailViewController) {
        let deadline = Date().addingTimeInterval(10)
        while controller.rebuilds < count, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertGreaterThanOrEqual(controller.rebuilds, count, "rebuilds")
    }

    @MainActor
    func testAnOpenScreenRebuildsItsRowsOnEachRecoveryInput() {
        let inputs = PassthroughSubject<Input, Never>()
        let transaction = Transaction(
            syntheticTxid: txidWire, directionRaw: 1, netAmount: -1_000,
            fee: nil, contextRaw: 0, date: Date())
        let controller = CountingDetailViewController(model: TxDetailModel(transaction: transaction))
        controller.recoveryInputs = inputs.eraseToAnyPublisher()
        controller.loadViewIfNeeded()

        // `viewDidLoad` builds the rows. Its swap-order lookup rebuilds them
        // again only if it finds a link, so each input is checked by what it
        // adds to the count.
        waitForRebuilds(1, of: controller)

        for input in [Input.lockLookup, .inFlightLocks, .projection] {
            let before = controller.rebuilds
            inputs.send(input)
            waitForRebuilds(before + 1, of: controller)
        }
    }

    // MARK: - Removal

    func testRemovalForEachState() {
        let broadcast = Retry(fundingTypeRaw: 5, statusRaw: 1, vout: 0)
        let locked = Retry(fundingTypeRaw: 5, statusRaw: 2, vout: 0)
        func removal(_ retry: Retry?, active: Bool, inMempool: Bool) -> Bool {
            TxDetailModel.offersUnconfirmedRemoval(
                retry: retry, transferActive: active, isInMempool: inMempool)
        }

        XCTAssertTrue(removal(broadcast, active: false, inMempool: true),
                      "a failed attempt offers it again")
        XCTAssertFalse(removal(broadcast, active: true, inMempool: true),
                       "the remover refuses while a transfer is active")
        XCTAssertFalse(removal(locked, active: false, inMempool: true),
                       "a locked lock is proven on-chain, even if the local context reads mempool")
        XCTAssertTrue(removal(nil, active: false, inMempool: true),
                      "a stuck mempool send")
        XCTAssertFalse(removal(nil, active: true, inMempool: true),
                       "not while a transfer is active")
        XCTAssertFalse(removal(nil, active: false, inMempool: false),
                       "nothing stuck in mempool")
    }

    // MARK: - Buy swap placeholder

    private func placeholderModel() -> TxDetailModel {
        let order = SwapOrder(
            id: "0xdeposit",
            direction: "buy",
            service: "swapkit",
            fromAsset: "ARB.USDT-0XFD086BC7",
            toAsset: "DASH",
            toAddress: "XdestinationAddress",
            depositAddress: "0xdeposit",
            expectedToAmount: "2.51",
            status: .notStarted,
            outboundTxHash: nil,
            timestamp: Int64(Date().timeIntervalSince1970) * 1000,
            finalisedAt: -1,
            fromAmount: "150",
            depositSeenAt: nil,
            providerDeniedAt: nil,
            depositMemo: "",
            ownerWalletId: "aa11",
            ownerNetwork: "0")
        return TxDetailModel(swapOrder: BuySwapOrderItem(order: order))
    }

    /// A Buy order shown before its deposit is on chain stands on a
    /// `.processing` placeholder transaction, which is nothing to retry or
    /// remove.
    func testABuySwapPlaceholderOffersNoRecoveryAction() {
        let actions = placeholderModel().recoveryActions
        XCTAssertNil(actions.retry)
        XCTAssertFalse(actions.offersRemoval)
    }

    /// A placeholder screen has no tax category section, after which the
    /// recovery section would be inserted.
    @MainActor
    func testAnOpenBuySwapPlaceholderScreenBuildsNoRecoverySection() {
        let inputs = PassthroughSubject<Input, Never>()
        let controller = CountingDetailViewController(model: placeholderModel())
        controller.recoveryInputs = inputs.eraseToAnyPublisher()
        controller.loadViewIfNeeded()
        waitForRebuilds(1, of: controller)
        let before = controller.rebuilds
        inputs.send(.inFlightLocks)
        waitForRebuilds(before + 1, of: controller)

        XCTAssertFalse(controller.currentSnapshot.sectionIdentifiers.contains(.recovery))
    }
}
