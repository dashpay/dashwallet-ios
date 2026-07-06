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

// TODO(dashpay-e2e): these survive solely for the DashPay-frozen ObjC
// surfaces (DWTransactionListDataProvider(+Stub), DWUserProfileDataSourceObject),
// which still format DSTransaction couriers directly. They fall with those
// surfaces when the DashPay tx UI migrates to SDK rows. The app's own
// `Transaction` wrapper no longer touches any of this.
@objc
extension DSTransaction {
    var date: Date {
        guard timestamp > 1 else {
            let chain = DWEnvironment.sharedInstance().currentChain
            let now = chain.timestamp(forBlockHeight: UInt32(TX_UNCONFIRMED))
            return Date(timeIntervalSince1970: now)
        }

        let txDate = Date(timeIntervalSince1970: timestamp)
        return txDate;
    }

    var formattedShortTxDate: String {
        DWDateFormatter.sharedInstance.dateOnly(from: date)
    }

    var formattedLongTxDate: String {
        DWDateFormatter.sharedInstance.longString(from: date)
    }

    var formattedISO8601TxDate: String {
        DWDateFormatter.sharedInstance.iso8601String(from: date)
    }
}
