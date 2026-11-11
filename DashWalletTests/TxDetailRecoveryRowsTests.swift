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

/// A model whose swap-order and placeholder lookups never call back, so an
/// open screen rebuilds its rows only on `viewDidLoad` and on the recovery
/// inputs. (The explorer-fee lookup asks nothing for the sent transaction
/// and the placeholder these tests open.)
private final class QuietTxDetailModel: TxDetailModel {
    override func resolveSwapExplorerLink(completion: @escaping () -> Void) {}
    override func observeSwapOrderPlaceholder(onChange: @escaping () -> Void) {}
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
    func testAProbeStoreChangeIsAnnounced() {
        let probes = AssetLockProbeStore.shared
        let wallet = "recoveryInputChangesTest"
        probes.clearForWallet(walletIdHex: wallet)
        let recorder = Recorder(TxDetailModel.recoveryInputChanges(
            lookup: ShieldedTxLookup(), registry: ShieldedAssetLocksInFlight()))

        probes.record(txid: txidWire, vout: 0, walletIdHex: wallet)
        XCTAssertEqual(recorder.count(of: .probes), 1, "recorded")
        probes.clearForWallet(walletIdHex: wallet)
        XCTAssertEqual(recorder.count(of: .probes), 2, "cleared")
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
    /// times, or ten seconds pass, then a little longer so a further rebuild
    /// has a chance to land, and checks it stopped at exactly `count`.
    @MainActor
    private func waitForRebuilds(_ count: Int, of controller: CountingDetailViewController,
                                 _ message: String = "") {
        let deadline = Date().addingTimeInterval(10)
        while controller.rebuilds < count, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(controller.rebuilds, count, message)
    }

    @MainActor
    func testAnOpenScreenRebuildsItsRowsOnEachRecoveryInput() {
        let inputs = PassthroughSubject<Input, Never>()
        let transaction = Transaction(
            syntheticTxid: txidWire, directionRaw: 1, netAmount: -1_000,
            fee: nil, contextRaw: 0, date: Date())
        let controller = CountingDetailViewController(model: QuietTxDetailModel(transaction: transaction))
        controller.recoveryInputs = inputs.eraseToAnyPublisher()
        controller.loadViewIfNeeded()

        continueAfterFailure = false
        // `viewDidLoad` builds the rows once; after that only the inputs
        // rebuild them, once each.
        waitForRebuilds(1, of: controller, "viewDidLoad")
        for (index, input) in [Input.lockLookup, .inFlightLocks, .projection, .probes].enumerated() {
            inputs.send(input)
            waitForRebuilds(2 + index, of: controller, "after \(input)")
        }
    }

    // MARK: - A lock an attempt is crediting

    /// Runs `body` on a transaction whose lock row in the shared lookup is
    /// pending (InstantSend-locked), and puts the lookup back afterwards.
    /// History and the details screen both read the shared lookup.
    @MainActor
    private func withPendingShieldedLock(drain: UUID? = nil, _ body: (Transaction) -> Void) {
        let lookup = ShieldedTxLookup.shared
        let saved = Dictionary(uniqueKeysWithValues: lookup.allEntries().map { ($0.txidHex, $0.info) })
        defer { lookup.store(saved) }
        lookup.store([Transaction.displayHex(txidWire): .init(
            amountDuffs: 1_000, statusRaw: AssetLockStatus.instantSendLocked.rawValue, vout: 0,
            fundingTypeRaw: 5, walletId: Data(repeating: 1, count: 32), drainOperation: drain)])
        body(Transaction(syntheticTxid: txidWire, directionRaw: 1, netAmount: -1_000,
                         fee: nil, contextRaw: 0, date: Date()))
    }

    /// A History row offers "tap to finish" only for a pending lock that no
    /// attempt is crediting (AC-02): a claimed lock, or the Max operation
    /// that built it while it settles, reads as an ordinary transfer.
    @MainActor
    func testAClaimedLockReadsAsInFlightOnHistory() {
        let drain = UUID()
        withPendingShieldedLock(drain: drain) { transaction in
            let registry = ShieldedAssetLocksInFlight()
            let lock = ShieldedAssetLocksInFlight.OutPoint(txidWire: txidWire, vout: 0)
            XCTAssertTrue(transaction.isPendingShieldedTransfer)
            XCTAssertFalse(transaction.isShieldedLockInFlight(in: registry), "nobody is crediting it: tap to finish")

            registry.claim(lock)
            XCTAssertTrue(transaction.isShieldedLockInFlight(in: registry), "an attempt holds the lock")
            registry.release(lock)
            XCTAssertFalse(transaction.isShieldedLockInFlight(in: registry), "released: tap to finish again")

            registry.claimDrain(drain)
            XCTAssertTrue(transaction.isShieldedLockInFlight(in: registry), "the Max operation that built it still holds it")
            registry.releaseDrain(drain)
            XCTAssertFalse(transaction.isShieldedLockInFlight(in: registry))
        }
    }

    /// The details of a lock an attempt is crediting offer no Retry or
    /// Complete Transfer (AC-03); once the attempt releases it, they do.
    @MainActor
    func testTheDetailsOfAClaimedLockOfferNoFinishAction() {
        withPendingShieldedLock { transaction in
            let registry = ShieldedAssetLocksInFlight.shared
            let lock = ShieldedAssetLocksInFlight.OutPoint(txidWire: txidWire, vout: 0)
            let model = QuietTxDetailModel(transaction: transaction)
            XCTAssertNotNil(model.recoveryActions.retry, "a stuck lock offers a finish action")

            registry.claim(lock)
            defer { while registry.contains(lock, drainOperation: nil) { registry.release(lock) } }
            XCTAssertNil(model.recoveryActions.retry, "no Retry or Complete Transfer while an attempt credits it")
            XCTAssertTrue(model.isAssetLockRetryInFlight)

            registry.release(lock)
            XCTAssertNotNil(model.recoveryActions.retry, "released: the finish action is back")
            XCTAssertFalse(model.isAssetLockRetryInFlight)
        }
    }

    @MainActor
    func testUnknownRecoverySuppressesRetryAndRemovalOnThisScreen() {
        withPendingShieldedLock { transaction in
            let model = QuietTxDetailModel(transaction: transaction)
            XCTAssertNotNil(model.recoveryActions.retry)
            model.recordRecoveryOutcome(.submittedAwaitingSync)
            XCTAssertNil(model.recoveryActions.retry)
            XCTAssertFalse(model.recoveryActions.offersRemoval)
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
        return QuietTxDetailModel(swapOrder: BuySwapOrderItem(order: order))
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
        continueAfterFailure = false
        waitForRebuilds(1, of: controller, "viewDidLoad")
        inputs.send(.inFlightLocks)
        waitForRebuilds(2, of: controller, "after inFlightLocks")

        XCTAssertFalse(controller.currentSnapshot.sectionIdentifiers.contains(.recovery))
    }
}
