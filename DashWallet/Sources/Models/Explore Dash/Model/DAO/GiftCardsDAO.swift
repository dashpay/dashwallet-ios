//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

// MARK: - GiftCardsDAO

protocol GiftCardsDAO {
    var giftCardTxIdPublisher: AnyPublisher<Data?, Never> { get }
    
    func create(dto: GiftCard) async
    func get(byTxId txId: Data) async -> GiftCard?
    func observeAll() -> AnyPublisher<[GiftCard], Never>
    func update(dto: GiftCard) async
    func updateCardDetails(txId: Data, number: String, pin: String?) async
    func updateBarcode(txId: Data, value: String, format: String) async
    func updateRedeemUrl(txId: Data, url: String, challenge: String?) async
    func delete(byTxId txId: Data) async
    func all() async -> [GiftCard]
}

// MARK: - GiftCardsDAOImpl

class GiftCardsDAOImpl: NSObject, GiftCardsDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: GiftCard] = [:]
    // `cache` is read/written from several concurrent async contexts (DB continuations resume on a
    // global queue, the details-screen ticker and loadGiftCard run in parallel). A plain Dictionary
    // is not thread-safe, and concurrent mutation corrupts its storage — which crashed as
    // "-[__NSTaggedDate count]: unrecognized selector" on garbage. Serialize all access with a lock.
    private let cacheLock = NSLock()

    private func cacheSet(_ value: GiftCard?, forKey key: String) {
        cacheLock.lock()
        cache[key] = value
        cacheLock.unlock()
    }

    private func cacheRemoveAll() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    private func cacheValues() -> [GiftCard] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return Array(cache.values)
    }

    @Published private var giftCardTxId: Data?
    private var allCardsSubject = CurrentValueSubject<[GiftCard], Never>([])
    
    var giftCardTxIdPublisher: AnyPublisher<Data?, Never> {
        $giftCardTxId.eraseToAnyPublisher()
    }
    
    static let shared = GiftCardsDAOImpl()
    
    override init() {
        super.init()
        Task {
            await loadAllCards()
        }
    }
    
    func create(dto: GiftCard) async {
        do {
            let insert = GiftCard.table.insert(or: .replace,
                                              GiftCard.txId <- dto.txId,
                                              GiftCard.merchantName <- dto.merchantName,
                                              GiftCard.merchantUrl <- dto.merchantUrl,
                                              GiftCard.price <- dto.price.description,
                                              GiftCard.number <- dto.number,
                                              GiftCard.pin <- dto.pin,
                                              GiftCard.barcodeValue <- dto.barcodeValue,
                                              GiftCard.barcodeFormat <- dto.barcodeFormat,
                                              GiftCard.note <- dto.note,
                                              GiftCard.provider <- dto.provider,
                                              GiftCard.redeemUrlChallenge <- dto.redeemUrlChallenge)
            try await execute(insert)
            let key = dto.txId.hexEncodedString()
            cacheSet(dto, forKey: key)
            self.giftCardTxId = dto.txId
            updateAllCardsSubject()
        } catch {
            print(error)
        }
    }
    
    func get(byTxId txId: Data) async -> GiftCard? {
        let statement = GiftCard.table.filter(GiftCard.txId == txId)
        
        do {
            let results: [GiftCard] = try await prepare(statement)
            let key = txId.hexEncodedString()
            cacheSet(results.first, forKey: key)
            return results.first
        } catch {
            print(error)
        }
        
        return nil
    }
    
    
    func observeAll() -> AnyPublisher<[GiftCard], Never> {
        return allCardsSubject.eraseToAnyPublisher()
    }
    
    func update(dto: GiftCard) async {
        await create(dto: dto)
    }
    
    func updateCardDetails(txId: Data, number: String, pin: String?) async {
        do {
            let update = GiftCard.table.filter(GiftCard.txId == txId)
                .update(GiftCard.number <- number,
                       GiftCard.pin <- pin,
                       GiftCard.note <- nil)
            try await execute(update)
            
            // Update cache and notify observers
            if let existingCard = await get(byTxId: txId) {
                let updatedCard = GiftCard(
                    txId: existingCard.txId,
                    merchantName: existingCard.merchantName,
                    merchantUrl: existingCard.merchantUrl,
                    price: existingCard.price,
                    number: number,
                    pin: pin,
                    barcodeValue: existingCard.barcodeValue,
                    barcodeFormat: existingCard.barcodeFormat,
                    note: nil,
                    provider: existingCard.provider,
                    redeemUrlChallenge: existingCard.redeemUrlChallenge
                )
                let key = txId.hexEncodedString()
                cacheSet(updatedCard, forKey: key)
                self.giftCardTxId = txId
                updateAllCardsSubject()
            }
        } catch {
            print(error)
        }
    }
    
    func updateBarcode(txId: Data, value: String, format: String) async {
        do {
            let update = GiftCard.table.filter(GiftCard.txId == txId)
                .update(GiftCard.barcodeValue <- value,
                       GiftCard.barcodeFormat <- format)
            try await execute(update)
            
            // Update cache and notify observers
            if let existingCard = await get(byTxId: txId) {
                let updatedCard = GiftCard(
                    txId: existingCard.txId,
                    merchantName: existingCard.merchantName,
                    merchantUrl: existingCard.merchantUrl,
                    price: existingCard.price,
                    number: existingCard.number,
                    pin: existingCard.pin,
                    barcodeValue: value,
                    barcodeFormat: format,
                    note: existingCard.note,
                    provider: existingCard.provider,
                    redeemUrlChallenge: existingCard.redeemUrlChallenge
                )
                let key = txId.hexEncodedString()
                cacheSet(updatedCard, forKey: key)
                self.giftCardTxId = txId
                updateAllCardsSubject()
            }
        } catch {
            print(error)
        }
    }

    func updateRedeemUrl(txId: Data, url: String, challenge: String?) async {
        do {
            let update = GiftCard.table.filter(GiftCard.txId == txId)
                .update(GiftCard.number <- url,
                        GiftCard.redeemUrlChallenge <- challenge)
            try await execute(update)

            if let existingCard = await get(byTxId: txId) {
                let updatedCard = GiftCard(
                    txId: existingCard.txId,
                    merchantName: existingCard.merchantName,
                    merchantUrl: existingCard.merchantUrl,
                    price: existingCard.price,
                    number: url,
                    pin: existingCard.pin,
                    barcodeValue: existingCard.barcodeValue,
                    barcodeFormat: existingCard.barcodeFormat,
                    note: existingCard.note,
                    provider: existingCard.provider,
                    redeemUrlChallenge: challenge
                )
                let key = txId.hexEncodedString()
                cacheSet(updatedCard, forKey: key)
                self.giftCardTxId = txId
                updateAllCardsSubject()
            }
        } catch {
            print(error)
        }
    }
    
    func delete(byTxId txId: Data) async {
        let key = txId.hexEncodedString()
        cacheSet(nil, forKey: key)
        self.giftCardTxId = txId
        
        do {
            let deleteQuery = GiftCard.table.filter(GiftCard.txId == txId).delete()
            try await execute(deleteQuery)
            updateAllCardsSubject()
        } catch {
            print(error)
        }
    }
    
    func all() async -> [GiftCard] {
        do {
            return try await prepare(GiftCard.table)
        } catch {
            print(error)
        }
        
        return []
    }
    
    private func loadAllCards() async {
        let cards = await all()
        cacheRemoveAll()
        for card in cards {
            let key = card.txId.hexEncodedString()
            cacheSet(card, forKey: key)
        }
        updateAllCardsSubject()
    }
    
    private func updateAllCardsSubject() {
        let allCards = cacheValues()
        allCardsSubject.send(allCards)
    }
}

// MARK: - async / await

extension GiftCardsDAOImpl {
    private func execute(_ query: Insert) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume() }
                
                do {
                    try db.run(query)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func execute(_ query: Update) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume() }
                
                do {
                    try db.run(query)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func execute(_ query: Delete) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume() }
                
                do {
                    try db.run(query)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func prepare<T: RowDecodable>(_ statement: QueryType) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume(returning: []) }
                
                var result: [T] = []
                
                do {
                    for row in try db.prepare(statement) {
                        let rowItem = T(row: row)
                        result.append(rowItem)
                    }
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
} 
