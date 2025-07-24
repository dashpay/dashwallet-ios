//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

import SwiftUI
import Combine

enum MainMenuNavigationDestination {
    case buySellPortal
    case explore
    case security
    case settings
    case tools
    case support
    #if DASHPAY
    case invite
    case voting
    case editProfile
    case showRequestDetails
    case showMixDashDialog
    case showDashPayInfo
    case joinDashPay
    #endif
}

protocol MainMenuViewModelDelegate: AnyObject {
    func mainMenuViewModelImportPrivateKey()
    func mainMenuViewModelOpenHomeScreen()
    func showPaymentsController(with pageIndex: Int)
    func showGiftCard(_ txId: Data)
}

@MainActor
class MainMenuViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var menuSections: [MenuSection] = []
    @Published var navigationDestination: MainMenuNavigationDestination?
    
    // MARK: - Dependencies
    
    #if DASHPAY
    let receiveModel: DWReceiveModelProtocol?
    let dashPayReady: DWDashPayReadyProtocol?
    let dashPayModel: DWDashPayProtocol?
    let userProfileModel: CurrentUserProfileModel?
    #endif
    
    weak var delegate: MainMenuViewModelDelegate?
    
    // MARK: - Initialization
    
    #if DASHPAY
    init(dashPayModel: DWDashPayProtocol? = nil,
         receiveModel: DWReceiveModelProtocol? = nil,
         dashPayReady: DWDashPayReadyProtocol? = nil,
         userProfileModel: CurrentUserProfileModel? = nil) {
        self.dashPayModel = dashPayModel
        self.receiveModel = receiveModel
        self.dashPayReady = dashPayReady
        self.userProfileModel = userProfileModel
        buildMenuSections()
    }
    #else
    init() {
        buildMenuSections()
    }
    #endif
    
    // MARK: - Menu Building
    
    private func buildMenuSections() {
        var sections: [MenuSection] = []
        
        // DashPay section (if enabled and not registered)
        #if DASHPAY
        if userProfileModel?.showJoinDashpay == true {
            sections.append(MenuSection(items: [
                .joinDashPay
            ]))
        }
        #endif
        
        // Main services section
        sections.append(MenuSection(items: [
            .buySellDash,
            .explore
        ]))
        
        // Settings section
        sections.append(MenuSection(items: [
            .security,
            .settings,
            .tools,
            .support
        ]))
        
        self.menuSections = sections
    }
    
    // MARK: - Actions
    
    func handleMenuAction(_ item: MenuItemType) {
        switch item {
        case .joinDashPay:
            // This will be handled by the JoinDashPayView integration
            break
        case .buySellDash:
            handleBuySellDash()
        case .explore:
            navigationDestination = .explore
        case .security:
            navigationDestination = .security
        case .settings:
            navigationDestination = .settings
        case .tools:
            navigationDestination = .tools
        case .support:
            navigationDestination = .support
        #if DASHPAY
        case .invite:
            navigationDestination = .invite
        case .voting:
            navigationDestination = .voting
        #endif
        }
    }

    private func handleBuySellDash() {
        DSAuthenticationManager.sharedInstance().authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            alertIfLockout: true
        ) { [weak self] authenticated, usedBiometrics, cancelled in
            if authenticated {
                self?.navigationDestination = .buySellPortal
            }
        }
    }
    
    // MARK: - DashPay Navigation Methods
    
    #if DASHPAY
    func showEditProfile() {
        navigationDestination = .editProfile
    }
    
    func showRequestDetails() {
        navigationDestination = .showRequestDetails
    }
    
    func showMixDashDialog() {
        navigationDestination = .showMixDashDialog
    }
    
    func showDashPayInfo() {
        navigationDestination = .showDashPayInfo
    }
    
    func joinDashPay() {
        navigationDestination = .joinDashPay
    }
    #endif
    
    func resetNavigation() {
        navigationDestination = nil
    }
    
    func updateModel() {
        #if DASHPAY
        let invitationsEnabled = DWGlobalOptions.sharedInstance().dpInvitationFlowEnabled && (userProfileModel?.blockchainIdentity != nil)
        let isVotingEnabled = VotingPrefsWrapper.getIsEnabled()
        #endif
        
        buildMenuSections()
    }
}

// MARK: - Data Models

struct MenuSection {
    let items: [MenuItemType]
}

enum MenuItemType: CaseIterable {
    case joinDashPay
    case buySellDash
    case explore
    case security
    case settings
    case tools
    case support
    #if DASHPAY
    case invite
    case voting
    #endif
    
    var title: String {
        switch self {
        case .joinDashPay:
            return NSLocalizedString("Join DashPay", comment: "")
        case .buySellDash:
            return NSLocalizedString("Buy & sell Dash", comment: "")
        case .explore:
            return NSLocalizedString("Explore", comment: "")
        case .security:
            return NSLocalizedString("Security", comment: "")
        case .settings:
            return NSLocalizedString("Settings", comment: "")
        case .tools:
            return NSLocalizedString("Tools", comment: "")
        case .support:
            return NSLocalizedString("Support", comment: "")
        #if DASHPAY
        case .invite:
            return NSLocalizedString("Invite", comment: "")
        case .voting:
            return NSLocalizedString("Voting", comment: "")
        #endif
        }
    }
    
    var subtitle: String? {
        switch self {
        case .joinDashPay:
            return NSLocalizedString("Create a username and say goodbye to numerical addresses", comment: "")
        case .buySellDash:
            return nil
        case .explore:
            return nil
        case .security:
            return nil
        case .settings:
            return nil
        case .tools:
            return nil
        case .support:
            return nil
        #if DASHPAY
        case .invite:
            return nil
        case .voting:
            return nil
        #endif
        }
    }
    
    var iconName: IconName {
        switch self {
        case .joinDashPay:
            return .custom("account", maxHeight: 22)
        case .buySellDash:
            return .custom("image.buy.and.sell", maxHeight: 22)
        case .explore:
            return .custom("image.explore", maxHeight: 22)
        case .security:
            return .custom("image.security", maxHeight: 22)
        case .settings:
            return .custom("image.settings", maxHeight: 22)
        case .tools:
            return .custom("image.tools", maxHeight: 22)
        case .support:
            return .custom("image.support", maxHeight: 22)
        #if DASHPAY
        case .invite:
            return .custom("invite", maxHeight: 22)
        case .voting:
            return .custom("voting", maxHeight: 22)
        #endif
        }
    }
}

