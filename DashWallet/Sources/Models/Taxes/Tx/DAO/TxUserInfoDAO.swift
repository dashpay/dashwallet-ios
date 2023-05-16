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

protocol TxUserInfoDAO {
    func create(dto: TxUserInfo)
    func get(by hash: Data) -> TxUserInfo?
    func update(dto: TxUserInfo)
    func delete(dto: TxUserInfo)
    func deleteAll()
}

// MARK: - TxUserInfoDAOImpl

class TxUserInfoDAOImpl: NSObject, TxUserInfoDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [Data: TxUserInfo] = [:]

    private let queue = DispatchQueue(label: "org.dash.infrastructure.queue.tx-user-info-dao", attributes: .concurrent)

    func create(dto: TxUserInfo) {
        do {
            let txUserInfo = TxUserInfo.table.insert(or: .replace,
                                                     TxUserInfo.txHashColumn <- dto.txHash,
                                                     TxUserInfo.txCategoryColumn <- dto.taxCategory.rawValue,
                                                     TxUserInfo.txRateColumn <- dto.rate,
                                                     TxUserInfo.txRateCurrencyCodeColumn <- dto.rateCurrency,
                                                     TxUserInfo.txRateMaximumFractionDigitsColumn <- dto.rateMaximumFractionDigits)
            try db.run(txUserInfo)

        } catch {
            print(error)
        }

        queue.async(flags: .barrier) { [weak self] in
            self?.cache[dto.txHash] = dto
        }
    }

    func all() -> [TxUserInfo] {
        let txUserInfos = TxUserInfo.table

        var userInfos: [TxUserInfo] = []

        do {
            for txInfo in try db.prepare(txUserInfos) {
                let userInfo = TxUserInfo(row: txInfo)
                userInfos.append(userInfo)
            }
        } catch {
            print(error)
        }

        return userInfos
    }

    func get(by hash: Data) -> TxUserInfo? {
        if let cached = cachedValue(by: hash) {
            return cached
        }

        let txUserInfo = TxUserInfo.table.filter(TxUserInfo.txHashColumn == hash)

        do {
            for txInfo in try db.prepare(txUserInfo) {
                let userInfo = TxUserInfo(row: txInfo)
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

    private func cachedValue(by key: Data) -> TxUserInfo? {
        var v: TxUserInfo?

        queue.sync {
            v = cache[key]
        }

        return v
    }

    func update(dto: TxUserInfo) {
        create(dto: dto)
    }

    func delete(dto: TxUserInfo) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache[dto.txHash] = nil
        }
    }

    func deleteAll() {
        do {
            try db.run(TxUserInfo.table.delete())
            queue.async(flags: .barrier) { [weak self] in
                self?.cache = [:]
            }
        } catch {
            print(error)
        }
    }

    static let shared = TxUserInfoDAOImpl()
}

extension TxUserInfoDAOImpl {
    func dictionaryOfAllItems() -> [Data: TxUserInfo] {
        _ = all()
        return cache
    }
}
