//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - BalanceModel

final class BalanceModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    
    @Published private(set) var state = SyncingActivityMonitor.shared.state
    /// `nil` until the selected wallet's balance has been read. A known zero
    /// is an amount; an unavailable snapshot uses the same placeholder as the
    /// other Home balance rows.
    @Published private(set) var value: UInt64?
    /// True while the wallet runs on testnet — drives the home header's
    /// TESTNET badge so test funds can't be mistaken for real Dash
    /// (fresh installs currently default to testnet by design).
    @Published private(set) var isTestnet = WalletEnvironment.isTestnet
    @Published var isBalanceHidden: Bool {
        didSet {
            DWGlobalOptions.sharedInstance().balanceHidden = isBalanceHidden
        }
    }
    
    var shouldShowTapToHideBalance: Bool {
        get { !DWGlobalOptions.sharedInstance().tapToHideBalanceShown }
        set(value) {
            DWGlobalOptions.sharedInstance().tapToHideBalanceShown = !value
        }
    }

    init() {
        isBalanceHidden = DWGlobalOptions.sharedInstance().balanceHidden
        SyncingActivityMonitor.shared.add(observer: self)

        // Wallet state publishes and clears on the main queue. Consume the
        // emitted snapshot directly: another run-loop hop delays the restored
        // amount behind startup work, and rereading `shared.balance` here sees
        // the old value because @Published emits from willSet.
        SwiftDashSDKWalletState.shared.$balance
            .sink { [weak self] snapshot in
                self?.applyBalance(snapshot)
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isTestnet = WalletEnvironment.isTestnet
            }
            .store(in: &cancellableBag)

        reloadBalance()
        observeAppLifecycle()
    }

    func hideBalanceIfNeeded() {
        if DWGlobalOptions.sharedInstance().balanceHidden {
            isBalanceHidden = true
        }
    }

    func reloadBalance() {
        applyBalance(SwiftDashSDKWalletState.shared.balance)
    }

    private func applyBalance(_ walletBalance: WalletBalance?) {
        // Source from SwiftDashSDKWalletState instead of
        // DWEnvironment.sharedInstance().currentWallet.balance. After M6
        // (commit 86ed72706), DashSync's SPV no longer runs and
        // DSWallet.balance is frozen — SwiftDashSDK is the authoritative
        // source. `WalletBalance.total` sums every bucket — confirmed,
        // unconfirmed, immature and locked — matching the "everything
        // user-visible" semantic dashwallet's UI displays.
        // Function #5 of the DashSync migration.
        let balanceValue = walletBalance?.total

        if let balanceValue, let previousValue = value,
            balanceValue > previousValue &&
            previousValue > 0 &&
            UIApplication.shared.applicationState != .background &&
            SyncingActivityMonitor.shared.progress > 0.995 {
            UIDevice.current.dw_playCoinSound()
        }

        value = balanceValue

        let options = DWGlobalOptions.sharedInstance()
        if let balanceValue, balanceValue > 0
            && options.walletNeedsBackup
            && (options.balanceChangedDate == nil) {
            options.balanceChangedDate = Date()
        }

        // Only write when the balance is actually known. `userHasBalance` is
        // persisted per wallet and is an input to the default shortcut bar, so
        // writing `false` for a not-yet-loaded balance let a single launch
        // before the wallet was bound permanently drop a shortcut from a funded
        // wallet's bar. `nil` means "not known yet", never "empty".
        if let total = walletBalance?.total {
            options.userHasBalance = total > 0
        }
        isBalanceHidden = DWGlobalOptions.sharedInstance().balanceHidden
    }
    
    func toggleBalanceVisibility() {
        isBalanceHidden = !isBalanceHidden
        shouldShowTapToHideBalance = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        SyncingActivityMonitor.shared.remove(observer: self)
    }
}

extension BalanceModel {
    func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.hideBalanceIfNeeded()
            }
            .store(in: &cancellableBag)
    }
}

// MARK: BalanceViewDataSource

extension BalanceModel: BalanceViewDataSource {
    var mainAmountString: String {
        value?.formattedDashAmount ?? "—"
    }

    var supplementaryAmountString: String {
        fiatAmountString()
    }
}

// MARK: SyncingActivityMonitorObserver

extension BalanceModel: SyncingActivityMonitorObserver {
    func syncingActivityMonitorProgressDidChange(_ progress: Double) {
        // NOP
    }

    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        self.state = state
        reloadBalance()
    }
}

extension BalanceModel {
    func dashAmountStringWithFont(_ font: UIFont, tintColor: UIColor) -> NSAttributedString {
        guard let value else {
            return NSAttributedString(string: "—", attributes: [.font: font, .foregroundColor: tintColor])
        }
        return NSAttributedString.dashAttributedString(for: value, tintColor: tintColor, font: font)
    }

    func fiatAmountString() -> String {
        guard let value else { return "—" }
        return CurrencyExchanger.shared.fiatAmountString(for: value.dashAmount)
    }

    /// Fiat string for an arbitrary duff amount — used by the balance
    /// breakdown rows (transparent / platform / shielded) and the
    /// combined-total hero, which aggregate more than `value`.
    func fiatString(forDuffs duffs: UInt64) -> String {
        CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount)
    }
}
