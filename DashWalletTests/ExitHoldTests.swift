//
//  ExitHoldTests.swift
//  DashWalletTests
//
//  ExitHold is shared ownership of two UIKit flags — a navigation stack's
//  edge-swipe gesture and a presented root's `isModalInPresentation` — by the
//  payment screens (`lockingExit`) and `PaymentController`. These pin the
//  counting: overlapping owners in either release order, repeated releases,
//  restoring an original value that was already locked, and independence of
//  separate stacks and roots. `PaymentInFlight` follows the same holds.
//

import UIKit
import XCTest
@testable import dashpay

@MainActor
final class ExitHoldTests: XCTestCase {
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: UIScreen.main.bounds)
    }

    override func tearDown() {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makeStack() -> (UINavigationController, UIViewController) {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(screen, animated: false)
        navigation.loadViewIfNeeded()
        return (navigation, screen)
    }

    private func gesture(of navigation: UINavigationController) -> Bool {
        navigation.interactivePopGestureRecognizer?.isEnabled ?? false
    }

    func testOverlappingHoldsKeepTheGestureClosedUntilTheLastReleaseInEitherOrder() {
        for releaseFirstHoldFirst in [true, false] {
            let (navigation, screen) = makeStack()
            XCTAssertTrue(gesture(of: navigation))

            let first = ExitHold(on: screen)
            let second = ExitHold(on: screen)
            XCTAssertFalse(gesture(of: navigation))

            (releaseFirstHoldFirst ? first : second).release()
            XCTAssertFalse(gesture(of: navigation), "one owner still holds it")

            (releaseFirstHoldFirst ? second : first).release()
            XCTAssertTrue(gesture(of: navigation), "the last release restores it")
        }
    }

    func testARepeatedReleaseDoesNotFreeAnotherOwnersHold() {
        let (navigation, screen) = makeStack()
        let first = ExitHold(on: screen)
        let second = ExitHold(on: screen)

        first.release()
        first.release()
        XCTAssertFalse(gesture(of: navigation), "the second owner's hold survives the repeat")

        second.release()
        XCTAssertTrue(gesture(of: navigation))
    }

    func testAnOriginallyDisabledGestureIsRestoredDisabled() {
        let (navigation, screen) = makeStack()
        navigation.interactivePopGestureRecognizer?.isEnabled = false

        let hold = ExitHold(on: screen)
        hold.release()

        XCTAssertFalse(gesture(of: navigation))
    }

    func testSeparateStacksAreHeldIndependently() {
        let (firstNavigation, firstScreen) = makeStack()
        let (secondNavigation, secondScreen) = makeStack()

        let first = ExitHold(on: firstScreen)
        let second = ExitHold(on: secondScreen)
        first.release()

        XCTAssertTrue(gesture(of: firstNavigation))
        XCTAssertFalse(gesture(of: secondNavigation))

        second.release()
        XCTAssertTrue(gesture(of: secondNavigation))
    }

    func testAPresentedRootIsHeldModalAndAnOriginallyModalOneStaysModal() {
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()

        let (navigation, screen) = makeStack()
        presenter.present(navigation, animated: false)
        XCTAssertNotNil(navigation.presentingViewController)
        XCTAssertFalse(navigation.isModalInPresentation)

        let first = ExitHold(on: screen)
        let second = ExitHold(on: screen)
        XCTAssertTrue(navigation.isModalInPresentation)
        second.release()
        XCTAssertTrue(navigation.isModalInPresentation, "one owner still holds it")
        first.release()
        XCTAssertFalse(navigation.isModalInPresentation)

        navigation.isModalInPresentation = true
        let third = ExitHold(on: screen)
        third.release()
        XCTAssertTrue(navigation.isModalInPresentation, "an originally modal root stays modal")
    }

    func testPaymentInFlightFollowsTheHoldsAndAnnouncesTheEndOnce() {
        let (_, screen) = makeStack()
        XCTAssertFalse(PaymentInFlight.isActive)

        let endings = Endings()
        let observer = NotificationCenter.default.addObserver(
            forName: PaymentInFlight.didEndNotification, object: nil, queue: nil) { _ in endings.count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let first = ExitHold(on: screen)
        let second = ExitHold(on: screen)
        XCTAssertTrue(PaymentInFlight.isActive)

        first.release()
        first.release()
        XCTAssertTrue(PaymentInFlight.isActive)
        XCTAssertEqual(endings.count, 0)

        second.release()
        XCTAssertFalse(PaymentInFlight.isActive)
        XCTAssertEqual(endings.count, 1)
    }
}

/// The notification is posted synchronously on the main thread.
private final class Endings: @unchecked Sendable {
    var count = 0
}
