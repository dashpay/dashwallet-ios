//
//  Created by Andrei Ashikhmin
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

private let kInfoShown = "crowdNodeInfoShownKey"
private let kLastKnownBalance = "lastKnownCrowdNodeBalanceKey"
private let kWithdrawalLimitPerTx = "crowdNodeWithdrawalLimitPerTxKey"
private let kWithdrawalLimitPerHour = "crowdNodeWithdrawalLimitPerHourKey"
private let kWithdrawalLimitPerDay = "crowdNodeWithdrawalLimitPerDayKey"
private let kWithdrawalLimitsInfoShown = "crowdNodeWithdrawalLimitsInfoShownKey"
private let kOnlineAccountState = "сrowdNodeOnlineAccountStateKey"
private let kOnlineAccountAddress = "crowdNodeOnlineAccountAddressKey"
private let kCrowdNodeAccountAddress = "crowdNodeAccountAddressKey"
private let kCrowdNodePrimaryAddress = "crowdNodePrimaryAddressKey"
private let kConfirmationDialogShown = "crowdNodeConfirmationDialogShownKey"

extension CrowdNode {
    var infoShown: Bool {
        get { UserDefaults.standard.bool(forKey: kInfoShown) }
        set(value) { UserDefaults.standard.set(value, forKey: kInfoShown) }
    }

    static var lastKnownBalance: UInt64 {
        get { UserDefaults.standard.value(forKey: kLastKnownBalance) as? UInt64 ?? 0 }
        set(value) { UserDefaults.standard.set(value, forKey: kLastKnownBalance) }
    }

    var crowdNodeWithdrawalLimitPerTx: UInt64 {
        get { UserDefaults.standard.value(forKey: kWithdrawalLimitPerTx) as? UInt64 ?? 15 * kOneDash }
        set(value) { UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerTx) }
    }

    var crowdNodeWithdrawalLimitPerHour: UInt64 {
        get { UserDefaults.standard.value(forKey: kWithdrawalLimitPerHour) as? UInt64 ?? 30 * kOneDash }
        set(value) { UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerHour) }
    }

    var crowdNodeWithdrawalLimitPerDay: UInt64 {
        get { UserDefaults.standard.value(forKey: kWithdrawalLimitPerDay) as? UInt64 ?? 60 * kOneDash }
        set(value) { UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerDay) }
    }

    var withdrawalLimitsInfoShown: Bool {
        get { UserDefaults.standard.bool(forKey: kWithdrawalLimitsInfoShown) }
        set(value) { UserDefaults.standard.set(value, forKey: kWithdrawalLimitsInfoShown) }
    }

    var savedOnlineAccountState: OnlineAccountState {
        get { OnlineAccountState(rawValue: UserDefaults.standard.integer(forKey: kOnlineAccountState)) ?? .none }
        set(value) { UserDefaults.standard.set(value.rawValue, forKey: kOnlineAccountState) }
    }

    var crowdNodeAccountAddress: String? {
        get { UserDefaults.standard.value(forKey: kCrowdNodeAccountAddress) as? String }
        set(value) { UserDefaults.standard.set(value, forKey: kCrowdNodeAccountAddress) }
    }

    var crowdNodePrimaryAddress: String? {
        get { UserDefaults.standard.value(forKey: kCrowdNodePrimaryAddress) as? String }
        set(value) { UserDefaults.standard.set(value, forKey: kCrowdNodePrimaryAddress) }
    }

    var confirmationDialogShown: Bool {
        get { UserDefaults.standard.bool(forKey: kConfirmationDialogShown) }
        set(value) { UserDefaults.standard.set(value, forKey: kConfirmationDialogShown) }
    }

    func resetUserDefaults() {
        infoShown = false
        CrowdNode.lastKnownBalance = 0
        withdrawalLimitsInfoShown = false
        savedOnlineAccountState = .none
        crowdNodeAccountAddress = nil
        crowdNodePrimaryAddress = nil
        confirmationDialogShown = false
    }
}
