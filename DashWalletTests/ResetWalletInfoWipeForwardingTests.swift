//
//  ResetWalletInfoWipeForwardingTests.swift
//  DashWalletTests
//
//  The SwiftUI Reset wallet screen is the delegate of the Objective-C
//  recovery-phrase screen it pushes in wipe mode. A completed wipe must reach
//  the caller's DWWipeDelegate (the chain that tears the main UI down to
//  onboarding); a dropped hand-off would leave the user in a wiped wallet UI.
//

import XCTest
@testable import dashpay

@MainActor
final class ResetWalletInfoWipeForwardingTests: XCTestCase {

    private final class WipeDelegateSpy: NSObject, DWWipeDelegate {
        private(set) var didWipeCount = 0

        func didWipeWallet() {
            didWipeCount += 1
        }
    }

    func testCompletedWipeIsForwardedToTheWipeDelegate() {
        let spy = WipeDelegateSpy()
        let controller = ResetWalletInfoHostingController(wipeDelegate: spy)

        controller.recoverViewControllerDidWipe(DWRecoverViewController())

        XCTAssertEqual(spy.didWipeCount, 1)
    }

    func testWipeDelegateIsNotRetained() {
        var spy: WipeDelegateSpy? = WipeDelegateSpy()
        weak var weakSpy = spy
        let controller = ResetWalletInfoHostingController(wipeDelegate: spy)

        spy = nil

        XCTAssertNil(weakSpy, "The controller must hold its wipe delegate weakly, like the Objective-C screen it replaces")
        // With the delegate gone a completed wipe is a no-op, not a crash.
        controller.recoverViewControllerDidWipe(DWRecoverViewController())
    }
}
