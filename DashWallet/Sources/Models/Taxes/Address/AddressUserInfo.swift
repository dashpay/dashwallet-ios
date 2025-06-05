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

// MARK: - AddressUserInfo

@objc class AddressUserInfo: NSObject {
    @objc var address: String
    @objc var taxCategory: TxMetadataTaxCategory = .unknown

    @objc
    init(address: String, taxCategory: TxMetadataTaxCategory) {
        self.address = address
        self.taxCategory = taxCategory
    }

    init(row: Row) {
        address = row[AddressUserInfo.addressColumn]
        taxCategory = TxMetadataTaxCategory(rawValue: row[TransactionMetadata.txCategoryColumn]) ?? .unknown

        super.init()
    }
}

@objc
extension AddressUserInfo {
    @objc
    func taxCategoryString() -> String {
        taxCategory.stringValue
    }
}

extension AddressUserInfo {
    static var table: Table { Table("address_userinfo") }
    static var txCategoryColumn: SQLite.Expression<Int> { SQLite.Expression<Int>("taxCategory") }
    static var addressColumn: SQLite.Expression<String> { SQLite.Expression<String>("address") }
}
