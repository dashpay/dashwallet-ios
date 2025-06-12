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
import Combine

// MARK: - Metadata Change Event

enum TransactionMetadataChange {
    case created(TransactionMetadata)
    case updated(TransactionMetadata, previousMetadata: TransactionMetadata)
    case deleted(TransactionMetadata)
    case deletedAll
}

// MARK: - TransactionMetadataDAO

protocol TransactionMetadataDAO {
    func create(dto: TransactionMetadata)
    func get(by hash: Data, ignoreCache: Bool) -> TransactionMetadata?
    func update(dto: TransactionMetadata)
    func delete(dto: TransactionMetadata)
    func deleteAll()
}

extension TransactionMetadataDAO {
    func get(by hash: Data) -> TransactionMetadata? {
        return get(by: hash, ignoreCache: false)
    }
}

// MARK: - TransactionMetadataDAOImpl

class TransactionMetadataDAOImpl: NSObject, TransactionMetadataDAO, ObservableObject {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [Data: TransactionMetadata] = [:]

    private let queue = DispatchQueue(label: "org.dash.infrastructure.queue.transaction-metadata-dao", attributes: .concurrent)
    
    @Published private(set) var lastChange: TransactionMetadataChange?
    
    func create(dto: TransactionMetadata) {
        do {
            let transactionMetadata = TransactionMetadata.table.insert(or: .replace,
                                                     TransactionMetadata.txHashColumn <- dto.txHash,
                                                     TransactionMetadata.txCategoryColumn <- dto.taxCategory.rawValue,
                                                     TransactionMetadata.txRateColumn <- dto.rate,
                                                     TransactionMetadata.txRateCurrencyCodeColumn <- dto.rateCurrency,
                                                     TransactionMetadata.txRateMaximumFractionDigitsColumn <- dto.rateMaximumFractionDigits,
                                                     TransactionMetadata.timestamp <- dto.timestamp,
                                                     TransactionMetadata.memo <- dto.memo,
                                                     TransactionMetadata.service <- dto.service,
                                                     TransactionMetadata.customIconId <- dto.customIconId)
            try db.run(transactionMetadata)

        } catch {
            print(error)
        }

        queue.async(flags: .barrier) { [weak self] in
            self?.cache[dto.txHash] = dto
            
            DispatchQueue.main.async {
                self?.lastChange = .created(dto)
            }
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

    func get(by hash: Data, ignoreCache: Bool = false) -> TransactionMetadata? {
        if !ignoreCache, let cached = cachedValue(by: hash) {
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
        guard let existingDto = get(by: dto.txHash) else {
            create(dto: dto)
            return
        }
        
        do {
            var setters: [Setter] = []
            
            if dto.taxCategory != .unknown && existingDto.taxCategory != dto.taxCategory {
                setters.append(TransactionMetadata.txCategoryColumn <- dto.taxCategory.rawValue)
            }
            
            if let rate = dto.rate, existingDto.rate != rate {
                setters.append(TransactionMetadata.txRateColumn <- rate)
            }
            
            if let rateCurrency = dto.rateCurrency, existingDto.rateCurrency != rateCurrency {
                setters.append(TransactionMetadata.txRateCurrencyCodeColumn <- rateCurrency)
            }
            
            if let rateMaximumFractionDigits = dto.rateMaximumFractionDigits, existingDto.rateMaximumFractionDigits != rateMaximumFractionDigits {
                setters.append(TransactionMetadata.txRateMaximumFractionDigitsColumn <- rateMaximumFractionDigits)
            }
            
            if let timestamp = dto.timestamp, existingDto.timestamp != timestamp {
                setters.append(TransactionMetadata.timestamp <- timestamp)
            }
            
            if let memo = dto.memo, existingDto.memo != memo {
                setters.append(TransactionMetadata.memo <- memo)
            }
            
            if let service = dto.service, existingDto.service != service {
                setters.append(TransactionMetadata.service <- service)
            }
            
            if let customIconId = dto.customIconId, existingDto.customIconId != customIconId {
                setters.append(TransactionMetadata.customIconId <- customIconId)
            }
            
            if !setters.isEmpty {
                let txUserInfo = TransactionMetadata.table.filter(TransactionMetadata.txHashColumn == dto.txHash)
                try db.run(txUserInfo.update(setters))
                
                // Update cache
                if let updated = get(by: dto.txHash, ignoreCache: true) {
                    DispatchQueue.main.async { [weak self] in
                        self?.lastChange = .updated(updated, previousMetadata: existingDto)
                    }
                }
            }
        } catch {
            print(error)
        }
    }

    func delete(dto: TransactionMetadata) {
        do {
            let txUserInfo = TransactionMetadata.table.filter(TransactionMetadata.txHashColumn == dto.txHash)
            try db.run(txUserInfo.delete())
            
            queue.async(flags: .barrier) { [weak self] in
                self?.cache[dto.txHash] = nil
                
                // Publish the deleted metadata event
                DispatchQueue.main.async {
                    self?.lastChange = .deleted(dto)
                }
            }
        } catch {
            print(error)
        }
    }

    func deleteAll() {
        do {
            try db.run(TransactionMetadata.table.delete())
            queue.async(flags: .barrier) { [weak self] in
                self?.cache = [:]
                
                // Publish the delete all event
                DispatchQueue.main.async {
                    self?.lastChange = .deletedAll
                }
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
