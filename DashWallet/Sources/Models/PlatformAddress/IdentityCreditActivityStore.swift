//
//  IdentityCreditActivityStore.swift
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
//  App-owned record of credits the Current identity received from someone else (ADR-0017).
//
//  Platform reports an identity's balance, not the transitions that credited it, so the app compares each network
//  read of the balance with its own baseline. A rise the wallet's own operations do not explain is one Received
//  row. Own operations are recognised by the traces they already leave: a consumed identity top-up asset lock for the
//  identity's index, a credit send to the identity in `CreditSendActivityStore`, and a shielded identity top-up
//  activity. Each trace explains one rise once (`identity_credit_claim`).
//
//  Limits, by design: rows carry the read time, not the arrival time; arrivals between two reads merge into one
//  row; the sender is unknown.
//

import Foundation
import SQLite
import SQLiteMigrationManager
import SwiftDashSDK
import SwiftData

extension Notification.Name {
    /// Posted on the main actor after the recorder wrote a Received row; the home history reloads on it.
    static let identityCreditActivityRecorded = Notification.Name("DWIdentityCreditActivityRecorded")
}

// MARK: - Record

struct IdentityCreditActivityRecord: Equatable {
    let id: Int64
    let walletId: Data
    let networkRaw: Int64
    let identityId: Data
    /// The rise the wallet's own operations do not explain, in duffs.
    let amountDuffs: Int64
    let balanceAfterDuffs: Int64
    let observedAt: Date
}

/// One own operation that credited the identity, found by its trace.
struct IdentityOwnCredit: Equatable {
    /// Stable id of the trace: `lock:<outpoint>`, `ledger:<operation id>` or `shielded:<account>:<entry id hex>`.
    let key: String
    let amountDuffs: Int64
    let date: Date
}

// MARK: - Tables

enum IdentityCreditActivitySchema {
    /// Latest balance per (wallet, network, identity), in duffs: the base each read is compared with.
    static let baseline = Table("identity_credit_baseline")
    /// Received rows (append-only).
    static let activity = Table("identity_credit_activity")
    /// Own-operation traces that already explained a rise.
    static let claim = Table("identity_credit_claim")

    static let colId = SQLite.Expression<Int64>("id")
    static let colWalletId = SQLite.Expression<Data>("wallet_id")
    static let colNetwork = SQLite.Expression<Int64>("network")
    static let colIdentityId = SQLite.Expression<Data>("identity_id")
    static let colBalance = SQLite.Expression<Int64>("balance")
    static let colAmount = SQLite.Expression<Int64>("amount")
    static let colBalanceAfter = SQLite.Expression<Int64>("balance_after")
    static let colObservedAt = SQLite.Expression<Double>("observed_at")
    static let colUpdatedAt = SQLite.Expression<Double>("updated_at")
    static let colKey = SQLite.Expression<String>("claim_key")
}

struct AddIdentityCreditActivityTables: Migration {
    var version: Int64 = 20261127120000

    func migrateDatabase(_ db: Connection) throws {
        typealias S = IdentityCreditActivitySchema
        try db.run(S.baseline.create(ifNotExists: true) { t in
            t.column(S.colWalletId)
            t.column(S.colNetwork)
            t.column(S.colIdentityId)
            t.column(S.colBalance)
            t.column(S.colUpdatedAt)
            t.unique(S.colWalletId, S.colNetwork, S.colIdentityId)
        })
        try db.run(S.activity.create(ifNotExists: true) { t in
            t.column(S.colId, primaryKey: .autoincrement)
            t.column(S.colWalletId)
            t.column(S.colNetwork)
            t.column(S.colIdentityId)
            t.column(S.colAmount)
            t.column(S.colBalanceAfter)
            t.column(S.colObservedAt)
        })
        try db.run(S.activity.createIndex(S.colWalletId, S.colNetwork, ifNotExists: true))
        try db.run(S.claim.create(ifNotExists: true) { t in
            t.column(S.colWalletId)
            t.column(S.colNetwork)
            t.column(S.colKey)
            t.column(S.colUpdatedAt)
            t.unique(S.colWalletId, S.colNetwork, S.colKey)
        })
    }
}

// MARK: - DAO

/// Reads and writes the three tables on the app's SQLite store, shared like `CreditSendActivityDAO`: the recorder,
/// the History projection and the wipe use one store.
final class IdentityCreditActivityDAO {
    static let shared = IdentityCreditActivityDAO()

    private let connection: () -> Connection

    init(connection: @escaping () -> Connection = { DatabaseConnection.shared.db }) {
        self.connection = connection
    }

    private var db: Connection { connection() }

    /// The baseline in duffs; nil when the identity was never read on this wallet and network.
    func baseline(walletId: Data, networkRaw: Int64, identityId: Data) -> Int64? {
        baselineRow(walletId: walletId, networkRaw: networkRaw, identityId: identityId)?.balance
    }

    /// The baseline and when it was read; nil when the identity was never read on this wallet and network.
    func baselineRow(walletId: Data, networkRaw: Int64, identityId: Data) -> (balance: Int64, readAt: Date)? {
        typealias S = IdentityCreditActivitySchema
        let query = S.baseline.select(S.colBalance, S.colUpdatedAt)
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw && S.colIdentityId == identityId)
        guard let row = try? db.pluck(query) else { return nil }
        return (row[S.colBalance], Date(timeIntervalSince1970: row[S.colUpdatedAt]))
    }

    func setBaseline(walletId: Data, networkRaw: Int64, identityId: Data, balanceDuffs: Int64, at date: Date) {
        typealias S = IdentityCreditActivitySchema
        _ = try? db.run(S.baseline.insert(
            or: .replace,
            S.colWalletId <- walletId,
            S.colNetwork <- networkRaw,
            S.colIdentityId <- identityId,
            S.colBalance <- balanceDuffs,
            S.colUpdatedAt <- date.timeIntervalSince1970))
    }

    func insertActivity(
        walletId: Data, networkRaw: Int64, identityId: Data, amountDuffs: Int64, balanceAfterDuffs: Int64, at date: Date
    ) {
        typealias S = IdentityCreditActivitySchema
        _ = try? db.run(S.activity.insert(
            S.colWalletId <- walletId,
            S.colNetwork <- networkRaw,
            S.colIdentityId <- identityId,
            S.colAmount <- amountDuffs,
            S.colBalanceAfter <- balanceAfterDuffs,
            S.colObservedAt <- date.timeIntervalSince1970))
    }

    /// The wallet's Received rows on `networkRaw`, newest first.
    func activities(walletId: Data, networkRaw: Int64) -> [IdentityCreditActivityRecord] {
        typealias S = IdentityCreditActivitySchema
        let query = S.activity
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw)
            .order(S.colObservedAt.desc, S.colId.desc)
        guard let rows = try? db.prepare(query) else { return [] }
        return rows.map { row in
            IdentityCreditActivityRecord(
                id: row[S.colId],
                walletId: row[S.colWalletId],
                networkRaw: row[S.colNetwork],
                identityId: row[S.colIdentityId],
                amountDuffs: row[S.colAmount],
                balanceAfterDuffs: row[S.colBalanceAfter],
                observedAt: Date(timeIntervalSince1970: row[S.colObservedAt]))
        }
    }

    func isClaimed(walletId: Data, networkRaw: Int64, key: String) -> Bool {
        typealias S = IdentityCreditActivitySchema
        let query = S.claim.select(S.colKey)
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw && S.colKey == key)
        return (try? db.pluck(query)) != nil
    }

    func claim(walletId: Data, networkRaw: Int64, key: String, at date: Date) {
        typealias S = IdentityCreditActivitySchema
        _ = try? db.run(S.claim.insert(
            or: .ignore,
            S.colWalletId <- walletId,
            S.colNetwork <- networkRaw,
            S.colKey <- key,
            S.colUpdatedAt <- date.timeIntervalSince1970))
    }

    /// Removes one wallet's baselines, rows and claims (the per-wallet Remove flow and each deletion of the full
    /// wipe).
    func delete(walletId: Data) {
        typealias S = IdentityCreditActivitySchema
        _ = try? db.run(S.baseline.filter(S.colWalletId == walletId).delete())
        _ = try? db.run(S.activity.filter(S.colWalletId == walletId).delete())
        _ = try? db.run(S.claim.filter(S.colWalletId == walletId).delete())
    }

    /// Removes every wallet's baselines, rows and claims (the full wipe).
    func deleteAll() {
        typealias S = IdentityCreditActivitySchema
        _ = try? db.run(S.baseline.delete())
        _ = try? db.run(S.activity.delete())
        _ = try? db.run(S.claim.delete())
    }
}

// MARK: - Recorder

@MainActor
enum IdentityCreditActivityRecorder {
    /// How long before the previous read an own operation may have started and still be credited after it: a
    /// shielded top-up is recorded when it starts, before its proof is built.
    static let ownOperationWindow: TimeInterval = 6 * 60 * 60

    enum Outcome: Equatable {
        /// First read of this identity on this wallet and network: the baseline, no row.
        case seeded
        /// No rise, or a rise the wallet's own operations explain.
        case unchanged
        /// A Received row of this many duffs.
        case received(duffs: Int64)
    }

    /// The part of `deltaDuffs` that `ownCredits` (oldest first) do not explain, and the traces that explain the
    /// rest. Traces are taken only while some of the rise is unexplained, so one that has not reached the balance
    /// yet stays for a later rise.
    static func split(deltaDuffs: Int64, ownCredits: [IdentityOwnCredit]) -> (receivedDuffs: Int64, claimed: [String]) {
        var remaining = deltaDuffs
        var claimed: [String] = []
        for credit in ownCredits.sorted(by: { $0.date < $1.date }) where remaining > 0 {
            claimed.append(credit.key)
            remaining -= credit.amountDuffs
        }
        return (max(0, remaining), claimed)
    }

    /// Compares one network read of the identity's balance with the baseline and records what someone else sent.
    /// `ownCredits` returns the own operations that credited the identity since a date: the previous read of this
    /// identity less `ownOperationWindow`, so an identity read again after a long pause (a Current identity switched
    /// back) still recognises the top-ups made meanwhile.
    @discardableResult
    static func observe(
        balanceCredits: UInt64,
        identityId: Data,
        walletId: Data,
        networkRaw: Int64,
        ownCredits: (_ since: Date) -> [IdentityOwnCredit],
        dao: IdentityCreditActivityDAO = .shared,
        now: Date = Date()
    ) -> Outcome {
        let balance = PlatformAddressActivityUnitPolicy.duffs(fromCredits: balanceCredits)
        guard let (baseline, readAt) = dao.baselineRow(
            walletId: walletId, networkRaw: networkRaw, identityId: identityId) else {
            dao.setBaseline(walletId: walletId, networkRaw: networkRaw, identityId: identityId, balanceDuffs: balance,
                            at: now)
            return .seeded
        }
        // A lower balance is an own spend, which has its own row.
        dao.setBaseline(walletId: walletId, networkRaw: networkRaw, identityId: identityId, balanceDuffs: balance,
                        at: now)
        let delta = balance - baseline
        guard delta > 0 else { return .unchanged }

        let since = readAt.addingTimeInterval(-ownOperationWindow)
        let unclaimed = ownCredits(since).filter {
            !dao.isClaimed(walletId: walletId, networkRaw: networkRaw, key: $0.key)
        }
        let (received, claimed) = split(deltaDuffs: delta, ownCredits: unclaimed)
        for key in claimed {
            dao.claim(walletId: walletId, networkRaw: networkRaw, key: key, at: now)
        }
        guard received > 0 else { return .unchanged }
        dao.insertActivity(walletId: walletId, networkRaw: networkRaw, identityId: identityId, amountDuffs: received,
                           balanceAfterDuffs: balance, at: now)
        NotificationCenter.default.post(name: .identityCreditActivityRecorded, object: nil)
        return .received(duffs: received)
    }

    /// The own operations since `since` that credited `identityId`, from the traces they leave.
    static func ownCredits(
        identityId: Data,
        walletId: Data,
        networkRaw: Int64,
        since: Date,
        container: ModelContainer,
        creditSends: CreditSendActivityDAO = .shared
    ) -> [IdentityOwnCredit] {
        var credits: [IdentityOwnCredit] = []
        let context = container.mainContext

        // Core: a consumed identity top-up lock for the identity's index (every Core route builds one). Its value
        // is above the credits granted by the processing fee.
        let topUpType = 1 // IdentityTopUp
        let consumed = 4 // Consumed
        var identityDescriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { $0.identityId == identityId })
        identityDescriptor.fetchLimit = 1
        if let identity = (try? context.fetch(identityDescriptor))?.first,
           identity.wallet?.walletId == walletId {
            let index = Int32(clamping: identity.identityIndex)
            let locks = FetchDescriptor<PersistentAssetLock>(
                predicate: #Predicate {
                    $0.walletId == walletId && $0.fundingTypeRaw == topUpType && $0.statusRaw == consumed
                        && $0.identityIndexRaw == index && $0.updatedAt >= since
                })
            for lock in (try? context.fetch(locks)) ?? [] {
                credits.append(.init(key: "lock:\(lock.outPointHex)", amountDuffs: lock.amountDuffs,
                                     date: lock.updatedAt))
            }
        }

        // Platform or another identity: the send the ledger recorded to this identity.
        let destination = identityId.toBase58String()
        for record in creditSends.records(walletId: walletId, networkRaw: networkRaw)
            where record.send.destinationKind == .identity && record.send.destination == destination
            && record.sentAt >= since {
            credits.append(.init(key: "ledger:\(record.operationId)",
                                 amountDuffs: Int64(clamping: record.send.amountDuffs), date: record.sentAt))
        }

        // Shielded: the pool's identity top-up activity, unless it failed.
        let shieldedTopUp = 9 // ShieldedActivityKind::IdentityTopUp
        let failed = 2
        let sinceMs = UInt64(max(0, since.timeIntervalSince1970) * 1000)
        let shielded = FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate {
                $0.walletId == walletId && $0.kindTag == shieldedTopUp && $0.identityId == identityId
                    && $0.status != failed && $0.createdAtMs >= sinceMs
            })
        for row in (try? context.fetch(shielded)) ?? [] {
            credits.append(.init(
                key: "shielded:\(row.accountIndex):\(row.entryId.map { String(format: "%02x", $0) }.joined())",
                amountDuffs: PlatformAddressActivityUnitPolicy.duffs(fromCredits: row.amount),
                date: Date(timeIntervalSince1970: TimeInterval(row.createdAtMs) / 1000)))
        }
        return credits
    }
}
