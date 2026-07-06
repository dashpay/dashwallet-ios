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
enum TxMetadataTaxCategory: Int {
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

    var isIncoming: Bool {
        self == .income || self == .transferIn
    }

    var isOutgoing: Bool {
        self == .expense || self == .transferOut
    }
}

// MARK: - Taxes

@objc
class Taxes: NSObject {

    var addressesUserInfos: AddressUserInfoDAO = AddressUserInfoDAOImpl()
    var txUserInfos: TransactionMetadataDAO = TransactionMetadataDAOImpl.shared

    @objc
    func mark(address: String, with taxCategory: TxMetadataTaxCategory) {
        addressesUserInfos.create(dto: AddressUserInfo(address: address, taxCategory: taxCategory))
    }

    func taxCategory(for tx: DSTransaction) -> TxMetadataTaxCategory {
        var taxCategory: TxMetadataTaxCategory = tx.defaultTaxCategory()

        for outputAddress in tx.outputAddresses {
            if let address = outputAddress as? String, let txCategory = self.taxCategory(for: address) {
                // Some transactions might have output that returns change
                // to the input same address, so need to check that directions match.
                let txDirection = tx.direction

                if (txDirection == .sent && txCategory.isOutgoing) ||
                    (txDirection == .received && txCategory.isIncoming) {
                    taxCategory = txCategory
                    break
                }
            }
        }

        taxCategory = txUserInfos.get(by: tx.txHashData)?.taxCategory ?? taxCategory

        return taxCategory
    }

    func taxCategory(for tx: Transaction) -> TxMetadataTaxCategory {
        if let dsTx = tx.tx {
            return taxCategory(for: dsTx)
        }

        // SDK-sourced rows: a stored .unknown means the user never classified
        // the tx (rows persisted before the direction default existed), so it
        // must not shadow the direction-derived default.
        if let stored = txUserInfos.get(by: tx.txHashData)?.taxCategory, stored != .unknown {
            return stored
        }

        return tx.direction.defaultTaxCategory
    }

    func taxCategory(for address: String) -> TxMetadataTaxCategory? {
        addressesUserInfos.get(by: address)?.taxCategory
    }

    @objc static let shared = Taxes()
}
