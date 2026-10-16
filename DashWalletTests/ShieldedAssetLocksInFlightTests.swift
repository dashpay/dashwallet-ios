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
        registry.beginFundingCall()
        registry.beginFundingCall()
        XCTAssertTrue(registry.hasActivity)

        registry.endFundingCall()
        XCTAssertTrue(registry.hasActivity, "the second call is still running")
        registry.endFundingCall()
        XCTAssertFalse(registry.hasActivity)

        // An extra end must not go below zero: the next call still counts.
        registry.endFundingCall()
        registry.beginFundingCall()
        XCTAssertTrue(registry.hasActivity)
        registry.endFundingCall()
        XCTAssertFalse(registry.hasActivity)
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
