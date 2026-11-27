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
//  App-owned record of credits the Current identity received from someone else (ADR-0077).
//
//  Platform reports an identity's balance, not the transitions that credited it, so the app compares each network
//  read of the balance with its own baseline. A rise is one Received row for the part the wallet's own operations
//  do not explain. Own operations are recognised by the traces they leave once the credit exists: a consumed
//  identity top-up asset lock for the identity's index, a credit send to the identity in `CreditSendActivityStore`,
//  and a confirmed shielded identity top-up activity. A trace counts for the read that started after it and before
//  which the previous read started, and only once (`identity_credit_claim`): the SDK re-dates its rows on every
//  write. A send whose result was unconfirmed counts for the first rise within `pendingWindow` after it.
//
//  Limits, by design: rows carry the read time, not the arrival time; arrivals between two reads merge into one
//  row; the sender is unknown; an own spend in the same interval (a DashPay fee) lowers the rise and so the row.
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
    /// When the trace was written: the lock consumed, the send returned or failed unconfirmed, the shielded top-up
    /// confirmed.
    let date: Date
    /// A send submitted with its result unconfirmed: the credit may come later than the trace.
    let isPending: Bool

    init(key: String, amountDuffs: Int64, date: Date, isPending: Bool = false) {
        self.key = key
        self.amountDuffs = amountDuffs
        self.date = date
        self.isPending = isPending
    }
}

// MARK: - Tables

enum IdentityCreditActivitySchema {
    /// Latest balance per (wallet, network, identity), in duffs, and when the read that gave it started.
    static let baseline = Table("identity_credit_baseline")
    /// Received rows (append-only).
    static let activity = Table("identity_credit_activity")
    /// Own-operation traces that already counted for a read.
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
    private let lock = NSLock()
    private var deletions: UInt64 = 0

    init(connection: @escaping () -> Connection = { DatabaseConnection.shared.db }) {
        self.connection = connection
    }

    private var db: Connection { connection() }

    /// Changes on every deletion: a read started before a wipe or a wallet removal must not write after it.
    var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return deletions
    }

    /// The baseline in duffs; nil when the identity was never read on this wallet and network.
    func baseline(walletId: Data, networkRaw: Int64, identityId: Data) -> Int64? {
        baselineRow(walletId: walletId, networkRaw: networkRaw, identityId: identityId)?.balance
    }

    /// The baseline and when the read that gave it started; nil when the identity was never read on this wallet and
    /// network.
    func baselineRow(walletId: Data, networkRaw: Int64, identityId: Data) -> (balance: Int64, readAt: Date)? {
        typealias S = IdentityCreditActivitySchema
        let query = S.baseline.select(S.colBalance, S.colUpdatedAt)
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw && S.colIdentityId == identityId)
        guard let row = try? db.pluck(query) else { return nil }
        return (row[S.colBalance], Date(timeIntervalSince1970: row[S.colUpdatedAt]))
    }

    func isClaimed(walletId: Data, networkRaw: Int64, key: String) -> Bool {
        typealias S = IdentityCreditActivitySchema
        let query = S.claim.select(S.colKey)
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw && S.colKey == key)
        return (try? db.pluck(query)) != nil
    }

    /// Moves the baseline to `balanceDuffs` read at `date`, marks `claims` counted and, when `receivedDuffs` is set,
    /// writes its Received row, in one transaction: a failure leaves none of them, so the next read sees the same rise
    /// again.
    func record(
        walletId: Data, networkRaw: Int64, identityId: Data, balanceDuffs: Int64, claims: [String],
        receivedDuffs: Int64?, at date: Date
    ) throws {
        typealias S = IdentityCreditActivitySchema
        try db.transaction {
            try db.run(S.baseline.insert(
                or: .replace,
                S.colWalletId <- walletId,
                S.colNetwork <- networkRaw,
                S.colIdentityId <- identityId,
                S.colBalance <- balanceDuffs,
                S.colUpdatedAt <- date.timeIntervalSince1970))
            for key in claims {
                try db.run(S.claim.insert(
                    or: .ignore,
                    S.colWalletId <- walletId,
                    S.colNetwork <- networkRaw,
                    S.colKey <- key,
                    S.colUpdatedAt <- date.timeIntervalSince1970))
            }
            if let receivedDuffs {
                try db.run(S.activity.insert(
                    S.colWalletId <- walletId,
                    S.colNetwork <- networkRaw,
                    S.colIdentityId <- identityId,
                    S.colAmount <- receivedDuffs,
                    S.colBalanceAfter <- balanceDuffs,
                    S.colObservedAt <- date.timeIntervalSince1970))
            }
        }
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

    /// Removes one wallet's baselines, rows and claims in one transaction (the per-wallet Remove flow and each
    /// deletion of the full wipe).
    func delete(walletId: Data) throws {
        typealias S = IdentityCreditActivitySchema
        bumpGeneration()
        try db.transaction {
            try db.run(S.baseline.filter(S.colWalletId == walletId).delete())
            try db.run(S.activity.filter(S.colWalletId == walletId).delete())
            try db.run(S.claim.filter(S.colWalletId == walletId).delete())
        }
    }

    /// Removes every wallet's baselines, rows and claims in one transaction (the full wipe).
    func deleteAll() throws {
        typealias S = IdentityCreditActivitySchema
        bumpGeneration()
        try db.transaction {
            try db.run(S.baseline.delete())
            try db.run(S.activity.delete())
            try db.run(S.claim.delete())
        }
    }

    private func bumpGeneration() {
        lock.lock(); defer { lock.unlock() }
        deletions &+= 1
    }
}

// MARK: - Recorder

@MainActor
enum IdentityCreditActivityRecorder {
    /// How long a send whose result was unconfirmed may still explain a rise.
    static let pendingWindow: TimeInterval = 6 * 60 * 60

    enum Outcome: Equatable {
        /// First read of this identity on this wallet and network: the baseline, no row.
        case seeded
        /// No rise, or a rise the wallet's own operations explain.
        case unchanged
        /// A Received row of this many duffs.
        case received(duffs: Int64)
        /// The store could not be written; the baseline stays, so the next read compares with it again.
        case failed
        /// The wallet's history was deleted while the balance was read; nothing was written.
        case dropped
    }

    /// The traces that count for a read started at `readStart` when the previous one started at `previousStart`:
    /// a written-after-the-credit trace between the two, and a pending one within `pendingWindow`, which counts only
    /// on a rise (its credit may still be ahead).
    static func counted(
        _ credits: [IdentityOwnCredit], previousStart: Date, readStart: Date, isRise: Bool
    ) -> [IdentityOwnCredit] {
        credits.filter { credit in
            guard credit.date <= readStart else { return false }
            if credit.isPending {
                return isRise && credit.date > readStart.addingTimeInterval(-pendingWindow)
            }
            return credit.date > previousStart
        }
    }

    /// Compares one network read of the identity's balance with the baseline and records what someone else sent.
    /// `readStart` is when the read was sent; `ownCredits` returns the wallet's own credits to the identity written
    /// after a date. `generation` is the store's generation taken before the read.
    @discardableResult
    static func observe(
        balanceCredits: UInt64,
        identityId: Data,
        walletId: Data,
        networkRaw: Int64,
        readStart: Date,
        generation: UInt64,
        ownCredits: (_ after: Date) -> [IdentityOwnCredit],
        dao: IdentityCreditActivityDAO = .shared
    ) -> Outcome {
        guard dao.generation == generation else { return .dropped }
        let balance = PlatformAddressActivityUnitPolicy.duffs(fromCredits: balanceCredits)
        guard let (baseline, previousStart) = dao.baselineRow(
            walletId: walletId, networkRaw: networkRaw, identityId: identityId) else {
            return write(.seeded, balance: balance, claims: [], received: nil, identityId: identityId,
                         walletId: walletId, networkRaw: networkRaw, at: readStart, dao: dao)
        }
        // A lower balance is an own spend, which has its own row; it only moves the baseline.
        let delta = balance - baseline
        let earliest = min(previousStart, readStart.addingTimeInterval(-pendingWindow))
        let unclaimed = ownCredits(earliest).filter {
            !dao.isClaimed(walletId: walletId, networkRaw: networkRaw, key: $0.key)
        }
        let own = counted(unclaimed, previousStart: previousStart, readStart: readStart, isRise: delta > 0)
        let unexplained = delta - own.reduce(Int64(0)) { $0 + $1.amountDuffs }
        let received = delta > 0 && unexplained > 0 ? unexplained : nil
        return write(received.map { .received(duffs: $0) } ?? .unchanged, balance: balance, claims: own.map(\.key),
                     received: received, identityId: identityId, walletId: walletId, networkRaw: networkRaw,
                     at: readStart, dao: dao)
    }

    // swiftlint:disable:next function_parameter_count
    private static func write(
        _ outcome: Outcome, balance: Int64, claims: [String], received: Int64?, identityId: Data, walletId: Data,
        networkRaw: Int64, at date: Date, dao: IdentityCreditActivityDAO
    ) -> Outcome {
        do {
            try dao.record(walletId: walletId, networkRaw: networkRaw, identityId: identityId, balanceDuffs: balance,
                           claims: claims, receivedDuffs: received, at: date)
        } catch {
            return .failed
        }
        if received != nil {
            NotificationCenter.default.post(name: .identityCreditActivityRecorded, object: nil)
        }
        return outcome
    }

    /// The own operations that credited `identityId`, by traces written after `after`.
    static func ownCredits(
        identityId: Data,
        walletId: Data,
        networkRaw: Int64,
        after: Date,
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
                        && $0.identityIndexRaw == index && $0.updatedAt > after
                })
            for lock in (try? context.fetch(locks)) ?? [] {
                credits.append(.init(key: "lock:\(lock.outPointHex)", amountDuffs: lock.amountDuffs,
                                     date: lock.updatedAt))
            }
        }

        // Platform or another identity: the send the ledger recorded to this identity, including one submitted with
        // its result unconfirmed.
        let destination = identityId.toBase58String()
        for record in creditSends.records(walletId: walletId, networkRaw: networkRaw)
            where record.send.destinationKind == .identity && record.send.destination == destination
            && record.sentAt > after {
            credits.append(.init(key: "ledger:\(record.operationId)",
                                 amountDuffs: Int64(clamping: record.send.amountDuffs), date: record.sentAt,
                                 isPending: record.status == .pending))
        }

        // Shielded: the pool's identity top-up activity, once confirmed; the row is written when the top-up starts,
        // so its confirmation is when the credit existed.
        let shieldedTopUp = 9 // ShieldedActivityKind::IdentityTopUp
        let confirmed = 1
        let shielded = FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate {
                $0.walletId == walletId && $0.kindTag == shieldedTopUp && $0.identityId == identityId
                    && $0.status == confirmed && $0.lastUpdated > after
            })
        for row in (try? context.fetch(shielded)) ?? [] {
            credits.append(.init(
                key: "shielded:\(row.accountIndex):\(row.entryId.map { String(format: "%02x", $0) }.joined())",
                amountDuffs: PlatformAddressActivityUnitPolicy.duffs(fromCredits: row.amount),
                date: row.lastUpdated))
        }
        return credits
    }
}
