//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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
import MessageUI
import Combine

class MainMenuViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    
    // MARK: - Properties
    
    weak var delegate: (DWWipeDelegate & MainMenuViewControllerDelegate)?
    
    private var contentView: MainMenuContentView {
        return view as! MainMenuContentView
    }
    
    private var receiveModel: DWReceiveModelProtocol?
    
    #if DASHPAY
    private var dashPayReady: DWDashPayReadyProtocol?
    private var dashPayModel: DWDashPayProtocol?
    private var userProfileModel: CurrentUserProfileModel?
    #endif
    
    // MARK: - Lifecycle
    
    @objc
    init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("More", comment: "")
    }
    
    #if DASHPAY
    @objc
    init(dashPayModel: DWDashPayProtocol, receiveModel: DWReceiveModelProtocol, dashPayReady: DWDashPayReadyProtocol, userProfileModel: CurrentUserProfileModel) {
        super.init(nibName: nil, bundle: nil)
        
        self.receiveModel = receiveModel
        self.dashPayReady = dashPayReady
        self.dashPayModel = dashPayModel
        self.userProfileModel = userProfileModel
        
        title = NSLocalizedString("More", comment: "")
    }
    #endif
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let frame = UIScreen.main.bounds
        view = MainMenuContentView(frame: frame)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        #if DASHPAY
        if let userProfileModel = userProfileModel {
            contentView.userModel = userProfileModel
        }
        setupObservers()
        #endif
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationItem.largeTitleDisplayMode = .never
        
        #if DASHPAY
        refreshContent()
        #else
        contentView.model = DWMainMenuModel(invitesEnabled: false, votingEnabled: false)
        #endif
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

#if DASHPAY
extension MainMenuViewController {
    func setupObservers() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in self?.refreshContent() }
            .store(in: &cancellableBag)
    }
    
    func refreshContent() {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        let invitationsEnabled = DWGlobalOptions.sharedInstance().dpInvitationFlowEnabled && 
            (userProfileModel?.identity != nil) && balance > DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        let isVotingEnabled = VotingPrefsWrapper.getIsEnabled()
        contentView.model = DWMainMenuModel(invitesEnabled: invitationsEnabled, votingEnabled: isVotingEnabled)
        contentView.updateUserHeader()
    }
}
#endif

// MARK: - MainMenuContentViewDelegate

extension MainMenuViewController: MainMenuContentViewDelegate {
    func mainMenuContentView(_ view: MainMenuContentView, didSelectMenuItem item: DWMainMenuItem) {
        switch item.type {
        case .buySellDash:
            DSAuthenticationManager.sharedInstance().authenticate(
                withPrompt: nil,
                usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
                alertIfLockout: true) { [weak self] authenticated, usedBiometrics, cancelled in
                    if authenticated {
                        let controller = BuySellPortalViewController.controller()
                        controller.hidesBottomBarWhenPushed = true
                        self?.navigationController?.pushViewController(controller, animated: true)
                    }
                }
            
        case .explore:
            let controller = DWExploreTestnetViewController()
            controller.delegate = self
            let nvc = BaseNavigationController(rootViewController: controller)
            present(nvc, animated: true)
            
        case .security:
            let controller = DWSecurityMenuViewController()
            controller.delegate = delegate
            navigationController?.pushViewController(controller, animated: true)
            
        case .settings:
            let controller = SettingsMenuViewController()
            controller.delegate = self
            navigationController?.pushViewController(controller, animated: true)
            
        case .tools:
            let controller = ToolsMenuViewController()
            controller.delegate = self
            navigationController?.pushViewController(controller, animated: true)
            
        case .support:
            presentSupportEmailController()
            
        #if DASHPAY
        case .invite:
            let controller = InvitationHistoryViewController()
            controller.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(controller, animated: true)
        case .voting:
            let controller = UsernameVotingViewController.controller()
            controller.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(controller, animated: true)
        #endif
            
        default:
            break
        }
    }
    
    #if DASHPAY
    func mainMenuContentView(showQRAction view: MainMenuContentView) {
        guard let receiveModel = receiveModel else { return }
        let controller = DWUserProfileModalQRViewController(model: receiveModel)
        present(controller, animated: true)
    }
    
    func mainMenuContentView(editProfileAction view: MainMenuContentView) {
        let controller = RootEditProfileViewController()
        controller.delegate = self
        let navigation = BaseNavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }
    
    func mainMenuContentView(joinDashPayAction view: MainMenuContentView) {
        guard let dashPayModel = dashPayModel else { return }
        let controller = CreateUsernameViewController(dashPayModel: dashPayModel, invitationURL: nil, definedUsername: nil)
        controller.hidesBottomBarWhenPushed = true
        controller.completionHandler = { [weak self] result in
            if result {
                self?.contentView.dw_showInfoHUD(withText: NSLocalizedString("Username was successfully requested", comment: "Usernames"), offsetForNavBar: true)
            } else {
                self?.contentView.dw_showInfoHUD(withText: NSLocalizedString("Your request was cancelled", comment: "Usernames"), offsetForNavBar: true)
            }
        }
        navigationController?.pushViewController(controller, animated: true)
    }
    
    func mainMenuContentView(showCoinJoin view: MainMenuContentView) {
        let controller = CoinJoinLevelsViewController.controller(isFullScreen: false)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
    
    func mainMenuContentView(showRequestDetails view: MainMenuContentView) {
        let controller = RequestDetailsViewController.controller()
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
    
    #endif
}

// MARK: - ToolsMenuViewControllerDelegate

extension MainMenuViewController: ToolsMenuViewControllerDelegate {
    func toolsMenuViewControllerImportPrivateKey(_ controller: ToolsMenuViewController) {
        navigationController?.popToRootViewController(animated: false)
        delegate?.mainMenuViewControllerImportPrivateKey(self)
    }
}

// MARK: - SettingsMenuViewControllerDelegate

extension MainMenuViewController: SettingsMenuViewControllerDelegate {
    func settingsMenuViewControllerDidRescanBlockchain(_ controller: SettingsMenuViewController) {
        navigationController?.popToRootViewController(animated: false)
        delegate?.mainMenuViewControllerOpenHomeScreen(self)
    }
}

// MARK: - DWExploreTestnetViewControllerDelegate

extension MainMenuViewController: DWExploreTestnetViewControllerDelegate {
    func exploreTestnetViewControllerShowSendPayment(_ controller: DWExploreTestnetViewController) {
        delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
    }
    
    func exploreTestnetViewControllerShowReceivePayment(_ controller: DWExploreTestnetViewController) {
        delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension MainMenuViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
} 
