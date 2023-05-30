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

// MARK: - BalanceModel

final class BalanceModel {
    private(set) var state: SyncingActivityMonitor.State

    private(set) var value: UInt64 = 0
    var isBalanceHidden: Bool

    var balanceDidChange: (() -> ())?

    init() {
        isBalanceHidden = DWGlobalOptions.sharedInstance().balanceHidden
        state = SyncingActivityMonitor.shared.state

        SyncingActivityMonitor.shared.add(observer: self)

        reloadBalance()

        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    func hideBalanceIfNeeded() {
        if DWGlobalOptions.sharedInstance().balanceHidden {
            isBalanceHidden = true
        }
    }

    @objc
    func applicationWillEnterForeground(_ notification: NSNotification) {
        hideBalanceIfNeeded()
    }

    private func reloadBalance() {
        let balanceValue = DWEnvironment.sharedInstance().currentWallet.balance

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

        balanceDidChange?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        SyncingActivityMonitor.shared.remove(observer: self)
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

