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
import Combine

// MARK: - MainTabbarTabs

private enum MainTabbarTabs: Int, CaseIterable {
    case home
    case contacts
    case payment
    case explore
    case more
}

extension MainTabbarTabs {
    var icon: UIImage {
        let name: String

        switch self {
        case .home:
            name = "tabbar_home_icon"
        case .contacts:
            name = "tabbar_contacts_icon"
        case .payment:
            name = "tabbar_pay_button"
        case .explore:
            name = "tabbar_discover_icon"
        case .more:
            name = "tabbar_other_icon"
        }

        return UIImage(named: name)!.withRenderingMode(.alwaysOriginal)
    }

    var selectedIcon: UIImage {
        let name: String

        switch self {
        case .home:
            name = "tabbar_home_selected"
        case .contacts:
            name = "tabbar_contacts_selected"
        case .payment:
            name = "tabbar_pay_button"
        case .explore:
            name = "tabbar_discover_selected"
        case .more:
            name = "tabbar_other_selected"
        }

        return UIImage(named: name)!.withRenderingMode(.alwaysOriginal)
    }
}

// MARK: - MainTabbarController

let kStaleRatesDuration: TimeInterval = 30 * 60 // 30 minutes

@objc
class MainTabbarController: UITabBarController {
    private var cancellableBag = Set<AnyCancellable>()
    private var ratesFetchErrorShown = false
    private var ratesVolatileWarningShown = false

    weak var homeController: HomeViewController?
    weak var menuNavigationController: MainMenuViewController?

    #if DASHPAY
    weak var contactsNavigationController: DWRootContactsViewController?
    #endif

    // TODO: Refactor this and send notification about wiped wallet instead of chaining the delegate
    @objc
    weak var wipeDelegate: DWWipeDelegate?

    @objc
    var isDemoMode = false

    @objc
    weak var demoDelegate: DWDemoDelegate?

    // TODO: Move it out from here and initialize the model inside home view controller
    @objc
    var homeModel: DWHomeProtocol!

    #if DASHPAY
    // TODO: MOCK_DASHPAY remove when not mocked
    private var blockchainIdentity: DSBlockchainIdentity? {
        if MOCK_DASHPAY.boolValue {
            if let username = DWGlobalOptions.sharedInstance().dashpayUsername {
                return DWEnvironment.sharedInstance().currentWallet.createBlockchainIdentity(forUsername: username)
            }
        }
        return DWEnvironment.sharedInstance().currentWallet.defaultBlockchainIdentity
    }
    #endif

    @objc
    init(homeModel: DWHomeProtocol) {
        super.init(nibName: nil, bundle: nil)

        self.homeModel = homeModel
        configureControllers()
        
        #if DASHPAY
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .sink { [weak self] _ in
                guard let self = self else { return }

                if self.blockchainIdentity != nil {
                    let previousIndex = self.selectedIndex
                    self.configureControllers()
                    self.selectedIndex = previousIndex == 0 ? 0 : previousIndex + 2
                    self.view.setNeedsLayout()
                    self.view.layoutIfNeeded()
                }
            }
            .store(in: &cancellableBag)
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        tabBar.barTintColor = .dw_background()
        setupRatesErrorHandling()
    }
}

// MARK: - Private
extension MainTabbarController {
    private func configureControllers() {
        var viewControllers: [UIViewController] = []

        // Home
        var item = UITabBarItem(title: nil, image: MainTabbarTabs.home.icon, selectedImage: MainTabbarTabs.home.selectedIcon)
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)

        let homeVC = HomeViewController()
        homeVC.delegate = self
        homeVC.model = homeModel
        homeVC.viewModel = homeModel is DWHomeModelStub ? HomeViewModel(transactionSource: StubTransactionSource(model: homeModel as! DWHomeModelStub)) : HomeViewModel.shared
        homeController = homeVC

        var nvc = BaseNavigationController(rootViewController: homeVC)
        nvc.tabBarItem = item
        viewControllers.append(nvc)
        
        #if DASHPAY
        let identity = self.blockchainIdentity
        
        if identity != nil {
            // Contacts
            item = UITabBarItem(title: nil, image: MainTabbarTabs.contacts.icon, selectedImage: MainTabbarTabs.contacts.selectedIcon)
            item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            
            let contactsVC = DWRootContactsViewController(payModel: homeModel.payModel, dataProvider: homeModel.getDataProvider(), dashPayModel: homeModel.dashPayModel, dashPayReady: homeModel)
            contactsNavigationController = contactsVC
            nvc = BaseNavigationController(rootViewController: contactsVC)
            nvc.tabBarItem = item
            viewControllers.append(nvc)
        }
        #endif

        // Payment (tapping this tab opens the payment modal instead of switching tabs)
        let paymentImage = Self.makePaymentTabImage()
        item = UITabBarItem(title: nil, image: paymentImage, selectedImage: paymentImage)
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        item.accessibilityIdentifier = "tabbar_payments_button"

        let paymentVC = EmptyController()
        paymentVC.tabBarItem = item
        viewControllers.append(paymentVC)
        
        #if DASHPAY
        if identity != nil {
            // Explore
            item = UITabBarItem(title: nil, image: MainTabbarTabs.explore.icon, selectedImage: MainTabbarTabs.explore.selectedIcon)
            item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            
            nvc = BaseNavigationController()
            let exploreScreen = ExploreMenuScreen(
                vc: nvc,
                showBackButton: false,
                onShowSendPayment: { [weak self] in self?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay) },
                onShowReceivePayment: { [weak self] in self?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive) },
                onShowGiftCard: { [weak self] txId in
                    self?.selectedIndex = MainTabbarTabs.home.rawValue
                    self?.homeController?.showGiftCardDetails(txId: txId)
                }
            )
            nvc.viewControllers = [UIHostingController(rootView: exploreScreen)]
            nvc.tabBarItem = item
            viewControllers.append(nvc)
        }
        #endif

        // More
        item = UITabBarItem(title: nil, image: MainTabbarTabs.more.icon, selectedImage: MainTabbarTabs.more.selectedIcon)
        item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        
        let menuVC: MainMenuViewController
        #if DASHPAY
        menuVC = MainMenuViewController(dashPayModel: homeModel.dashPayModel, receiveModel: homeModel.receiveModel, dashPayReady: homeModel, userProfileModel: homeModel.dashPayModel.userProfile)
        #else
        menuVC = MainMenuViewController()
        #endif
        
        menuVC.delegate = self
        menuNavigationController = menuVC

        nvc = BaseNavigationController(rootViewController: menuVC)
        nvc.tabBarItem = item
        viewControllers.append(nvc)

        self.viewControllers = viewControllers
    }

    /// Creates a tab bar image with a blue circle background and the payment icon centered on top.
    private static func makePaymentTabImage() -> UIImage {
        let size: CGFloat = 47
        let rect = CGRect(x: 0, y: 0, width: size, height: size)

        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { context in
            // Draw blue circle background
            UIColor.dw_dashBlue().setFill()
            UIBezierPath(ovalIn: rect).fill()

            // Draw icon centered
            if let icon = UIImage(named: "tabbar_pay_button") {
                let iconSize = CGSize(width: 22, height: 22)
                let iconOrigin = CGPoint(x: (size - iconSize.width) / 2, y: (size - iconSize.height) / 2)
                icon.draw(in: CGRect(origin: iconOrigin, size: iconSize))
            }
        }

        return image.withRenderingMode(.alwaysOriginal)
    }

    private func closePayments(completion: (() -> Void)? = nil) {
        paymentIsOpened = false

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
    
    #if DASHPAY
    @objc
    public func handleDeeplink(_ url: URL, definedUsername: String?) {
        dismiss(animated: false, completion: nil)
        selectedIndex = MainTabbarTabs.home.rawValue
        homeController?.handleDeeplink(url, definedUsername: definedUsername)
    }
    #endif
}

// MARK: MainMenuViewControllerDelegate

extension MainTabbarController: MainMenuViewControllerDelegate {
    func mainMenuViewControllerImportPrivateKey() {
        performScanQRCodeAction()
    }
    
    func mainMenuViewControllerOpenHomeScreen() {
        selectedIndex = MainTabbarTabs.home.rawValue
    }
    
    func showGiftCard(_ txId: Data) {
        selectedIndex = MainTabbarTabs.home.rawValue
        homeController?.showGiftCardDetails(txId: txId)
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
        paymentIsOpened = false

        controller.dismiss(animated: true) {
            self.performScanQRCodeAction()
        }
    }

    func paymentsViewControllerDidCancel(_ controller: PaymentsViewController) {
        closePayments()
    }
}

// MARK: HomeViewControllerDelegate

extension MainTabbarController: HomeViewControllerDelegate {
    func showPaymentsController(withActivePage pageIndex: NSInteger) {
        showPaymentsController(withActivePage: PaymentsViewControllerState(rawValue: pageIndex)!)
    }

    func showPaymentsController(withActivePage pageIndex: PaymentsViewControllerState) {
        paymentIsOpened = true

        let receiveModel = DWReceiveModel()
        let payModel = DWPayModel()

        let controller = PaymentsViewController.controller(withReceiveModel: receiveModel,
                                                           payModel: payModel,
                                                           dataProvider: homeModel.getDataProvider())

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
        if viewController is EmptyController {
            // Intercept the payment tab tap — show the payment modal instead of switching tabs
            showPaymentsController(withActivePage: .none)
            return false
        }
        return true
    }
}


// MARK: - EmptyController

private final class EmptyController: UIViewController { }

// MARK: - MainTabbarController + SuccessTxDetailViewControllerDelegate

extension MainTabbarController: SuccessTxDetailViewControllerDelegate {
    func txDetailViewControllerDidFinish(controller: SuccessTxDetailViewController) { }
}

// MARK: - Exchange Rates

extension MainTabbarController {
    private func setupRatesErrorHandling() {
        BaseRatesProvider.shared.$hasFetchError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasError in
                guard let self = self else { return }
                
                if hasError && !self.ratesFetchErrorShown {
                    self.showRatesError()
                    self.ratesFetchErrorShown = true
                }
            }
            .store(in: &cancellableBag)
        
        BaseRatesProvider.shared.$isVolatile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVolatile in
                guard let self = self else { return }
                
                if isVolatile && !self.ratesVolatileWarningShown {
                    self.showVolatileWarning()
                    self.ratesVolatileWarningShown = true
                }
            }
            .store(in: &cancellableBag)
    }
    
    private func showRatesError() {
        let lastUpdated = BaseRatesProvider.shared.lastUpdated
        let now = Date().timeIntervalSince1970
        let text: String
        
        if lastUpdated != 0 && Double(lastUpdated) + kStaleRatesDuration < now {
            text = NSLocalizedString("Prices are at least 30 minutes old. Fiat values may be incorrect.", comment: "Stale rates")
        } else {
            text = NSLocalizedString("Prices weren't retrieved. Fiat values may be incorrect.", comment: "Stale rates")
        }
        
        self.showToast(
            text: text,
            icon: .system("exclamationmark.triangle.fill"),
            actionText: NSLocalizedString("OK", comment: "Stale rates"),
            action: { toastView in
                self.hideToast(toastView: toastView)
            }
        )
    }
    
    private func showVolatileWarning() {
        self.showToast(
            text: NSLocalizedString("Prices have fluctuated more than 50% since the last update.", comment: "Stale rates"),
            icon: .system("exclamationmark.triangle.fill"),
            actionText: NSLocalizedString("OK", comment: "Stale rates"),
            action: { toastView in
                self.hideToast(toastView: toastView)
            }
        )
    }
}
