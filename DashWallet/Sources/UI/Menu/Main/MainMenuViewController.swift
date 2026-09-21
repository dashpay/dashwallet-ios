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
import DashUIKit
import MessageUI


class MainMenuViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: DWWipeDelegate?
    
    private var hostingController: UIHostingController<MainMenuScreen>!
    
    #if DASHPAY
    private let receiveModel: DWReceiveModelProtocol?
    private let dashPayReady: DWDashPayReadyProtocol?
    private let dashPayModel: DWDashPayProtocol?
    private let userProfileModel: CurrentUserProfileModel?
    #endif
    
    // MARK: - Initialization
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        #if DASHPAY
        self.receiveModel = nil
        self.dashPayReady = nil
        self.dashPayModel = nil
        self.userProfileModel = nil
        #endif
        
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    #if DASHPAY
    init(dashPayModel: DWDashPayProtocol,
               receiveModel: DWReceiveModelProtocol,
               dashPayReady: DWDashPayReadyProtocol,
               userProfileModel: CurrentUserProfileModel) {
        self.receiveModel = receiveModel
        self.dashPayReady = dashPayReady
        self.dashPayModel = dashPayModel
        self.userProfileModel = userProfileModel
        
        super.init(nibName: nil, bundle: nil)
    }
    #endif
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    override func loadView() {
        super.loadView()
        setupSwiftUIView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Navigation is now handled in SwiftUI
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Restore the tab bar when returning to this root screen. The
        // Join DashPay → CreateUsername push uses
        // `hidesBottomBarWhenPushed = true`; if the PIN modal sits on
        // top of the tab bar controller and the CreateUsername VC pops
        // out from underneath it (the known early-dismiss bug), UIKit
        // never restores the tab bar on the pop. Forcing it visible
        // here is a no-op when the bar is already showing.
        tabBarController?.tabBar.isHidden = false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - SwiftUI Setup
    
    private func setupSwiftUIView() {
        #if DASHPAY
        let swiftUIView = MainMenuScreen(
            vc: navigationController!,
            delegate: delegate as? MainMenuViewControllerDelegate,
            wipeDelegate: delegate,
            dashPayModel: dashPayModel,
            dashPayReady: dashPayReady,
            userProfileModel: userProfileModel
        ) {
            self.presentSupportEmailController()
        }
        #else
        let swiftUIView = MainMenuScreen(
            vc: navigationController!,
            delegate: delegate as? MainMenuViewControllerDelegate,
            wipeDelegate: delegate
        ) {
            self.presentSupportEmailController()
        }
        #endif
        
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
}


// MARK: - MFMailComposeViewControllerDelegate

extension MainMenuViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

struct MainMenuScreen: View {
    private let vc: UINavigationController
    private let delegateInternal: DelegateInternal
    private let onContactSupport: () -> ()
    
    @ObservedObject private var viewModel: MainMenuViewModel
    @State private var openSettings: Bool = false
    @State private var showTools: Bool = false
    @State private var showGovernance: Bool = false
    @State private var showSyncInfo: Bool = false
    @State private var showWallets: Bool = false
    @State private var showIdentities: Bool = false
    @State private var showSecurity: Bool = false
    @State private var showDashPayInfo: Bool = false
    @State private var showCreditsPurchasedToast: Bool = false
    @State private var navigateToDashPayFlow: Bool = false
    
    #if DASHPAY
    private let joinDPViewModel = JoinDashPayViewModel(initialState: .none)
    
    init(
        vc: UINavigationController,
        delegate: MainMenuViewControllerDelegate? = nil,
        wipeDelegate: DWWipeDelegate? = nil,
        dashPayModel: DWDashPayProtocol? = nil,
        dashPayReady: DWDashPayReadyProtocol? = nil,
        userProfileModel: CurrentUserProfileModel? = nil,
        onContactSupport: @escaping () -> ()
    ) {
        self.vc = vc
        self.onContactSupport = onContactSupport
        let viewModel = MainMenuViewModel(
            dashPayModel: dashPayModel,
            dashPayReady: dashPayReady,
            userProfileModel: userProfileModel
        )
        self.delegateInternal = DelegateInternal(
            delegate: delegate,
            wipeDelegate: wipeDelegate,
            viewModel: viewModel)
        self.viewModel = viewModel
    }
    #else
    
    init(
        vc: UINavigationController,
        delegate: MainMenuViewControllerDelegate? = nil,
        wipeDelegate: DWWipeDelegate? = nil,
        onContactSupport: @escaping () -> ()
    ) {
        self.vc = vc
        self.onContactSupport = onContactSupport
        let viewModel = MainMenuViewModel()
        self.delegateInternal = DelegateInternal(
            delegate: delegate,
            wipeDelegate: wipeDelegate,
            viewModel: viewModel)
        self.viewModel = viewModel
    }
    #endif
    
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                #if DASHPAY
                // Once a username is actually the user's, More leads to their
                // profile. This is also what a won vote resolves into: the
                // request row goes, the profile appears.
                if let username = viewModel.profileUsername {
                    DashUIKit.MenuItem(
                        leadingIcon: .custom("dp_user_generic", bundle: .main),
                        title: NSLocalizedString("Profile", comment: "DashPay"),
                        helpText: username,
                        accessory: .none
                    )
                    .onTapGesture { editProfile() }
                    .modifier(MenuViewModifier())
                    .padding(.vertical, 20)
                    .padding(.horizontal, 20)
                }

                if viewModel.showJoinDashpay {
                    JoinDashPayMenuItem(
                        viewModel: joinDPViewModel,
                        // The row replaced a card with two buttons, so it
                        // needs a handler covering both — see
                        // `handleJoinDashPayRowTap`.
                        onTap: { state in
                            handleJoinDashPayRowTap(state: state)
                        },
                        // Same destination as the row's tap: the details
                        // screen carries the explainer behind its own info
                        // control, as on Android.
                        onShowVotingInfo: { handleJoinDashPayRowTap(state: .voting) },
                        surface: .more,
                        isSyncing: viewModel.isSyncing
                    )
                    .padding(.vertical, 20)
                    .padding(.horizontal, 20)
                }
                #endif
                
                // Menu items grouped in sections
                VStack(spacing: 20) {
                    // Menu list - first group (first 2 items)
                    if viewModel.items.count >= 2 {
                        VStack(spacing: 2) {
                            ForEach(viewModel.items.prefix(2)) { item in
                                MenuItem(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    icon: item.icon,
                                    showChevron: false,
                                    action: item.action
                                )
                                .frame(minHeight: 56)
                            }
                        }
                        .padding(6)
                        .background(Color.dash.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
                    }

                    // Menu list - second group (remaining items)
                    if viewModel.items.count > 2 {
                        VStack(spacing: 2) {
                            ForEach(viewModel.items.dropFirst(2)) { item in
                                MenuItem(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    icon: item.icon,
                                    showChevron: false,
                                    action: item.action
                                )
                                .frame(minHeight: 56)
                            }
                        }
                        .padding(6)
                        .background(Color.dash.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 60)
            }
            
            if showCreditsPurchasedToast {
                ToastView(
                    text: NSLocalizedString("Successful purchase", comment: ""),
                    icon: .system("checkmark.circle.fill")
                )
                .frame(height: 20)
                .padding(.bottom, 30)
            }
            
            NavigationLink(
                destination: SettingsScreen(vc: vc, onDidRescan: {
                    self.vc.popToRootViewController(animated: false)
                    self.delegateInternal.mainMenuViewControllerOpenHomeScreen()
                }),
                isActive: $openSettings
            ) {
                EmptyView()
            }
            
            NavigationLink(
                destination: ToolsMenuScreen(vc: vc),
                isActive: $showTools
            ) {
                EmptyView()
            }

            NavigationLink(
                destination: GovernanceMenuScreen(vc: vc),
                isActive: $showGovernance
            ) {
                EmptyView()
            }
            
            NavigationLink(
                destination: SyncInfoMenuScreen(vc: vc),
                isActive: $showSyncInfo
            ) {
                EmptyView()
            }

            NavigationLink(
                destination: WalletsScreen(vc: vc, wipeDelegate: delegateInternal.wipeDelegate),
                isActive: $showWallets
            ) {
                EmptyView()
            }

            NavigationLink(
                destination: IdentitiesScreen(vc: vc),
                isActive: $showIdentities
            ) {
                EmptyView()
            }

            NavigationLink(
                destination: SecurityMenuScreen(vc: vc, wipeDelegate: delegateInternal.wipeDelegate),
                isActive: $showSecurity
            ) {
                EmptyView()
            }
        }
        .background(Color.dash.primaryBackground)
        .onAppear {
            viewModel.buildMenuSections()
            viewModel.refreshProfileUsername()
            #if DASHPAY
            // A vote can resolve while the user sits on this screen, and this
            // check is what notices. It was only triggered from Home, so More
            // kept showing "Voting" — or nothing — long after the result.
            DWIdentityRegistrationCoordinator.shared.checkPendingContestResolution()
            #endif
        }
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        #if DASHPAY
        .sheet(isPresented: $showDashPayInfo, onDismiss: {
            if navigateToDashPayFlow {
                navigateToDashPayFlow = false
                joinDashPay()
            }
        }) {
            let dialog = JoinDashPayInfoDialog(
                action: {
                    navigateToDashPayFlow = true
                },
                onClaimInvitation: {
                    self.claimInvitation()
                },
                onShieldFunds: {
                    self.shieldFunds()
                })
            
            // No detent here: the dialog is a `BottomSheet.selfSizing`, which
            // publishes its own measured height.
            dialog
        }
        #endif
    }
    
    #if DASHPAY
    private func handleJoinDashPayTap(state: JoinDashPayState) {
        switch state {
        case .registered:
            editProfile()
        case .voting:
            showUsernameRequestStatus()
        case .none:
            handleJoinButtonAction()
        default:
            break
        }
    }

    /// The DashPay row is tappable while a contested submission is being voted
    /// on; this is where it goes. Reached only in the `.voting` state, which
    /// `JoinDashPayViewModel` derives from
    /// `DWContestedNameStatusService.pendingLabel`.
    private func showUsernameRequestStatus() {
        guard let label = DWContestedNameStatusService.shared.pendingLabel else { return }
        let screen = UsernameRequestStatusScreen(
            viewModel: UsernameRequestStatusViewModel(label: label),
            // `MainMenuScreen` is a struct and `vc` is the stack it lives in,
            // so the pop is captured directly — there is no reference cycle
            // for a `weak self` to break here.
            onBack: { vc.popViewController(animated: true) })
        let controller = UIHostingController(rootView: screen)
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    /// Where a tap on the DashPay menu row goes. The row replaced a card with
    /// two buttons, so it has to cover what both of them did — it is not the
    /// old action button under a new name.
    ///
    /// In particular `.callToAction` must NOT reach `editProfile()`: that
    /// method guards on an existing identity and returns silently for exactly
    /// the users this state describes, which read on screen as a dead row.
    private func handleJoinDashPayRowTap(state: JoinDashPayState) {
        switch state {
        case .loading, .retryLoading:
            return
        case .usernameRequired:
            joinDashPay()
        case .none, .callToAction, .blocked, .failed, .contested:
            // Not registered (or the attempt failed): open the join flow,
            // which also carries the "Have an invitation?" entry.
            handleJoinButtonAction()
        case .creationFailed, .interrupted:
            // Straight to the form, whose recovery machinery picks the attempt
            // up — NOT through the info dialog. That dialog's continuation
            // evaluates funding readiness, and a Core-funded attempt has
            // already spent the registration amount: the interstitial would
            // then disable Continue and hide the transparent escape, walling
            // off the one screen that waives the balance requirement for a
            // recovery. Home's row goes straight to the form for the same
            // reason (`showCreateUsername`). The reported label comes along so
            // the user does not retype it.
            openCreateUsernameForRecovery(username: joinDPViewModel.username)
        case .creating:
            // Nothing to act on while it runs.
            break
        case .approved:
            // Acknowledge the report as well as acting on it. Without this
            // `completedTileUsername` stays persisted, and since More's row is
            // now kept visible by that record (`reportsRegistration`), the
            // completed-registration row would come back after the user had
            // already opened the profile from it — including on the next
            // launch. `handleJoinDashPayAction` is a different entry point and
            // this row does not go through it.
            editProfile()
            joinDPViewModel.markAsDismissed()
            viewModel.refreshJoinDashPayBanner()
        case .registered:
            editProfile()
        case .voting:
            showUsernameRequestStatus()
        }
    }

    private func handleJoinDashPayAction(state: JoinDashPayState) {
        switch state {
        case .blocked, .failed, .contested:
            handleJoinButtonAction()
        default:
            editProfile()
            joinDPViewModel.markAsDismissed()
            viewModel.refreshJoinDashPayBanner()
        }
    }
    
    private func handleJoinButtonAction() {
        // Always open the info dialog — same reason as HomeView: it is the
        // only surface carrying "Have an invitation?", and the one-shot latch
        // hid the redeem path for good from anyone who had already tapped
        // Upgrade before their invitation arrived.
        showDashPayInfo = true
    }
    #endif
    
    private func handleNavigation(_ destination: MainMenuNavigationDestination?) {
        switch destination {
        case .explore:
            showExplore()
        case .syncInfo:
            showSyncInfo = true
        case .wallets:
            showWallets = true
        case .identities:
            showIdentities = true
        case .security:
            showSecurity = true
        case .settings:
            openSettings = true
        case .tools:
            showTools = true
        case .support:
            onContactSupport()
        case .governance:
            showGovernance = true
        case .none:
            return
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }
    
    // MARK: - Navigation Methods
    
    private func showExplore() {
        let screen = ExploreMenuScreen(
            vc: vc,
            onShowSendPayment: { delegateInternal.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue) },
            onShowReceivePayment: { delegateInternal.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue) },
            onShowGiftCard: { txId in delegateInternal.showGiftCard(txId) }
        )
        let controller = UIHostingController(rootView: screen)
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }




    #if DASHPAY
    private func editProfile() {
        // Gate on the strict SDK-side identity check so the editor
        // never opens against a missing identity — Save would fail
        // and the screen would render blank. See profileAction() in
        // HomeViewController for the same gate.
        guard DWCurrentUserIdentityInfo.shared.hasIdentity else { return }
        let controller = RootEditProfileViewController()
        controller.delegate = delegateInternal
        let navigation = BaseNavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        vc.present(navigation, animated: true)
    }
    
    #if DASHPAY
    /// Manual redeem entry (Join DashPay dialog → "Have an invitation?").
    private func claimInvitation() {
        guard let dashPayModel = viewModel.dashPayModel else { return }
        ClaimInvitationFlow.pushRedeemScreen(on: vc, dashPayModel: dashPayModel)
    }

    /// The "Shield your funds first" leg of the username privacy step.
    /// Preselected, not pinned — the form still lets either endpoint change.
    private func shieldFunds() {
        let controller = InternalTransferHostingController(transferTo: .balance(.shielded))
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    #endif

    private func joinDashPay() {
        guard let dashPayModel = viewModel.dashPayModel else { return }
        if DWIdentityRegistrationCoordinator.shared.registrationRecovery().isPending {
            pushCreateUsernameForm(dashPayModel: dashPayModel)
            return
        }

        // A registration waiting to be recovered goes straight to the form,
        // whatever brought the user here. Same rule as Home's
        // `showCreateUsername`: the failed attempt already spent the
        // registration amount, so the readiness interstitial would refuse to
        // let it through on a balance the recovery does not need. The recovery
        // IS the funding.
        if DWIdentityRegistrationCoordinator.shared.hasPendingRegistrationRecovery() {
            pushCreateUsernameForm(dashPayModel: dashPayModel)
            return
        }

        // Straight to the form: the shielded question now lives on the Join
        // DashPay sheet's privacy page, and the get-ready interstitial that
        // used to stand here is gone.
        pushCreateUsernameForm(dashPayModel: dashPayModel)
    }

    /// The retry action behind the row's `.creationFailed` / `.interrupted`
    /// report: the create form, prefilled, with no readiness gate in front of
    /// it.
    private func openCreateUsernameForRecovery(username: String) {
        guard let dashPayModel = viewModel.dashPayModel else { return }
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.pushCreateUsernameForm(
            on: vc,
            dashPayModel: dashPayModel,
            definedUsername: trimmed.isEmpty ? nil : trimmed)
    }


    private func pushCreateUsernameForm(dashPayModel: DWDashPayProtocol) {
        Self.pushCreateUsernameForm(on: vc, dashPayModel: dashPayModel)
    }

    private static func pushCreateUsernameForm(
        on navigationController: UINavigationController,
        dashPayModel: DWDashPayProtocol,
        definedUsername: String? = nil
    ) {
        let controller = CreateUsernameViewController(
            dashPayModel: dashPayModel,
            invitationURL: nil,
            definedUsername: definedUsername
        )
        controller.hidesBottomBarWhenPushed = true
        controller.completionHandler = { [weak navigationController] result in
            let message = result 
                ? NSLocalizedString("Username was successfully requested", comment: "Usernames")
                : NSLocalizedString("Your request was cancelled", comment: "Usernames")
            
            // Find the root view controller to show HUD
            if let rootVC = navigationController?.viewControllers.first {
                rootVC.view.dw_showInfoHUD(withText: message, offsetForNavBar: true)
            }
        }
        navigationController.pushViewController(controller, animated: true)
    }
    #endif
}


extension MainMenuScreen {
    class DelegateInternal: NSObject, RootEditProfileViewControllerDelegate {
        private weak var delegate: MainMenuViewControllerDelegate?
        weak var wipeDelegate: DWWipeDelegate?
        private let viewModel: MainMenuViewModel
        
        init(delegate: MainMenuViewControllerDelegate?, wipeDelegate: DWWipeDelegate?, viewModel: MainMenuViewModel) {
            self.delegate = delegate
            self.wipeDelegate = wipeDelegate
            self.viewModel = viewModel
        }
        
        func mainMenuViewControllerOpenHomeScreen() {
            if let delegate = delegate {
                delegate.mainMenuViewControllerOpenHomeScreen()
            }
        }
        
        func showPaymentsController(withActivePage pageIndex: Int) {
            delegate?.showPaymentsController(withActivePage: pageIndex)
        }
        
        func showGiftCard(_ txId: Data) {
            delegate?.showGiftCard(txId)
        }
        
        #if DASHPAY
        func editProfileViewController(_ controller: RootEditProfileViewController,
                                     updateDisplayName rawDisplayName: String,
                                     aboutMe rawAboutMe: String,
                                     avatarURLString: String?,
                                     avatarImage: UIImage?) {
            #if DASHPAY
            // The credit gate runs BEFORE the write, against the identity's
            // real balance — the warning used to fire after the update had
            // already been broadcast, and against a mock counter
            // (`BuyCreditsModel.currentCredits`) that had nothing to do with
            // the identity.
            Task { @MainActor in
                guard await controller.confirmAgainstIdentityCredits() else {
                    controller.dismiss(animated: true)
                    return
                }

                viewModel.userProfileModel?.updateModel.update(
                    withDisplayName: rawDisplayName,
                    aboutMe: rawAboutMe,
                    avatarURLString: avatarURLString,
                    avatarImage: avatarImage)
                controller.dismiss(animated: true)
            }
            #else
            controller.dismiss(animated: true)
            #endif
        }
        
        func editProfileViewControllerDidCancel(_ controller: RootEditProfileViewController) {
            controller.dismiss(animated: true)
        }
        #endif
    }

}
