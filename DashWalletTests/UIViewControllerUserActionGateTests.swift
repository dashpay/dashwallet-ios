//
//  UIViewControllerUserActionGateTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

@testable import dashwallet
import UIKit
import XCTest

@MainActor
final class UIViewControllerUserActionGateTests: XCTestCase {
    func testActionRemainsExclusiveUntilExplicitlyEnded() {
        let controller = UIViewController()

        XCTAssertTrue(controller.dw_beginExclusiveUserAction())
        XCTAssertFalse(controller.dw_beginExclusiveUserAction())

        controller.dw_endExclusiveUserAction()

        XCTAssertTrue(controller.dw_beginExclusiveUserAction())
    }

    func testEachControllerHasAnIndependentGate() {
        let first = UIViewController()
        let second = UIViewController()

        XCTAssertTrue(first.dw_beginExclusiveUserAction())
        XCTAssertTrue(second.dw_beginExclusiveUserAction())
        XCTAssertFalse(first.dw_beginExclusiveUserAction())
        XCTAssertFalse(second.dw_beginExclusiveUserAction())
    }
}
