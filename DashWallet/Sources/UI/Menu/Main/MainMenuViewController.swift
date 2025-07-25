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

class MainMenuViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: DWWipeDelegate?
    
    var viewModel: MainMenuViewModel!
    private var hostingController: UIHostingController<MainMenuView>!
    
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
        navigationItem.largeTitleDisplayMode = .never
        viewModel.buildMenuSections()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
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
        
        let swiftUIView = MainMenuView(
            vc: navigationController!,
            viewModel: viewModel,
            delegate: delegate as? MainMenuViewControllerDelegate,
            wipeDelegate: delegate
        )
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
    
    // MARK: - Support Email (keeping as requested)
    
    override func presentSupportEmailController() {
        // TODO: Implementation kept as requested - to be handled later
    }
}


// MARK: - MFMailComposeViewControllerDelegate

extension MainMenuViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

struct MainMenuView: View {
    private let vc: UINavigationController
    private let delegateInternal: DelegateInternal
    @StateObject private var viewModel: MainMenuViewModel
    @State private var openSettings: Bool = false
    @State private var showTools: Bool = false
    @State private var showSecurity: Bool = false
    
    #if DASHPAY
    let joinDPViewModel = JoinDashPayViewModel(initialState: .none)
    #endif
    
    init(vc: UINavigationController, viewModel: MainMenuViewModel, delegate: MainMenuViewControllerDelegate? = nil, wipeDelegate: DWWipeDelegate? = nil) {
        self.vc = vc
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.delegateInternal = DelegateInternal(
            delegate: delegate,
            wipeDelegate: wipeDelegate,
            viewModel: viewModel
        )
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text(NSLocalizedString("More", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primaryText)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                #if DASHPAY
                // Join DashPay section (if needed)
                if viewModel.userProfileModel?.showJoinDashpay == true {
                    JoinDashPayView(
                        viewModel: joinDPViewModel,
                        onTap: { state in
                            handleJoinDashPayTap(state: state)
                        },
                        onActionButton: { state in
                            handleJoinDashPayAction(state: state)
                        },
                        onDismissButton: { state in
                            joinDPViewModel.markAsDismissed()
                        },
                        onSizeChange: { size in
                            // Handle size changes if needed
                        }
                    )
                    .padding(.horizontal, 18)
                }
                #endif
                
                // Menu sections
                ForEach(Array(viewModel.menuSections.enumerated()), id: \.offset) { index, section in
                    MenuSectionView(section: section) { menuItem in
                        viewModel.handleMenuAction(menuItem)
                    }
                }
                
                Spacer(minLength: 60) // Bottom padding for tab bar
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
                destination: ToolsMenuScreen(vc: vc, onImportPrivateKey: {
                    self.vc.popToRootViewController(animated: false)
                    self.delegateInternal.mainMenuViewControllerImportPrivateKey()
                }),
                isActive: $showTools
            ) {
                EmptyView()
            }
            
            NavigationLink(
                destination: SecurityScreen(vc: vc),
                isActive: $showSecurity
            ) {
                EmptyView()
            }
        }
        .background(Color.primaryBackground)
        .onAppear {
            viewModel.buildMenuSections()
        }
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
    }
    
    #if DASHPAY
    private func handleJoinDashPayTap(state: JoinDashPayState) {
        switch state {
        case .registered:
            viewModel.showEditProfile()
        case .voting:
            viewModel.showRequestDetails()
        case .none:
            handleJoinButtonAction()
        default:
            break
        }
    }
    
    private func handleJoinDashPayAction(state: JoinDashPayState) {
        switch state {
        case .blocked, .failed, .contested:
            handleJoinButtonAction()
        default:
            viewModel.showEditProfile()
            joinDPViewModel.markAsDismissed()
        }
    }
    
    private func handleJoinButtonAction() {
        let shouldShowMixDashDialog = CoinJoinService.shared.mode == .none || !UsernamePrefs.shared.mixDashShown
        let shouldShowDashPayInfo = !UsernamePrefs.shared.joinDashPayInfoShown
        
        if shouldShowMixDashDialog {
            viewModel.showMixDashDialog()
        } else if shouldShowDashPayInfo {
            viewModel.showDashPayInfo()
        } else {
            viewModel.joinDashPay()
        }
    }
    #endif
    
    private func handleNavigation(_ destination: MainMenuNavigationDestination?) {
        switch destination {
        case .buySellPortal:
            showBuySellPortal()
        case .explore:
            showExplore()
        case .security:
            showSecurity = true
        case .settings:
            openSettings = true
        case .tools:
            showTools = true
        case .support:
            break // TODO
        #if DASHPAY
        case .invite:
            showInvite()
        case .voting:
            showVoting()
        case .editProfile:
            editProfile()
        case .showRequestDetails:
            showRequestDetails()
        case .showMixDashDialog:
            showMixDashDialog()
        case .showDashPayInfo:
            showDashPayInfo()
        case .joinDashPay:
            joinDashPay()
        #endif
        case .none:
            return
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }
    
    // MARK: - Navigation Methods
    
    private func showBuySellPortal() {
        let controller = BuySellPortalViewController.controller()
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func showExplore() {
        let controller = ExploreViewController()
        controller.delegate = delegateInternal
        let navigationController = BaseNavigationController(rootViewController: controller)
        vc.present(navigationController, animated: true)
    }
    
    #if DASHPAY
    private func showInvite() {
        let controller = DWInvitationHistoryViewController()
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func showVoting() {
        let controller = UsernameVotingViewController.controller()
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func editProfile() {
        let controller = RootEditProfileViewController()
        controller.delegate = delegateInternal
        let navigation = BaseNavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        vc.present(navigation, animated: true)
    }
    
    private func showRequestDetails() {
        let controller = RequestDetailsViewController.controller()
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func showMixDashDialog() {
        let swiftUIView = MixDashDialog(
            positiveAction: {
                let controller = CoinJoinLevelsViewController.controller(isFullScreen: false)
                controller.hidesBottomBarWhenPushed = true
                self.vc.pushViewController(controller, animated: true)
            },
            negativeAction: {
                if UsernamePrefs.shared.joinDashPayInfoShown {
                    self.joinDashPay()
                } else {
                    UsernamePrefs.shared.joinDashPayInfoShown = true
                    self.showDashPayInfo()
                }
            }
        )
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(260)
        vc.present(hostingController, animated: true)
    }
    
    private func showDashPayInfo() {
        let swiftUIView = JoinDashPayInfoDialog {
            self.joinDashPay()
        }
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(600)
        vc.present(hostingController, animated: true)
    }
    
    private func joinDashPay() {
        guard let dashPayModel = viewModel.dashPayModel else { return }
        
        let controller = CreateUsernameViewController(
            dashPayModel: dashPayModel,
            invitationURL: nil,
            definedUsername: nil
        )
        controller.hidesBottomBarWhenPushed = true
        controller.completionHandler = { result in
            let message = result 
                ? NSLocalizedString("Username was successfully requested", comment: "Usernames")
                : NSLocalizedString("Your request was cancelled", comment: "Usernames")
            
            // Find the root view controller to show HUD
            if let rootVC = self.vc.viewControllers.first {
                rootVC.view.dw_showInfoHUD(withText: message, offsetForNavBar: true)
            }
        }
        vc.pushViewController(controller, animated: true)
    }
    #endif
}

struct MenuSectionView: View {
    let section: MenuSection
    let onMenuItemTap: (MenuItemType) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(section.items, id: \.self) { item in
                MenuItemView(item: item) {
                    onMenuItemTap(item)
                }
            }
        }
        .padding(.vertical, 5)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
        .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
        .padding(.horizontal, 20)
    }
}

struct MenuItemView: View {
    let item: MenuItemType
    let action: () -> Void
    
    var body: some View {
        MenuItem(
            title: item.title,
            subtitle: nil,
            icon: item.iconName,
            showChevron: false,
            action: action
        )
    }
}

// MARK: - DelegateInternal

extension MainMenuView {
    class DelegateInternal: NSObject {
        private weak var delegate: MainMenuViewControllerDelegate?
        private weak var wipeDelegate: DWWipeDelegate?
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
        
        func mainMenuViewControllerImportPrivateKey() {
            if let delegate = delegate {
                delegate.mainMenuViewControllerImportPrivateKey()
            }
        }
        
        func showPaymentsController(withActivePage pageIndex: Int) {
            delegate?.showPaymentsController(withActivePage: pageIndex)
        }
        
        func showGiftCard(_ txId: Data) {
            delegate?.showGiftCard(txId)
        }
    }
}

extension MainMenuView.DelegateInternal: ExploreViewControllerDelegate {
    func exploreViewControllerShowSendPayment(_ controller: ExploreViewController) {
        showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
    }
    
    func exploreViewControllerShowReceivePayment(_ controller: ExploreViewController) {
        showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
    }
    
    func exploreViewControllerShowGiftCard(_ controller: ExploreViewController, txId: Data) {
        showGiftCard(txId)
    }
}

#if DASHPAY
extension MainMenuView.DelegateInternal: RootEditProfileViewControllerDelegate {
    func editProfileViewController(_ controller: RootEditProfileViewController,
                                 updateDisplayName rawDisplayName: String,
                                 aboutMe rawAboutMe: String,
                                 avatarURLString: String?) {
        #if DASHPAY
        viewModel.userProfileModel?.updateModel.update(withDisplayName: rawDisplayName, aboutMe: rawAboutMe, avatarURLString: avatarURLString)
        #endif
        controller.dismiss(animated: true)
    }
    
    func editProfileViewControllerDidCancel(_ controller: RootEditProfileViewController) {
        controller.dismiss(animated: true)
    }
}
#endif
