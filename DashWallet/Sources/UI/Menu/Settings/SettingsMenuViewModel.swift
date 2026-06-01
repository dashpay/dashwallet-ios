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

enum SettingsMenuNavigationDestination {
    case coinjoin
    case currencySelector
    case network
    case rescan
    case about
    case exportCSV
}

@MainActor
class SettingsMenuViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let coinJoinService = CoinJoinService.shared
    
    @Published var items: [MenuItemModel] = []
    @Published var navigationDestination: SettingsMenuNavigationDestination?
    @Published var notificationsEnabled: Bool
    @Published var showCSVExportActivity = false
    @Published var csvExportData: (fileName: String, file: URL)?
    @Published var showCoinJoinSweepConfirmation = false

    /// Minimum CoinJoin-account balance (duffs) worth surfacing a sweep for —
    /// below this it's un-sweepable dust/fragments, not a real denomination.
    private static let minCoinJoinSweepDuffs: UInt64 = 1000

    /// Live CoinJoin-account spendable balance (duffs) — the SDK source of
    /// truth, NOT the legacy DashSync `CoinJoinService`.
    private var coinJoinLeftoverDuffs: UInt64 {
        SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
    }

    /// Whether to show the conditional "Move CoinJoin Funds" row.
    var hasCoinJoinLeftover: Bool {
        coinJoinLeftoverDuffs > Self.minCoinJoinSweepDuffs
    }

    /// Formatted leftover amount for the confirmation dialog.
    var coinJoinLeftoverFormatted: String {
        String(format: "%.6f DASH", Double(coinJoinLeftoverDuffs) / Double(DUFFS))
    }
    
    var networkName: String {
        return DWEnvironment.sharedInstance().currentChain.name
    }
    
    var localCurrencyCode: String {
        return CurrencyExchangerObjcWrapper.localCurrencyCode
    }
    
    var isBalanceHidden: Bool {
        DWGlobalOptions.sharedInstance().balanceHidden
    }
    
    init() {
        self.notificationsEnabled = DWGlobalOptions.sharedInstance().localNotificationsEnabled
        refreshMenuItems()
        setupCoinJoinObservers()
        setupCurrencyChangeObserver()
    }
    
    func resetNavigation() {
        navigationDestination = nil
        showCSVExportActivity = false
        csvExportData = nil
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

        // SDK CoinJoin-account balance drives the conditional "Move CoinJoin
        // Funds" row: it appears while a leftover exists and self-removes once
        // the post-sweep balance refresh drops it below the threshold.
        SwiftDashSDKWalletState.shared.$coinJoinBalanceDuffs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMenuItems()
            }
            .store(in: &cancellableBag)
    }
    
    private func setupCurrencyChangeObserver() {
        NotificationCenter.default.publisher(for: Notification.Name.fiatCurrencyDidChange)
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
                icon: .custom("image.network.monitor", maxHeight: 22),
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

        // Conditional migration row: only while leftover CoinJoin funds exist.
        if hasCoinJoinLeftover {
            items.append(
                MenuItemModel(
                    title: NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
                    subtitle: NSLocalizedString("CoinJoin is no longer supported", comment: "CoinJoin"),
                    icon: .custom("image.coinjoin.menu", maxHeight: 22),
                    action: { [weak self] in
                        self?.showCoinJoinSweepConfirmation = true
                    }
                )
            )
        }
        
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

    // MARK: - CoinJoin Sweep

    /// Sweep the leftover CoinJoin-account balance into the user's spendable
    /// balance via the shared `WalletSendService` flow (PIN → resolve own
    /// BIP44 address → sweep → balance refresh). The "Move CoinJoin Funds"
    /// row self-removes once the refreshed balance drops below the threshold.
    func performCoinJoinSweep() async {
        do {
            _ = try await WalletSendService.shared.sweepCoinJoin()
        } catch {
            // Auth-cancel is an expected no-op; on other failures the row
            // stays visible (balance unchanged) so the user can retry.
            #if DEBUG
            print("🎯 CoinJoin sweep failed: \(error)")
            #endif
        }
    }

    // MARK: - Network Switching
    
    func switchToMainnet() async -> Bool {
        await DWEnvironment.sharedInstance().switchToMainnet()
    }
    
    func switchToTestnet() async -> Bool {
        return await DWEnvironment.sharedInstance().switchToTestnet()
    }
    
    func switchToEvonet() async -> Bool {
        await DWEnvironment.sharedInstance().switchToEvonet()
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
    
    func exportCSV() async throws {
        let result = try await generateCSVReport()
        csvExportData = result
        showCSVExportActivity = true
    }
}
