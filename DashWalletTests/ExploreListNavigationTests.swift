//
//  ExploreListNavigationTests.swift
//  DashWalletTests
//
//  The Explore lists draw DashUIKit's bar in place of the system one. The
//  navigation controller asks whether to hide its bar before the list's view
//  loads, and the bar's leading control follows how the list was shown:
//  back and pop when pushed, close and dismiss when it is a modal root.
//  None of these tests load a list's view. A details screen's "Show all
//  locations" hands its opener's handlers on.
//

import UIKit
import XCTest
@testable import dashpay

@MainActor
final class ExploreListNavigationTests: XCTestCase {

    // MARK: - System bar policy before the view loads

    func testUnloadedAtmListHidesTheSystemBar() {
        let atmList = AtmListViewController()

        XCTAssertFalse(atmList.isViewLoaded)
        XCTAssertTrue(atmList.isNavigationBarHidden)
        XCTAssertTrue(atmList.isBackButtonHidden)
    }

    func testMerchantListWithoutConfigurationKeepsTheSystemBar() {
        let merchantList = MerchantListViewController()

        XCTAssertFalse(merchantList.isNavigationBarHidden)
        XCTAssertFalse(merchantList.isBackButtonHidden)
    }

    func testConfiguredMerchantListHidesTheSystemBar() {
        let merchantList = MerchantListViewController()
        merchantList.customNavBar = .init(title: "Where to Spend", leading: .close, onBack: { }, onInfo: nil)

        XCTAssertFalse(merchantList.isViewLoaded)
        XCTAssertTrue(merchantList.isNavigationBarHidden)
        XCTAssertTrue(merchantList.isBackButtonHidden)
    }

    // MARK: - Leading control

    func testPushedAtmListShowsBack() {
        let navigationController = UINavigationController(rootViewController: UIViewController())
        let atmList = AtmListViewController()
        navigationController.pushViewController(atmList, animated: false)

        XCTAssertEqual(atmList.defaultCustomNavBarLeading, .back)
    }

    func testModalRootAtmListShowsClose() {
        let atmList = AtmListViewController()
        let navigationController = PresentedNavigationController(rootViewController: atmList)
        navigationController.presenter = UIViewController()

        XCTAssertEqual(atmList.defaultCustomNavBarLeading, .close)
    }

    func testRootOfAnUnpresentedStackShowsBack() {
        let atmList = AtmListViewController()
        _ = UINavigationController(rootViewController: atmList)

        XCTAssertEqual(atmList.defaultCustomNavBarLeading, .back)
    }

    // MARK: - Back action

    func testBackFromAPushedListPops() {
        let navigationController = SpyNavigationController(rootViewController: UIViewController())
        let atmList = SpyAtmListViewController()
        navigationController.pushViewController(atmList, animated: false)

        atmList.closeOrPop()

        XCTAssertEqual(navigationController.popCount, 1)
        XCTAssertEqual(atmList.dismissCount, 0)
    }

    func testCloseFromAModalRootDismisses() {
        let atmList = SpyAtmListViewController()
        let navigationController = SpyNavigationController(rootViewController: atmList)

        atmList.closeOrPop()

        XCTAssertEqual(navigationController.popCount, 0)
        XCTAssertEqual(atmList.dismissCount, 1)
    }

    func testCloseWithoutANavigationControllerDismisses() {
        let atmList = SpyAtmListViewController()

        atmList.closeOrPop()

        XCTAssertEqual(atmList.dismissCount, 1)
    }

    // MARK: - Show all locations

    /// A location opened from "Show all locations" completes a payment or a
    /// gift card purchase through the handlers the merchant's details got.
    func testShowAllLocationsCarriesTheDetailsHandlers() {
        let merchant = ExplorePointOfUse.Merchant(merchantId: "1", paymentMethod: .giftCard, type: .physical, deeplink: nil,
                                                  savingsBasisPoints: 0, denominationsType: nil, redeemType: nil)
        let place = ExplorePointOfUse(id: 1, name: "Place", category: .merchant(merchant), active: true, city: nil,
                                      territory: nil, address1: nil, address2: nil, address3: nil, address4: nil,
                                      latitude: nil, longitude: nil, website: nil, phone: nil, logoLocation: nil,
                                      coverImage: nil, source: nil)
        let details = POIDetailsViewController(pointOfUse: place)
        var paid = false
        var sold = false
        var purchasedGiftCard: Data?
        details.payWithDashHandler = { paid = true }
        details.sellDashHandler = { sold = true }
        details.onGiftCardPurchased = { purchasedGiftCard = $0 }

        let allLocations = details.makeAllLocationsController(searchRadius: kDefaultRadius)
        allLocations.payWithDashHandler?()
        allLocations.sellDashHandler?()
        allLocations.onGiftCardPurchased?(Data([1, 2]))

        XCTAssertTrue(paid)
        XCTAssertTrue(sold)
        XCTAssertEqual(purchasedGiftCard, Data([1, 2]))
    }
}

// MARK: - Test doubles

/// Reports a presenter without being presented, so the test never loads the
/// list's view.
private final class PresentedNavigationController: UINavigationController {
    var presenter: UIViewController?

    override var presentingViewController: UIViewController? { presenter }
}

private final class SpyNavigationController: UINavigationController {
    private(set) var popCount = 0

    override func popViewController(animated: Bool) -> UIViewController? {
        popCount += 1
        return nil
    }
}

private final class SpyAtmListViewController: AtmListViewController {
    private(set) var dismissCount = 0

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCount += 1
    }
}
