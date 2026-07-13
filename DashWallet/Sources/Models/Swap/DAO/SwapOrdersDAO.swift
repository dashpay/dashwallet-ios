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

import Combine
import Foundation
@preconcurrency import SQLite

// MARK: - SwapOrdersDAO

protocol SwapOrdersDAO {
    func create(dto: SwapOrder) async
    func save(dto: SwapOrder) async throws
    func get(byId id: String) async -> SwapOrder?
    func update(dto: SwapOrder) async
    func delete(byId id: String) async
    func all() async -> [SwapOrder]
    func observeAll() -> AnyPublisher<[SwapOrder], Never>
    func observeActive() -> AnyPublisher<[SwapOrder], Never>
}

// MARK: - SwapOrdersDAOImpl

actor SwapOrdersDAOImpl: SwapOrdersDAO {
    static let shared = SwapOrdersDAOImpl()
    private nonisolated(unsafe) let allOrdersSubject = CurrentValueSubject<[SwapOrder], Never>([])
    private var cache: [String: SwapOrder] = [:]
    // `lazy` so the bootstrap Task is created on first access (after init), avoiding a
    // "self captured before all members were initialized" error. First read/write awaits it.
    private lazy var hydration: Task<Void, Never> = Task { [weak self] in
        await self?.bootstrap()
    }

    private init() {}

    // MARK: - Protocol

    func create(dto: SwapOrder) async {
        do {
            try await save(dto: dto)
        } catch {
            DSLogger.log("SwapOrdersDAO: create failed: \(error)")
        }
    }

    func save(dto: SwapOrder) async throws {
        await hydration.value

        let insert = SwapOrder.table.insert(
            or: .replace,
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
        try execute(insert)
        cache[dto.id] = dto
        emitUpdate()
    }

    func get(byId id: String) async -> SwapOrder? {
        await hydration.value

        let query = SwapOrder.table.filter(SwapOrder.colId == id)
        do {
            let results: [SwapOrder] = try read(query)
            let order = results.first
            if let order {
                cache[id] = order
            } else {
                cache.removeValue(forKey: id)
            }
            return order
        } catch {
            DSLogger.log("SwapOrdersDAO: get failed: \(error)")
            return nil
        }
    }

    func update(dto: SwapOrder) async {
        do {
            try await save(dto: dto)
        } catch {
            DSLogger.log("SwapOrdersDAO: update failed: \(error)")
        }
    }

    func delete(byId id: String) async {
        await hydration.value

        do {
            let deleteQuery = SwapOrder.table.filter(SwapOrder.colId == id).delete()
            try execute(deleteQuery)
            cache.removeValue(forKey: id)
            emitUpdate()
        } catch {
            DSLogger.log("SwapOrdersDAO: delete failed: \(error)")
        }
    }

    func all() async -> [SwapOrder] {
        await hydration.value

        do {
            let orders: [SwapOrder] = try read(SwapOrder.table)
            cache = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
            return orders
        } catch {
            DSLogger.log("SwapOrdersDAO: all failed: \(error)")
            return Array(cache.values)
        }
    }

    nonisolated func observeAll() -> AnyPublisher<[SwapOrder], Never> {
        Task { await hydration.value }
        allOrdersSubject.eraseToAnyPublisher()
    }

    nonisolated func observeActive() -> AnyPublisher<[SwapOrder], Never> {
        Task { await hydration.value }
        allOrdersSubject
            .map { $0.filter { $0.status.isActive } }
            .eraseToAnyPublisher()
    }

    // MARK: - Private

    private func bootstrap() async {
        do {
            let orders: [SwapOrder] = try read(SwapOrder.table)
            cache = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
            emitUpdate()
        } catch {
            DSLogger.log("SwapOrdersDAO: bootstrap failed: \(error)")
        }
    }

    private func emitUpdate() {
        allOrdersSubject.send(Array(cache.values))
    }
}

// MARK: - Database helpers
//
// The DAO is an `actor`, so it already serialises every DB access — no extra queue is needed
// (and a `DispatchQueue.async` hop would capture the non-Sendable `Connection`/query in a
// `@Sendable` closure). `swap_orders` is a tiny table, so running SQLite synchronously on the
// actor's executor is cheap and race-free.

extension SwapOrdersDAOImpl {
    private func execute(_ query: Insert) throws {
        let db: Connection = DatabaseConnection.shared.db
        try db.run(query)
    }

    private func execute(_ query: Delete) throws {
        let db: Connection = DatabaseConnection.shared.db
        try db.run(query)
    }

    private func read<T: RowDecodable>(_ statement: QueryType) throws -> [T] {
        let db: Connection = DatabaseConnection.shared.db
        return try db.prepare(statement).map { T(row: $0) }
    }
}
