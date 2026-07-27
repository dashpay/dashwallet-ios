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

// MARK: - Units

/// Platform-address balances arrive from the SDK in credits (1e11/DASH),
/// while the app's transaction/history presentation uses duffs (1e8/DASH).
/// Convert once at the recorder boundary so every persisted baseline and
/// activity value has the unit promised by its API.
struct PlatformAddressActivityUnitPolicy {
    static let creditsPerDuff: UInt64 = 1_000

    static func duffs(fromCredits credits: UInt64) -> Int64 {
        Int64(clamping: credits / creditsPerDuff)
    }

    static func unshieldMatches(
        creditedAmountCredits: UInt64,
        observedDeltaDuffs: Int64
    ) -> Bool {
        duffs(fromCredits: creditedAmountCredits) == observedDeltaDuffs
    }
}

enum ShieldedActivityValue {
    static let unshieldKind = 4
    static let confirmedStatus = 1
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

/// Correct the first recorder schema, which stored SDK credits in columns
/// documented and rendered as duffs, and add durable post-unshield jobs.
///
/// Dividing existing observations is lossless for wallet-originated amounts
/// (all public transfer amounts are whole duffs). A fresh install runs this
/// immediately after creating empty activity tables.
struct NormalizePlatformAddressActivityUnitsAndAddCreditReconciliations: Migration {
    var version: Int64 = 20260727140000

    func migrateDatabase(_ db: Connection) throws {
        try db.run("UPDATE platform_address_baseline SET balance = balance / 1000")
        try db.run("""
            UPDATE platform_address_activity
            SET amount = amount / 1000,
                balance_after = balance_after / 1000
            """)

        typealias S = PlatformCreditReconciliationSchema
        try db.run(S.table.create(ifNotExists: true) { t in
            t.column(S.colId, primaryKey: true)
            t.column(S.colWalletId)
            t.column(S.colNetwork)
            t.column(S.colAddress)
            t.column(S.colAddressHash)
            t.column(S.colAmountCredits)
            t.column(S.colExpectedBalanceCredits)
            t.column(S.colActivityEntryId)
            t.column(S.colCreditedHeight)
            t.column(S.colCompleted)
            t.column(S.colCreatedAt)
            t.column(S.colUpdatedAt)
        })
        try db.run(S.table.createIndex(
            S.colWalletId, S.colNetwork, S.colCompleted, ifNotExists: true))
    }
}

// MARK: - Credit reconciliation

struct PlatformCreditReconciliationRecord: Identifiable, Equatable {
    let id: String
    let walletId: Data
    let networkRaw: Int64
    let address: String
    let addressHash: Data
    let amountCredits: UInt64
    let expectedBalanceCredits: UInt64
    let activityEntryId: Data?
    let creditedHeight: UInt64?
    let isCompleted: Bool
    let createdAt: Date
}

enum PlatformCreditReconciliationSchema {
    static let table = Table("platform_credit_reconciliation")

    static let colId = SQLite.Expression<String>("id")
    static let colWalletId = SQLite.Expression<Data>("wallet_id")
    static let colNetwork = SQLite.Expression<Int64>("network")
    static let colAddress = SQLite.Expression<String>("address")
    static let colAddressHash = SQLite.Expression<Data>("address_hash")
    static let colAmountCredits = SQLite.Expression<Int64>("amount_credits")
    static let colExpectedBalanceCredits = SQLite.Expression<Int64>("expected_balance_credits")
    static let colActivityEntryId = SQLite.Expression<Data?>("activity_entry_id")
    static let colCreditedHeight = SQLite.Expression<Int64?>("credited_height")
    static let colCompleted = SQLite.Expression<Bool>("completed")
    static let colCreatedAt = SQLite.Expression<Double>("created_at")
    static let colUpdatedAt = SQLite.Expression<Double>("updated_at")
}

final class PlatformCreditReconciliationDAO {
    static let shared = PlatformCreditReconciliationDAO()

    private var db: Connection { DatabaseConnection.shared.db }

    func create(
        walletId: Data,
        networkRaw: Int64,
        address: String,
        addressHash: Data,
        amountCredits: UInt64,
        expectedBalanceCredits: UInt64,
        activityEntryId: Data? = nil,
        creditedHeight: UInt64? = nil,
        createdAt: Date = Date()
    ) -> PlatformCreditReconciliationRecord {
        typealias S = PlatformCreditReconciliationSchema
        let id = UUID().uuidString
        let now = Date()
        _ = try? db.run(S.table.insert(
            S.colId <- id,
            S.colWalletId <- walletId,
            S.colNetwork <- networkRaw,
            S.colAddress <- address,
            S.colAddressHash <- addressHash,
            S.colAmountCredits <- Int64(clamping: amountCredits),
            S.colExpectedBalanceCredits <- Int64(clamping: expectedBalanceCredits),
            S.colActivityEntryId <- activityEntryId,
            S.colCreditedHeight <- creditedHeight.map { Int64(clamping: $0) },
            S.colCompleted <- false,
            S.colCreatedAt <- createdAt.timeIntervalSince1970,
            S.colUpdatedAt <- now.timeIntervalSince1970))
        return PlatformCreditReconciliationRecord(
            id: id,
            walletId: walletId,
            networkRaw: networkRaw,
            address: address,
            addressHash: addressHash,
            amountCredits: amountCredits,
            expectedBalanceCredits: expectedBalanceCredits,
            activityEntryId: activityEntryId,
            creditedHeight: creditedHeight,
            isCompleted: false,
            createdAt: createdAt)
    }

    func records(walletId: Data, networkRaw: Int64) -> [PlatformCreditReconciliationRecord] {
        typealias S = PlatformCreditReconciliationSchema
        let query = S.table
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw)
            .order(S.colCreatedAt.asc)
        guard let rows = try? db.prepare(query) else { return [] }
        return rows.map { row in
            PlatformCreditReconciliationRecord(
                id: row[S.colId],
                walletId: row[S.colWalletId],
                networkRaw: row[S.colNetwork],
                address: row[S.colAddress],
                addressHash: row[S.colAddressHash],
                amountCredits: UInt64(max(0, row[S.colAmountCredits])),
                expectedBalanceCredits: UInt64(max(0, row[S.colExpectedBalanceCredits])),
                activityEntryId: row[S.colActivityEntryId],
                creditedHeight: row[S.colCreditedHeight].map { UInt64(max(0, $0)) },
                isCompleted: row[S.colCompleted],
                createdAt: Date(timeIntervalSince1970: row[S.colCreatedAt]))
        }
    }

    func attachActivity(id: String, entryId: Data, creditedHeight: UInt64) {
        typealias S = PlatformCreditReconciliationSchema
        let row = S.table.filter(S.colId == id)
        _ = try? db.run(row.update(
            S.colActivityEntryId <- entryId,
            S.colCreditedHeight <- Int64(clamping: creditedHeight),
            S.colUpdatedAt <- Date().timeIntervalSince1970))
    }

    func markCompleted(id: String) {
        typealias S = PlatformCreditReconciliationSchema
        let row = S.table.filter(S.colId == id)
        _ = try? db.run(row.update(
            S.colCompleted <- true,
            S.colUpdatedAt <- Date().timeIntervalSince1970))
    }

    func markAllPending(walletId: Data, networkRaw: Int64) {
        typealias S = PlatformCreditReconciliationSchema
        let rows = S.table.filter(
            S.colWalletId == walletId && S.colNetwork == networkRaw)
        _ = try? db.run(rows.update(
            S.colCompleted <- false,
            S.colUpdatedAt <- Date().timeIntervalSince1970))
    }

    func delete(id: String) {
        typealias S = PlatformCreditReconciliationSchema
        _ = try? db.run(S.table.filter(S.colId == id).delete())
    }

    func deleteAll(walletId: Data, networkRaw: Int64) {
        typealias S = PlatformCreditReconciliationSchema
        let rows = S.table.filter(
            S.colWalletId == walletId && S.colNetwork == networkRaw)
        _ = try? db.run(rows.delete())
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

    func deleteActivity(id: Int64) {
        typealias S = PlatformAddressActivitySchema
        _ = try? db.run(S.activity.filter(S.colId == id).delete())
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
    static let ownOperationWindow: TimeInterval = 6 * 60 * 60

    static func observe(
        addresses: [DerivedPlatformAddress],
        walletId: Data,
        network: Network,
        container: ModelContainer
    ) {
        guard !addresses.isEmpty else { return }
        let networkRaw = Int64(network.rawValue)
        let dao = PlatformAddressActivityDAO.shared
        cleanupMisclassifiedOwnOperations(
            dao: dao,
            walletId: walletId,
            networkRaw: networkRaw,
            network: network,
            container: container)
        let baseline = dao.baselineBalances(walletId: walletId, networkRaw: networkRaw)

        // First observation of this wallet+network: seed the baseline
        // silently. Recording the whole standing balance as "received
        // today" would be fabricated history.
        guard !baseline.isEmpty else {
            for entry in addresses where entry.balance > 0 {
                dao.upsertBaseline(
                    walletId: walletId, networkRaw: networkRaw,
                    address: entry.address,
                    balanceDuffs: PlatformAddressActivityUnitPolicy.duffs(
                        fromCredits: entry.balance))
            }
            return
        }

        var increases: [(address: String, delta: Int64, after: Int64)] = []
        var netChange: Int64 = 0
        for entry in addresses {
            let after = PlatformAddressActivityUnitPolicy.duffs(fromCredits: entry.balance)
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
    /// address and credited principal. The unshield builder reserves the fee
    /// in addition to `amount`; the Platform address receives `amount`
    /// exactly, while the shielded pool is debited by amount + fee.
    private static func matchesOwnUnshield(
        address: String,
        deltaDuffs: Int64,
        walletId: Data,
        network: Network,
        container: ModelContainer,
        observedAt: Date = Date()
    ) -> Bool {
        let cutoffMs = UInt64(max(0, observedAt.timeIntervalSince1970 - ownOperationWindow) * 1000)
        let upperBoundMs = UInt64(
            max(0, observedAt.timeIntervalSince1970 + ownOperationWindow) * 1000)
        let unshieldKind = ShieldedActivityValue.unshieldKind
        let descriptor = FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate {
                $0.walletId == walletId
                    && $0.kindTag == unshieldKind
                    && $0.createdAtMs >= cutoffMs
                    && $0.createdAtMs <= upperBoundMs
            })
        guard let rows = try? container.mainContext.fetch(descriptor) else { return false }
        for row in rows {
            guard row.counterparty.count == 21 else { continue }
            let destination = AddressTransformer.formatAddress(
                row.counterparty, asBech32m: true, isTestnet: network != .mainnet)
            guard destination == address else { continue }
            if PlatformAddressActivityUnitPolicy.unshieldMatches(
                creditedAmountCredits: row.amount,
                observedDeltaDuffs: deltaDuffs)
            {
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
        container: ModelContainer,
        observedAt: Date = Date()
    ) -> Bool {
        guard let storageBytes = AddressTransformer.parseAddress(address),
              storageBytes.count == 21 else { return false }
        let addressHash = storageBytes.dropFirst()
        let cutoff = observedAt.addingTimeInterval(-ownOperationWindow)
        let upperBound = observedAt.addingTimeInterval(ownOperationWindow)
        let topUpType = 4 // AssetLockAddressTopUp
        let descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate {
                $0.walletId == walletId
                    && $0.fundingTypeRaw == topUpType
                    && $0.updatedAt >= cutoff
                    && $0.updatedAt <= upperBound
            })
        guard let rows = try? container.mainContext.fetch(descriptor) else { return false }
        return rows.contains { lock in
            lock.recipientPlatformAddressHash == Data(addressHash)
                && deltaDuffs <= lock.amountDuffs
        }
    }

    /// Versions before the credits→duffs fix could append an own unshield or
    /// Core top-up as a generic "Received" row. Remove only rows that match an
    /// app-owned operation by destination, converted amount, and observation
    /// window; genuine external receives remain untouched.
    private static func cleanupMisclassifiedOwnOperations(
        dao: PlatformAddressActivityDAO,
        walletId: Data,
        networkRaw: Int64,
        network: Network,
        container: ModelContainer
    ) {
        var removedAny = false
        for record in dao.activities(walletId: walletId, networkRaw: networkRaw) {
            let isOwnOperation = matchesOwnUnshield(
                address: record.address,
                deltaDuffs: record.amountDuffs,
                walletId: walletId,
                network: network,
                container: container,
                observedAt: record.observedAt)
                || matchesOwnAssetLockTopUp(
                    address: record.address,
                    deltaDuffs: record.amountDuffs,
                    walletId: walletId,
                    container: container,
                    observedAt: record.observedAt)
            guard isOwnOperation else { continue }
            dao.deleteActivity(id: record.id)
            removedAny = true
        }
        if removedAny {
            NotificationCenter.default.post(name: .platformAddressActivityRecorded, object: nil)
        }
    }
}
