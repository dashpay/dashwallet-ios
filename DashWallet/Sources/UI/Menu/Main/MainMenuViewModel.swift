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
    case explore
    case syncInfo
    case wallets
    case identities
    case security
    case settings
    case tools
    case support
    case governance
}

protocol MainMenuViewModelDelegate: AnyObject {
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
    @Published private(set) var showJoinDashpay: Bool = false
    @Published private(set) var isSyncing: Bool = false
    #endif

    weak var delegate: MainMenuViewModelDelegate?

    private var cancellableBag = Set<AnyCancellable>()

    /// Wallets and Identities are advanced surfaces: they expose accounts,
    /// derivation and Platform identities, which is more than an ordinary user
    /// is asked to reason about. They appear only while Advanced mode is on.
    private var showsAdvancedRows: Bool {
        DWGlobalOptions.sharedInstance().advancedModeEnabled
    }

    /// The menu is built once, so without this a row toggled in Settings would
    /// not appear until something else rebuilt it.
    private func observeAdvancedMode() {
        NotificationCenter.default.publisher(for: .advancedModeDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenuSections()
            }
            .store(in: &cancellableBag)
    }

    #if DASHPAY
    init(dashPayModel: DWDashPayProtocol? = nil,
         dashPayReady: DWDashPayReadyProtocol? = nil,
         userProfileModel: CurrentUserProfileModel? = nil) {
        self.dashPayModel = dashPayModel
        self.dashPayReady = dashPayReady
        self.userProfileModel = userProfileModel
        buildMenuSections()
        observeAdvancedMode()

        userProfileModel?.$showJoinDashpay
            .receive(on: DispatchQueue.main)
            .assign(to: &$showJoinDashpay)

        userProfileModel?.$isSyncing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSyncing)
    }

    func refreshJoinDashPayBanner() {
        userProfileModel?.refreshJoinDashPayBanner()
    }
    #else
    init() {
        buildMenuSections()
        observeAdvancedMode()
    }
    #endif
    
    // MARK: - Menu Building
    
    func buildMenuSections() {
        var allItems: [MenuItemModel] = []
        
        // Explore
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Explore", comment: ""),
            icon: .custom("image.explore", maxHeight: 30),
            action: { [weak self] in
                self?.navigationDestination = .explore
            }
        ))
        
        // Sync Info
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Sync Info", comment: ""),
            icon: .system("arrow.triangle.2.circlepath"),
            action: { [weak self] in
                self?.navigationDestination = .syncInfo
            }
        ))

        if showsAdvancedRows {
            // Wallets
            allItems.append(MenuItemModel(
                title: NSLocalizedString("Wallets", comment: ""),
                icon: .custom("image.wallets", maxHeight: 30),
                action: { [weak self] in
                    self?.navigationDestination = .wallets
                }
            ))

            // Identities — the device's Dash Platform identities (under Wallets)
            allItems.append(MenuItemModel(
                title: NSLocalizedString("Identities", comment: "Identities"),
                icon: .system("person.crop.circle"),
                action: { [weak self] in
                    self?.navigationDestination = .identities
                }
            ))
        }

        // Security
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Security", comment: ""),
            icon: .custom("image.security", maxHeight: 30),
            action: { [weak self] in
                self?.navigationDestination = .security
            }
        ))
        
        // Settings
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Settings", comment: ""),
            icon: .custom("image.settings", maxHeight: 30),
            action: { [weak self] in
                self?.navigationDestination = .settings
            }
        ))
        
        // Tools
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Tools", comment: ""),
            icon: .custom("image.tools", maxHeight: 30),
            action: { [weak self] in
                self?.navigationDestination = .tools
            }
        ))
        
        // Support
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Support", comment: ""),
            icon: .custom("image.support", maxHeight: 30),
            action: { [weak self] in
                self?.navigationDestination = .support
            }
        ))
        
        // Governance — Masternodes plus (on DashPay builds, when enabled)
        // username Voting. Not DashPay-gated: Masternodes is a Core-side
        // surface that every build configuration can reach.
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Governance", comment: "Governance"),
            icon: .custom("menu_voting", maxHeight: 30),
            action: { [weak self] in
                self?.navigationDestination = .governance
            }
        ))
        
        self.items = allItems
    }
    
    // MARK: - Actions

    func resetNavigation() {
        navigationDestination = nil
    }
    
    func showCreditsWarning(heading: String, message: String) {
        creditsWarningHeading = heading
        creditsWarningMessage = message
        showCreditsWarning = true
    }
}
