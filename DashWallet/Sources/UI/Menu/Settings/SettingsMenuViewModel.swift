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
import UIKit

enum SettingsNavDest {
    case coinjoin
    case currencySelector
    case network
    case rescan
    case about
    case none
}

@MainActor
class SettingsMenuViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let coinJoinService = CoinJoinService.shared
    
    @Published var items: [MenuItemModel] = []
    @Published private(set) var navigationDestination: SettingsNavDest = .none
    @Published var notificationsEnabled: Bool
    
    var networkName: String {
        return DWEnvironment.sharedInstance().currentChain.name
    }
    
    var localCurrencyCode: String {
        return CurrencyExchangerObjcWrapper.localCurrencyCode
    }
    
    init() {
        self.notificationsEnabled = DWGlobalOptions.sharedInstance().localNotificationsEnabled
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
                subtitle: localCurrencyCode,
                icon: .custom("image.currency", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .currencySelector
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Enable Receive Notifications", comment: ""),
                icon: .custom("image.notifications", maxHeight: 22),
                showToggle: true,
                isToggled: notificationsEnabled,
                action: { [weak self] in
                    guard let self = self else { return }
                    self.notificationsEnabled.toggle()
                    DWGlobalOptions.sharedInstance().localNotificationsEnabled = self.notificationsEnabled
                    self.refreshMenuItems()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Network", comment: ""),
                subtitle: networkName,
                icon: .custom("image.rescan", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .network
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Rescan Blockchain", comment: ""),
                icon: .custom("image.rescan", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .rescan
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("About", comment: ""),
                icon: .custom("image.about", maxHeight: 22),
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
    
    // MARK: - Network Switching
    
    func switchToMainnet() async -> Bool {
        return await DWEnvironment.sharedInstance().switchToMainnet()
    }
    
    func switchToTestnet() async -> Bool {
        return await DWEnvironment.sharedInstance().switchToTestnet()
    }
    
    func switchToEvonet() async -> Bool {
        return await DWEnvironment.sharedInstance().switchToEvonet()
    }
    
    // MARK: - Blockchain Rescan Actions
    
    func rescanTransactions() {
        DWGlobalOptions.sharedInstance().isResyncingWallet = true
        let chainManager = DWEnvironment.sharedInstance().currentChainManager
        chainManager.syncBlocksRescan()
    }
    
    func fullResync() {
        DWGlobalOptions.sharedInstance().isResyncingWallet = true
        let chainManager = DWEnvironment.sharedInstance().currentChainManager
        chainManager.masternodeListAndBlocksRescan()
    }
    
    #if DEBUG
    func resyncMasternodeList() {
        DWGlobalOptions.sharedInstance().isResyncingWallet = true
        let chainManager = DWEnvironment.sharedInstance().currentChainManager
        chainManager.masternodeListRescan()
    }
    #endif
    
    // MARK: - CSV Report Generation
    
    func generateCSVReport() async throws -> (fileName: String, file: URL) {
        try await withCheckedThrowingContinuation { continuation in
            TaxReportGenerator.generateCSVReport(
                completionHandler: { fileName, file in
                    continuation.resume(returning: (fileName, file))
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }
}
