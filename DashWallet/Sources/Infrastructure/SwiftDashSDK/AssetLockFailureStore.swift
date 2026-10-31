//
//  AssetLockFailureStore.swift
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

import Foundation
import OSLog
import SwiftDashSDK

/// The last failure a tracked asset lock's retry produced, as the diagnostic
/// export prints it.
///
/// Ticket 32104: a lock refused by Platform with a consensus error that cannot
/// change (too many inputs) looked identical to a lock waiting on the network
/// in every log export, because the error existed only in the alert the user
/// dismissed. Recording the typed error case next to the outpoint lets
/// `summary.txt` say why a lock is stuck without re-running the retry.
struct AssetLockFailureRecord: Codable, Equatable, Sendable {
    /// The typed error case (`assetLockTooManyInputs`, `consensusRejection`,
    /// `transferFailed`…) — the searchable part.
    let errorCase: String
    /// The error's own text: the SDK detail string, with the consensus code
    /// in front when the rejection carried one.
    let detail: String
    let recordedAt: Date

    /// One log-line form: `case=<errorCase> detail=<detail>`.
    var logDescription: String {
        "case=\(errorCase) detail=\(detail)"
    }

    /// Name the error by its typed case and keep its detail string, unwrapping
    /// the coordinator's `transferFailed` envelope so a Platform rejection
    /// reaches the log as `assetLockTooManyInputs` / `consensusRejection`
    /// rather than as the envelope's name.
    ///
    /// Pure: callable from tests with any `Error`.
    static func describe(_ error: Error, at date: Date = Date()) -> AssetLockFailureRecord {
        if case ShieldedTransferCoordinator.CoordinatorError.transferFailed(let inner) = error {
            return describe(inner, at: date)
        }
        // The recovery service reports a coordinator route's failure by its
        // display text; the typed error it came from rides along.
        if case AssetLockRecoveryService.RecoveryError.failed(_, let underlying?) = error {
            return describe(underlying, at: date)
        }
        if let platformError = error as? PlatformWalletError {
            var detail = platformError.errorDescription ?? String(describing: platformError)
            if case .consensusRejection(let consensus, _) = platformError {
                detail = "consensus code=\(consensus.code) kind=\(consensus.kind) \(detail)"
            }
            if let reason = platformError.failureReason {
                detail += " reason=\(reason)"
            }
            return AssetLockFailureRecord(
                errorCase: caseName(of: platformError) ?? String(describing: type(of: platformError)),
                detail: detail,
                recordedAt: date)
        }
        let typeName = String(describing: type(of: error))
        let errorCase = caseName(of: error).map { "\(typeName).\($0)" } ?? typeName
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return AssetLockFailureRecord(errorCase: errorCase, detail: detail, recordedAt: date)
    }

    /// The enum case label without its payload. A payload-less case has no
    /// mirror child, so its description is already the bare name. `nil` for
    /// an error that is not an enum: a struct's first child is a stored
    /// property (`URLError._nsError`), and an `NSError`'s description is its
    /// whole `Error Domain=… UserInfo={…}` dump, neither of which names a case.
    private static func caseName(of error: Error) -> String? {
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else { return nil }
        if let label = mirror.children.first?.label {
            return label
        }
        return String(describing: error)
    }
}

/// App-side memory of the last retry failure per tracked asset lock, keyed by
/// outpoint (`<txid display hex>:<vout>`, the `PersistentAssetLock.outPointHex`
/// form) so the entry survives a restore that rebuilds the SDK row.
///
/// Advisory and bounded: the newest `limit` outpoints are kept, the oldest
/// recorded entries are evicted first. Losing it costs one line in a log
/// export, never money. The singleton exists for the same reason
/// `AssetLockProbeStore.shared` does — the three retry surfaces (transaction
/// details, the bulk pass, the transfer sheet) all go through
/// `AssetLockRecoveryService`, which has no injection point for per-launch
/// stores; tests construct their own instance over a private `UserDefaults`
/// suite.
final class AssetLockFailureStore {

    /// Outpoint key → last failure. Named so the decode site can spell the
    /// type without a dictionary-literal expression.
    typealias FailureMap = [String: AssetLockFailureRecord]

    static let shared = AssetLockFailureStore()

    /// Outpoints retained. Restored wallets routinely carry dozens of
    /// `RecoveredFromChain` locks, so the cap is the bulk pass's working set
    /// plus headroom, not a handful.
    static let defaultLimit = 50

    private let defaults: UserDefaults
    private let limit: Int
    private let lock = NSLock()
    private let key = "assetLockFailure.v1.byOutPoint"
    private var cache: [String: AssetLockFailureRecord]?

    init(defaults: UserDefaults = .standard, limit: Int = AssetLockFailureStore.defaultLimit) {
        self.defaults = defaults
        self.limit = max(1, limit)
    }

    /// `<txid display hex>:<vout>` — the same key `PersistentAssetLock.outPointHex`
    /// carries, so the export can join the two without a byte-order step.
    static func outPointKey(txidWire: Data, vout: UInt32) -> String {
        displayHex(txidWire: txidWire) + ":\(vout)"
    }

    /// Wire-order txid bytes as the display-order hex a block explorer shows.
    static func displayHex(txidWire: Data) -> String {
        txidWire.reversed().map { String(format: "%02x", $0) }.joined()
    }

    /// Remember `error` as the last failure of the lock at `txidWire:vout`.
    /// Thread-safe; evicts the oldest entries past the cap.
    @discardableResult
    func record(txidWire: Data, vout: UInt32, error: Error, at date: Date = Date()) -> AssetLockFailureRecord {
        let failure = AssetLockFailureRecord.describe(error, at: date)
        record(failure, forOutPointKey: Self.outPointKey(txidWire: txidWire, vout: vout))
        return failure
    }

    func record(_ record: AssetLockFailureRecord, forOutPointKey key: String) {
        lock.lock(); defer { lock.unlock() }
        var all = loaded()
        all[key] = record
        all = Self.bounded(all, limit: limit)
        cache = all
        persist(all)
    }

    /// The last recorded failure for an outpoint, if any.
    func failure(txidWire: Data, vout: UInt32) -> AssetLockFailureRecord? {
        failure(forOutPointKey: Self.outPointKey(txidWire: txidWire, vout: vout))
    }

    func failure(forOutPointKey key: String) -> AssetLockFailureRecord? {
        lock.lock(); defer { lock.unlock() }
        return loaded()[key]
    }

    /// Every stored entry, for the diagnostic export's join.
    func allFailures() -> [String: AssetLockFailureRecord] {
        lock.lock(); defer { lock.unlock() }
        return loaded()
    }

    /// Full wipe: outpoints are gone with the wallets, so the whole map goes.
    func resetForWipe() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
        cache = nil
    }

    /// Keep the `limit` most recently recorded entries. Pure, so the eviction
    /// order is testable without a `UserDefaults`.
    static func bounded(
        _ entries: [String: AssetLockFailureRecord],
        limit: Int
    ) -> [String: AssetLockFailureRecord] {
        guard entries.count > limit else { return entries }
        let kept = entries
            .sorted { lhs, rhs in
                if lhs.value.recordedAt != rhs.value.recordedAt {
                    return lhs.value.recordedAt > rhs.value.recordedAt
                }
                return lhs.key < rhs.key
            }
            .prefix(limit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private func loaded() -> [String: AssetLockFailureRecord] {
        if let cache { return cache }
        var decoded: [String: AssetLockFailureRecord] = [:]
        if let data = defaults.data(forKey: key) {
            let stored: [String: AssetLockFailureRecord]? =
                try? JSONDecoder().decode(FailureMap.self, from: data)
            decoded = stored ?? [:]
        }
        cache = decoded
        return decoded
    }

    private func persist(_ entries: [String: AssetLockFailureRecord]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

/// The one format every asset-lock retry outcome is logged in, whichever
/// surface ran the retry (transaction details, the bulk pass, the transfer
/// sheet's resume). Lines go to os_log AND to `DWLogger`, whose files are what
/// a diagnostic export carries — os_log alone never reaches support.
enum AssetLockRetryLog {
    static let lockRetryPrefix = "🔁 LOCK-RETRY ::"
    static let shieldPrefix = "🛡️ SHIELD-TX ::"

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.asset-lock-retry")

    /// `<prefix> <event> txid=<display hex>:<vout> type=<n> (<name>)
    /// statusBefore=<n> (<name>) <result>`. Pure, so the format is pinned by
    /// a test.
    static func line(
        prefix: String,
        event: String,
        txidWire: Data,
        vout: UInt32,
        fundingTypeRaw: Int,
        statusBeforeRaw: Int?,
        result: String
    ) -> String {
        let outPoint = AssetLockFailureStore.outPointKey(txidWire: txidWire, vout: vout)
        let type = "\(fundingTypeRaw) (\(DiagnosticLogExporter.fundingTypeName(fundingTypeRaw)))"
        let status = statusBeforeRaw
            .map { "\($0) (\(DiagnosticLogExporter.assetLockStatusName($0)))" } ?? "unknown"
        return "\(prefix) \(event) txid=\(outPoint) type=\(type) statusBefore=\(status) \(result)"
    }

    /// Write a finished line to both sinks.
    static func write(_ line: String, isFailure: Bool) {
        if isFailure {
            logger.error("\(line, privacy: .public)")
        } else {
            logger.info("\(line, privacy: .public)")
        }
        DWLogger.log(line)
    }

    /// Log a non-failure outcome (`result` is e.g. `outcome=completed`).
    static func logOutcome(
        _ result: String,
        prefix: String = lockRetryPrefix,
        event: String,
        txidWire: Data,
        vout: UInt32,
        fundingTypeRaw: Int,
        statusBeforeRaw: Int?
    ) {
        write(
            line(prefix: prefix, event: event, txidWire: txidWire, vout: vout,
                 fundingTypeRaw: fundingTypeRaw, statusBeforeRaw: statusBeforeRaw, result: result),
            isFailure: false)
    }

    /// Persist `error` as the lock's last failure, then log it with its typed
    /// case and detail string.
    @discardableResult
    static func logFailure(
        _ error: Error,
        prefix: String = lockRetryPrefix,
        event: String,
        txidWire: Data,
        vout: UInt32,
        fundingTypeRaw: Int,
        statusBeforeRaw: Int?,
        store: AssetLockFailureStore = .shared
    ) -> AssetLockFailureRecord {
        let record = store.record(txidWire: txidWire, vout: vout, error: error)
        write(
            line(prefix: prefix, event: event, txidWire: txidWire, vout: vout,
                 fundingTypeRaw: fundingTypeRaw, statusBeforeRaw: statusBeforeRaw,
                 result: "FAILED \(record.logDescription)"),
            isFailure: true)
        return record
    }
}
