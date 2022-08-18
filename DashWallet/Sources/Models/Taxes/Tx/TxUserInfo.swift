//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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
import SQLite

extension TxUserInfoTaxCategory {
    var stringValue: String {
        switch (self) {
        case .unknown:
            return NSLocalizedString("Transfer", comment: "")
        case .transferOut:
            return NSLocalizedString("Transfer Out", comment: "")
        case .transferIn:
            return NSLocalizedString("Transfer In", comment: "")
        case .expense:
            return NSLocalizedString("Expense", comment: "")
        case .income:
            return NSLocalizedString("Income", comment: "")
        }
    }
    
    
    var nextTaxCategory: TxUserInfoTaxCategory {
        switch self {
        case .unknown:
            return .unknown
        case .income:
            return .transferIn
        case .transferIn:
            return .income
        case .expense:
            return .transferOut
        case .transferOut:
            return .expense
        }
    }
}

@objc class TxUserInfo: NSObject {
    @objc var txHash: Data
    @objc var taxCategory: TxUserInfoTaxCategory = .unknown
    
    @objc init(hash: Data, taxCategory: TxUserInfoTaxCategory) {
        self.txHash = hash
        self.taxCategory = taxCategory
    }
    
    init(row: Row) {
        self.txHash = row[TxUserInfo.txHashColumn]
        self.taxCategory = TxUserInfoTaxCategory(rawValue: row[TxUserInfo.txCategoryColumn]) ?? .unknown
        
        super.init()
    }
}

@objc extension TxUserInfo {
    @objc func taxCategoryString() -> String {
        return taxCategory.stringValue
    }
}
extension TxUserInfo {
    static var table: Table { return Table("tx_userinfo") }
    static var txCategoryColumn: Expression<Int> { return Expression<Int>("taxCategory") }
    static var txHashColumn: Expression<Data> { return Expression<Data>("txHash") }
}

@objc extension DSTransaction {
    @objc func defaultTaxCategory() -> TxUserInfoTaxCategory {
        switch (self.direction()) {
        case .moved:
            return .expense
        case .sent:
            return .transferOut
        case .received:
            return .transferIn
        case .notAccountFunds:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
    
    @objc func defaultTaxCategoryString() -> String {
        let category = defaultTaxCategory()
        return category.stringValue
    }
}
