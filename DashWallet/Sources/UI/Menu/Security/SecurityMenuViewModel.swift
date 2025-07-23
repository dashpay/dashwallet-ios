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

import Foundation
import Combine

enum SecurityMenuNavigationDestination {
    case viewRecoveryPhrase
    case changePin
    case advancedSecurity
    case resetWallet
}

class SecurityMenuViewModel: ObservableObject {
    @Published var navigationDestination: SecurityMenuNavigationDestination?
    @Published var showBiometricsAlert = false
    @Published var items: [MenuItemModel] = []
    @Published var biometricsEnabled = false
    @Published var balanceHidden = false
    
    let model = DWSecurityMenuModel()
    
    init() {
        setupItems()
        biometricsEnabled = model.biometricsEnabled
        balanceHidden = model.balanceHidden
    }
    
    private func setupItems() {
        var menuItems: [MenuItemModel] = []
        
        menuItems.append(MenuItemModel(
            title: NSLocalizedString("View Recovery Phrase", comment: ""),
            icon: .custom("image.recovery.phrase", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .viewRecoveryPhrase
            }
        ))
        
        menuItems.append(MenuItemModel(
            title: NSLocalizedString("Change PIN", comment: ""),
            icon: .custom("image.change.pin", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .changePin
            }
        ))
        
        if model.hasTouchID || model.hasFaceID {
            let title = model.hasTouchID ? NSLocalizedString("Enable Touch ID", comment: "") : NSLocalizedString("Enable Face ID", comment: "")
            let iconName = model.hasTouchID ? "image.touch.id" : "image.face.id"
            menuItems.append(MenuItemModel(
                title: title,
                icon: .custom(iconName, maxHeight: 22),
                showToggle: true,
                isToggled: self.biometricsEnabled,
                action: { [weak self] in
                    guard let self = self else { return }
                    let newValue = !self.biometricsEnabled
                    self.toggleBiometrics(newValue)
                }
            ))
        }
        
        menuItems.append(MenuItemModel(
            title: NSLocalizedString("Autohide Balance", comment: ""),
            icon: .custom("image.autohide.balance", maxHeight: 22),
            showToggle: true,
            isToggled: self.balanceHidden,
            action: { [weak self] in
                guard let self = self else { return }
                let newValue = !self.balanceHidden
                self.model.balanceHidden = newValue
            }
        ))
        
        menuItems.append(MenuItemModel(
            title: NSLocalizedString("Advanced Security", comment: ""),
            icon: .custom("image.advanced.security", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .advancedSecurity
            }
        ))
        
        menuItems.append(MenuItemModel(
            title: NSLocalizedString("Reset Wallet", comment: ""),
            icon: .custom("image.reset.wallet", maxHeight: 22),
            action: { [weak self] in
                self?.navigationDestination = .resetWallet
            }
        ))
        
        items = menuItems
    }
    
    private func toggleBiometrics(_ enabled: Bool) {
        model.setBiometricsEnabled(enabled) { [weak self] success in
            DispatchQueue.main.async {
                if !success {
                    // Revert the toggle
                    self?.biometricsEnabled = !enabled
                    
                    // Show alert if trying to enable but access was denied
                    if enabled {
                        self?.showBiometricsAlert = true
                    }
                } else {
                    self?.biometricsEnabled = enabled
                }
                
                // Refresh items to update the toggle state
                self?.setupItems()
            }
        }
    }
    
    func resetNavigation() {
        navigationDestination = nil
        showBiometricsAlert = false
    }
}
