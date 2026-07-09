//
//  Created by Andrei Ashikhmin
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

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

// MARK: - ObservedTransaction from persisted rows

extension ObservedTransaction {
    /// Build from a persisted SwiftDashSDK row + a consensus decode of its raw
    /// bytes. nil (logged) when the bytes fail to decode. Main-actor: the row's
    /// model context and the `Transaction` wrapper are main-bound.
    @MainActor
    init?(row: PersistentTransaction, network: Network) {
        let decoded: DecodedTransaction
        do {
            decoded = try TransactionDecoder.decode(row.transactionData, network: network)
        } catch {
            TransactionObserver.logger.error(
                "🅾 OBSERVER :: decode failed for \(row.txidHex, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        if decoded.txid != row.txid {
            // Both are wire order; a mismatch means corrupt bytes — log loudly
            // but keep the row's txid as the identity the rest of the app uses.
            TransactionObserver.logger.error(
                "🅾 OBSERVER :: txid mismatch row=\(row.txidHex, privacy: .public) decoded=\(decoded.txidDisplayHex, privacy: .public)")
        }
        txid = row.txid
        txidHexDisplay = row.txidHex
        outputs = decoded.outputs.map { Output(address: $0.address, amount: $0.valueDuffs) }
        inputAddresses = Set(decoded.inputs.compactMap { $0.address })
        // The row's TXOs are exactly the wallet's own outputs of this tx.
        let ownAddresses = Set(row.outputs.map(\.address))
        ownOutputsAmount = row.outputs.reduce(0) { $0 + $1.amount }
        ownOutputAddresses = decoded.outputs.compactMap { $0.address }.filter { ownAddresses.contains($0) }
        isChainAccepted = row.context >= 1 || row.blockHeight > 0
        // firstSeen first (device-clock stamp at first observation — the
        // ordering key the observer's freshness floor uses), blockTimestamp
        // as the fallback for rows restored from chain data.
        let ts: UInt64 = row.firstSeen != 0 ? row.firstSeen : UInt64(row.blockTimestamp)
        timestamp = ts == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(ts))
        wrapped = Transaction(persistentTransaction: row)
    }
}

// MARK: - TransactionObserver

/// Watches SwiftDashSDK-persisted transactions for CrowdNode protocol matches.
///
/// Replaces the DashSync `DSTransactionManagerTransactionStatusDidChange`
/// pipeline (dead post-M6 — DashSync no longer syncs, so it never fired and
/// every await hung forever). The Rust persister writes `PersistentTransaction`
/// rows on every Core SPV batch and SwiftData posts
/// `NSManagedObjectContextDidSave`; each save triggers a bounded rescan.
public final class TransactionObserver {
    static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "crowdnode-observer")

    /// `firstSeen` is stamped from the device clock when the SDK first sees a
    /// tx, and responses always postdate the request we broadcast — so a small
    /// skew window below `after` keeps a same-code response from a PREVIOUS
    /// request (e.g. an earlier deposit's ack) out of this wait while never
    /// dropping a response that raced the subscription.
    private static let matchFloorSkew: TimeInterval = 120
    /// Rows admitted per rescan; the floor predicate already bounds the
    /// window, this guards a resync burst mid-wait.
    private static let rescanFetchLimit = 200

    // MARK: Shared row scanner

    /// Persisted rows decoded to `ObservedTransaction`, newest-first
    /// (`firstSeen` desc). Empty (logged) when the SDK host has no container
    /// yet or the network is unsupported. Safe from any thread — trampolines
    /// to main because this scanner reads through `mainContext`.
    static func fetchObserved(
        fetchLimit: Int? = nil,
        firstSeenAtOrAfter: UInt64? = nil
    ) -> [ObservedTransaction] {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                fetchObservedOnMain(fetchLimit: fetchLimit, firstSeenAtOrAfter: firstSeenAtOrAfter)
            }
        }
        var result: [ObservedTransaction] = []
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated {
                fetchObservedOnMain(fetchLimit: fetchLimit, firstSeenAtOrAfter: firstSeenAtOrAfter)
            }
        }
        return result
    }

    @MainActor
    private static func fetchObservedOnMain(
        fetchLimit: Int?,
        firstSeenAtOrAfter: UInt64?
    ) -> [ObservedTransaction] {
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            logger.info("🅾 OBSERVER :: no model container / active wallet yet — empty scan")
            return []
        }
        guard case .success(let network) = SwiftDashSDKWalletRuntime.shared.resolveCurrentNetwork() else {
            logger.error("🅾 OBSERVER :: unsupported network — empty scan")
            return []
        }
        // Scope to the active wallet via the TXO join: gather the wallet's
        // txids from its walletId-scoped TXO rows (CrowdNode responses land
        // in the active wallet's own addresses), then match transactions in
        // that set. `PersistentTransaction` carries no walletId of its own.
        let txoDescriptor = FetchDescriptor<PersistentTxo>(
            predicate: #Predicate { $0.walletId == walletId })
        let txos = (try? container.mainContext.fetch(txoDescriptor)) ?? []
        var txids = Set<Data>()
        for txo in txos {
            if let producing = txo.transaction { txids.insert(producing.txid) }
            if let spending = txo.spendingTransaction { txids.insert(spending.txid) }
        }
        guard !txids.isEmpty else { return [] }
        var descriptor = FetchDescriptor<PersistentTransaction>(
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)])
        if let floor = firstSeenAtOrAfter {
            descriptor.predicate = #Predicate { txids.contains($0.txid) && $0.firstSeen >= floor }
        } else {
            descriptor.predicate = #Predicate { txids.contains($0.txid) }
        }
        if let fetchLimit {
            descriptor.fetchLimit = fetchLimit
        }
        do {
            let rows = try container.mainContext.fetch(descriptor)
            return rows.compactMap { ObservedTransaction(row: $0, network: network) }
        } catch {
            logger.error("🅾 OBSERVER :: PersistentTransaction fetch failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: Matching

    /// Emits every persisted tx matching any filter, deduped by txid within
    /// the subscription. Scans immediately at subscribe (the response may have
    /// been persisted before the await started), then rescans on every
    /// SwiftData save.
    func observe(filters: [TransactionFilter], after: Date) -> AnyPublisher<ObservedTransaction, Never> {
        let floor = UInt64(max(0, after.timeIntervalSince1970 - Self.matchFloorSkew))
        return Deferred {
            var seenTxids = Set<Data>()
            return NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
                .map { _ in () }
                .prepend(()) // immediate initial scan
                .receive(on: RunLoop.main)
                .flatMap { _ in
                    Self.fetchObserved(fetchLimit: Self.rescanFetchLimit, firstSeenAtOrAfter: floor)
                        .filter { tx in filters.contains { $0.matches(tx) } }
                        .publisher
                }
                .filter { seenTxids.insert($0.txid).inserted }
        }
        .eraseToAnyPublisher()
    }

    /// Waits for the first persisted tx that matches any filter. Capture
    /// `after` just before broadcasting the request the response answers.
    func first(filters: TransactionFilter..., after: Date = Date()) async -> ObservedTransaction {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = observe(filters: filters, after: after).first().sink(receiveValue: { tx in
                TransactionObserver.logger.info("🅾 OBSERVER :: matched \(tx.txidHexDisplay, privacy: .public)")
                cancellable?.cancel()
                continuation.resume(returning: tx)
            })
        }
    }
}
