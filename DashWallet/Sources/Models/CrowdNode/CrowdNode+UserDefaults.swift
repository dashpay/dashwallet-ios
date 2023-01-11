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

private let kCrowdNodeInfoShown = "crowdNodeInfoShownKey"
private let kLastKnownCrowdNodeBalance = "lastKnownCrowdNodeBalanceKey"
private let kCrowdNodeWithdrawalLimitPerTx = "crowdNodeWithdrawalLimitPerTxKey"
private let kCrowdNodeWithdrawalLimitPerHour = "crowdNodeWithdrawalLimitPerHourKey"
private let kCrowdNodeWithdrawalLimitPerDay = "crowdNodeWithdrawalLimitPerDayKey"

extension CrowdNode {
    var infoShown: Bool {
        get { UserDefaults.standard.bool(forKey: kCrowdNodeInfoShown) }
        set(value) { UserDefaults.standard.set(value, forKey: kCrowdNodeInfoShown) }
    }
    
    var lastKnownBalance: UInt64 {
        get { UserDefaults.standard.value(forKey: kLastKnownCrowdNodeBalance) as? UInt64 ?? 0 }
        set(value) { UserDefaults.standard.set(value, forKey: kLastKnownCrowdNodeBalance) }
    }
    
    var crowdNodeWithdrawalLimitPerTx: UInt64 {
        get { UserDefaults.standard.value(forKey: kCrowdNodeWithdrawalLimitPerTx) as? UInt64 ?? 15 * kOneDash }
        set(value) { UserDefaults.standard.set(value, forKey: kCrowdNodeWithdrawalLimitPerTx) }
    }
    
    var crowdNodeWithdrawalLimitPerHour: UInt64 {
        get { UserDefaults.standard.value(forKey: kCrowdNodeWithdrawalLimitPerHour) as? UInt64 ?? 30 * kOneDash }
        set(value) { UserDefaults.standard.set(value, forKey: kCrowdNodeWithdrawalLimitPerHour) }
    }
    
    var crowdNodeWithdrawalLimitPerDay: UInt64 {
        get { UserDefaults.standard.value(forKey: kCrowdNodeWithdrawalLimitPerDay) as? UInt64 ?? 60 * kOneDash }
        set(value) { UserDefaults.standard.set(value, forKey: kCrowdNodeWithdrawalLimitPerDay) }
    }
    
//    @property (nonatomic, assign) BOOL crowdNodeInfoShown;
//    @property (nonatomic, assign) UInt64 lastKnownCrowdNodeBalance;
//    @property (nonatomic, assign) UInt64 crowdNodeWithdrawalLimitPerTx;
//    @property (nonatomic, assign) UInt64 crowdNodeWithdrawalLimitPerHour;
//    @property (nonatomic, assign) UInt64 crowdNodeWithdrawalLimitPerDay;
    
//
//    func storedAccount(with authInterop: CBAuthInterop) -> CBAccount? {
//        guard let data = UserDefaults.standard.data(forKey: kUserDefaultAccountAccessKey) else {
//            return nil
//        }
//
//        let decoder = JSONDecoder()
//        guard let accountInfo = try? decoder.decode(CoinbaseUserAccountData.self, from: data) else {
//            return nil
//        }
//
//        return CBAccount(accountName: kDashAccount, info: accountInfo, authInterop: authInterop)
//    }
//
//    func removeAccount() {
//        UserDefaults.standard.removeObject(forKey: kUserDefaultAccountAccessKey)
//    }
//
//    @discardableResult
//    func store(account: CBAccount) -> Bool {
//        let encoder = JSONEncoder()
//        guard let data = try? encoder.encode(account.info) else {
//            return false
//        }
//
//        UserDefaults.standard.set(data, forKey: kUserDefaultAccountAccessKey)
//        return true
//    }
}
