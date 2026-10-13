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
    /// Whether the cache has been filled from the table: the first read can fail, and until
    /// one succeeds the cache holds only the rows written or read one by one since.
    private var isHydrated = false
    private var hasLoggedHydrationFailure = false

    private init() {}

    #if DEBUG
    /// Stands in for the read of the whole table, so a test can make a read fail. Nothing
    /// else is replaced: single-row reads and writes still go to the database.
    private var readingAll: (@Sendable () throws -> [SwapOrder])?

    init(readingAll: @escaping @Sendable () throws -> [SwapOrder]) {
        self.readingAll = readingAll
    }
    #endif

    /// The last published snapshot, for synchronous readers (the Home timeline rebuild runs
    /// off the main actor and cannot await). Until a read of the table succeeds it is the
    /// cache as of the last write: the orders written or read one by one since launch.
    nonisolated var currentOrders: [SwapOrder] { allOrdersSubject.value }

    // MARK: - Protocol

    func create(dto: SwapOrder) async {
        do {
            try await save(dto: dto)
        } catch {
            DWLogger.log("SwapOrdersDAO: create failed: \(error)")
        }
    }

    func save(dto: SwapOrder) async throws {
        hydrate()
        try store(dto)
    }

    /// Changes the row `id` as it is now: read, changed and written with nothing in
    /// between, so this write undoes nothing another writer stored. (A `save` of a row
    /// read earlier still replaces what an `amend` stored in between.) `change` returns
    /// false to leave the row alone. Returns whether the row was written.
    @discardableResult
    func amend(id: String, _ change: @Sendable (inout SwapOrder) -> Bool) async throws -> Bool {
        hydrate()
        let rows: [SwapOrder] = try read(SwapOrder.table.filter(SwapOrder.colId == id))
        guard var order = rows.first, change(&order) else { return false }
        try store(order)
        return true
    }

    private func store(_ dto: SwapOrder) throws {
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
            SwapOrder.colLastChecked <- dto.lastChecked,
            SwapOrder.colFromAmount <- dto.fromAmount,
            SwapOrder.colDepositDeadline <- dto.depositDeadline,
            SwapOrder.colDepositSeenAt <- dto.depositSeenAt,
            SwapOrder.colProviderDeniedAt <- dto.providerDeniedAt,
            SwapOrder.colDepositMemo <- dto.depositMemo,
            SwapOrder.colOwnerWalletId <- dto.ownerWalletId,
            SwapOrder.colOwnerNetwork <- dto.ownerNetwork,
            SwapOrder.colPayoutNamedAt <- dto.payoutNamedAt,
            SwapOrder.colPayoutCandidates <- dto.payoutCandidates
        )
        try execute(insert)
        cache[dto.id] = dto
        emitUpdate()
    }

    func get(byId id: String) async -> SwapOrder? {
        hydrate()

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
            DWLogger.log("SwapOrdersDAO: get failed: \(error)")
            return nil
        }
    }

    func update(dto: SwapOrder) async {
        do {
            try await save(dto: dto)
        } catch {
            DWLogger.log("SwapOrdersDAO: update failed: \(error)")
        }
    }

    func delete(byId id: String) async {
        hydrate()

        do {
            let deleteQuery = SwapOrder.table.filter(SwapOrder.colId == id).delete()
            try execute(deleteQuery)
            cache.removeValue(forKey: id)
            emitUpdate()
        } catch {
            DWLogger.log("SwapOrdersDAO: delete failed: \(error)")
        }
    }

    func all() async -> [SwapOrder] {
        do {
            return try reload()
        } catch {
            DWLogger.log("SwapOrdersDAO: all failed: \(error)")
            return Array(cache.values)
        }
    }

    nonisolated func observeAll() -> AnyPublisher<[SwapOrder], Never> {
        Task { await hydrate() }
        return allOrdersSubject.eraseToAnyPublisher()
    }

    nonisolated func observeActive() -> AnyPublisher<[SwapOrder], Never> {
        Task { await hydrate() }
        return allOrdersSubject
            .map { $0.filter { $0.status.isActive } }
            .eraseToAnyPublisher()
    }

    // MARK: - Private

    /// Fills the cache from the table while no read of it has succeeded: the first one
    /// can fail, and the snapshot would otherwise stay without the stored orders until
    /// something read the whole table.
    private func hydrate() {
        guard !isHydrated else { return }
        do {
            try reload()
        } catch {
            // Every entry point retries: one line, not one per call.
            guard !hasLoggedHydrationFailure else { return }
            hasLoggedHydrationFailure = true
            DWLogger.log("SwapOrdersDAO: hydration failed: \(error)")
        }
    }

    /// Reads the whole table into the cache and publishes it when it differs from the
    /// last snapshot. An unchanged read publishes nothing — subscribers read the table
    /// in answer to a publication.
    @discardableResult
    private func reload() throws -> [SwapOrder] {
        let orders = try readAll()
        cache = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        isHydrated = true
        let published = Dictionary(uniqueKeysWithValues: allOrdersSubject.value.map { ($0.id, $0) })
        if published != cache {
            emitUpdate()
        }
        return orders
    }

    private func readAll() throws -> [SwapOrder] {
        #if DEBUG
        if let readingAll { return try readingAll() }
        #endif
        return try read(SwapOrder.table)
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
