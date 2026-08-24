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
    case currencySelector
    case network
    case about
    case exportCSV
}

@MainActor
class SettingsMenuViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()

    @Published var items: [MenuItemModel] = []
    @Published var navigationDestination: SettingsMenuNavigationDestination?
    @Published var notificationsEnabled: Bool
    @Published var showCSVExportActivity = false
    @Published var csvExportData: (fileName: String, file: URL)?
    @Published var showCoinJoinSweepConfirmation = false
    @Published var coinJoinSweepErrorMessage: String?

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
        String(format: "%.6f DASH", Double(coinJoinLeftoverDuffs) / Double(kOneDash))
    }
    
    var networkName: String {
        return WalletEnvironment.networkDisplayName
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
                icon: .custom("image.currency", maxHeight: 30),
                action: { [weak self] in
                    self?.navigationDestination = .currencySelector
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Notifications", comment: ""),
                icon: .custom("image.notifications", maxHeight: 30),
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
                icon: .custom("image.network.monitor", maxHeight: 30),
                action: { [weak self] in
                    self?.navigationDestination = .network
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("About", comment: ""),
                icon: .custom("image.about", maxHeight: 30),
                action: { [weak self] in
                    self?.navigationDestination = .about
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
        DWLogger.log("SettingsMenuViewModel: sweep invoked from Settings menu (\(coinJoinLeftoverFormatted))")
        do {
            _ = try await WalletSendService.shared.sweepCoinJoin()
        } catch {
            DWLogger.log("SettingsMenuViewModel: sweep failed: \(error)")
            // Auth-cancel is an expected no-op (nil message); a real failure
            // surfaces an alert. The row stays visible so the user can retry.
            coinJoinSweepErrorMessage = WalletSendService.coinJoinSweepUserMessage(for: error)
        }
    }

    // MARK: - Network Switching

    func switchToMainnet() async -> Bool {
        await switchNetwork(to: .mainnet)
    }

    func switchToTestnet() async -> Bool {
        await switchNetwork(to: .testnet)
    }

    /// Route through the runtime's managed switch: strict teardown → rebuild
    /// with the blocking overlay window up for the whole transition. A thrown
    /// failure leaves the overlay in its `.failed` phase (Retry lives there),
    /// so this only reports the outcome to the settings screen.
    private func switchNetwork(to kind: WalletEnvironment.NetworkKind) async -> Bool {
        NetworkSwitchOverlayPresenter.shared.ensureActive()
        do {
            try await SwiftDashSDKWalletRuntime.shared.switchNetwork(to: kind)
            return true
        } catch {
            DWLogger.log("SettingsMenuViewModel: network switch failed: \(error)")
            return false
        }
    }

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
