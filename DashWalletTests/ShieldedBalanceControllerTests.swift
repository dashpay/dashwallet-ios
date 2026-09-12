import Foundation
import XCTest
#if canImport(dashpay)
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
