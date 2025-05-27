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
    func create(dto: GiftCard) async
    func get(byTxId txId: Data) async -> GiftCard?
    func observeCard(byTxId txId: Data) -> AnyPublisher<GiftCard?, Never>
    func update(dto: GiftCard) async
    func updateCardDetails(txId: Data, number: String, pin: String?) async
    func updateBarcode(txId: Data, value: String, format: String) async
    func delete(byTxId txId: Data) async
    func all() async -> [GiftCard]
}

// MARK: - GiftCardsDAOImpl

class GiftCardsDAOImpl: NSObject, GiftCardsDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: GiftCard] = [:]
    private var subjects: [String: CurrentValueSubject<GiftCard?, Never>] = [:]
    
    static let shared = GiftCardsDAOImpl()
    
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
                                              GiftCard.note <- dto.note)
            try await execute(insert)
            let key = dto.txId.hexEncodedString()
            self.cache[key] = dto
            self.subjects[key]?.send(dto)
        } catch {
            print(error)
        }
    }
    
    func get(byTxId txId: Data) async -> GiftCard? {
        let statement = GiftCard.table.filter(GiftCard.txId == txId)
        
        do {
            let results: [GiftCard] = try await prepare(statement)
            let key = txId.hexEncodedString()
            self.cache[key] = results.first
            return results.first
        } catch {
            print(error)
        }
        
        return nil
    }
    
    func observeCard(byTxId txId: Data) -> AnyPublisher<GiftCard?, Never> {
        let key = txId.hexEncodedString()
        
        if subjects[key] == nil {
            subjects[key] = CurrentValueSubject<GiftCard?, Never>(cache[key])
            
            Task {
                let card = await get(byTxId: txId)
                subjects[key]?.send(card)
            }
        }
        
        return subjects[key]!.eraseToAnyPublisher()
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
                    note: nil
                )
                let key = txId.hexEncodedString()
                cache[key] = updatedCard
                subjects[key]?.send(updatedCard)
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
                    note: existingCard.note
                )
                let key = txId.hexEncodedString()
                cache[key] = updatedCard
                subjects[key]?.send(updatedCard)
            }
        } catch {
            print(error)
        }
    }
    
    func delete(byTxId txId: Data) async {
        let key = txId.hexEncodedString()
        self.cache[key] = nil
        self.subjects[key]?.send(nil)
        
        do {
            let deleteQuery = GiftCard.table.filter(GiftCard.txId == txId).delete()
            try await execute(deleteQuery)
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