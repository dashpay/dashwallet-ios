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
final class PlatformBalanceControllerTests: XCTestCase {
    private let scope = PlatformBalanceController.Scope(walletId: Data([1]), network: "testnet")
    private let owner = NSObject()
    private enum Failure: Error { case read }

    func testLocalBalanceIsAvailableWithoutStartingSyncIncludingZero() {
        let controller = PlatformBalanceController()
        XCTAssertNil(controller.state.credits)
        let session = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: session) { 25_000 }
        XCTAssertEqual(controller.state, .available(25_000))
        controller.read(using: session) { 0 }
        XCTAssertEqual(controller.state, .available(0))
    }

    func testFailedFirstReadStaysUnknownAndCanRetry() {
        let controller = PlatformBalanceController()
        let session = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        XCTAssertThrowsError(try controller.read(using: session) { throw Failure.read })
        XCTAssertEqual(controller.state, .unavailable)
        controller.read(using: session) { 42 }
        XCTAssertEqual(controller.state, .available(42))
    }

    func testFailedReadAndManagerReplacementKeepLastKnownAmount() {
        let controller = PlatformBalanceController()
        let first = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: first) { 42 }
        controller.detach()
        XCTAssertEqual(controller.state, .available(42))
        let replacement = NSObject()
        let next = controller.begin(scope: scope, owner: ObjectIdentifier(replacement))
        XCTAssertThrowsError(try controller.read(using: next) { throw Failure.read })
        XCTAssertEqual(controller.state, .available(42))
        XCTAssertFalse(controller.read(using: first) { XCTFail("Old owner must not read"); return 999 })
        controller.read(using: next) { 0 }
        XCTAssertEqual(controller.state, .available(0))
    }

    func testStoppedSessionCannotPublishAfterSameManagerRestarts() {
        let controller = PlatformBalanceController()
        let first = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: first) { 42 }
        controller.detach()
        let next = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        XCTAssertNotEqual(first, next)
        XCTAssertFalse(controller.read(using: first) { XCTFail("Queued delivery must be dropped"); return 0 })
        XCTAssertEqual(controller.state, .available(42))
    }

    func testWalletSwitchClearsOldBalanceAndRejectsOldDelivery() {
        let controller = PlatformBalanceController()
        let first = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: first) { 42 }
        let second = controller.begin(scope: .init(walletId: Data([2]), network: scope.network), owner: ObjectIdentifier(owner))
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertFalse(controller.read(using: first) { 999 })
        controller.read(using: second) { 12 }
        XCTAssertEqual(controller.state, .available(12))
    }

    func testSameWalletOnAnotherNetworkDoesNotReuseAmount() {
        let controller = PlatformBalanceController()
        let first = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: first) { 42 }
        let second = controller.begin(scope: .init(walletId: scope.walletId, network: "mainnet"), owner: ObjectIdentifier(owner))
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertThrowsError(try controller.read(using: second) { throw Failure.read })
        XCTAssertNil(controller.state.credits)
        XCTAssertFalse(controller.isCurrent(first))
    }

    func testClearDoesNotRestorePreClearAmountOnRetryFailure() {
        let controller = PlatformBalanceController()
        let first = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: first) { 42 }
        controller.clear()
        XCTAssertNil(controller.state.credits)
        let next = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        XCTAssertThrowsError(try controller.read(using: next) { throw Failure.read })
        XCTAssertNil(controller.state.credits)
        XCTAssertFalse(controller.read(using: first) { 42 })
    }

    func testInvalidatedReadCannotPublishItsResult() {
        let controller = PlatformBalanceController()
        let session = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        XCTAssertFalse(controller.read(using: session) {
            controller.clear()
            return 42
        })
        XCTAssertEqual(controller.state, .unavailable)
    }

    func testMissingAccountIsDifferentFromReadFailureAndKnownZero() {
        let controller = PlatformBalanceController()
        let session = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: session) { 0 }
        controller.read(using: session) { nil }
        XCTAssertEqual(controller.state, .unavailable)
    }
    func testSuccessfulClearPublishesLocalZeroAndRejectsPreClearEvents() {
        let controller = PlatformBalanceController()
        let original = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: original) { 42 }
        controller.clear()
        let cleared = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: cleared) { 0 }
        XCTAssertEqual(controller.state, .available(0))
        XCTAssertFalse(controller.read(using: original) { 42 })
        XCTAssertThrowsError(try controller.read(using: cleared) { throw Failure.read })
        XCTAssertEqual(controller.state, .available(0))
    }

    func testWalletMaterialChangePreservesOnlyTheSameSelection() {
        let controller = PlatformBalanceController()
        let session = controller.begin(scope: scope, owner: ObjectIdentifier(owner))
        controller.read(using: session) { 42 }
        controller.invalidateUnless(scope: scope)
        XCTAssertEqual(controller.state.credits, 42)
        controller.invalidateUnless(scope: .init(walletId: scope.walletId, network: "another network"))
        XCTAssertNil(controller.state.credits)
        XCTAssertFalse(controller.isCurrent(session))
    }

}
