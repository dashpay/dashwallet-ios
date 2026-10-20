//
//  ShieldedAssetLocksInFlightTests.swift
//  DashWalletTests
//
//  Ownership of the asset locks a running transfer is consuming (#1042 /
//  PR #1212). A fresh transfer's lock is claimed by the SDK's built-lock
//  callback on the FFI worker thread; the coordinator takes that claim over
//  when the call returns, and leaving the in-flight phases releases it. A
//  lock that is still claimed must refuse a second attempt.
//

import Combine
import XCTest
import SwiftDashSDK
@testable import dashpay

final class ShieldedAssetLocksInFlightTests: XCTestCase {

    private typealias OutPoint = ShieldedAssetLocksInFlight.OutPoint

    private let lockA = OutPoint(txidWire: Data(repeating: 0xA1, count: 32), vout: 0)
    private let lockB = OutPoint(txidWire: Data(repeating: 0xB2, count: 32), vout: 0)

    /// The tests run inside the app, which reads `shared`. Drop whatever a
    /// failed assertion left claimed there so it can't leak into the app or
    /// the next test.
    override func tearDown() {
        let shared = ShieldedAssetLocksInFlight.shared
        let locks = [lockA, lockB]
        MainActor.assumeIsolated {
            for lock in locks {
                while shared.contains(lock) { shared.release(lock) }
            }
        }
        super.tearDown()
    }

    // MARK: - Core Sync's pending list

    /// The Core Sync screen keeps its pending list in state and re-reads it
    /// on these emissions, so a lock whose running attempt fails while the
    /// screen is up comes back on it, and one probed already spent leaves.
    @MainActor
    func testThePendingListIsAnnouncedWhenARunningAttemptReleasesItsLock() {
        let registry = ShieldedAssetLocksInFlight()
        let lookup = ShieldedTxLookup()
        let probes = AssetLockProbeStore.shared
        let probeWallet = "pendingRecoveriesChangesTest"
        // A run killed before its cleanup leaves the probe filed, and a
        // repeat record posts nothing.
        probes.clearForWallet(walletIdHex: probeWallet)
        defer { probes.clearForWallet(walletIdHex: probeWallet) }
        var emissions = 0
        let subscription = AssetLockRecoveryService
            .pendingRecoveriesChanges(lookup: lookup, registry: registry, probes: probes)
            .sink { emissions += 1 }
        /// Runs the main queue until `count` emissions, then a little longer
        /// so a further one has a chance to land.
        func drain(until count: Int) {
            let deadline = Date().addingTimeInterval(10)
            while emissions < count, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        registry.claim(lockA)
        drain(until: 1)
        XCTAssertEqual(emissions, 1, "the attempt claimed its lock")

        registry.release(lockA)
        drain(until: 2)
        XCTAssertEqual(emissions, 2, "the attempt failed and released it")

        lookup.markConsumed(txidWire: lockB.txidWire)
        drain(until: 3)
        XCTAssertEqual(emissions, 3, "the lookup changed")

        probes.record(txid: lockA.txidWire, walletIdHex: probeWallet)
        drain(until: 4)
        XCTAssertEqual(emissions, 4, "the lock was probed already spent")

        probes.clearForWallet(walletIdHex: probeWallet)
        drain(until: 5)
        XCTAssertEqual(emissions, 5, "the probes were cleared")
        subscription.cancel()
    }

    // MARK: - Registry

    @MainActor
    func testClaimsAreCountedPerLock() {
        let registry = ShieldedAssetLocksInFlight()
        registry.claim(lockA)
        registry.claim(lockA)

        registry.release(lockA)
        XCTAssertTrue(registry.contains(lockA), "one claim is still held")

        registry.release(lockA)
        XCTAssertFalse(registry.contains(lockA))
        XCTAssertFalse(registry.hasActivity)
    }

    @MainActor
    func testLocksAreIndependent() {
        let registry = ShieldedAssetLocksInFlight()
        registry.claim(lockA)

        XCTAssertFalse(registry.contains(lockB))
        XCTAssertTrue(registry.containsTransaction(txidWire: lockA.txidWire))
        XCTAssertFalse(registry.containsTransaction(txidWire: lockB.txidWire))

        registry.release(lockB)
        XCTAssertTrue(registry.contains(lockA), "releasing another lock leaves this claim")
    }

    @MainActor
    func testBuiltLockClaimIsVisibleBeforeItsPublication() {
        let registry = ShieldedAssetLocksInFlight()
        let published = expectation(description: "objectWillChange on the main queue")
        let subscription = registry.objectWillChange.sink {
            XCTAssertTrue(Thread.isMainThread, "SwiftUI observers must hear the change on main")
            published.fulfill()
        }

        let claimedOnWorker = expectation(description: "claim on a worker thread")
        DispatchQueue.global().async {
            registry.claimBuiltLock(self.lockA)
            // The SDK persists the lock's row right after the callback
            // returns, so the claim must already be readable here.
            XCTAssertTrue(registry.contains(self.lockA))
            claimedOnWorker.fulfill()
        }

        wait(for: [claimedOnWorker, published], timeout: 2)
        subscription.cancel()
        registry.release(lockA)
        XCTAssertFalse(registry.contains(lockA))
    }

    @MainActor
    func testFundingCallsCountAsActivityBeforeAnyLockExists() {
        let registry = ShieldedAssetLocksInFlight()
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertTrue(registry.hasActivity)

        registry.endFundingCall()
        XCTAssertTrue(registry.hasActivity, "the second call is still running")
        registry.endFundingCall()
        XCTAssertFalse(registry.hasActivity)

        // An extra end must not go below zero: the next call still counts.
        registry.endFundingCall()
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertTrue(registry.hasActivity)
        registry.endFundingCall()
        XCTAssertFalse(registry.hasActivity)
    }

    @MainActor
    func testARemovalIsAdmittedOnlyWithoutActivityAndHoldsOffTransfers() {
        let registry = ShieldedAssetLocksInFlight()
        registry.claim(lockA)
        XCTAssertEqual(registry.beginRemoval(), .transferActive, "a lock is being consumed")
        registry.release(lockA)
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertEqual(registry.beginRemoval(), .transferActive, "a fresh transfer is running")
        registry.endFundingCall()

        // Screens offering a removal or a retry rebuild when the hold starts
        // and when it ends.
        var published = 0
        let subscription = registry.objectWillChange.sink { published += 1 }
        defer { subscription.cancel() }

        XCTAssertEqual(registry.beginRemoval(), .admitted)
        XCTAssertEqual(published, 1)
        XCTAssertTrue(registry.isRemovalInProgress)
        XCTAssertEqual(registry.beginRemoval(), .removalHeld, "one removal at a time")
        XCTAssertFalse(registry.beginFundingCall(), "no transfer starts during the reload")
        XCTAssertFalse(registry.hasActivity, "a refused funding call is not counted")
        XCTAssertEqual(registry.admitResume(lockA), .walletReloading)
        XCTAssertFalse(registry.contains(lockA), "a refused resume claims nothing")

        registry.endRemoval()
        XCTAssertEqual(published, 2)
        XCTAssertFalse(registry.isRemovalInProgress)
        XCTAssertTrue(registry.beginFundingCall())
        registry.endFundingCall()
    }

    @MainActor
    func testAResumeClaimsALockOnlyWhileNoOtherAttemptHasIt() {
        let registry = ShieldedAssetLocksInFlight()
        XCTAssertEqual(registry.admitResume(lockA), .admitted)
        XCTAssertTrue(registry.contains(lockA))
        XCTAssertEqual(registry.admitResume(lockA), .claimedElsewhere)
        XCTAssertEqual(registry.admitResume(lockB), .admitted, "another lock is independent")

        registry.release(lockA)
        registry.release(lockB)
        XCTAssertFalse(registry.hasActivity, "the refused resume added no claim")
    }

    // MARK: - Coordinator

    @MainActor
    func testResumeOfAClaimedLockIsRefused() async throws {
        ShieldedAssetLocksInFlight.shared.claim(lockA)
        defer { ShieldedAssetLocksInFlight.shared.release(lockA) }
        let coordinator = ShieldedTransferCoordinator()
        let lock = lockA

        // Not awaited: an admitted resume would go on to the PIN prompt and
        // never return, so the test waits for the refusal with a deadline.
        Task { await coordinator.resumeAssetLock(outPointTxidWire: lock.txidWire, outPointVout: lock.vout) }
        let deadline = Date().addingTimeInterval(2)
        while coordinator.phase == .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        guard case .failed = coordinator.phase else {
            return XCTFail("expected a refusal, got \(coordinator.phase)")
        }
        guard case .assetLockInFlight? = coordinator.lastFailure as? ShieldedTransferCoordinator.CoordinatorError else {
            return XCTFail("expected assetLockInFlight, got \(String(describing: coordinator.lastFailure))")
        }
        XCTAssertTrue(ShieldedAssetLocksInFlight.shared.contains(lockA), "the refusal must not release the running claim")
    }

    @MainActor
    func testResumeIsRefusedWhileARemovalReloadsTheWallet() async throws {
        let registry = ShieldedAssetLocksInFlight.shared
        guard registry.beginRemoval() == .admitted else {
            return XCTFail("the shared registry has activity left over")
        }
        defer { registry.endRemoval() }
        let coordinator = ShieldedTransferCoordinator()
        let lock = lockA

        // Not awaited: an admitted resume would go on to the PIN prompt and
        // never return, so the test waits for the refusal with a deadline.
        Task { await coordinator.resumeAssetLock(outPointTxidWire: lock.txidWire, outPointVout: lock.vout) }
        let deadline = Date().addingTimeInterval(2)
        while coordinator.phase == .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        guard case .walletReloading? = coordinator.lastFailure as? ShieldedTransferCoordinator.CoordinatorError else {
            return XCTFail("expected walletReloading, got \(String(describing: coordinator.lastFailure))")
        }
        XCTAssertFalse(registry.contains(lockA), "a refused resume claims nothing")
    }

    @MainActor
    func testFinishTakesOverTheBuiltLockClaimWithoutASecondOne() {
        let registry = ShieldedAssetLocksInFlight.shared
        let coordinator = ShieldedTransferCoordinator()
        let capture = NewAssetLockCapture(initialState: nil)
        registry.claimBuiltLock(lockB)
        capture.withLock { $0 = lockB }

        coordinator.finishNewAssetLock(capture)
        XCTAssertTrue(registry.contains(lockB))
        XCTAssertNil(coordinator.lastAssetLockOutPoint, "success does not arm Try again")

        // Leaving the in-flight phases releases it, and one release frees it:
        // the coordinator took over the callback's claim without adding one.
        coordinator.reset()
        XCTAssertFalse(registry.contains(lockB))
    }

    @MainActor
    func testFailureArmsTryAgainUnlessTheBroadcastWasRejected() {
        let registry = ShieldedAssetLocksInFlight.shared

        for (failure, armed) in [
            (PlatformWalletError.transactionBroadcastUnconfirmed("timeout") as Error, true),
            (PlatformWalletError.walletOperation("proof wait failed") as Error, true),
            (PlatformWalletError.transactionBroadcastRejected("bad-txns") as Error, false),
        ] {
            let coordinator = ShieldedTransferCoordinator()
            let capture = NewAssetLockCapture(initialState: nil)
            registry.claimBuiltLock(lockA)
            capture.withLock { $0 = lockA }

            coordinator.finishNewAssetLock(capture, armingRetryAfter: failure)

            XCTAssertEqual(ShieldedTransferCoordinator.keepsLockForRetry(after: failure), armed, "\(failure)")
            XCTAssertEqual(coordinator.lastAssetLockOutPoint, armed ? lockA : nil, "\(failure)")
            coordinator.reset()
            XCTAssertFalse(registry.contains(lockA), "\(failure)")
        }
    }
}
