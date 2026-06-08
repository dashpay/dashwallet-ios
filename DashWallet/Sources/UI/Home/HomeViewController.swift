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

@objc(DWHomeViewControllerDelegate)
protocol HomeViewControllerDelegate: AnyObject {
    func showPaymentsController(withActivePage pageIndex: Int)
}

class HomeViewController: DWBasePayViewController, NavigationBarDisplayable {
    private var cancellableBag = Set<AnyCancellable>()
    var model: DWHomeProtocol!
    var viewModel: HomeViewModel!
    private var homeView: HomeView!
    weak var delegate: (HomeViewControllerDelegate & DWWipeDelegate)?

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
        homeView = HomeView(frame: frame, delegate: self, viewModel: viewModel)
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

        #if DASHPAY
        // Row #17 stage A — seed the nav-bar avatar on launch from
        // the current model state. Without this, the avatar would
        // only appear after a `DWDashPayRegistrationStatusUpdated`
        // notification fires (i.e., during a fresh registration);
        // re-launching with an already-registered wallet wouldn't
        // show it until something prompted a refresh.
        refreshIdentityAvatar()
        #endif
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

        // Refresh the SDK's local DPNS-names cache from the blockchain
        // so the avatar/profile sheet/Edit Profile see legitimately-
        // owned names that weren't written by registerDpnsName in this
        // session (e.g. names registered before a reinstall, names
        // synced after a network switch, names that fell out of the
        // local cache after a contested-sync rewrite). Fire-and-forget —
        // the helper invalidates its snapshot on completion so the
        // next read picks up new names automatically.
        DWCurrentUserIdentityInfo.shared.syncFromNetwork()

        let upgrading = model.performOnSetupUpgrades()
        if !upgrading {
            // since these both methods might display modals, don't allow running them simultaneously
            showWalletBackupReminderIfNeeded()
        }

        model.registerForPushNotifications()
        model.checkCrowdNodeState()
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

    /// Row #17 stage A — re-evaluate avatar visibility + notification
    /// bell from the central model state. Called from the legacy
    /// `homeView(_:didUpdateProfile:)` delegate (DashSync-side
    /// updates), from the `DWDashPayRegistrationStatusUpdated`
    /// observer in `configureObservers()` (SwiftDashSDK-side
    /// updates), and once from `viewDidLoad` to seed visibility on
    /// re-launch for an already-registered wallet.
    func refreshIdentityAvatar() {
        let hasIdentity = model.dashPayModel.hasIdentity
        let hasNotifications = model.dashPayModel.unreadNotificationsCount > 0
        avatarView?.isHidden = !hasIdentity
        refreshNotificationBell(hasIdentity: hasIdentity, hasNotifications: hasNotifications)
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
        // Gate every avatar tap on the strict SDK-side identity
        // check. The Save path in `DWProfileUpdateBridge` resolves
        // the identity from the SDK helper, so opening Edit Profile
        // without `hasIdentity` would just produce a broken screen
        // (no display name, names list empty, save fails). Belt-
        // and-suspenders for the avatar that should already be
        // hidden when this is false.
        guard DWCurrentUserIdentityInfo.shared.hasIdentity else { return }

        // Row #17 stage A — branch on the underlying DashSync identity
        // object. DashSync-side identities (Core-funded path
        // reconstructed by DashSync's on-chain scanner, or a wallet
        // that already had a DashSync identity before the migration)
        // open `DWEditProfileViewController` directly. SwiftDashSDK-
        // only identities (Platform-Payment path, or any future SDK
        // path with no Core footprint) get the SDK profile sheet,
        // which now (Row #17 proper) carries an Edit button that
        // re-enters `RootEditProfileViewController`. The editor reads
        // from `DWCurrentUserIdentityInfo` and writes via
        // `DWProfileUpdateBridge`, so it works for both paths.
        if model.dashPayModel.blockchainIdentity != nil {
            let controller = RootEditProfileViewController()
            controller.delegate = self
            let navigation = BaseNavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            present(navigation, animated: true, completion: nil)
        } else {
            let sheet = SDKIdentityProfileSheet { [weak self] in
                // SDKIdentityProfileSheet has already called dismiss()
                // by the time this fires; chain into the same editor
                // after the dismissal completes.
                guard let self else { return }
                let controller = RootEditProfileViewController()
                controller.delegate = self
                let navigation = BaseNavigationController(rootViewController: controller)
                navigation.modalPresentationStyle = .fullScreen
                self.present(navigation, animated: true, completion: nil)
            }
            let hosting = UIHostingController(rootView: sheet)
            present(hosting, animated: true, completion: nil)
        }
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
        // Restored original avatar shape — DWDPAvatarView wrapped in
        // `UIBarButtonItem(customView:)` with a tap-gesture
        // recognizer. This is the configuration that was working
        // for DashSync-registered identities before the migration.
        // Row #17 stage A keeps it intact and only changes the
        // visibility gate to also honor SwiftDashSDK-side identity
        // (via `model.dashPayModel.hasIdentity`), plus a
        // `DWDashPayRegistrationStatusUpdated` observer in
        // `configureObservers()` so SDK registrations unhide the
        // avatar live without needing the legacy DashSync delegate
        // path.
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
    
    func showGiftCardDetails(txId: Data) {
        let hostingController = UIHostingController(rootView: 
            GiftCardDetailsSheet(txId: txId).background(Color.primaryBackground)
        )
        
        present(hostingController, animated: true, completion: nil)
    }
    
    private func configureObservers() {
        #if DASHPAY
        // Row #17 stage A — the legacy `homeView(_:didUpdateProfile:)`
        // delegate callback only fires when DashSync's
        // `defaultBlockchainIdentity` flips. A SwiftDashSDK-side
        // registration (Platform-Payment path, or Core path on a
        // wallet without DashSync identity reconstruction) never
        // toggles that delegate, so the avatar wouldn't appear until
        // a screen change forced a redraw. Subscribing to the
        // canonical `DWDashPayRegistrationStatusUpdatedNotification`
        // re-evaluates the visibility gate against the central
        // `hasIdentity` flag as soon as the bridge posts a terminal
        // phase.
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshIdentityAvatar()
            }
            .store(in: &cancellableBag)
        #endif

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

        viewModel.$showCoinJoinSweepDialog
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self = self, show else { return }
                self.showCoinJoinSweepDialog()
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

    private func showCoinJoinSweepDialog() {
        let amount = viewModel.coinJoinSweepAmountFormatted
        showModalDialog(
            style: .regular,
            icon: .system("arrow.down.circle"),
            heading: NSLocalizedString("Move your mixed coins", comment: "CoinJoin"),
            textBlock1: String(format: NSLocalizedString("You have %@ in CoinJoin mixed coins. CoinJoin is no longer supported — move them to your spendable balance.", comment: "CoinJoin"), amount),
            positiveButtonText: NSLocalizedString("Move funds", comment: "CoinJoin"),
            positiveButtonAction: {
                DSLogger.log("CJTEST HomeViewController: sweep invoked from Home popup (\(amount))")
                self.viewModel.showCoinJoinSweepDialog = false
                Task {
                    let errorMessage = await self.viewModel.performCoinJoinSweep()
                    guard let errorMessage else { return }
                    await MainActor.run {
                        self.showModalDialog(
                            style: .error,
                            icon: .system("exclamationmark.triangle"),
                            heading: NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
                            textBlock1: errorMessage,
                            positiveButtonText: NSLocalizedString("OK", comment: "")
                        )
                    }
                }
            },
            negativeButtonText: NSLocalizedString("Later", comment: "CoinJoin"),
            negativeButtonAction: {
                self.viewModel.showCoinJoinSweepDialog = false
            }
        )
    }
}


#if DASHPAY
// MARK: - RootEditProfileViewControllerDelegate

extension HomeViewController: RootEditProfileViewControllerDelegate {
    func editProfileViewController(_ controller: RootEditProfileViewController, updateDisplayName rawDisplayName: String, aboutMe rawAboutMe: String, avatarURLString: String?, avatarImage: UIImage?) {
        // Row #17 proper: pass the cropped UIImage through so the
        // SDK profile-update path can hand the bytes to
        // `DashPayProfileUpdate.avatarBytes` for hash computation.
        // The DashSync path inside `DWDPUpdateProfileModel` ignores
        // the image parameter — it uses the URL only.
        model.dashPayModel.userProfile.updateModel.update(
            withDisplayName: rawDisplayName,
            aboutMe: rawAboutMe,
            avatarURLString: avatarURLString,
            avatarImage: avatarImage)
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

    func homeViewShowSyncingStatus() {
        let controller = SyncingAlertViewController()
        present(controller, animated: true, completion: nil)
    }
    
    #if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfile identity: DSBlockchainIdentity?, unreadNotifications: UInt) {
        avatarView.blockchainIdentity = identity
        // Row #17 stage A — visibility gate uses
        // `model.dashPayModel.hasIdentity` (OR of DashSync's
        // `defaultBlockchainIdentity != nil` and SwiftDashSDK's
        // `dashpayRegistrationCompleted`) so SDK-registered
        // identities surface in the avatar even when DashSync has
        // no `DSBlockchainIdentity` object to populate it with.
        // The `DSBlockchainIdentity` passed in is still assigned to
        // `avatarView.blockchainIdentity` so DashSync-side avatar
        // rendering (letter, branded color, profile image) keeps
        // working; SDK-only identities get the avatar view's
        // default placeholder.
        let hasIdentity = model.dashPayModel.hasIdentity
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

// MARK: - ShortcutsActionDelegate

extension HomeViewController: ShortcutsActionDelegate {
    func shortcutsView(didSelectAction action: ShortcutAction, sender: UIView?) {
        performAction(for: action, sender: sender)
    }

    func shortcutsView(didLongPressPosition position: Int, currentAction: ShortcutAction) {
        if currentAction.type == .secureWallet && DWGlobalOptions.sharedInstance().walletNeedsBackup {
            showBackupWarningThenSelect(position: position)
        } else {
            presentShortcutSelection(for: position)
        }
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
