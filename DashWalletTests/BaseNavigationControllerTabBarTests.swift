//
//  BaseNavigationControllerTabBarTests.swift
//  DashWalletTests
//
//  Only a tab's root screen shows the tab bar: BaseNavigationController marks
//  every controller stacked above the root with `hidesBottomBarWhenPushed`.
//

import UIKit
import XCTest
@testable import dashpay

@MainActor
final class BaseNavigationControllerTabBarTests: XCTestCase {

    func testRootKeepsTheTabBar() {
        let root = UIViewController()
        _ = BaseNavigationController(rootViewController: root)

        XCTAssertFalse(root.hidesBottomBarWhenPushed)
    }

    func testFirstPushOntoAnEmptyStackKeepsTheTabBar() {
        let navigationController = BaseNavigationController(nibName: nil, bundle: nil)
        let root = UIViewController()

        navigationController.pushViewController(root, animated: false)

        XCTAssertFalse(root.hidesBottomBarWhenPushed)
    }

    func testEveryPushAboveTheRootHidesTheTabBar() {
        let root = UIViewController()
        let navigationController = BaseNavigationController(rootViewController: root)
        let first = UIViewController()
        let second = UIViewController()

        navigationController.pushViewController(first, animated: false)
        navigationController.pushViewController(second, animated: false)

        XCTAssertFalse(root.hidesBottomBarWhenPushed)
        XCTAssertTrue(first.hidesBottomBarWhenPushed)
        XCTAssertTrue(second.hidesBottomBarWhenPushed)
    }

    func testSetViewControllersHidesTheTabBarAboveTheFirst() {
        let navigationController = BaseNavigationController(nibName: nil, bundle: nil)
        let root = UIViewController()
        let middle = UIViewController()
        let top = UIViewController()

        navigationController.setViewControllers([root, middle, top], animated: false)

        XCTAssertFalse(root.hidesBottomBarWhenPushed)
        XCTAssertTrue(middle.hidesBottomBarWhenPushed)
        XCTAssertTrue(top.hidesBottomBarWhenPushed)
    }
}
