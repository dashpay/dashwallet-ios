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
    @Published private(set) var value: UInt64 = 0
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

        // Subscribe to SwiftDashSDKWalletState's balance publisher.
        // After M6 retired DashSync's SPV, this is the authoritative source
        // for the home screen balance — DSWallet.balance is frozen at
        // whatever was cached pre-M6. The DSWalletBalanceDidChange observer
        // in `observeWallet()` is kept as a backstop and now harmlessly
        // re-fires `reloadBalance()` (which also reads from this publisher).
        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadBalance()
            }
            .store(in: &cancellableBag)

        reloadBalance()
        observeWallet()
    }

    func hideBalanceIfNeeded() {
        if DWGlobalOptions.sharedInstance().balanceHidden {
            isBalanceHidden = true
        }
    }

    func reloadBalance() {
        // Source from SwiftDashSDKWalletState instead of
        // DWEnvironment.sharedInstance().currentWallet.balance. After M6
        // (commit 86ed72706), DashSync's SPV no longer runs and
        // DSWallet.balance is frozen — SwiftDashSDK is the authoritative
        // source. `WalletBalance.total` = confirmed + unconfirmed + immature,
        // matching the "everything user-visible" semantic dashwallet's
        // UI displays. Function #5 of the DashSync migration.
        let walletBalance = SwiftDashSDKWalletState.shared.balance
        let balanceValue = walletBalance?.total ?? 0

        if balanceValue > value &&
            value > 0 &&
            UIApplication.shared.applicationState != .background &&
            SyncingActivityMonitor.shared.progress > 0.995 {
            UIDevice.current.dw_playCoinSound()
        }

        value = balanceValue

        let options = DWGlobalOptions.sharedInstance()
        if balanceValue > 0
            && options.walletNeedsBackup
            && (options.balanceChangedDate == nil) {
            options.balanceChangedDate = Date()
        }

        options.userHasBalance = balanceValue > 0
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
    func observeWallet() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.hideBalanceIfNeeded()
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadBalance()
            }
            .store(in: &cancellableBag)
    }
}

// MARK: BalanceViewDataSource

extension BalanceModel: BalanceViewDataSource {
    var mainAmountString: String {
        value.formattedDashAmount
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
        NSAttributedString.dashAttributedString(for: value, tintColor: tintColor, font: font)
    }

    func fiatAmountString() -> String {
        CurrencyExchanger.shared.fiatAmountString(for: value.dashAmount)
    }
}

