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
    
    @Published var items: [MenuItemModel] = []
    @Published var navigationDestination: MainMenuNavigationDestination?
    @Published var showCreditsWarning: Bool = false
    @Published var creditsWarningHeading: String = ""
    @Published var creditsWarningMessage: String = ""
    
    #if DASHPAY
    let dashPayReady: DWDashPayReadyProtocol?
    let dashPayModel: DWDashPayProtocol?
    let userProfileModel: CurrentUserProfileModel?
    #endif
    
    weak var delegate: MainMenuViewModelDelegate?
    
    #if DASHPAY
    init(dashPayModel: DWDashPayProtocol? = nil,
         dashPayReady: DWDashPayReadyProtocol? = nil,
         userProfileModel: CurrentUserProfileModel? = nil) {
        self.dashPayModel = dashPayModel
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
    
    func buildMenuSections() {
        var allItems: [MenuItemModel] = []
        
        // Buy & Sell Dash
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Buy & sell Dash", comment: ""),
            icon: .custom("image.buy.and.sell", maxHeight: 22),
            action: { [weak self] in
                self?.handleBuySellDash()
            }
        ))
        
        // Explore
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Explore", comment: ""),
            icon: .custom("image.explore", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .explore
            }
        ))
        
        // Security
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Security", comment: ""),
            icon: .custom("image.security", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .security
            }
        ))
        
        // Settings
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Settings", comment: ""),
            icon: .custom("image.settings", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .settings
            }
        ))
        
        // Tools
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Tools", comment: ""),
            icon: .custom("image.tools", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .tools
            }
        ))
        
        // Support
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Support", comment: ""),
            icon: .custom("image.support", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .support
            }
        ))
        
        #if DASHPAY
        // Voting
        if VotingPrefs.shared.votingEnabled {
            allItems.append(MenuItemModel(
                title: NSLocalizedString("Voting", comment: ""),
                icon: .custom("menu_voting", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .voting
                }
            ))
        }
        #endif
        
        self.items = allItems
    }
    
    // MARK: - Actions

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
    
    func resetNavigation() {
        navigationDestination = nil
    }
    
    func showCreditsWarning(heading: String, message: String) {
        creditsWarningHeading = heading
        creditsWarningMessage = message
        showCreditsWarning = true
    }
}
