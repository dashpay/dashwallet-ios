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
import Combine
import SwiftUI
import DashUIKit

// Swift-only (no ObjC references remain): lets requirements use Swift-only
// types like `ChainNetwork`.
protocol HomeViewControllerDelegate: AnyObject {
    func showPaymentsController(withActivePage pageIndex: Int)
    /// Opens the payments landing on the Receive tab with `network`
    /// preselected in its Core/Platform/Shielded toggle.
    func showReceiveLanding(network: ChainNetwork)
    /// Opens the balance-row send sheet (Send ↔ Internal) pinned to
    /// `network` as the source.
    func showSendLanding(network: ChainNetwork)
}

class HomeViewController: DWBasePayViewController, NavigationBarDisplayable {
    private var cancellableBag = Set<AnyCancellable>()
    private var isSyncObserverRegistered = false
    private var pendingCrowdNodeReminder = false
    private var isCrowdNodeReminderRetryScheduled = false
    private weak var crowdNodeBalanceReminderController: UIViewController?
    var model: DWHomeProtocol!
    var viewModel: HomeViewModel!
    private var homeView: HomeView!
    weak var delegate: (HomeViewControllerDelegate & DWWipeDelegate)?

    /// True while the home feed is scrolled to the top — the navigation
    /// bar stays hidden there so the balance header owns the space; it
    /// slides in once the balances scroll away. Read by
    /// `BaseNavigationController` through `isNavigationBarHidden` on
    /// every navigation transition, so pushed screens keep their bar and
    /// popping back restores the current scroll-derived state.
    private var hidesNavigationBarAtTop = true

    #if DASHPAY
    var isBackButtonHidden: Bool = false
    private var invitationSetup: DWInvitationSetupState?
    private var avatarView: DWDPAvatarView!
    #else
    var isBackButtonHidden: Bool = true
    #endif

    var isNavigationBarHidden: Bool { hidesNavigationBarAtTop }

    override var payModel: any DWPayModelProtocol {
        get { return model.payModel }
        set { }
    }
    
    deinit {
        if isSyncObserverRegistered {
            SyncingActivityMonitor.shared.remove(observer: self)
        }
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

        registerSyncObserverIfNeeded()
        setupView()
        performJailbreakCheck()
        configureObservers()

        #if DASHPAY
        // Seed the navigation avatar for an identity that was already
        // registered before this controller was created.
        refreshIdentityAvatar()
        #endif
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.applyOpaqueAppearance(with: UIColor.dw_dashNavigationBlue(), shadowColor: .clear)
        // Apply the scroll-derived bar state directly too —
        // `BaseNavigationController.willShow` reads `isNavigationBarHidden`
        // on transitions, but the home tab must also start hidden on
        // first display and stay correct if hosted outside that
        // navigation controller subclass.
        navigationController?.setNavigationBarHidden(hidesNavigationBarAtTop, animated: animated)
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

        // Reconcile a pending contested-username submission against the
        // resolved vote state (O(1) early-out when nothing is pending).
        DWIdentityRegistrationCoordinator.shared.checkPendingContestResolution()

        showWalletBackupReminderIfNeeded()

        model.registerForPushNotifications()
        model.checkCrowdNodeState()
        presentCrowdNodeBalanceReminderIfNeeded()
    }

    #if DASHPAY
    func handleDeeplink(_ url: URL, definedUsername: String?) {
        if DWInvitationService.shared.hasLocalIdentity {
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
            return
        }

        // The redeem screen owns validation: an unrecognized or
        // structurally invalid link renders its inline error state
        // (and the field stays editable), so no pre-flight alert is
        // needed. Claim-time failures (already claimed, wrong network,
        // insufficient voucher) surface in the username form's error
        // alert from the coordinator.
        let prefill = DWInvitationLinkNormalizer.normalize(url) ?? url.absoluteString
        ClaimInvitationFlow.pushRedeemScreen(
            on: navigationController,
            dashPayModel: model.dashPayModel,
            initialLink: prefill,
            definedUsername: definedUsername)
    }
    #endif

    // MARK: - Private

    #if DASHPAY
    /// Re-evaluates avatar visibility and the notification bell from the
    /// app-owned identity snapshot. Called on launch, after a profile update,
    /// and whenever registration state changes.
    func refreshIdentityAvatar() {
        let hasIdentity = model.dashPayModel.hasIdentity
        let hasNotifications = model.dashPayModel.unreadNotificationsCount > 0
#if DEBUG
        DWLogger.log("Home avatar state: registrationCompleted=\(model.dashPayModel.registrationCompleted), sdkUsername=\(DWCurrentUserIdentityInfo.shared.username ?? "nil"), sdkAvatarURL=\(DWCurrentUserIdentityInfo.shared.avatarURL ?? "nil")")
#endif
        avatarView.configureAsCurrentUser()
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
        // Notifications are backed by the SwiftDashSDK contacts service.
        let controller = UIHostingController(rootView: NotificationsScreen())
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc func profileAction() {
        let sheet = SDKIdentityProfileSheet { [weak self] in
            // SDKIdentityProfileSheet dismisses before invoking this callback.
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
    #endif

    private func setupView() {
        let logoImage: UIImage?
        let logoHeight: CGFloat
        if WalletEnvironment.isTestnet {
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
        // The app-owned avatar is shown only when the current wallet has an
        // identity. Registration notifications refresh this visibility live.
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

    private func showReclassifyTransaction(with transaction: Transaction?) {
        let vc = TxReclassifyTransactionsInfoViewController.controller()
        vc.delegate = self
        vc.transaction = transaction
        self.present(vc, animated: true, completion: nil)
    }

    private func presentTransactionDetails(_ transaction: Transaction) {
        let model = TxDetailModel(transaction: transaction)
        let controller = TXDetailViewController(model: model)
        let nvc = BaseNavigationController(rootViewController: controller)
        present(nvc, animated: true, completion: nil)
    }
    
    func showGiftCardDetails(txId: Data) {
        let presentGiftCardSheet: () -> Void = { [weak self] in
            self?.viewModel.giftCardTxId = txId
        }

        if let presentedViewController {
            presentedViewController.dismiss(animated: true) {
                DispatchQueue.main.async(execute: presentGiftCardSheet)
            }
        } else {
            DispatchQueue.main.async(execute: presentGiftCardSheet)
        }
    }
    
    private func configureObservers() {
        #if DASHPAY
        // Registration updates refresh the avatar from the canonical
        // app-owned identity snapshot.
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
                    self.showTimeSkewDialog(diffSeconds: diffSeconds, coinjoin: false)
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

        // Background→foreground is the primary way a user returns after a
        // contested-name voting window (~45 min testnet / ~2 weeks mainnet).
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { _ in
                DWIdentityRegistrationCoordinator.shared.checkPendingContestResolution()
            }
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

        CrowdNodeBalanceReminder.shared.$hasBalance
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasBalance in
                guard let self = self else { return }

                if hasBalance {
                    self.presentCrowdNodeBalanceReminderIfNeeded()
                } else {
                    self.pendingCrowdNodeReminder = false
                    self.dismissCrowdNodeBalanceReminder(markDismissed: false, animated: true)
                }
            }
            .store(in: &cancellableBag)
    }

    private func registerSyncObserverIfNeeded() {
        guard !isSyncObserverRegistered else { return }

        SyncingActivityMonitor.shared.add(observer: self)
        isSyncObserverRegistered = true
    }

    private func presentCrowdNodeBalanceReminderIfNeeded() {
        guard isViewLoaded else { return }
        guard SyncingActivityMonitor.shared.state == .syncDone else { return }
        guard CrowdNodeBalanceReminder.shared.shouldShowOnActiveScreen else {
            pendingCrowdNodeReminder = false
            return
        }
        guard crowdNodeBalanceReminderController == nil else {
            pendingCrowdNodeReminder = false
            return
        }
        // Present on whatever view is currently active (any tab / pushed screen), not just Home.
        // The sync observer fires even when Home isn't the visible tab, so `self` may be off-screen.
        //
        // The top controller may itself be a dialog — the PIN prompt (DSRequestPinViewController)
        // is a DWAlertController and reports no presentedViewController of its own, so presenting
        // over it would pass the check. Stacking on top of the PIN breaks its dismissal and lets
        // its completion fire twice, which trips NSParameterAssert(completion) in DashSync.
        guard let presenter = activeTopViewController(),
              presenter.presentedViewController == nil,
              !(presenter is UIAlertController),
              !(presenter is DWAlertController) else {
            pendingCrowdNodeReminder = true
            scheduleCrowdNodeReminderRetryIfNeeded()
            return
        }

        let bottomSheet = DashUIKit.BottomSheet(showBackButton: .constant(false), fillsHeight: false) {
            CrowdNodeBalanceReminderSheet(
                onWithdraw: { [weak self] in
                    self?.openCrowdNodeWithdrawalFromReminder()
                },
                onDismiss: { [weak self] in
                    self?.dismissCrowdNodeBalanceReminder(markDismissed: true, animated: true)
                }
            )
        }

        let hostingController = UIHostingController(rootView: bottomSheet)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.presentationController?.delegate = self
        // Fill the whole sheet (incl. the bottom safe-area strip) with the sheet background.
        hostingController.view.backgroundColor = UIColor(Color.dash.primaryBackground)

        if let sheetPC = hostingController.sheetPresentationController {
            sheetPC.prefersGrabberVisible = false
            // Custom corner radius only below iOS 26; iOS 26+ keeps the native sheet styling.
            if #unavailable(iOS 26.0) {
                sheetPC.preferredCornerRadius = 24
            }

            // SwiftUI's `.presentationDetents` (used by `.selfSizingSheet()`) does NOT bridge to a
            // UIHostingController presented via UIKit `present()` — UIKit would fall back to `.large`.
            // So size the sheet to its content here with a custom UIKit detent.
            if #available(iOS 16.0, *) {
                let width = presenter.view.bounds.width
                let bottomInset = presenter.view.window?.safeAreaInsets.bottom ?? 0
                let contentHeight = hostingController
                    .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                    .height
                sheetPC.detents = [.custom { context in
                    min(contentHeight + bottomInset, context.maximumDetentValue)
                }]
            } else {
                sheetPC.detents = [.medium()]
            }
        }

        pendingCrowdNodeReminder = false
        crowdNodeBalanceReminderController = hostingController
        // Show at most once per session — don't re-present on subsequent HomeView appearances.
        CrowdNodeBalanceReminder.shared.markActiveScreenReminderShown()
        presenter.present(hostingController, animated: true)
    }

    /// The active tab's top-most controller. Resolves via the tab-bar ancestor, which stays
    /// reachable even when Home isn't the selected tab (so the reminder can appear anywhere).
    private func activeTopViewController() -> UIViewController? {
        (tabBarController ?? view.window?.rootViewController)?.topController()
    }

    private func dismissCrowdNodeBalanceReminder(markDismissed: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        pendingCrowdNodeReminder = false

        if markDismissed {
            CrowdNodeBalanceReminder.shared.dismissActiveScreenReminder()
        }

        guard let controller = crowdNodeBalanceReminderController else {
            completion?()
            return
        }

        crowdNodeBalanceReminderController = nil
        controller.dismiss(animated: animated, completion: completion)
    }

    private func openCrowdNodeWithdrawalFromReminder() {
        dismissCrowdNodeBalanceReminder(markDismissed: false, animated: true) { [weak self] in
            guard let self = self, let presenter = self.activeTopViewController() else { return }
            CrowdNodeWithdrawalRouter.openWithdrawal(from: presenter)
        }
    }

    private func scheduleCrowdNodeReminderRetryIfNeeded() {
        guard pendingCrowdNodeReminder, !isCrowdNodeReminderRetryScheduled else { return }

        isCrowdNodeReminderRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            self.isCrowdNodeReminderRetryScheduled = false
            guard self.pendingCrowdNodeReminder else { return }

            self.presentCrowdNodeBalanceReminderIfNeeded()
        }
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
                DWLogger.log("CJTEST HomeViewController: sweep invoked from Home popup (\(amount))")
                self.viewModel.showCoinJoinSweepDialog = false
                Task { @MainActor in
                    // The post-sync popup (ModalDialog) is mid-dismissal here —
                    // its wrapper calls dismiss(animated:) immediately before
                    // running this action. Presenting the PIN now races that
                    // dismissal: DSAuthenticationManager.presentController:
                    // silently fails to present over the dismissing modal, so
                    // the auth continuation never resumes and the sweep hangs
                    // after the "preparing CoinJoin sweep" log. Wait (bounded
                    // ~3s) for the modal to finish dismissing first, so the PIN
                    // presents over a stable HomeViewController.
                    var waited = 0
                    while self.presentedViewController != nil, waited < 60 {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        waited += 1
                    }
                    let errorMessage = await self.viewModel.performCoinJoinSweep()
                    guard let errorMessage else { return }
                    // `positiveButtonAction:` binds the void overload (the async
                    // `-> Bool` overload has no action parameter).
                    self.showModalDialog(
                        style: .error,
                        icon: .system("exclamationmark.triangle"),
                        heading: NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
                        textBlock1: errorMessage,
                        positiveButtonText: NSLocalizedString("OK", comment: ""),
                        positiveButtonAction: nil
                    )
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
        // Pass the cropped image through so the profile bridge can compute
        // the avatar hash from the uploaded bytes.
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
    func homeViewRequestUsername() {
        let action = ShortcutAction(type: .createUsername)
        performAction(for: action, sender: nil)
    }

    #if DASHPAY
    func homeViewClaimInvitation() {
        showClaimInvitation()
    }
    #endif

    func homeViewShowSyncingStatus() {
        let controller = SyncingAlertViewController()
        present(controller, animated: true, completion: nil)
    }

    func homeViewDidChangeTopBarVisibility(shouldShow: Bool) {
        // At the top of the feed the navigation bar stays hidden so the
        // balance header gets the full height; once the user scrolls the
        // balances away, the bar (Dash logo + avatar) slides in.
        // `isNavigationBarHidden` keeps `BaseNavigationController`'s
        // willShow pass consistent with the live state, so pushes show
        // the bar for their own screens and pops restore ours.
        let shouldHide = !shouldShow
        guard hidesNavigationBarAtTop != shouldHide else { return }
        hidesNavigationBarAtTop = shouldHide
        if navigationController?.topViewController === self {
            navigationController?.setNavigationBarHidden(shouldHide, animated: true)
        }
    }

    func homeViewShowReceive(network: ChainNetwork) {
        delegate?.showReceiveLanding(network: network)
    }

    func homeViewShowSend(network: ChainNetwork) {
        delegate?.showSendLanding(network: network)
    }
    
    #if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfileWithUnreadNotifications unreadNotifications: UInt) {
        avatarView.configureAsCurrentUser()
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
    func txReclassifyTransactionsFlowDidClose(controller: TxReclassifyTransactionsInfoViewController, transaction: Transaction) {
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
        if state == .syncDone {
            #if DASHPAY
            if let invitationSetup = invitationSetup, let invitation = invitationSetup.invitation {
                handleDeeplink(invitation, definedUsername: invitationSetup.chosenUsername)
                self.invitationSetup = nil
                return
            }
            #endif

            presentCrowdNodeBalanceReminderIfNeeded()
        }
    }
}

extension HomeViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === crowdNodeBalanceReminderController else { return }

        crowdNodeBalanceReminderController = nil
        CrowdNodeBalanceReminder.shared.dismissActiveScreenReminder()
    }
}
