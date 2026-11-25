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
//  App-owned ledger of outgoing Platform-address and identity credit sends.
//
//  A send that spends Platform-address credits or identity credits leaves no
//  SDK history row: Platform-address history has no event stream, and the
//  identity spends record nothing the app reads. `PlatformAddressActivityStore`
//  observes only balance increases. So the app records each such send where it
//  makes it (`CreditSendLedger.recording`), and Home History shows the record.
//
//  One row per SDK call, keyed by an operation id made for that call. Two
//  sync-derived readings of the same send defer to the row:
//  - the balance increase the BLAST recorder observes on the wallet's own
//    Platform address claims the row (`claimIncrease`) instead of recording a
//    "Received";
//  - the Core payout of a withdrawal to the wallet's own Core address replaces
//    the row in History (`SwiftDashSDKWalletSource.creditSendItems`) and reads
//    as an Internal Transfer (`Transaction.creditWithdrawalSource`).
//

import Foundation
import SQLite
import SQLiteMigrationManager
import SwiftDashSDK

extension Notification.Name {
    /// Posted on the main actor after the ledger wrote a row; the home history reloads on it.
    static let creditSendActivityRecorded = Notification.Name("DWCreditSendActivityRecorded")
}

// MARK: - Record

/// The balance a credit send spent.
enum CreditSendSource: Int64 {
    case platform = 0
    case identity = 1
}

/// The kind of destination a credit send paid.
enum CreditSendDestinationKind: Int64 {
    case core = 0
    case platform = 1
    case identity = 2
}

enum CreditSendStatus: Int64 {
    /// The SDK call returned: the transition executed.
    case sent = 0
    /// Submitted, its result not confirmed (ADR-0040 `inFlight`).
    case pending = 1
}

/// What a send is, handed to the ledger before it runs.
struct CreditSend: Equatable {
    let source: CreditSendSource
    let destinationKind: CreditSendDestinationKind
    /// The destination in its display form: a Base58Check Core address, a bech32m Platform address or a Base58
    /// identity id.
    let destination: String
    let amountDuffs: UInt64
}

struct CreditSendRecord: Equatable {
    let id: Int64
    let operationId: String
    let walletId: Data
    let networkRaw: Int64
    let send: CreditSend
    let status: CreditSendStatus
    let sentAt: Date
}

// MARK: - Table

enum CreditSendActivitySchema {
    static let table = Table("credit_send_activity")

    static let colId = SQLite.Expression<Int64>("id")
    static let colOperationId = SQLite.Expression<String>("operation_id")
    static let colWalletId = SQLite.Expression<Data>("wallet_id")
    static let colNetwork = SQLite.Expression<Int64>("network")
    static let colSource = SQLite.Expression<Int64>("source")
    static let colDestinationKind = SQLite.Expression<Int64>("destination_kind")
    static let colDestination = SQLite.Expression<String>("destination")
    static let colAmount = SQLite.Expression<Int64>("amount")
    static let colStatus = SQLite.Expression<Int64>("status")
    /// 1 once a sync-derived balance increase on the destination was attributed to this send.
    static let colClaimed = SQLite.Expression<Int64>("claimed")
    static let colSentAt = SQLite.Expression<Double>("sent_at")
}

struct AddCreditSendActivityTable: Migration {
    var version: Int64 = 20261125120000

    func migrateDatabase(_ db: Connection) throws {
        typealias S = CreditSendActivitySchema
        try db.run(S.table.create(ifNotExists: true) { t in
            t.column(S.colId, primaryKey: .autoincrement)
            t.column(S.colOperationId, unique: true)
            t.column(S.colWalletId)
            t.column(S.colNetwork)
            t.column(S.colSource)
            t.column(S.colDestinationKind)
            t.column(S.colDestination)
            t.column(S.colAmount)
            t.column(S.colStatus)
            t.column(S.colClaimed, defaultValue: 0)
            t.column(S.colSentAt)
        })
        try db.run(S.table.createIndex(S.colWalletId, S.colNetwork, ifNotExists: true))
    }
}

// MARK: - DAO

/// Reads and writes the ledger on the app's SQLite store (the connection `PlatformAddressActivityDAO` uses). Shared
/// like that DAO: the History projection, the BLAST recorder, `Transaction` and the wipe all read one store.
final class CreditSendActivityDAO {
    static let shared = CreditSendActivityDAO()

    private let connection: () -> Connection
    private let lock = NSLock()
    /// Core destinations by wallet: `Transaction` asks once per row render, off the main thread.
    private var withdrawalDestinations: [Data: [String: CreditSendSource]] = [:]

    init(connection: @escaping () -> Connection = { DatabaseConnection.shared.db }) {
        self.connection = connection
    }

    private var db: Connection { connection() }

    /// Writes one send. False when the operation id is already recorded or the write failed.
    @discardableResult
    func insert(
        _ send: CreditSend, operationId: String, walletId: Data, networkRaw: Int64, status: CreditSendStatus,
        sentAt: Date
    ) -> Bool {
        typealias S = CreditSendActivitySchema
        let inserted: Bool
        do {
            let rowId = try db.run(S.table.insert(
                or: .ignore,
                S.colOperationId <- operationId,
                S.colWalletId <- walletId,
                S.colNetwork <- networkRaw,
                S.colSource <- send.source.rawValue,
                S.colDestinationKind <- send.destinationKind.rawValue,
                S.colDestination <- send.destination,
                S.colAmount <- Int64(clamping: send.amountDuffs),
                S.colStatus <- status.rawValue,
                S.colClaimed <- 0,
                S.colSentAt <- sentAt.timeIntervalSince1970))
            inserted = rowId > 0 && db.changes > 0
        } catch {
            inserted = false
        }
        invalidateCache()
        return inserted
    }

    /// The wallet's sends on `networkRaw`, newest first.
    func records(walletId: Data, networkRaw: Int64) -> [CreditSendRecord] {
        typealias S = CreditSendActivitySchema
        let query = S.table
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw)
            .order(S.colSentAt.desc, S.colId.desc)
        return records(for: query)
    }

    /// Attributes a balance increase the BLAST recorder observed on the wallet's own Platform `address` to the oldest
    /// send sent there since `since` that the increase fits under and no earlier increase claimed. That send now
    /// reads as executed. True when one was claimed: the increase is the send arriving, not a payment received.
    func claimIncrease(
        walletId: Data, networkRaw: Int64, address: String, deltaDuffs: Int64, since: Date
    ) -> Bool {
        typealias S = CreditSendActivitySchema
        let candidate = S.table
            .select(S.colId)
            .filter(S.colWalletId == walletId && S.colNetwork == networkRaw
                && S.colDestinationKind == CreditSendDestinationKind.platform.rawValue
                && S.colDestination == address && S.colClaimed == 0
                && S.colAmount >= deltaDuffs && S.colSentAt >= since.timeIntervalSince1970)
            .order(S.colSentAt.asc, S.colId.asc)
            .limit(1)
        guard let id = (try? db.pluck(candidate))?[S.colId] else { return false }
        let claimed = (try? db.run(S.table.filter(S.colId == id).update(
            S.colClaimed <- 1, S.colStatus <- CreditSendStatus.sent.rawValue))) ?? 0
        return claimed > 0
    }

    /// The source of a withdrawal the wallet sent to the Core `address`, nil when none did. Read from a per-wallet
    /// cache that every write refreshes.
    func withdrawalSource(toCoreAddress address: String, walletId: Data) -> CreditSendSource? {
        lock.lock(); defer { lock.unlock() }
        if let cached = withdrawalDestinations[walletId] { return cached[address] }
        typealias S = CreditSendActivitySchema
        let query = S.table
            .select(S.colDestination, S.colSource)
            .filter(S.colWalletId == walletId
                && S.colDestinationKind == CreditSendDestinationKind.core.rawValue)
        var destinations: [String: CreditSendSource] = [:]
        if let rows = try? db.prepare(query) {
            for row in rows {
                destinations[row[S.colDestination]] = CreditSendSource(rawValue: row[S.colSource])
            }
        }
        withdrawalDestinations[walletId] = destinations
        return destinations[address]
    }

    /// Removes one wallet's sends (the per-wallet Remove flow and each deletion of the full wipe).
    func delete(walletId: Data) {
        typealias S = CreditSendActivitySchema
        _ = try? db.run(S.table.filter(S.colWalletId == walletId).delete())
        invalidateCache()
    }

    /// Removes every wallet's sends (the full wipe, once wallet ids are gone).
    func deleteAll() {
        _ = try? db.run(CreditSendActivitySchema.table.delete())
        invalidateCache()
    }

    private func invalidateCache() {
        lock.lock(); defer { lock.unlock() }
        withdrawalDestinations = [:]
    }

    private func records(for query: Table) -> [CreditSendRecord] {
        typealias S = CreditSendActivitySchema
        guard let rows = try? db.prepare(query) else { return [] }
        return rows.compactMap { row in
            guard let source = CreditSendSource(rawValue: row[S.colSource]),
                  let kind = CreditSendDestinationKind(rawValue: row[S.colDestinationKind]),
                  let status = CreditSendStatus(rawValue: row[S.colStatus]) else { return nil }
            return CreditSendRecord(
                id: row[S.colId],
                operationId: row[S.colOperationId],
                walletId: row[S.colWalletId],
                networkRaw: row[S.colNetwork],
                send: CreditSend(
                    source: source, destinationKind: kind, destination: row[S.colDestination],
                    amountDuffs: UInt64(max(0, row[S.colAmount]))),
                status: status,
                sentAt: Date(timeIntervalSince1970: row[S.colSentAt]))
        }
    }
}

// MARK: - Ledger

/// Where the app records a credit send it makes. Every spend of Platform-address or identity credits runs through
/// `recording`: the Platform transfer and withdrawal (`ShieldedTransferCoordinator.performPlatformSend` /
/// `performPlatformWithdraw`), the identity top-up from Platform (`IdentityCreditsTopUp.fromPlatform`) and the
/// identity credit spends (`IdentityCreditSpend`).
@MainActor
enum CreditSendLedger {
    /// Who a send is recorded for: read before the send runs, so a wallet switch during it cannot move the row.
    struct Owner: Equatable {
        let walletId: Data
        let networkRaw: Int64
    }

    static func currentOwner() -> Owner? {
        guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
              let network = SwiftDashSDKHost.shared.runningNetwork else { return nil }
        return Owner(walletId: walletId, networkRaw: Int64(network.rawValue))
    }

    /// Runs `spend` and records `send` once: as sent when it returns, as pending when it throws a submitted-but-
    /// unconfirmed error (`isSubmittedUnconfirmed`). Any other error recorded nothing: the SDK refused before or at
    /// the submission. The error is rethrown unchanged.
    static func recording<T>(
        _ send: CreditSend,
        owner currentOwner: () -> Owner? = currentOwner,
        dao: CreditSendActivityDAO = .shared,
        now: () -> Date = Date.init,
        _ spend: () async throws -> T
    ) async throws -> T {
        let owner = currentOwner()
        do {
            let result = try await spend()
            record(send, status: .sent, owner: owner, dao: dao, at: now())
            return result
        } catch {
            if isSubmittedUnconfirmed(error) {
                record(send, status: .pending, owner: owner, dao: dao, at: now())
            }
            throw error
        }
    }

    /// The SDK's "submitted, result not confirmed" errors, after which a send must not be retried.
    nonisolated static func isSubmittedUnconfirmed(_ error: Error) -> Bool {
        switch error {
        case SDKError.stateTransitionResultUnconfirmed, PlatformWalletError.transactionBroadcastUnconfirmed,
             PlatformWalletError.shieldedSpendUnconfirmed:
            return true
        default:
            return false
        }
    }

    private static func record(
        _ send: CreditSend, status: CreditSendStatus, owner: Owner?, dao: CreditSendActivityDAO, at date: Date
    ) {
        guard let owner else {
            DWLogger.log("Credit send not recorded in History: no wallet")
            return
        }
        let written = dao.insert(
            send, operationId: UUID().uuidString, walletId: owner.walletId, networkRaw: owner.networkRaw,
            status: status, sentAt: date)
        DWLogger.log(
            "Credit send \(written ? "recorded" : "not recorded") in History: source=\(send.source) "
                + "destination=\(send.destinationKind) status=\(status)")
        if written {
            NotificationCenter.default.post(name: .creditSendActivityRecorded, object: nil)
        }
    }
}
