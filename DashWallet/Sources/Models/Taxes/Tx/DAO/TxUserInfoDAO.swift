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
    func all() -> [TxUserInfo]
    func update(dto: TxUserInfo)
    func delete(dto: TxUserInfo)
    func deleteAll()
}

// MARK: - TxUserInfoDAOImpl

@objc
class TxUserInfoDAOImpl: NSObject, TxUserInfoDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [Data: TxUserInfo] = [:]

    @objc
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

        cache[dto.txHash] = dto
    }

    @objc
    func all() -> [TxUserInfo] {
        let txUserInfos = TxUserInfo.table

        var userInfos: [TxUserInfo] = []

        do {
            for txInfo in try db.prepare(txUserInfos) {
                let userInfo = TxUserInfo(row: txInfo)
                cache[userInfo.txHash] = userInfo
                userInfos.append(userInfo)
            }
        } catch {
            print(error)
        }

        return userInfos
    }

    @objc
    func get(by hash: Data) -> TxUserInfo? {
        if let cached = cache[hash] {
            return cached
        }

        let txUserInfo = TxUserInfo.table.filter(TxUserInfo.txHashColumn == hash)

        do {
            for txInfo in try db.prepare(txUserInfo) {
                let userInfo = TxUserInfo(row: txInfo)
                cache[hash] = userInfo
                return userInfo
            }
        } catch {
            print(error)
        }

        return nil
    }

    @objc
    func update(dto: TxUserInfo) {
        create(dto: dto)
    }

    @objc
    func delete(dto: TxUserInfo) {
        cache[dto.txHash] = nil
    }

    @objc
    func deleteAll() {
        do {
            try db.run(TxUserInfo.table.delete())
            cache = [:]
        } catch {
            print(error)
        }
    }

    @objc static let shared = TxUserInfoDAOImpl()
}

extension TxUserInfoDAOImpl {
    @objc
    func dictionaryOfAllItems() -> [Data: TxUserInfo] {
        all()
        return cache
    }
}
