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
    /// bytes. nil (logged) when the bytes fail to decode.
    ///
    /// Runs on whatever thread owns `row`'s context — it only reads the row's
    /// own properties and its TXO relationship, decodes bytes, and wraps the
    /// row (`HomeViewModel`'s reload already builds `Transaction` off the main
    /// thread the same way). It was `@MainActor` while the only caller read
    /// through `mainContext`; the scanner now owns its context, and forcing
    /// the decode back onto the main actor is what made a CrowdNode restore
    /// stall the main thread for ~2s.
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
    /// Scans slower than this get a log line; see `scan`.
    private static let slowScanLogThresholdMs = 150

    /// The main-actor-owned SDK handles a scan needs, resolved once per call.
    private struct HostHandles {
        let container: ModelContainer
        let walletId: Data
        let network: Network
    }

    // MARK: Shared row scanner

    /// Persisted rows decoded to `ObservedTransaction`, newest-first
    /// (`firstSeen` desc). Empty (logged) when the SDK host has no container
    /// yet or the network is unsupported. Safe from any thread.
    ///
    /// The scan itself runs on the CALLER's thread against its own
    /// `ModelContext`, never `mainContext` — callers that hold the main
    /// thread (`CrowdNode.restoreState`) therefore pay the scan inline, so
    /// keep it cheap. Only the two host reads need the main actor; they are
    /// cheap property reads.
    ///
    /// `ObservedTransaction` is a struct decoded from each row, so the results
    /// carry nothing back to the context they were read through.
    static func fetchObserved(
        fetchLimit: Int? = nil,
        firstSeenAtOrAfter: UInt64? = nil
    ) -> [ObservedTransaction] {
        let handles = { @MainActor () -> HostHandles? in
            guard let container = SwiftDashSDKHost.shared.modelContainer,
                  let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
                logger.info("🅾 OBSERVER :: no model container / active wallet yet — empty scan")
                return nil
            }
            guard case .success(let network) = SwiftDashSDKWalletRuntime.shared.resolveCurrentNetwork() else {
                logger.error("🅾 OBSERVER :: unsupported network — empty scan")
                return nil
            }
            return HostHandles(container: container, walletId: walletId, network: network)
        }

        let resolved: HostHandles?
        if Thread.isMainThread {
            resolved = MainActor.assumeIsolated { handles() }
        } else {
            resolved = DispatchQueue.main.sync { MainActor.assumeIsolated { handles() } }
        }
        guard let resolved else { return [] }
        let key = SharedScanKey(
            walletId: resolved.walletId,
            network: resolved.network,
            fetchLimit: fetchLimit,
            firstSeenAtOrAfter: firstSeenAtOrAfter)
        if let shared = sharedScanResult(for: key) { return shared }
        let rows = scan(
            container: resolved.container,
            walletId: resolved.walletId,
            network: resolved.network,
            fetchLimit: fetchLimit,
            firstSeenAtOrAfter: firstSeenAtOrAfter)
        rememberSharedScan(rows, for: key)
        return rows
    }

    // MARK: Per-pass scan sharing

    /// Identity of one scan's result: the wallet and network it was read for,
    /// plus the arguments that shaped the fetch.
    private struct SharedScanKey: Hashable {
        let walletId: Data
        let network: Network
        let fetchLimit: Int?
        let firstSeenAtOrAfter: UInt64?
    }

    private static let sharedScanLock = NSLock()
    private static var sharedScanDepth = 0
    private static var sharedScanResults: [SharedScanKey: [ObservedTransaction]] = [:]

    /// Serves identical `fetchObserved` calls made inside `body` from a single
    /// fetch + decode.
    ///
    /// A CrowdNode restore asks the same question twice — `tryRestoreSignUp`
    /// and `getApiAddressConfirmationTx` scan with identical arguments — and
    /// on a wallet with thousands of transactions each pass cost ~12s of fetch
    /// and decode, paid inline by the caller's thread.
    ///
    /// Scoped to the call rather than cached across passes on purpose: a row's
    /// `context` / `blockHeight` change as it confirms without the row count
    /// moving, so a longer-lived memo would answer `isChainAccepted` from
    /// stale data.
    static func withSharedScan<T>(_ body: () throws -> T) rethrows -> T {
        sharedScanLock.lock()
        sharedScanDepth += 1
        sharedScanLock.unlock()
        defer {
            sharedScanLock.lock()
            sharedScanDepth -= 1
            if sharedScanDepth == 0 {
                sharedScanResults.removeAll()
            }
            sharedScanLock.unlock()
        }
        return try body()
    }

    private static func sharedScanResult(for key: SharedScanKey) -> [ObservedTransaction]? {
        sharedScanLock.lock()
        defer { sharedScanLock.unlock() }
        guard sharedScanDepth > 0 else { return nil }
        return sharedScanResults[key]
    }

    private static func rememberSharedScan(_ rows: [ObservedTransaction], for key: SharedScanKey) {
        sharedScanLock.lock()
        defer { sharedScanLock.unlock() }
        guard sharedScanDepth > 0 else { return }
        sharedScanResults[key] = rows
    }

    /// Total persisted transaction count, or nil when the SDK host has no
    /// container yet. A `SELECT COUNT(*)` with no join, predicate or decode —
    /// cheap enough for callers to use as a "has anything new been persisted"
    /// check before deciding whether a full rescan is worth its cost.
    static func persistedTransactionCount() -> Int? {
        let container = { @MainActor () -> ModelContainer? in
            SwiftDashSDKHost.shared.modelContainer
        }
        let resolved: ModelContainer?
        if Thread.isMainThread {
            resolved = MainActor.assumeIsolated { container() }
        } else {
            resolved = DispatchQueue.main.sync { MainActor.assumeIsolated { container() } }
        }
        guard let resolved else { return nil }
        return try? ModelContext(resolved).fetchCount(FetchDescriptor<PersistentTransaction>())
    }

    private static func scan(
        container: ModelContainer,
        walletId: Data,
        network: Network,
        fetchLimit: Int?,
        firstSeenAtOrAfter: UInt64?
    ) -> [ObservedTransaction] {
        // Own context, so the scan never contends with the main actor.
        let context = ModelContext(container)
        // Scope to the active wallet through the TXO relationship, evaluated
        // by the store: a transaction is this wallet's when it produced or
        // spent one of the wallet's TXOs, and `PersistentTxo.walletId` is
        // indexed. Doing the same join in Swift — fetch every walletId TXO,
        // fault `.transaction` and `.spendingTransaction` on each, then feed
        // the resulting txid set back through a `contains` predicate — costs
        // two relationship faults per TXO plus an IN-list the width of the
        // wallet's history, which is where this scan's seconds went.
        var descriptor = FetchDescriptor<PersistentTransaction>(
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)])
        if let floor = firstSeenAtOrAfter {
            descriptor.predicate = #Predicate {
                $0.firstSeen >= floor &&
                    ($0.outputs.contains { $0.walletId == walletId } ||
                        $0.inputs.contains { $0.walletId == walletId })
            }
        } else {
            descriptor.predicate = #Predicate {
                $0.outputs.contains { $0.walletId == walletId } ||
                    $0.inputs.contains { $0.walletId == walletId }
            }
        }
        if let fetchLimit {
            descriptor.fetchLimit = fetchLimit
        }
        do {
            let fetchStart = Date()
            let rows = try context.fetch(descriptor)
            let fetchMs = Int(Date().timeIntervalSince(fetchStart) * 1000)
            let decodeStart = Date()
            let observed = rows.compactMap { ObservedTransaction(row: $0, network: network) }
            let decodeMs = Int(Date().timeIntervalSince(decodeStart) * 1000)
            // Only when it actually costs something: `observe()` rescans on
            // every SwiftData save, so an unconditional line here is sync-time
            // log spam. A slow scan is worth seeing because callers on the
            // main thread pay it inline.
            if fetchMs + decodeMs > Self.slowScanLogThresholdMs {
                DWLogger.log("CrowdNode scan: fetch \(rows.count) rows in \(fetchMs)ms, decode in \(decodeMs)ms")
            }
            return observed
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
