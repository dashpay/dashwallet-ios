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

// MARK: - TxUserInfoDAO

protocol TransactionMetadataDAO {
    func create(dto: TransactionMetadata)
    func get(by hash: Data) -> TransactionMetadata?
    func update(dto: TransactionMetadata)
    func delete(dto: TransactionMetadata)
    func deleteAll()
}

// MARK: - TxUserInfoDAOImpl

class TransactionMetadataDAOImpl: NSObject, TransactionMetadataDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [Data: TransactionMetadata] = [:]

    private let queue = DispatchQueue(label: "org.dash.infrastructure.queue.transaction-metadata-dao", attributes: .concurrent)

    func create(dto: TransactionMetadata) {
        do {
            let transactionMetadata = TransactionMetadata.table.insert(or: .replace,
                                                     TransactionMetadata.txHashColumn <- dto.txHash,
                                                     TransactionMetadata.txCategoryColumn <- dto.taxCategory.rawValue,
                                                     TransactionMetadata.txRateColumn <- dto.rate,
                                                     TransactionMetadata.txRateCurrencyCodeColumn <- dto.rateCurrency,
                                                     TransactionMetadata.txRateMaximumFractionDigitsColumn <- dto.rateMaximumFractionDigits)
            try db.run(transactionMetadata)

        } catch {
            print(error)
        }

        queue.async(flags: .barrier) { [weak self] in
            self?.cache[dto.txHash] = dto
        }
    }

    func all() -> [TransactionMetadata] {
        let txUserInfos = TransactionMetadata.table

        var userInfos: [TransactionMetadata] = []

        do {
            for txInfo in try db.prepare(txUserInfos) {
                let userInfo = TransactionMetadata(row: txInfo)
                userInfos.append(userInfo)
            }
        } catch {
            print(error)
        }

        return userInfos
    }

    func get(by hash: Data) -> TransactionMetadata? {
        if let cached = cachedValue(by: hash) {
            return cached
        }

        let txUserInfo = TransactionMetadata.table.filter(TransactionMetadata.txHashColumn == hash)

        do {
            for txInfo in try db.prepare(txUserInfo) {
                let userInfo = TransactionMetadata(row: txInfo)
                queue.async(flags: .barrier) { [weak self] in
                    self?.cache[hash] = userInfo
                }
                return userInfo
            }
        } catch {
            print(error)
        }

        return nil
    }

    private func cachedValue(by key: Data) -> TransactionMetadata? {
        var v: TransactionMetadata?

        queue.sync {
            v = cache[key]
        }

        return v
    }

    func update(dto: TransactionMetadata) {
        create(dto: dto)
    }

    func delete(dto: TransactionMetadata) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache[dto.txHash] = nil
        }
    }

    func deleteAll() {
        do {
            try db.run(TransactionMetadata.table.delete())
            queue.async(flags: .barrier) { [weak self] in
                self?.cache = [:]
            }
        } catch {
            print(error)
        }
    }

    static let shared = TransactionMetadataDAOImpl()
}

extension TransactionMetadataDAOImpl {
    func dictionaryOfAllItems() -> [Data: TransactionMetadata] {
        _ = all()
        return cache
    }
}
