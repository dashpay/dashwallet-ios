//
//  PlatformAddressActivityStore.swift
//  DashWallet
//
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
//  App-owned ledger of observed incoming Platform-address payments.
//
//  Platform (DIP-17) address history has no SDK-persisted event stream:
//  the BLAST sync surfaces only absolute per-address balances (and its
//  per-pass sync event carries aggregate counters, no per-address
//  entries). So a third party paying one of the wallet's Platform
//  addresses changed the balance with NOTHING in the home history —
//  confusing. This store closes that gap observationally: after every
//  BLAST pass the recorder diffs per-address balances against a
//  persisted baseline and records increases as "received" activity.
//
//  Honest limits, by design:
//  - Rows are stamped with the OBSERVATION time (no block attribution
//    is available), so history begins at install time and a payment
//    that lands while the app is closed is recorded at next launch.
//  - Increases caused by the wallet's own internal moves are
//    suppressed so they don't double-show next to their existing
//    history rows (shielded-unshield row / core top-up row). The
//    unshield match is exact (destination address + net amount); the
//    asset-lock top-up match is by recipient address hash. Anything
//    not attributable to an own operation records as received.
//

import Foundation
import SQLite
import SQLiteMigrationManager
import SwiftData
import SwiftDashSDK

extension Notification.Name {
    /// Posted after the recorder inserts at least one received-activity
    /// row; the home history reloads on it.
    static let platformAddressActivityRecorded = Notification.Name("DWPlatformAddressActivityRecorded")
}

// MARK: - Record

struct PlatformAddressActivityRecord: Identifiable {
    let id: Int64
    let walletId: Data
    let networkRaw: Int64
    let address: String
    /// Observed balance increase, in duffs.
    let amountDuffs: Int64
    let balanceAfterDuffs: Int64
    let observedAt: Date
}

// MARK: - Tables

enum PlatformAddressActivitySchema {
    /// Latest known per-address balance — the diff baseline. One row per
    /// (wallet, network, address); silently updated for decreases and
    /// own-operation increases so only genuine receives reach `activity`.
    static let baseline = Table("platform_address_baseline")
    /// Observed incoming payments (append-only).
    static let activity = Table("platform_address_activity")

    static let colId = SQLite.Expression<Int64>("id")
    static let colWalletId = SQLite.Expression<Data>("wallet_id")
    static let colNetwork = SQLite.Expression<Int64>("network")
    static let colAddress = SQLite.Expression<String>("address")
    static let colBalance = SQLite.Expression<Int64>("balance")
    static let colAmount = SQLite.Expression<Int64>("amount")
    static let colBalanceAfter = SQLite.Expression<Int64>("balance_after")
    static let colObservedAt = SQLite.Expression<Double>("observed_at")
    static let colUpdatedAt = SQLite.Expression<Double>("updated_at")
}

struct AddPlatformAddressActivityTables: Migration {
    var version: Int64 = 20260717160000

    func migrateDatabase(_ db: Connection) throws {
        typealias S = PlatformAddressActivitySchema
        try db.run(S.baseline.create(ifNotExists: true) { t in
            t.column(S.colWalletId)
            t.column(S.colNetwork)
            t.column(S.colAddress)
            t.column(S.colBalance)
            t.column(S.colUpdatedAt)
            t.unique(S.colWalletId, S.colNetwork, S.colAddress)
        })
        try db.run(S.activity.create(ifNotExists: true) { t in
            t.column(S.colId, primaryKey: .autoincrement)
            t.column(S.colWalletId)
            t.column(S.colNetwork)
            t.column(S.colAddress)
            t.column(S.colAmount)
            t.column(S.colBalanceAfter)
            t.column(S.colObservedAt)
        })
        try db.run(S.activity.createIndex(S.colWalletId, S.colNetwork, ifNotExists: true))
    }
}

// MARK: - DAO

final class PlatformAddressActivityDAO {
    static let shared = PlatformAddressActivityDAO()

    private var db: Connection { DatabaseConnection.shared.db }

    /// Baseline balances (duffs) per address for the wallet+network.
    /// Empty means "never observed" — the recorder then seeds silently.
    func baselineBalances(walletId: Data, networkRaw: Int64) -> [String: Int64] {
        typealias S = PlatformAddressActivitySchema
        var result: [String: Int64] = [:]
        let query = S.baseline
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw)
        if let rows = try? db.prepare(query) {
            for row in rows {
                result[row[S.colAddress]] = row[S.colBalance]
            }
        }
        return result
    }

    func upsertBaseline(walletId: Data, networkRaw: Int64, address: String, balanceDuffs: Int64) {
        typealias S = PlatformAddressActivitySchema
        _ = try? db.run(S.baseline.insert(
            or: .replace,
            S.colWalletId <- walletId,
            S.colNetwork <- networkRaw,
            S.colAddress <- address,
            S.colBalance <- balanceDuffs,
            S.colUpdatedAt <- Date().timeIntervalSince1970))
    }

    func insertActivity(
        walletId: Data,
        networkRaw: Int64,
        address: String,
        amountDuffs: Int64,
        balanceAfterDuffs: Int64
    ) {
        typealias S = PlatformAddressActivitySchema
        _ = try? db.run(S.activity.insert(
            S.colWalletId <- walletId,
            S.colNetwork <- networkRaw,
            S.colAddress <- address,
            S.colAmount <- amountDuffs,
            S.colBalanceAfter <- balanceAfterDuffs,
            S.colObservedAt <- Date().timeIntervalSince1970))
    }

    /// All received-activity rows for the wallet+network, newest first.
    func activities(walletId: Data, networkRaw: Int64) -> [PlatformAddressActivityRecord] {
        typealias S = PlatformAddressActivitySchema
        let query = S.activity
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw)
            .order(S.colObservedAt.desc)
        guard let rows = try? db.prepare(query) else { return [] }
        return rows.map { row in
            PlatformAddressActivityRecord(
                id: row[S.colId],
                walletId: row[S.colWalletId],
                networkRaw: row[S.colNetwork],
                address: row[S.colAddress],
                amountDuffs: row[S.colAmount],
                balanceAfterDuffs: row[S.colBalanceAfter],
                observedAt: Date(timeIntervalSince1970: row[S.colObservedAt]))
        }
    }
}

// MARK: - Recorder

/// Diffs each BLAST pass's per-address balances against the persisted
/// baseline and records unattributed increases as received activity.
/// Main-actor: called from `PlatformAddressSyncCoordinator` after its
/// snapshot refresh; reads SwiftData through the host's main context.
@MainActor
enum PlatformAddressActivityRecorder {

    /// Suppression window for matching an increase to an own operation.
    /// Wide on purpose: an own unshield's credit may only be OBSERVED
    /// many minutes after the operation (next full rescan).
    private static let ownOperationWindow: TimeInterval = 6 * 60 * 60

    static func observe(
        addresses: [DerivedPlatformAddress],
        walletId: Data,
        network: Network,
        container: ModelContainer
    ) {
        guard !addresses.isEmpty else { return }
        let networkRaw = Int64(network.rawValue)
        let dao = PlatformAddressActivityDAO.shared
        let baseline = dao.baselineBalances(walletId: walletId, networkRaw: networkRaw)

        // First observation of this wallet+network: seed the baseline
        // silently. Recording the whole standing balance as "received
        // today" would be fabricated history.
        guard !baseline.isEmpty else {
            for entry in addresses where entry.balance > 0 {
                dao.upsertBaseline(
                    walletId: walletId, networkRaw: networkRaw,
                    address: entry.address, balanceDuffs: Int64(entry.balance))
            }
            return
        }

        var increases: [(address: String, delta: Int64, after: Int64)] = []
        var netChange: Int64 = 0
        for entry in addresses {
            let after = Int64(entry.balance)
            let before = baseline[entry.address] ?? 0
            let delta = after - before
            if delta == 0 { continue }
            netChange += delta
            if delta > 0 {
                increases.append((entry.address, delta, after))
            } else {
                // Decrease: own spend (transfer/shield/withdrawal) — those
                // flows have their own history representations. Baseline
                // moves silently.
                dao.upsertBaseline(
                    walletId: walletId, networkRaw: networkRaw,
                    address: entry.address, balanceDuffs: after)
            }
        }
        guard !increases.isEmpty else { return }

        // A pass whose deltas cancel out is an intra-wallet shuffle
        // (own transfer between own addresses + change) — nothing was
        // received.
        let shuffleOnly = netChange == 0

        var recorded = false
        for increase in increases {
            let internallyExplained = shuffleOnly
                || matchesOwnUnshield(
                    address: increase.address, deltaDuffs: increase.delta,
                    walletId: walletId, network: network, container: container)
                || matchesOwnAssetLockTopUp(
                    address: increase.address, deltaDuffs: increase.delta,
                    walletId: walletId, container: container)
            if !internallyExplained {
                dao.insertActivity(
                    walletId: walletId, networkRaw: networkRaw,
                    address: increase.address, amountDuffs: increase.delta,
                    balanceAfterDuffs: increase.after)
                recorded = true
            }
            dao.upsertBaseline(
                walletId: walletId, networkRaw: networkRaw,
                address: increase.address, balanceDuffs: increase.after)
        }
        if recorded {
            NotificationCenter.default.post(name: .platformAddressActivityRecorded, object: nil)
        }
    }

    /// Exact match against an own internal unshield: same destination
    /// address, credited amount == entry.amount − fee (the recipient
    /// receives the principal net of the pool fee).
    private static func matchesOwnUnshield(
        address: String,
        deltaDuffs: Int64,
        walletId: Data,
        network: Network,
        container: ModelContainer
    ) -> Bool {
        let cutoffMs = UInt64(max(0, Date().timeIntervalSince1970 - ownOperationWindow) * 1000)
        let unshieldKind = 4
        let descriptor = FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate {
                $0.walletId == walletId && $0.kindTag == unshieldKind && $0.createdAtMs >= cutoffMs
            })
        guard let rows = try? container.mainContext.fetch(descriptor) else { return false }
        for row in rows {
            guard row.counterparty.count == 21 else { continue }
            let destination = AddressTransformer.formatAddress(
                row.counterparty, asBech32m: true, isTestnet: network != .mainnet)
            guard destination == address else { continue }
            let creditedCredits = row.amount - (row.hasFee ? row.fee : 0)
            if Int64(creditedCredits / 1000) == deltaDuffs {
                return true
            }
        }
        return false
    }

    /// Match against an own Transparent → Platform top-up: the asset
    /// lock stores the recipient's 20-byte platform address hash, so the
    /// address match is exact; the credited amount is the lock value
    /// minus a small conversion fee, so the delta only has to fit under
    /// the lock value.
    private static func matchesOwnAssetLockTopUp(
        address: String,
        deltaDuffs: Int64,
        walletId: Data,
        container: ModelContainer
    ) -> Bool {
        guard let storageBytes = AddressTransformer.parseAddress(address),
              storageBytes.count == 21 else { return false }
        let addressHash = storageBytes.dropFirst()
        let cutoff = Date().addingTimeInterval(-ownOperationWindow)
        let topUpType = 4 // AssetLockAddressTopUp
        let descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate {
                $0.walletId == walletId && $0.fundingTypeRaw == topUpType && $0.updatedAt >= cutoff
            })
        guard let rows = try? container.mainContext.fetch(descriptor) else { return false }
        return rows.contains { lock in
            lock.recipientPlatformAddressHash == Data(addressHash)
                && deltaDuffs <= lock.amountDuffs
        }
    }
}
