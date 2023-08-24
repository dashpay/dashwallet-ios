//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit

// MARK: - MainTabbarTabs

private enum MainTabbarTabs: Int, CaseIterable {
    case home
    case payment
    case more
}

extension MainTabbarTabs {
    var isEmpty: Bool {
        self == .payment
    }

    var icon: UIImage {
        let name: String

        switch self {
        case .home:
            name = "tabbar_home_icon"
        case .payment:
            return UIImage()
        case .more:
            name = "tabbar_other_icon"
        }

        return UIImage(named: name)!
    }
}

// MARK: - MainTabbarController

@objc
class MainTabbarController: UITabBarController {
    static let kAnimationDuration: TimeInterval = 0.35

    weak var homeController: DWHomeViewController?
    // weak var contactsNavigationController: DWContacts?
    weak var menuNavigationController: DWMainMenuViewController?

    // TODO: Refactor this and send notification about wiped wallet instead of chaining the delegate
    @objc
    weak var wipeDelegate: DWWipeDelegate?

    private var paymentButton: PaymentButton!

    @objc
    var isDemoMode = false

    @objc
    weak var demoDelegate: DWDemoDelegate?

    // TODO: Move it out from here and initialize the model inside home view controller
    @objc
    var homeModel: DWHomeProtocol!

    @objc
    init(homeModel: DWHomeProtocol) {
        super.init(nibName: nil, bundle: nil)

        self.homeModel = homeModel
        configureControllers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Actions

    @objc
    private func paymentButtonAction() {
        showPaymentsController(withActivePage: .none)
    }

    // MARK: Life Cycle

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        tabBar.addSubview(paymentButton)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        configureHierarchy()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Add Payment Button again to make sure it's at the top
        tabBar.addSubview(paymentButton)
    }
}

// MARK: - Private
extension MainTabbarController {
    private func configureControllers() {
        var viewControllers: [UIViewController] = []

        // Home
        var item = UITabBarItem(title: nil, image: MainTabbarTabs.home.icon, tag: 0)
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)

        let homeVC = DWHomeViewController()
        homeVC.delegate = self
        homeVC.model = homeModel
        homeController = homeVC

        var nvc = BaseNavigationController(rootViewController: homeVC)
        nvc.tabBarItem = item
        viewControllers.append(nvc)

        // Payment
        item = UITabBarItem(title: "", image: UIImage(), tag: 1)
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)

        let vc = EmptyController()
        vc.tabBarItem = item
        viewControllers.append(vc)

        // More
        item = UITabBarItem(title: nil, image: MainTabbarTabs.more.icon, tag: 2)
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        let menuVC = DWMainMenuViewController()
        menuVC.delegate = self
        menuNavigationController = menuVC

        nvc = BaseNavigationController(rootViewController: menuVC)
        nvc.tabBarItem = item
        viewControllers.append(nvc)

        self.viewControllers = viewControllers
    }

    private func configureHierarchy() {
        paymentButton = PaymentButton()
        paymentButton.translatesAutoresizingMaskIntoConstraints = false
        paymentButton.addTarget(self, action: #selector(paymentButtonAction), for: .touchUpInside)
        tabBar.addSubview(paymentButton)

        NSLayoutConstraint.activate([
            paymentButton.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            paymentButton.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: UIDevice.hasHomeIndicator ? 4 : 1),

            paymentButton.widthAnchor.constraint(equalToConstant: PaymentButton.kCenterCircleSize),
            paymentButton.heightAnchor.constraint(equalToConstant: PaymentButton.kCenterCircleSize),
        ])

        tabBar.barTintColor = .dw_background()
        tabBar.tintColor = .dw_dashBlue()
        tabBar.unselectedItemTintColor = .dw_tabbarInactiveButton()
    }

    private func closePayments(completion: (() -> Void)? = nil) {
        paymentButton.isOpened = false

        guard let top = selectedViewController?.topController(),
              top != selectedViewController
        else {
            completion?()
            return
        }

        top.dismiss(animated: true) {
            completion?()
        }
    }
}

// MARK: - Public
extension MainTabbarController {
    @objc
    public func performScanQRCodeAction() {
        dismiss(animated: false, completion: nil)
        selectedIndex = MainTabbarTabs.home.rawValue
        homeController?.performScanQRCodeAction()
    }

    @objc
    public func performPay(to url: URL) {
        dismiss(animated: false, completion: nil)
        selectedIndex = MainTabbarTabs.home.rawValue
        homeController?.performPay(to: url)
    }

    @objc
    public func handleFile(_ file: Data) {
        dismiss(animated: false, completion: nil)
        selectedIndex = MainTabbarTabs.home.rawValue
        homeController?.handleFile(file)
    }

    @objc
    public func openPaymentsScreen() {
        assert(isDemoMode, "Invalid usage. Should be used in Demo mode only")
        showPaymentsController(withActivePage: .pay)
    }

    @objc
    public func closePaymentsScreen() {
        assert(isDemoMode, "Invalid usage. Should be used in Demo mode only")
        closePayments()
    }
}

// MARK: DWMainMenuViewControllerDelegate

extension MainTabbarController: DWMainMenuViewControllerDelegate {
    func mainMenuViewControllerImportPrivateKey(_ controller: DWMainMenuViewController) {
        performScanQRCodeAction()
    }

    func mainMenuViewControllerOpenHomeScreen(_ controller: DWMainMenuViewController) {
        selectedIndex = MainTabbarTabs.home.rawValue
    }
}

// MARK: DWWipeDelegate

extension MainTabbarController: DWWipeDelegate {
    func didWipeWallet() {
        wipeDelegate?.didWipeWallet()
    }
}

// MARK: PaymentsViewControllerDelegate

extension MainTabbarController: PaymentsViewControllerDelegate {
    func paymentsViewControllerDidFinishPayment(_ controller: PaymentsViewController, tx: DSTransaction, contact: DWDPBasicUserItem?) {
        closePayments { [weak self] in
            self?.presentTxDetails(for: tx, contact: contact)
        }
    }

    private func presentTxDetails(for tx: DSTransaction, contact: DWDPBasicUserItem?) {
        let model = TxDetailModel(transaction: Transaction(transaction: tx))
        let vc = SuccessTxDetailViewController(model: model)
        vc.modalPresentationStyle = .fullScreen
        vc.contactItem = contact
        vc.delegate = self
        selectedViewController?.topController().present(vc, animated: true)
    }

    func paymentsViewControllerWantsToImportPrivateKey(_ controller: PaymentsViewController) {
        paymentButton.isOpened = false

        controller.dismiss(animated: true) {
            self.performScanQRCodeAction()
        }
    }

    func paymentsViewControllerDidCancel(_ controller: PaymentsViewController) {
        closePayments()
    }
}

// MARK: DWHomeViewControllerDelegate

extension MainTabbarController: DWHomeViewControllerDelegate {
    func showPaymentsController(withActivePage pageIndex: NSInteger) {
        showPaymentsController(withActivePage: PaymentsViewControllerState(rawValue: pageIndex)!)
    }

    func showPaymentsController(withActivePage pageIndex: PaymentsViewControllerState) {
        paymentButton.isOpened = true

        let receiveModel = DWReceiveModel()
        let payModel = DWPayModel()

        let controller = PaymentsViewController.controller(withReceiveModel: receiveModel,
                                                           payModel: payModel)

        controller.delegate = self
        controller.currentState = pageIndex
        controller.demoMode = isDemoMode
        controller.demoDelegate = demoDelegate

        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true

        if isDemoMode {
            demoDelegate?.presentModalController(navigationController, sender: self)
        } else {
            selectedViewController?.topController().present(navigationController, animated: true)
        }
    }
}

// MARK: UITabBarControllerDelegate

extension MainTabbarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        !(viewController is EmptyController)
    }
}

// MARK: - EmptyController

private final class EmptyController: UIViewController { }

// MARK: - MainTabbarController + SuccessTxDetailViewControllerDelegate

extension MainTabbarController: SuccessTxDetailViewControllerDelegate {
    func txDetailViewControllerDidFinish(controller: SuccessTxDetailViewController) { }
}
