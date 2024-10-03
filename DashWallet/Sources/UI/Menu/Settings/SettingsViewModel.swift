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

import Combine

enum SettingsNavDest {
    case coinjoin
    case currencySelector
    case network
    case rescan
    case about
    case none
}

class SettingsViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let coinJoinService = CoinJoinService.shared
    private var model: DWSettingsMenuModel
    @Published var items: [MenuItemModel] = []
    @Published private(set) var navigationDestination: SettingsNavDest = .none
    
    init(model: DWSettingsMenuModel) {
        self.model = model
        refreshMenuItems()
        setupCoinJoinObservers()
    }
    
    func resetNavigation() {
        self.navigationDestination = .none
    }
    
    private func setupCoinJoinObservers() {
        coinJoinService.$progress
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMenuItems()
            }
            .store(in: &cancellableBag)
        
        coinJoinService.$mode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMenuItems()
            }
            .store(in: &cancellableBag)
        
        coinJoinService.$mixingState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMenuItems()
            }
            .store(in: &cancellableBag)
    }
    
    private func refreshMenuItems() {
        self.items = [
            MenuItemModel(
                title: NSLocalizedString("Local Currency", comment: ""),
                subtitle: model.localCurrencyCode,
                showChevron: true,
                action: { [weak self] in
                    self?.navigationDestination = .currencySelector
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Enable Receive Notifications", comment: ""),
                showToggle: true,
                isToggled: model.notificationsEnabled,
                action: { [weak self] in
                    self?.model.notificationsEnabled.toggle()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Network", comment: ""),
                subtitle: model.networkName,
                showChevron: true,
                action: { [weak self] in
                    self?.navigationDestination = .network
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Rescan Blockchain", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.navigationDestination = .rescan
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("About", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.navigationDestination = .about
                }
            ),
            CoinJoinMenuItemModel(
                title: NSLocalizedString("CoinJoin", comment: "CoinJoin"),
                isOn: coinJoinService.mode != .none,
                state: coinJoinService.mixingState,
                progress: coinJoinService.progress.progress,
                mixed: Double(coinJoinService.progress.coinJoinBalance) / Double(DUFFS),
                total: Double(coinJoinService.progress.totalBalance) / Double(DUFFS),
                action: { [weak self] in
                    self?.navigationDestination = .coinjoin
                }
            )
        ]
        
        #if DASHPAY
        items.append(contentsOf: [
            MenuItemModel(
                title: "Enable Voting",
                showToggle: true,
                isToggled: VotingPrefs.shared.votingEnabled,
                action: {
                    VotingPrefs.shared.votingEnabled.toggle()
                }
            )
        ])
        #endif
    }
}
