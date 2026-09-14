import Foundation
import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
@testable import dashpay
#else
@testable import ShieldedBalanceHarness
#endif

@MainActor
final class ShieldedBalanceControllerTests: XCTestCase {
    private let wallet = ShieldedBalanceController.Scope(walletId: Data([1]), network: "testnet")

    func testRestoresBeforeAnySyncAndKeepsKnownZeroDistinctFromUnknown() async {
        let controller = ShieldedBalanceController()
        let owner = NSObject()
        XCTAssertNil(controller.state.credits)
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) { .restored(150_000) }
        XCTAssertEqual(controller.state, .restored(150_000))
        XCTAssertTrue(controller.isPrepared)
        controller.accept(credits: 0)
        XCTAssertEqual(controller.state, .refreshed(0))
        XCTAssertTrue(controller.state.isAvailable)
    }

    func testSameWalletManagerRetryPreservesAmountWhenRestoreFails() async {
        let controller = ShieldedBalanceController()
        let first = NSObject(), replacement = NSObject()
        await controller.restore(scope: wallet, owner: ObjectIdentifier(first)) { .restored(200) }
        controller.accept(credits: 175)
        controller.detach()
        XCTAssertEqual(controller.state, .restored(175))
        await controller.restore(scope: wallet, owner: ObjectIdentifier(replacement)) {
            throw NSError(domain: "synthetic", code: 1)
        }
        XCTAssertEqual(controller.state, .restored(175))
        XCTAssertFalse(controller.isPrepared)
        XCTAssertNotNil(controller.lastError)
    }

    func testManagerDetachKeepsRestoreFailureUntilClearOrSuccessfulRead() async {
        let controller = ShieldedBalanceController()
        let owner = NSObject()
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) {
            throw NSError(domain: "restore incomplete", code: 1)
        }
        let failure = controller.lastError
        XCTAssertNotNil(failure)
        controller.detach()
        XCTAssertEqual(controller.lastError, failure)
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) { .restored(0) }
        XCTAssertNil(controller.lastError)
        controller.detach()
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) {
            throw NSError(domain: "restore incomplete", code: 2)
        }
        XCTAssertNotNil(controller.lastError)
        controller.clear()
        XCTAssertNil(controller.lastError)
    }

    func testFailedInitializationCanBeRetriedOnSameManager() async {
        let controller = ShieldedBalanceController()
        let owner = NSObject()
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) {
            throw NSError(domain: "synthetic", code: 1)
        }
        XCTAssertFalse(controller.isPrepared)
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) { .restored(200) }
        XCTAssertEqual(controller.state, .restored(200))
        XCTAssertTrue(controller.isPrepared)
        XCTAssertNil(controller.lastError)
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) {
            XCTFail("A prepared manager must not bind again")
            return .unavailable
        }
    }

    func testNewWalletOrNetworkNeverInheritsOldAmountAfterFailedRead() async {
        let controller = ShieldedBalanceController()
        let owner = NSObject()
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) { .restored(200) }
        for scope in [
            ShieldedBalanceController.Scope(walletId: Data([2]), network: "testnet"),
            ShieldedBalanceController.Scope(walletId: Data([1]), network: "mainnet")
        ] {
            await controller.restore(scope: scope, owner: ObjectIdentifier(owner)) {
                throw NSError(domain: "synthetic", code: 1)
            }
            XCTAssertEqual(controller.state, .unavailable)
        }
    }

    func testNewerSyncWinsOverAnOlderLocalRead() async {
        let controller = ShieldedBalanceController()
        let owner = NSObject()
        let started = expectation(description: "local read started")
        var continuation: CheckedContinuation<ShieldedBalanceState, Never>?
        let load = Task {
            await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        controller.accept(credits: 250)
        continuation?.resume(returning: .restored(100))
        await load.value
        XCTAssertEqual(controller.state, .refreshed(250))
    }

    func testClearedWalletCannotBeRepaintedByUncancellableOldRead() async {
        let controller = ShieldedBalanceController()
        let owner = NSObject()
        let started = expectation(description: "old read started")
        var continuation: CheckedContinuation<ShieldedBalanceState, Never>?
        let load = Task {
            await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        controller.clear()
        let destination = ShieldedBalanceController.Scope(walletId: Data([2]), network: "testnet")
        await controller.restore(scope: destination, owner: ObjectIdentifier(owner)) { .restored(30) }
        continuation?.resume(returning: .restored(999))
        await load.value
        XCTAssertEqual(controller.state, .restored(30))
    }

    private enum SnapshotTestError: Error {
        case bindingChanged, storageFailed
    }

    func testLaunchSnapshotRetriesBothBindDeliveries() async throws {
        var reads = 0
        let amount = try await ShieldedBalanceController.readLocalSnapshot(
            load: {
                reads += 1
                if reads <= 2 { throw SnapshotTestError.bindingChanged }
                return UInt64(123)
            },
            isBindingChange: { ($0 as? SnapshotTestError) == .bindingChanged })
        XCTAssertEqual(amount, 123)
        XCTAssertEqual(reads, 3)
    }

    func testSnapshotBindingChurnIsBounded() async {
        var reads = 0
        do {
            let _: UInt64 = try await ShieldedBalanceController.readLocalSnapshot(
                load: { reads += 1; throw SnapshotTestError.bindingChanged },
                isBindingChange: { ($0 as? SnapshotTestError) == .bindingChanged })
            XCTFail("Repeated binding changes must stop retrying")
        } catch {
            XCTAssertEqual(error as? SnapshotTestError, .bindingChanged)
        }
        XCTAssertEqual(reads, 3)
    }

    func testSnapshotStorageFailureAndScopeCancellationDoNotRetry() async {
        for failure: Error in [SnapshotTestError.storageFailed, CancellationError()] {
            var reads = 0
            do {
                let _: UInt64 = try await ShieldedBalanceController.readLocalSnapshot(
                    load: { reads += 1; throw failure },
                    isBindingChange: { ($0 as? SnapshotTestError) == .bindingChanged })
                XCTFail("Non-bind failures must propagate")
            } catch {
                XCTAssertEqual(reads, 1)
                XCTAssertEqual(error is CancellationError, failure is CancellationError)
            }
        }
    }

    func testCancelledSnapshotDoesNotRetryAReportedBindChange() async {
        let started = expectation(description: "snapshot read started")
        var finish: CheckedContinuation<UInt64, Error>?
        var reads = 0
        let task = Task {
            try await ShieldedBalanceController.readLocalSnapshot(
                load: {
                    reads += 1
                    return try await withCheckedThrowingContinuation {
                        finish = $0
                        started.fulfill()
                    }
                },
                isBindingChange: { ($0 as? SnapshotTestError) == .bindingChanged })
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        finish?.resume(throwing: SnapshotTestError.bindingChanged)
        do {
            _ = try await task.value
            XCTFail("Cancellation must win over binding retry")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(reads, 1)
    }

    func testNoHistoryIsPreparedButDoesNotPublishFalseZero() async {
        let controller = ShieldedBalanceController()
        let owner = NSObject()
        await controller.restore(scope: wallet, owner: ObjectIdentifier(owner)) { .unavailable }
        XCTAssertTrue(controller.isPrepared)
        XCTAssertNil(controller.state.credits)
        controller.accept(credits: 0)
        controller.markStale()
        XCTAssertEqual(controller.state, .restored(0))
    }
}
