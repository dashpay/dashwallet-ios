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
    @Published var advancedModeEnabled: Bool
    @Published var showAdvancedModeInfo = false
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
    
    /// Effective permission from `NotificationPermissionCoordinator`: the
    /// in-app toggle and the live OS authorization combined. While the OS
    /// grant is denied the row shows off and tapping it opens the app's iOS
    /// Settings page instead of flipping a preference that can't take effect.
    @Published private var notificationPermissionState: NotificationPermissionState

    private let notificationPermissions: NotificationPermissionCoordinator

    init(notificationPermissions: NotificationPermissionCoordinator = NotificationPermissionCoordinator()) {
        self.notificationPermissions = notificationPermissions
        // The OS half of the state arrives asynchronously; until then render
        // from the in-app toggle alone.
        self.notificationPermissionState = notificationPermissions.userWantsNotifications ? .on : .offByUser
        self.advancedModeEnabled = DWGlobalOptions.sharedInstance().advancedModeEnabled
        refreshMenuItems()
        setupCoinJoinObservers()
        setupCurrencyChangeObserver()
        refreshNotificationPermissionState()
        // The user may come back from iOS Settings with a changed grant.
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshNotificationPermissionState()
            }
            .store(in: &cancellableBag)
    }

    private func refreshNotificationPermissionState() {
        Task { [weak self] in
            guard let self else { return }
            let state = await self.notificationPermissions.effectiveState()
            if self.notificationPermissionState != state {
                self.notificationPermissionState = state
                self.refreshMenuItems()
            }
        }
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
                // `.awaitingAuthorization` renders like `.on`: the user's
                // toggle is on and only the OS grant is still pending.
                isToggled: notificationPermissionState == .on
                    || notificationPermissionState == .awaitingAuthorization,
                action: { [weak self] in
                    guard let self = self else { return }
                    if self.notificationPermissionState == .blockedBySystem {
                        // The system grant is off, so the in-app toggle can't
                        // deliver anything — send the user to iOS Settings.
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        return
                    }
                    self.notificationPermissions.userWantsNotifications.toggle()
                    // Render the flip immediately from the toggle; the OS
                    // half of the state re-derives asynchronously.
                    self.notificationPermissionState = self.notificationPermissions.userWantsNotifications ? .on : .offByUser
                    self.refreshMenuItems()
                    self.refreshNotificationPermissionState()
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

        // Last: it changes what other screens show rather than doing anything
        // here, so it reads as a postscript to the settings above rather than
        // one of them.
        items.append(
            MenuItemModel(
                title: NSLocalizedString("Advanced mode", comment: "Settings"),
                icon: .custom("image.about", maxHeight: 30),
                showInfo: true,
                showToggle: true,
                isToggled: advancedModeEnabled,
                action: { [weak self] in
                    guard let self = self else { return }
                    self.setAdvancedMode(!self.advancedModeEnabled)
                },
                infoAction: { [weak self] in
                    self?.showAdvancedModeInfo = true
                }
            )
        )
    }

    // MARK: - Advanced mode

    /// Write the flag, then announce it. The announcement is the point: the
    /// setting reaches far beyond this screen, and a consumer that only read
    /// the value when it appeared would keep showing the old state until it
    /// was rebuilt for some unrelated reason.
    func setAdvancedMode(_ enabled: Bool) {
        guard enabled != advancedModeEnabled else { return }
        advancedModeEnabled = enabled
        DWGlobalOptions.sharedInstance().advancedModeEnabled = enabled
        DWLogger.log("Settings: advanced mode \(enabled ? "enabled" : "disabled")")
        NotificationCenter.default.post(name: .advancedModeDidChange, object: nil)
        refreshMenuItems()
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
        WalletLifecycleOverlayPresenter.shared.ensureActive()
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
