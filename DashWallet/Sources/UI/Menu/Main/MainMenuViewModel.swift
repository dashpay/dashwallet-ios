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
    
    #if DASHPAY
    let dashPayReady: DWDashPayReadyProtocol?
    let dashPayModel: DWDashPayProtocol?
    let userProfileModel: CurrentUserProfileModel?
    @Published private(set) var showJoinDashpay: Bool = false
    @Published private(set) var isSyncing: Bool = false
    /// The username this wallet actually owns, or nil while it owns none.
    ///
    /// Drives the Profile entry: once a name is the user's — a plain
    /// registration, an instant companion, or a contested request that won its
    /// vote — More leads to their profile instead of offering to join.
    /// Contested labels still out for a vote are excluded by
    /// `DWCurrentUserIdentityInfo` itself, so a pending request never shows a
    /// profile that does not exist yet.
    @Published private(set) var profileUsername: String?
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

        refreshProfileUsername()
        // The same notifications the banner policy listens to: registration
        // finishing, a contest resolving in our favour, or a wallet/network
        // switch changing whose names these are.
        for name in [
            Notification.Name.DWDashPayRegistrationStatusUpdated,
            SwiftDashSDKWalletState.activeWalletDidChangeNotification,
            NSNotification.Name.DWCurrentNetworkDidChange
        ] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshProfileUsername() }
                .store(in: &cancellableBag)
        }
    }

    func refreshProfileUsername() {
        // Only names this identity actually owns.
        //
        // `DWGlobalOptions.dashpayUsername` used to stand in for them, and it
        // cannot: it is one global value, cleared on a network change but not
        // on a wallet change, and `namesAreLoaded` is also true for an identity
        // that owns nothing. Switching between two wallets on one network then
        // showed the first wallet's username on the second wallet's profile
        // row — and opened the editor against the second wallet's identity.
        let identity = MainActor.assumeIsolated { DWCurrentUserIdentityInfo.shared.refreshedSnapshot() }
        let username = identity.usernames.first
        profileUsername = (username?.isEmpty == false) ? username : nil
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
    
}
