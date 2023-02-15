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
private let kOnlineInfoShown = "crowdNodeOnlineInfoShownKey"
private let kSignedEmailMessageId = "crowdNodeSignedEmailMessageId"
private let kShouldShowConfirmedNotification = "shouldShowConfirmedNotification"

class CrowdNodeDefaults {
    public static let shared: CrowdNodeDefaults = .init()
    
    var crowdNodeAccountAddress: String? {
        get { UserDefaults.standard.value(forKey: kCrowdNodeAccountAddress) as? String }
        set(value) { UserDefaults.standard.set(value, forKey: kCrowdNodeAccountAddress) }
    }
    
    private var _infoShown: Bool? = nil
    var infoShown: Bool {
        get { _infoShown ?? UserDefaults.standard.bool(forKey: kInfoShown) }
        set(value) {
            _infoShown = value;
            UserDefaults.standard.set(value, forKey: kInfoShown)
        }
    }

    private var _lastKnownBalance: UInt64? = nil
    var lastKnownBalance: UInt64 {
        get { _lastKnownBalance ?? UserDefaults.standard.value(forKey: kLastKnownBalance) as? UInt64 ?? 0 }
        set(value) {
            _lastKnownBalance = value
            UserDefaults.standard.set(value, forKey: kLastKnownBalance)
        }
    }

    private var _crowdNodeWithdrawalLimitPerTx: UInt64? = nil
    var crowdNodeWithdrawalLimitPerTx: UInt64 {
        get { _crowdNodeWithdrawalLimitPerTx ?? UserDefaults.standard.value(forKey: kWithdrawalLimitPerTx) as? UInt64 ?? 15 * kOneDash }
        set(value) {
            _crowdNodeWithdrawalLimitPerTx = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerTx)
        }
    }

    private var _crowdNodeWithdrawalLimitPerHour: UInt64? = nil
    var crowdNodeWithdrawalLimitPerHour: UInt64 {
        get { _crowdNodeWithdrawalLimitPerHour ?? UserDefaults.standard.value(forKey: kWithdrawalLimitPerHour) as? UInt64 ?? 30 * kOneDash }
        set(value) {
            _crowdNodeWithdrawalLimitPerHour = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerHour)
        }
    }

    private var _crowdNodeWithdrawalLimitPerDay: UInt64? = nil
    var crowdNodeWithdrawalLimitPerDay: UInt64 {
        get { _crowdNodeWithdrawalLimitPerDay ?? UserDefaults.standard.value(forKey: kWithdrawalLimitPerDay) as? UInt64 ?? 60 * kOneDash }
        set(value) {
            _crowdNodeWithdrawalLimitPerDay = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerDay)
        }
    }

    private var _withdrawalLimitsInfoShown: Bool? = nil
    var withdrawalLimitsInfoShown: Bool {
        get { _withdrawalLimitsInfoShown ?? UserDefaults.standard.bool(forKey: kWithdrawalLimitsInfoShown) }
        set(value) {
            _withdrawalLimitsInfoShown = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitsInfoShown)
        }
    }

    private var _savedOnlineAccountState: CrowdNode.OnlineAccountState? = nil
    var savedOnlineAccountState: CrowdNode.OnlineAccountState {
        get { _savedOnlineAccountState ?? CrowdNode.OnlineAccountState(rawValue: UserDefaults.standard.integer(forKey: kOnlineAccountState)) ?? .none }
        set(value) {
            _savedOnlineAccountState = value
            UserDefaults.standard.set(value.rawValue, forKey: kOnlineAccountState)
        }
    }

    private var _crowdNodePrimaryAddress: String? = nil
    var crowdNodePrimaryAddress: String? {
        get { _crowdNodePrimaryAddress ?? UserDefaults.standard.value(forKey: kCrowdNodePrimaryAddress) as? String }
        set(value) {
            _crowdNodePrimaryAddress = value
            UserDefaults.standard.set(value, forKey: kCrowdNodePrimaryAddress)
        }
    }

    private var _confirmationDialogShown: Bool? = nil
    var confirmationDialogShown: Bool {
        get { _confirmationDialogShown ?? UserDefaults.standard.bool(forKey: kConfirmationDialogShown) }
        set(value) {
            _confirmationDialogShown = value
            UserDefaults.standard.set(value, forKey: kConfirmationDialogShown)
        }
    }
    
    private var _onlineInfoShown: Bool? = nil
    var onlineInfoShown: Bool {
        get { _onlineInfoShown ?? UserDefaults.standard.bool(forKey: kOnlineInfoShown) }
        set(value) {
            _onlineInfoShown = value
            UserDefaults.standard.set(value, forKey: kOnlineInfoShown)
        }
    }
    
    private var _shouldShowConfirmedNotification: Bool? = nil
    var shouldShowConfirmedNotification: Bool {
        get { _shouldShowConfirmedNotification ?? UserDefaults.standard.bool(forKey: kShouldShowConfirmedNotification) }
        set(value) {
            _shouldShowConfirmedNotification = value
            UserDefaults.standard.set(value, forKey: kShouldShowConfirmedNotification)
        }
    }
    
    private var _signedEmailMessageId: Int? = nil
    var signedEmailMessageId: Int {
        get { _signedEmailMessageId ?? UserDefaults.standard.value(forKey: kSignedEmailMessageId) as? Int ?? -1 }
        set(value) {
            _signedEmailMessageId = value
            UserDefaults.standard.set(value, forKey: kSignedEmailMessageId)
        }
    }
    

    func resetUserDefaults() {
        infoShown = false
        lastKnownBalance = 0
        withdrawalLimitsInfoShown = false
        savedOnlineAccountState = .none
        crowdNodeAccountAddress = nil
        crowdNodePrimaryAddress = nil
        confirmationDialogShown = false
        onlineInfoShown = false
        signedEmailMessageId = -1
        
    }
}
