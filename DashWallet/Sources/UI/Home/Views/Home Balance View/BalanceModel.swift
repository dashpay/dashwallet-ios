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

final class BalanceModel {
    var value: UInt64 = 0

    init() {
        reloadBalance()
    }

    private func reloadBalance() {
        let balanceValue = DWEnvironment.sharedInstance().currentWallet.balance
        
        if (balanceValue > value &&
            value > 0 &&
            UIApplication.shared.applicationState != .background &&
            SyncingActivityMonitor.shared.progress > 0.995) {
            UIDevice.current.dw_playCoinSound()
        }

        value = balanceValue
        
        let options = DWGlobalOptions.sharedInstance()
        if (balanceValue > 0
            && options.walletNeedsBackup
            && (options.balanceChangedDate == nil)) {
            options.balanceChangedDate = Date()
        }

        options.userHasBalance = balanceValue > 0;
    }
}

extension BalanceModel {
    func dashAmountStringWithFont(_ font: UIFont, tintColor: UIColor) -> NSAttributedString {
        NSAttributedString.dashAttributedString(for: value, tintColor: tintColor, font: font)
    }

    func mainAmountString() -> String {
        value.formattedDashAmount
    }

    func fiatAmountString() -> String {
        CurrencyExchanger.shared.fiatAmountString(for: value.dashAmount)
    }
}
