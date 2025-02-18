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
import SwiftUI
import Combine

class HomeViewController: DWBasePayViewController, NavigationBarDisplayable {
    private var cancellableBag = Set<AnyCancellable>()
    var model: DWHomeProtocol!
    private var homeView: HomeView!
    weak var delegate: (DWHomeViewControllerDelegate & DWWipeDelegate)?
    private let viewModel = HomeViewModel.shared

    #if DASHPAY
    var isBackButtonHidden: Bool = false
    private var invitationSetup: DWInvitationSetupState?
    private var avatarView: DWDPAvatarView!
    #else
    var isBackButtonHidden: Bool = true
    #endif
    
    override var payModel: any DWPayModelProtocol {
        get { return model.payModel }
        set { }
    }
    
    override var dataProvider: DWTransactionListDataProviderProtocol {
        get { return model.getDataProvider() }
        set { }
    }

    deinit {
        print("☠️ \(String(describing: self))")
    }

    override func loadView() {
        let frame = UIScreen.main.bounds
        homeView = HomeView(frame: frame, delegate: self)
        homeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        homeView.shortcutsDelegate = self
        view = homeView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(model != nil)

        setupView()
        performJailbreakCheck()
        configureObservers()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.applyOpaqueAppearance(with: UIColor.dw_dashNavigationBlue(), shadowColor: .clear)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let upgrading = model.performOnSetupUpgrades()
        if !upgrading {
            // since these both methods might display modals, don't allow running them simultaneously
            showWalletBackupReminderIfNeeded()
        }

        model.registerForPushNotifications()
        model.checkCrowdNodeState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        homeView.hideBalanceIfNeeded()
    }

    #if DASHPAY
    func handleDeeplink(_ url: URL, definedUsername: String?) {
        if model.dashPayModel.blockchainIdentity != nil {
            let title = NSLocalizedString("Username already found", comment: "")
            let message = NSLocalizedString("You cannot claim this invite since you already have a Dash username", comment: "")
            let alert = DPAlertViewController(icon: UIImage(named: "icon_invitation_error")!, title: title, description: message)
            present(alert, animated: true, completion: nil)
            return
        }

        if SyncingActivityMonitor.shared.state != .syncDone {
            let state = DWInvitationSetupState()
            state.invitation = url
            state.chosenUsername = definedUsername
            invitationSetup = state
            SyncingActivityMonitor.shared.add(observer: self)
            return
        }

        model.handleDeeplink(url) { [weak self] success, errorTitle, errorMessage in
            guard let self = self else { return }

            if success {
                self.showCreateUsername(withInvitation: url, definedUsername: definedUsername)
            } else {
                let alert = DPAlertViewController(icon: UIImage(named: "icon_invitation_error")!, title: errorTitle ?? "", description: errorMessage ?? "")
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    #endif

    // MARK: - Private

    #if DASHPAY
    override func payViewControllerDidHidePaymentResult(toContact contact: DWDPBasicUserItem?) {
        guard let contact = contact else { return }

        let profile = DWModalUserProfileViewController(item: contact, payModel: payModel, dataProvider: dataProvider)
        present(profile, animated: true, completion: nil)
    }

    func refreshNotificationBell(hasIdentity: Bool, hasNotifications: Bool) {
        if !hasIdentity {
            navigationItem.rightBarButtonItem = nil
            return
        }

        let notificationsImage = UIImage(named: hasNotifications ? "icon_bell_active" : "icon_bell")!.withRenderingMode(.alwaysOriginal)
        let notificationButton = UIBarButtonItem(image: notificationsImage, style: .plain, target: self, action: #selector(notificationAction))
        notificationButton.tintColor = .white
        navigationItem.rightBarButtonItem = notificationButton
    }

    @objc func notificationAction() {
        let controller = DWNotificationsViewController(payModel: payModel, dataProvider: dataProvider)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc func profileAction() {
        let controller = RootEditProfileViewController()
        controller.delegate = self
        let navigation = BaseNavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true, completion: nil)
    }
    #endif

    private func setupView() {
        let logoImage: UIImage?
        let logoHeight: CGFloat
        if DWEnvironment.sharedInstance().currentChain.chainType.tag == ChainType_TestNet {
            logoImage = UIImage(named: "dash_logo_testnet")
            logoHeight = 40.0
        } else {
            logoImage = UIImage(named: "dash_logo_template")
            logoHeight = 23.0
        }
        assert(logoImage != nil)

        let imageView = UIImageView(image: logoImage)
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        let frame = CGRect(x: 0.0, y: 0.0, width: 89.0, height: logoHeight)
        imageView.frame = frame

        let contentView = UIView(frame: frame)
        contentView.addSubview(imageView)

        navigationItem.titleView = contentView

        #if DASHPAY
        let avatarView = DWDPAvatarView(frame: CGRect(origin: .zero, size: CGSize(width: 30.0, height: 30.0)))
        avatarView.isSmall = true
        avatarView.isHidden = true
        avatarView.backgroundMode = .random
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(profileAction))
        avatarView.addGestureRecognizer(tapRecognizer)
        self.avatarView = avatarView
        let avatarButton = UIBarButtonItem(customView: avatarView)
        navigationItem.leftBarButtonItem = avatarButton
        #endif

        homeView.model = model
    }

    private func showReclassifyTransaction(with transaction: DSTransaction?) {
        let vc = TxReclassifyTransactionsInfoViewController.controller()
        vc.delegate = self
        vc.transaction = transaction
        self.present(vc, animated: true, completion: nil)
    }

    private func presentTransactionDetails(_ transaction: DSTransaction) {
        let model = TxDetailModel(transaction: transaction)
        let controller = TXDetailViewController(model: model)
        let nvc = BaseNavigationController(rootViewController: controller)
        present(nvc, animated: true, completion: nil)
    }
    
    private func configureObservers() {
        viewModel.$showTimeSkewAlertDialog
            .sink { [weak self] showTimeSkew in
                guard let self = self else { return }
                
                if showTimeSkew {
                    let diffSeconds = (viewModel.timeSkew < 0 ? -1 : 1) * Int64(ceil(abs(viewModel.timeSkew)))
                    let coinJoinOn = viewModel.coinJoinMode != .none
                    self.showTimeSkewDialog(diffSeconds: diffSeconds, coinjoin: coinJoinOn)
                }
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
            .sink { [weak self] _ in self?.viewModel.checkTimeSkew(force: true) }
            .store(in: &cancellableBag)
        
        viewModel.$showReclassifyTransaction
            .removeDuplicates()
            .filter { $0 != nil }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tx in
                self?.showReclassifyTransaction(with: tx)
                self?.viewModel.reclassifyTransactionShown(isShown: true)
            }
            .store(in: &cancellableBag)
    }
    
    private func showTimeSkewDialog(diffSeconds: Int64, coinjoin: Bool) {
        let settingsURL = URL(string: UIApplication.openSettingsURLString)
        let hasSettings = settingsURL != nil && UIApplication.shared.canOpenURL(settingsURL!)
        let message: String
        
        if coinjoin {
            let position = diffSeconds > 0 ? NSLocalizedString("ahead", comment: "TimeSkew") : NSLocalizedString("behind", comment: "TimeSkew")
            message = String(format: NSLocalizedString("Your device time is %@ by %d seconds. You cannot use CoinJoin due to this difference.\n\nThe time settings on your device needs to be changed to “Set time automatically” to use CoinJoin.", comment: "TimeSkew"), position, abs(diffSeconds))
        } else {
            message = String(format: NSLocalizedString("Your device time is off by %d minutes. You probably cannot send or receive Dash due to this problem.\n\nYou should check and if necessary correct your date, time and timezone settings.", comment: "TimeSkew"), abs(diffSeconds / 60))
        }
        
        showModalDialog(
            style: .warning,
            icon: .system("exclamationmark.triangle"),
            heading: NSLocalizedString("Check date & time settings", comment: "TimeSkew"),
            textBlock1: message,
            positiveButtonText: NSLocalizedString("Settings", comment: ""),
            positiveButtonAction: hasSettings ? {
                self.viewModel.showTimeSkewAlertDialog = false
                if let url = settingsURL {
                    UIApplication.shared.open(url)
                }
            } : nil,
            negativeButtonText: NSLocalizedString("Dismiss", comment: ""),
            negativeButtonAction: {
                self.viewModel.showTimeSkewAlertDialog = false
            }
        )
    }
}


#if DASHPAY
// MARK: - RootEditProfileViewControllerDelegate

extension HomeViewController: RootEditProfileViewControllerDelegate {
    func editProfileViewController(_ controller: RootEditProfileViewController, updateDisplayName rawDisplayName: String, aboutMe rawAboutMe: String, avatarURLString: String?) {
        model.dashPayModel.userProfile.updateModel.update(withDisplayName: rawDisplayName, aboutMe: rawAboutMe, avatarURLString: avatarURLString)
        controller.dismiss(animated: true, completion: nil)
    }

    func editProfileViewControllerDidCancel(_ controller: RootEditProfileViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
}
#endif

// MARK: - HomeViewDelegate

extension HomeViewController: HomeViewDelegate {
    func homeViewShowCoinJoin() {
        let controller = CoinJoinLevelsViewController.controller(isFullScreen: true)
        present(controller, animated: true, completion: nil)
    }
    
    func homeViewRequestUsername() {
        let action = ShortcutAction(type: .createUsername)
        performAction(for: action, sender: nil)
    }
    
    func homeViewShowTxFilter() {
        showTxFilter(displayModeCallback: { [weak self] mode in
            self?.viewModel.displayMode = mode
        }, shouldShowRewards: true)
    }

    func homeViewShowSyncingStatus() {
        let controller = SyncingAlertViewController()
        present(controller, animated: true, completion: nil)
    }
    
    #if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfile identity: DSBlockchainIdentity?, unreadNotifications: UInt) {
        avatarView.blockchainIdentity = identity
        let hasIdentity = identity != nil
        let hasNotifications = unreadNotifications > 0
        avatarView.isHidden = !hasIdentity
        refreshNotificationBell(hasIdentity: hasIdentity, hasNotifications: hasNotifications)
    }
    
    func homeViewEditProfile() {
        profileAction()
    }
    #endif
}

// MARK: - TxReclassifyTransactionsInfoViewControllerDelegate

extension HomeViewController: TxReclassifyTransactionsInfoViewControllerDelegate {
    func txReclassifyTransactionsFlowDidClose(controller: TxReclassifyTransactionsInfoViewController, transaction: DSTransaction) {
        presentTransactionDetails(transaction)
    }
}

// MARK: - DWShortcutsActionDelegate

extension HomeViewController: ShortcutsActionDelegate {
    func shortcutsView(_ view: UIView, didSelectAction action: ShortcutAction, sender: UIView) {
        performAction(for: action, sender: sender)
    }
}

// MARK: - SyncingActivityMonitorObserver

extension HomeViewController: SyncingActivityMonitorObserver {
    func syncingActivityMonitorProgressDidChange(_ progress: Double) {
        // pass
    }

    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        #if DASHPAY
        if state == .syncDone {
            if let invitationSetup = invitationSetup {
                handleDeeplink(invitationSetup.invitation!, definedUsername: invitationSetup.chosenUsername)
                self.invitationSetup = nil
            }
            SyncingActivityMonitor.shared.remove(observer: self)
        }
        #endif
    }
}
