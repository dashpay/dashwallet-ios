//
//  PaymentLinkRoutingTests.swift
//  DashWalletTests
//
//  A link never destroys what is on screen. While a send waits on the network
//  (`PaymentInFlightHold`, ending exactly once, also when dropped), for
//  `PaymentInFlight.resultGracePeriod` after it, or while anything is
//  presented in the chain the router would dismiss, a link that would replace
//  the screen is refused with a notice and not kept.
//

import UIKit
import XCTest
@testable import dashpay

@MainActor
final class PaymentLinkRoutingTests: XCTestCase {
    private var window: UIWindow!
    private var notices = 0
    private var realNotice: (() -> Void)!

    override func setUp() {
        super.setUp()
        PaymentInFlight.abandonHolds()
        realNotice = PaymentInFlight.showRefusalNotice
        PaymentInFlight.showRefusalNotice = { [unowned self] in self.notices += 1 }
        // Attached to the host app's scene: presentations only run for a
        // window that is really on screen.
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = .alert + 1
    }

    override func tearDown() {
        PaymentInFlight.abandonHolds()
        PaymentInFlight.showRefusalNotice = realNotice
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// The window's root holding a tab bar with a navigation stack, as the
    /// app's root holds its main screen.
    private func showMainScreen() -> (root: UIViewController, tabScreen: UIViewController) {
        let root = UIViewController()
        let tabScreen = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [UINavigationController(rootViewController: tabScreen)]
        root.addChild(tabs)
        root.view.addSubview(tabs.view)
        tabs.didMove(toParent: root)
        window.rootViewController = root
        window.makeKeyAndVisible()
        return (root, tabScreen)
    }

    // MARK: Holds

    func testAHoldEndsOnceAndAlsoWhenItsOwnerDropsIt() {
        let hold = PaymentInFlightHold()
        let other = PaymentInFlightHold()
        hold.end()
        hold.end()
        XCTAssertTrue(PaymentInFlight.isActive, "a repeated end does not end another hold")
        other.end()
        XCTAssertFalse(PaymentInFlight.isActive)

        var dropped: PaymentInFlightHold? = PaymentInFlightHold()
        XCTAssertTrue(PaymentInFlight.isActive)
        XCTAssertNotNil(dropped)
        dropped = nil
        XCTAssertFalse(PaymentInFlight.isActive, "a dropped hold ends")
    }

    func testATeardownAbandonsHoldsWithoutAGracePeriodAndTheirLateEndsChangeNothing() {
        var old: PaymentInFlightHold? = PaymentInFlightHold()
        PaymentInFlight.abandonHolds()
        XCTAssertFalse(PaymentInFlight.isActiveOrSettling, "a wipe or network switch ends them at once")

        let fresh = PaymentInFlightHold()
        old?.end()
        old = nil
        XCTAssertTrue(PaymentInFlight.isActive, "an abandoned hold ending late does not end a new one")
        fresh.end()
        XCTAssertFalse(PaymentInFlight.isActive)
    }

    func testAHeldNetworkWaitHoldsForTheWaitAndStartsTheResultsGrace() async throws {
        let result = try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: true) { () -> Int in
            XCTAssertTrue(PaymentInFlight.isActive, "held while the send waits")
            return 7
        }
        XCTAssertEqual(result, 7)
        XCTAssertFalse(PaymentInFlight.isActive, "ended with the wait")
        XCTAssertTrue(PaymentInFlight.isActiveOrSettling, "the result's way to the screen is still covered")

        do {
            _ = try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: true) { () -> Int in
                throw CancellationError()
            }
            XCTFail("the failure reaches the caller")
        } catch is CancellationError {}
        XCTAssertFalse(PaymentInFlight.isActive, "a failed wait ends its hold too")
    }

    func testAnUnheldNetworkWaitHoldsNothing() async throws {
        _ = try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: false) { () -> Int in
            XCTAssertFalse(PaymentInFlight.isActive, "a background send does not refuse links")
            return 1
        }
        XCTAssertFalse(PaymentInFlight.isActiveOrSettling)
    }

    // MARK: The router's rule

    func testALinkIsRoutedWhenNothingIsPresentedAndNothingIsInFlight() {
        let (root, _) = showMainScreen()
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root))
        XCTAssertEqual(notices, 0)
    }

    func testALinkIsRefusedDuringASendAndItsResultsGraceThenRoutedAndNothingIsReplayed() {
        let (root, _) = showMainScreen()
        let send = PaymentInFlightHold()
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "refused while the send waits")
        send.end()
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "refused while its result may still be on its way")
        XCTAssertEqual(notices, 2, "each refusal says so")

        spin(until: { !PaymentInFlight.isActiveOrSettling }, timeout: PaymentInFlight.resultGracePeriod + 2)
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root), "routed once the grace has passed")
        XCTAssertEqual(notices, 2, "nothing refused earlier is kept or replayed")
    }

    func testALinkIsRefusedWhileAnythingThatRoutingWouldDismissIsPresented() {
        let (root, tabScreen) = showMainScreen()
        let sheet = UIViewController()
        var shown = false
        // From a screen deep in a tab, like a success screen or a sheet over a
        // payment screen: the presentation lands at the root.
        tabScreen.present(sheet, animated: false) { shown = true }
        spin(until: { shown })
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "refused over a presented screen")

        let alert = UIAlertController(title: "Done", message: nil, preferredStyle: .alert)
        var alertShown = false
        sheet.present(alert, animated: false) { alertShown = true }
        spin(until: { alertShown })
        XCTAssertTrue(PaymentInFlight.refusesLink(over: root), "and over an alert on top of it")

        var dismissed = false
        root.dismiss(animated: false) { dismissed = true }
        spin(until: { dismissed })
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root), "routed again once nothing is presented")
    }

    func testAPresentationKeptInsideAScreensOwnContextDoesNotRefuseALink() {
        let (root, tabScreen) = showMainScreen()
        // A screen that defines its own presentation context, as some tab
        // screens do: the router's dismissal never reaches what it presents.
        tabScreen.definesPresentationContext = true
        let local = UIViewController()
        local.modalPresentationStyle = .currentContext
        var shown = false
        tabScreen.present(local, animated: false) { shown = true }
        spin(until: { shown })
        XCTAssertFalse(PaymentInFlight.refusesLink(over: root))
    }

    func testOnlyLinksThatReplaceTheScreenAreSubjectToTheRule() throws {
        func replacesScreen(_ className: String) throws -> Bool {
            let type = try XCTUnwrap(NSClassFromString(className) as? NSObject.Type, className)
            return try XCTUnwrap(type.init().value(forKey: "replacesScreen") as? Bool)
        }
        XCTAssertTrue(try replacesScreen("DWURLPayAction"))
        XCTAssertTrue(try replacesScreen("DWURLScanQRAction"))
        XCTAssertTrue(try replacesScreen("DWURLDashConnectAction"))
        XCTAssertFalse(try replacesScreen("DWURLIntegrationAction"), "a sign-in callback must not wait")
        XCTAssertFalse(try replacesScreen("DWURLRequestAction"), "an address request replaces nothing")
    }
}
