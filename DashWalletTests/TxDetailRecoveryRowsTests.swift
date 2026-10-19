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

        registry.beginFundingCall()
        XCTAssertEqual(recorder.count(of: .inFlightLocks), 1)
        registry.endFundingCall()
        XCTAssertEqual(recorder.count(of: .inFlightLocks), 2)
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
}
