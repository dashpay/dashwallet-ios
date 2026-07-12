//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

// MARK: - SwapOrdersDAO

protocol SwapOrdersDAO {
    func create(dto: SwapOrder) async
    func get(byId id: String) async -> SwapOrder?
    func update(dto: SwapOrder) async
    func delete(byId id: String) async
    func all() async -> [SwapOrder]
    func observeAll() -> AnyPublisher<[SwapOrder], Never>
    func observeActive() -> AnyPublisher<[SwapOrder], Never>
}

// MARK: - SwapOrdersDAOImpl

class SwapOrdersDAOImpl: SwapOrdersDAO {
    static let shared = SwapOrdersDAOImpl()

    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: SwapOrder] = [:]
    private var allOrdersSubject = CurrentValueSubject<[SwapOrder], Never>([])

    private init() {
        Task { await loadAll() }
    }

    // MARK: - Protocol

    func create(dto: SwapOrder) async {
        do {
            let insert = SwapOrder.table.insert(or: .replace,
                SwapOrder.colId <- dto.id,
                SwapOrder.colDirection <- dto.direction,
                SwapOrder.colService <- dto.service,
                SwapOrder.colProvider <- dto.provider,
                SwapOrder.colFromAsset <- dto.fromAsset,
                SwapOrder.colToAsset <- dto.toAsset,
                SwapOrder.colToAddress <- dto.toAddress,
                SwapOrder.colDepositAddress <- dto.depositAddress,
                SwapOrder.colExpectedToAmount <- dto.expectedToAmount,
                SwapOrder.colActualToAmount <- dto.actualToAmount,
                SwapOrder.colStatus <- dto.status.rawValue,
                SwapOrder.colOutboundTxHash <- dto.outboundTxHash,
                SwapOrder.colTimestamp <- dto.timestamp,
                SwapOrder.colFinalisedAt <- dto.finalisedAt,
                SwapOrder.colLastChecked <- dto.lastChecked
            )
            try await execute(insert)
            cache[dto.id] = dto
            emitUpdate()
        } catch {
            DSLogger.log("SwapOrdersDAO: create failed: \(error)")
        }
    }

    func get(byId id: String) async -> SwapOrder? {
        let query = SwapOrder.table.filter(SwapOrder.colId == id)
        do {
            let results: [SwapOrder] = try await prepare(query)
            cache[id] = results.first
            return results.first
        } catch {
            DSLogger.log("SwapOrdersDAO: get failed: \(error)")
            return nil
        }
    }

    func update(dto: SwapOrder) async {
        await create(dto: dto)
    }

    func delete(byId id: String) async {
        cache.removeValue(forKey: id)
        do {
            let deleteQuery = SwapOrder.table.filter(SwapOrder.colId == id).delete()
            try await execute(deleteQuery)
            emitUpdate()
        } catch {
            DSLogger.log("SwapOrdersDAO: delete failed: \(error)")
        }
    }

    func all() async -> [SwapOrder] {
        do {
            return try await prepare(SwapOrder.table)
        } catch {
            DSLogger.log("SwapOrdersDAO: all failed: \(error)")
            return []
        }
    }

    func observeAll() -> AnyPublisher<[SwapOrder], Never> {
        allOrdersSubject.eraseToAnyPublisher()
    }

    func observeActive() -> AnyPublisher<[SwapOrder], Never> {
        allOrdersSubject
            .map { $0.filter { $0.status.isActive } }
            .eraseToAnyPublisher()
    }

    // MARK: - Private

    private func loadAll() async {
        let orders = await all()
        cache.removeAll()
        for order in orders { cache[order.id] = order }
        emitUpdate()
    }

    private func emitUpdate() {
        allOrdersSubject.send(Array(cache.values))
    }
}

// MARK: - Async / await helpers

extension SwapOrdersDAOImpl {
    private func execute(_ query: Insert) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return continuation.resume() }
                do {
                    try self.db.run(query)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func execute(_ query: Delete) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return continuation.resume() }
                do {
                    try self.db.run(query)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func prepare<T: RowDecodable>(_ statement: QueryType) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return continuation.resume(returning: []) }
                var result: [T] = []
                do {
                    for row in try self.db.prepare(statement) {
                        result.append(T(row: row))
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
