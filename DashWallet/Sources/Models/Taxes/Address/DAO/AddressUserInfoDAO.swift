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

// MARK: - AddressUserInfoDAO

protocol AddressUserInfoDAO {
    func create(dto: AddressUserInfo)
    func all() -> [AddressUserInfo]
    func get(by address: String) -> AddressUserInfo?
    func update(dto: AddressUserInfo)
    func delete(dto: AddressUserInfo)
}

// MARK: - AddressUserInfoDAOImpl

@objc
class AddressUserInfoDAOImpl: NSObject, AddressUserInfoDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: AddressUserInfo] = [:]

    @objc func create(dto: AddressUserInfo) {
        do {
            let userInfo = AddressUserInfo.table.insert(or: .replace, AddressUserInfo.addressColumn <- dto.address,
                                                        AddressUserInfo.txCategoryColumn <- dto.taxCategory.rawValue)
            try db.run(userInfo)

        } catch {
            print(error)
        }

        cache[dto.address] = dto
    }

    @objc func all() -> [AddressUserInfo] {
        let txUserInfos = AddressUserInfo.table

        var userInfos: [AddressUserInfo] = []

        do {
            for txInfo in try db.prepare(txUserInfos) {
                let userInfo = AddressUserInfo(row: txInfo)
                cache[userInfo.address] = userInfo
                userInfos.append(userInfo)
            }
        } catch {
            print(error)
        }

        return userInfos
    }

    @objc func get(by address: String) -> AddressUserInfo? {
        if let cached = cache[address] {
            return cached
        }

        let userInfo = AddressUserInfo.table.filter(AddressUserInfo.addressColumn == address)

        do {
            for txInfo in try db.prepare(userInfo) {
                let userInfo = AddressUserInfo(row: txInfo)
                cache[address] = userInfo
                return userInfo
            }
        } catch {
            print(error)
        }

        return nil
    }

    @objc func update(dto: AddressUserInfo) {
        create(dto: dto)
    }

    @objc func delete(dto: AddressUserInfo) {
        cache[dto.address] = nil
    }

    @objc static let shared = AddressUserInfoDAOImpl()
}

extension AddressUserInfoDAOImpl {
    @objc func dictionaryOfAllItems() -> [String: AddressUserInfo] {
        all()
        return cache
    }
}
