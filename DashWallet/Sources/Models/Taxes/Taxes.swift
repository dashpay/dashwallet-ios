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

    /// Internal Transfer — movement between the wallet's own balances
    /// (Core ↔ Shielded/Platform/identity funding, or a plain self-send).
    /// Appended last so the persisted raw values of the older cases keep
    /// their meaning.
    case internalTransfer

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

    func taxCategory(for tx: Transaction) -> TxMetadataTaxCategory {
        // A stored .unknown means the user never classified the tx (rate
        // stamping and rows persisted before the direction default existed
        // both leave it .unknown), so it must not shadow the live
        // transaction-derived default.
        if let stored = txUserInfos.get(by: tx.txHashData)?.taxCategory, stored != .unknown {
            return stored
        }

        return tx.defaultTaxCategory
    }

    func taxCategory(for address: String) -> TxMetadataTaxCategory? {
        addressesUserInfos.get(by: address)?.taxCategory
    }

    @objc static let shared = Taxes()
}
