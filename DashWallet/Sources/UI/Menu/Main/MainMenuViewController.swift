//
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import SwiftUI
import MessageUI

@objc(DWMainMenuViewController) 
class MainMenuViewController: UIViewController {
    
    // MARK: - Properties
    
    @objc weak var delegate: DWWipeDelegate?
    
    private var viewModel: MainMenuViewModel!
    private var hostingController: UIHostingController<MainMenuView>!
    
    #if DASHPAY
    private let receiveModel: DWReceiveModelProtocol?
    private let dashPayReady: DWDashPayReadyProtocol?
    private let dashPayModel: DWDashPayProtocol?
    private let userProfileModel: CurrentUserProfileModel?
    #endif
    
    // MARK: - Initialization
    
    @objc override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        #if DASHPAY
        self.receiveModel = nil
        self.dashPayReady = nil
        self.dashPayModel = nil
        self.userProfileModel = nil
        #endif
        
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupViewController()
    }
    
    #if DASHPAY
    @objc init(dashPayModel: DWDashPayProtocol,
               receiveModel: DWReceiveModelProtocol,
               dashPayReady: DWDashPayReadyProtocol,
               userProfileModel: CurrentUserProfileModel) {
        self.receiveModel = receiveModel
        self.dashPayReady = dashPayReady
        self.dashPayModel = dashPayModel
        self.userProfileModel = userProfileModel
        
        super.init(nibName: nil, bundle: nil)
        setupViewController()
    }
    #endif
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupViewController() {
//        title = NSLocalizedString("More", comment: "") todo
    }
    
    // MARK: - View Lifecycle
    
    override func loadView() {
        super.loadView()
        setupSwiftUIView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNotificationObservers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.largeTitleDisplayMode = .never
        viewModel.updateModel()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - SwiftUI Setup
    
    private func setupSwiftUIView() {
        #if DASHPAY
        viewModel = MainMenuViewModel(
            dashPayModel: dashPayModel,
            receiveModel: receiveModel,
            dashPayReady: dashPayReady,
            userProfileModel: userProfileModel
        )
        #else
        viewModel = MainMenuViewModel()
        #endif
        
        let swiftUIView = MainMenuView(viewModel: viewModel)
        hostingController = UIHostingController(rootView: swiftUIView)
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(showBuySellPortal), name: .showBuySellPortal, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showExplore), name: .showExplore, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showSecurity), name: .showSecurity, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showSettings), name: .showSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showTools), name: .showTools, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showSupport), name: .showSupport, object: nil)
        
        #if DASHPAY
        NotificationCenter.default.addObserver(self, selector: #selector(showInvite), name: .showInvite, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showVoting), name: .showVoting, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(editProfile), name: .editProfile, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showRequestDetails), name: .showRequestDetails, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showMixDashDialog), name: .showMixDashDialog, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showDashPayInfo), name: .showDashPayInfo, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(joinDashPay), name: .joinDashPay, object: nil)
        #endif
    }
    
    // MARK: - Navigation Handlers
    
    @objc private func showBuySellPortal() {
        DSAuthenticationManager.sharedInstance().authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            alertIfLockout: true
        ) { [weak self] authenticated, usedBiometrics, cancelled in
            if authenticated {
                let controller = BuySellPortalViewController.controller()
                controller.hidesBottomBarWhenPushed = true
                self?.navigationController?.pushViewController(controller, animated: true)
            }
        }
    }
    
    @objc private func showExplore() {
        let controller = ExploreViewController()
        controller.delegate = self
        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true)
    }
    
    @objc private func showSecurity() {
        let controller = SecurityMenuViewController()
        controller.delegate = delegate
        navigationController?.pushViewController(controller, animated: true)
    }
    
    @objc private func showSettings() {
        let controller = SettingsMenuViewController()
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }
    
    @objc private func showTools() {
        let controller = ToolsMenuViewController()
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }
    
    @objc private func showSupport() {
        presentSupportEmailController()
    }
    
    #if DASHPAY
    @objc private func showInvite() {
        let controller = DWInvitationHistoryViewController()
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
    
    @objc private func showVoting() {
        let controller = UsernameVotingViewController.controller()
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
    
    @objc private func editProfile() {
        let controller = DWRootEditProfileViewController()
        controller.delegate = self
        let navigation = DWNavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }
    
    @objc private func showRequestDetails() {
        let controller = RequestDetailsViewController.controller()
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
    
    @objc private func showMixDashDialog() {
        let swiftUIView = MixDashDialog(
            positiveAction: { [weak self] in
                let controller = CoinJoinLevelsViewController.controller(isFullScreen: false)
                controller.hidesBottomBarWhenPushed = true
                self?.navigationController?.pushViewController(controller, animated: true)
            },
            negativeAction: { [weak self] in
                if UsernamePrefs.shared.joinDashPayInfoShown {
                    self?.joinDashPay()
                } else {
                    UsernamePrefs.shared.joinDashPayInfoShown = true
                    self?.showDashPayInfo()
                }
            }
        )
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(260)
        present(hostingController, animated: true)
    }
    
    @objc private func showDashPayInfo() {
        let swiftUIView = JoinDashPayInfoDialog { [weak self] in
            self?.joinDashPay()
        }
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(600)
        present(hostingController, animated: true)
    }
    
    @objc private func joinDashPay() {
        guard let dashPayModel = dashPayModel else { return }
        
        let controller = CreateUsernameViewController(
            dashPayModel: dashPayModel,
            invitationURL: nil,
            definedUsername: nil
        )
        controller.hidesBottomBarWhenPushed = true
        controller.completionHandler = { [weak self] result in
            if result {
                self?.view.dw_showInfoHUD(withText: NSLocalizedString("Username was successfully requested", comment: "Usernames"), offsetForNavBar: true)
            } else {
                self?.view.dw_showInfoHUD(withText: NSLocalizedString("Your request was cancelled", comment: "Usernames"), offsetForNavBar: true)
            }
        }
        navigationController?.pushViewController(controller, animated: true)
    }
    #endif
}

// MARK: - DWToolsMenuViewControllerDelegate

extension MainMenuViewController: ToolsMenuViewControllerDelegate {
    func toolsMenuViewControllerImportPrivateKey(_ controller: ToolsMenuViewController) {
        navigationController?.popToRootViewController(animated: false)
        if let mainMenuDelegate = delegate as? MainMenuViewControllerDelegate {
            mainMenuDelegate.mainMenuViewControllerImportPrivateKey(self)
        }
    }
}

// MARK: - DWSettingsMenuViewControllerDelegate

extension MainMenuViewController: SettingsMenuViewControllerDelegate {
    func settingsMenuViewControllerDidRescanBlockchain(_ controller: SettingsMenuViewController) {
        navigationController?.popToRootViewController(animated: false)
        if let mainMenuDelegate = delegate as? MainMenuViewControllerDelegate {
            mainMenuDelegate.mainMenuViewControllerOpenHomeScreen(self)
        }
    }
}

// MARK: - DWExploreViewControllerDelegate

extension MainMenuViewController: ExploreViewControllerDelegate {
    func exploreViewControllerShowSendPayment(_ controller: ExploreViewController) {
        if let mainMenuDelegate = delegate as? MainMenuViewControllerDelegate {
            mainMenuDelegate.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
        }
    }
    
    func exploreViewControllerShowReceivePayment(_ controller: ExploreViewController) {
        if let mainMenuDelegate = delegate as? MainMenuViewControllerDelegate {
            mainMenuDelegate.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
        }
    }
    
    func exploreViewControllerShowGiftCard(_ controller: ExploreViewController, txId: Data) {
        if let mainMenuDelegate = delegate as? MainMenuViewControllerDelegate {
            mainMenuDelegate.showGiftCard(txId)
        }
    }
}

// MARK: - DWRootEditProfileViewControllerDelegate

#if DASHPAY
extension MainMenuViewController: DWRootEditProfileViewControllerDelegate {
    func editProfileViewController(_ controller: DWRootEditProfileViewController,
                                 updateDisplayName rawDisplayName: String,
                                 aboutMe rawAboutMe: String,
                                 avatarURLString: String?) {
        userProfileModel?.updateModel.update(withDisplayName: rawDisplayName, aboutMe: rawAboutMe, avatarURLString: avatarURLString)
        controller.dismiss(animated: true)
    }
    
    func editProfileViewControllerDidCancel(_ controller: DWRootEditProfileViewController) {
        controller.dismiss(animated: true)
    }
}
#endif

// MARK: - MFMailComposeViewControllerDelegate

extension MainMenuViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}
