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

// MARK: - TxUserInfoTaxCategory

@objc
enum TxUserInfoTaxCategory: Int {
    /// Unknown
    case unknown

    /// Income
    case income

    /// Transfer In
    case transferIn

    /// Transfer Out
    case transferOut

    /// Expense
    case expense
}

// MARK: - Taxes

@objc
class Taxes: NSObject {

    var addressesUserInfos: AddressUserInfoDAO = AddressUserInfoDAOImpl()
    var txUserInfos: TxUserInfoDAO = TxUserInfoDAOImpl.shared

    @objc
    func initialize() {
        DispatchQueue.main.async {
            // Prefetch all items
            let _ = self.addressesUserInfos.all()
        }
    }

    @objc
    func mark(address: String, with taxCategory: TxUserInfoTaxCategory) {
        addressesUserInfos.create(dto: AddressUserInfo(address: address, taxCategory: taxCategory))
    }

    func taxCategory(for tx: DSTransaction) -> TxUserInfoTaxCategory {
        var taxCategory: TxUserInfoTaxCategory = tx.defaultTaxCategory()

        if let txCategory = txUserInfos.get(by: tx.txHashData)?.taxCategory {
            taxCategory = txCategory
        } else if let inputAddress = tx.inputAddresses.first as? String,
                  let txCategory = self.taxCategory(for: inputAddress) {
            taxCategory = txCategory
        }

        return taxCategory
    }

    func taxCategory(for address: String) -> TxUserInfoTaxCategory? {
        addressesUserInfos.get(by: address)?.taxCategory
    }

    @objc static let shared = Taxes()
}
