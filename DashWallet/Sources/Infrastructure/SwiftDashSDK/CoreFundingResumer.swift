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

import Foundation
import SwiftDashSDK
import SwiftData

/// The recipient of a Core → someone else's Platform payment, kept under the asset lock's outpoint from the moment
/// the lock exists, so a recovery pass can pay the same recipient the same amount.
struct ExternalFundingRecipientRecord: Codable, Equatable, Sendable {
    let addressType: UInt8
    let hash: Data
    let recipientAmountDuffs: UInt64

    /// A handler for `onAssetLockBuilt` that saves this record under the lock's outpoint and then runs `then`. It only
    /// writes to the store, as the SDK requires of the handler.
    func builtHandler(
        store: ExternalFundingRecipientStoring,
        then: AssetLockBuiltHandler? = nil
    ) -> AssetLockBuiltHandler {
        { outPoint in
            store.save(self, forOutPointHex: outPoint.outPointHex)
            then?(outPoint)
        }
    }
}

/// What recovery knows of a Core → Platform lock's recipient: the external record of a payment to someone else, or
/// the mark of a top-up of the wallet's own addresses. The SDK row carries neither while the lock is in flight.
protocol ExternalFundingRecipientStoring: Sendable {
    func save(_ record: ExternalFundingRecipientRecord, forOutPointHex outPointHex: String)
    /// `nil` when nothing was saved for the outpoint. Throws `UnreadableFundingRecipientRecord` when something was
    /// saved but cannot be decoded.
    func record(forOutPointHex outPointHex: String) throws -> ExternalFundingRecipientRecord?
    func markOwn(outPointHex: String)
    func isMarkedOwn(outPointHex: String) -> Bool
    /// Forgets the record and the own mark of a lock that is finished.
    func removeRecipient(outPointHex: String)
    /// Every outpoint with a record or an own mark.
    func entryOutPointHexes() -> Set<String>
    /// When this build first launched, before the wallet runtime started. Own marks began with this build, and an
    /// external Core → Platform payment did not exist before it, so a lock row created before this moment is own,
    /// unless the SDK rebuilt it from the chain. `nil` when it was never recorded.
    var ownMarkingStart: Date? { get }
}

extension ExternalFundingRecipientStoring {
    /// A handler for `onAssetLockBuilt` of a top-up of the wallet's own addresses that marks the lock own and then
    /// runs `then`. It only writes to the store, as the SDK requires of the handler.
    func ownBuiltHandler(then: AssetLockBuiltHandler? = nil) -> AssetLockBuiltHandler {
        { outPoint in
            markOwn(outPointHex: outPoint.outPointHex)
            then?(outPoint)
        }
    }
}

/// Something was saved as the recipient record of a lock, but it cannot be decoded.
struct UnreadableFundingRecipientRecord: Error {}

/// Records survive a restart as JSON in `UserDefaults`, own marks as a Boolean.
final class UserDefaultsFundingRecipientStore: ExternalFundingRecipientStoring, @unchecked Sendable {
    private static let keyPrefix = "externalFundingRecipient."
    private static let ownKeyPrefix = "ownFundingLock."
    private static let ownMarkingStartKey = "ownFundingLockMarkingStart"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ record: ExternalFundingRecipientRecord, forOutPointHex outPointHex: String) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.keyPrefix + outPointHex)
    }

    func record(forOutPointHex outPointHex: String) throws -> ExternalFundingRecipientRecord? {
        guard let stored = defaults.object(forKey: Self.keyPrefix + outPointHex) else { return nil }
        guard let data = stored as? Data,
              let record = try? JSONDecoder().decode(ExternalFundingRecipientRecord.self, from: data)
        else { throw UnreadableFundingRecipientRecord() }
        return record
    }

    func markOwn(outPointHex: String) {
        defaults.set(true, forKey: Self.ownKeyPrefix + outPointHex)
    }

    func isMarkedOwn(outPointHex: String) -> Bool {
        defaults.bool(forKey: Self.ownKeyPrefix + outPointHex)
    }

    var ownMarkingStart: Date? {
        defaults.object(forKey: Self.ownMarkingStartKey) as? Date
    }

    func removeRecipient(outPointHex: String) {
        defaults.removeObject(forKey: Self.keyPrefix + outPointHex)
        defaults.removeObject(forKey: Self.ownKeyPrefix + outPointHex)
    }

    func entryOutPointHexes() -> Set<String> {
        Set(defaults.dictionaryRepresentation().keys.compactMap { key in
            [Self.keyPrefix, Self.ownKeyPrefix].first(where: key.hasPrefix).map { String(key.dropFirst($0.count)) }
        })
    }

    /// The full wipe: every record and own mark goes. `ownMarkingStart` stays, since it describes this build, not the
    /// wallet.
    func resetForWipe() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.keyPrefix) || key.hasPrefix(Self.ownKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Records `ownMarkingStart` unless it is already recorded. Runs at launch, before the wallet runtime starts and
    /// before any lock row of this launch can exist.
    static func recordOwnMarkingStartIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard defaults.object(forKey: ownMarkingStartKey) == nil else { return }
        defaults.set(now, forKey: ownMarkingStartKey)
    }
}

/// The launch hook of `UserDefaultsFundingRecipientStore.recordOwnMarkingStartIfNeeded` for `AppDelegate`.
@objc(DWOwnFundingLockMarks)
final class OwnFundingLockMarks: NSObject {
    @objc
    static func recordStartIfNeeded() {
        UserDefaultsFundingRecipientStore.recordOwnMarkingStartIfNeeded()
    }
}

/// The two SDK calls that build and fund a Core → Platform lock.
protocol AssetLockFundingEdge {
    func fundOwn(
        lockValueDuffs: UInt64, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
        onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance]

    func fundExternal(
        lockValueDuffs: UInt64, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
        onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance]
}

/// Funds Platform from Core through a new asset lock and records, the moment the lock is built, who it pays: an own
/// mark for a top-up of the wallet's own addresses, the recipient record for a payment to someone else. Recovery reads
/// that through `CoreFundingRecipientCheck`.
struct CoreFunder {
    let edge: AssetLockFundingEdge
    let recipientStore: ExternalFundingRecipientStoring

    func fundOwn(
        lockValueDuffs: UInt64, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
        onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
        try await edge.fundOwn(
            lockValueDuffs: lockValueDuffs, platformAccountIndex: platformAccountIndex, recipients: recipients,
            onAssetLockBuilt: recipientStore.ownBuiltHandler(then: onAssetLockBuilt))
    }

    func fundExternal(
        record: ExternalFundingRecipientRecord,
        lockValueDuffs: UInt64, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
        onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
        try await edge.fundExternal(
            lockValueDuffs: lockValueDuffs, platformAccountIndex: platformAccountIndex, recipients: recipients,
            onAssetLockBuilt: record.builtHandler(store: recipientStore, then: onAssetLockBuilt))
    }
}

/// Removes the record and own mark of every lock whose row is consumed. Recovery never offers a consumed lock
/// (`AssetLockRecoveryService.statusAllowsRetry`), so nothing reads its entry again. A lock whose row still reads as
/// unfinished keeps its entry: a repeated resume of it must reach the SDK, which reports it already consumed. An entry
/// without a row is kept too, since the built handler writes it before the SDK persists the row.
struct CoreFundingRecipientSweep {
    let recipientStore: ExternalFundingRecipientStoring
    let container: ModelContainer

    @MainActor
    func removeFinished() throws {
        let consumed = AssetLockRecoveryService.consumedStatus
        for outPointHex in recipientStore.entryOutPointHexes() {
            var descriptor = FetchDescriptor<PersistentAssetLock>(
                predicate: #Predicate { $0.outPointHex == outPointHex && $0.statusRaw == consumed })
            descriptor.fetchLimit = 1
            if try container.mainContext.fetchCount(descriptor) > 0 {
                recipientStore.removeRecipient(outPointHex: outPointHex)
            }
        }
    }
}

/// The two SDK resume calls the recovery chooses between.
protocol AssetLockResumeEdge {
    func resumeOwn(
        outPointTxid: Data, outPointVout: UInt32, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance]

    func resumeExternal(
        outPointTxid: Data, outPointVout: UInt32, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance]
}

/// `ManagedPlatformAddressWallet` with the signer its funding and resume calls take. Funding spends from Core
/// account 0.
struct SignedPlatformAddressWallet: AssetLockResumeEdge, AssetLockFundingEdge {
    let wallet: ManagedPlatformAddressWallet
    let signer: KeychainSigner

    func fundOwn(
        lockValueDuffs: UInt64, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
        onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
        try await wallet.fundFromAssetLock(
            amountDuffs: lockValueDuffs, fundingAccountIndex: 0, platformAccountIndex: platformAccountIndex,
            recipients: recipients, signer: signer, onAssetLockBuilt: onAssetLockBuilt)
    }

    func fundExternal(
        lockValueDuffs: UInt64, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
        onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
        try await wallet.fundFromAssetLockExternal(
            amountDuffs: lockValueDuffs, fundingAccountIndex: 0, platformAccountIndex: platformAccountIndex,
            recipients: recipients, signer: signer, onAssetLockBuilt: onAssetLockBuilt)
    }

    func resumeOwn(
        outPointTxid: Data, outPointVout: UInt32, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
        try await wallet.resumeFundFromAssetLock(
            outPointTxid: outPointTxid, outPointVout: outPointVout, platformAccountIndex: platformAccountIndex,
            recipients: recipients, signer: signer)
    }

    func resumeExternal(
        outPointTxid: Data, outPointVout: UInt32, platformAccountIndex: UInt32,
        recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
        try await wallet.resumeFundFromAssetLockExternal(
            outPointTxid: outPointTxid, outPointVout: outPointVout, platformAccountIndex: platformAccountIndex,
            recipients: recipients, signer: signer)
    }
}

/// Who a Core → Platform lock pays when it is resumed: the recorded recipient when the lock was an external payment,
/// the wallet's own addresses when the lock is proven own — marked own when it was built, `recipientIsExternal ==
/// false` on its row, or a row created before `ownMarkingStart` that the SDK did not rebuild from the chain. Any other
/// lock is refused, never paid to the sender: an external lock whose record is missing looks exactly like it. A lock
/// with an undecodable record is refused whatever proves it own. Reads only the store and the lock's row, so a resume
/// asks it before the PIN.
struct CoreFundingRecipientCheck {
    enum Recipient: Equatable {
        case external(ExternalFundingRecipientRecord)
        case own
    }

    let recipientStore: ExternalFundingRecipientStoring
    let container: ModelContainer
    let log: (String) -> Void

    @MainActor
    func recipient(outPointTxid: Data, outPointVout: UInt32) throws -> Recipient {
        let outPointHex = Self.outPointHex(txid: outPointTxid, vout: outPointVout)
        let record: ExternalFundingRecipientRecord?
        do {
            record = try recipientStore.record(forOutPointHex: outPointHex)
        } catch {
            log("Asset lock recipient record is unreadable; not resumed")
            throw CoreFundingResumer.ResumeError.recipientUnknown
        }
        let row = try lockRow(outPointHex: outPointHex)
        let rowMark = row?.recipientIsExternal
        if record != nil || rowMark == true {
            guard let record else {
                log("External asset lock has no recipient record; not resumed")
                throw CoreFundingResumer.ResumeError.externalRecipientRecordMissing
            }
            return .external(record)
        }
        guard rowMark == false || recipientStore.isMarkedOwn(outPointHex: outPointHex)
            || predatesOwnMarks(row) else {
            log("Asset lock has neither a recipient record nor an own mark; not resumed")
            throw CoreFundingResumer.ResumeError.recipientUnknown
        }
        return .own
    }

    static func outPointHex(txid: Data, vout: UInt32) -> String {
        var raw = txid
        var le = vout.littleEndian
        withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) }
        return PersistentAssetLock.encodeOutPoint(rawBytes: raw)
    }

    /// A row the SDK rebuilt from the chain after a restore proves nothing by its age: its `createdAt` is when it was
    /// rebuilt, and a restore on a build before `ownMarkingStart` may have rebuilt someone else's payment.
    private func predatesOwnMarks(_ row: PersistentAssetLock?) -> Bool {
        guard let row, let start = recipientStore.ownMarkingStart,
              row.statusRaw != AssetLockRecoveryService.recoveredFromChainStatus else { return false }
        return row.createdAt < start
    }

    @MainActor
    private func lockRow(outPointHex: String) throws -> PersistentAssetLock? {
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { $0.outPointHex == outPointHex })
        descriptor.fetchLimit = 1
        return try container.mainContext.fetch(descriptor).first
    }
}

/// Resumes an asset lock that funded Platform to the recipient `CoreFundingRecipientCheck` names.
struct CoreFundingResumer {
    enum ResumeError: LocalizedError, Equatable {
        case externalRecipientRecordMissing
        /// Neither an external record nor a proof that the lock is own.
        case recipientUnknown
        case invalidAmount

        static var cannotFinishMessage: String {
            NSLocalizedString(
                "This transfer can't be finished automatically because the wallet can't confirm who it should pay. Nothing was sent. Your funds remain locked and safe.",
                comment: "Recovery refuses a Core to Platform transfer whose recipient is unknown")
        }

        var errorDescription: String? {
            switch self {
            case .externalRecipientRecordMissing, .recipientUnknown: Self.cannotFinishMessage
            case .invalidAmount: nil
            }
        }
    }

    struct OwnAddresses {
        let recipientHash: Data
        let remainderHash: Data
        let accountIndex: UInt32
    }

    let edge: AssetLockResumeEdge
    let recipientStore: ExternalFundingRecipientStoring
    let container: ModelContainer
    let ownAddresses: OwnAddresses
    let log: (String) -> Void

    @MainActor
    func resume(
        outPointTxid: Data,
        outPointVout: UInt32,
        ownRecipientAmountDuffs: UInt64
    ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
        let check = CoreFundingRecipientCheck(recipientStore: recipientStore, container: container, log: log)
        switch try check.recipient(outPointTxid: outPointTxid, outPointVout: outPointVout) {
        case .external(let record):
            return try await edge.resumeExternal(
                outPointTxid: outPointTxid, outPointVout: outPointVout, platformAccountIndex: ownAddresses.accountIndex,
                recipients: [
                    .init(
                        addressType: record.addressType, hash: record.hash,
                        credits: try credits(record.recipientAmountDuffs)),
                    remainder
                ])
        case .own:
            return try await edge.resumeOwn(
                outPointTxid: outPointTxid, outPointVout: outPointVout, platformAccountIndex: ownAddresses.accountIndex,
                recipients: [
                    .init(
                        addressType: 0, hash: ownAddresses.recipientHash,
                        credits: try credits(ownRecipientAmountDuffs)),
                    remainder
                ])
        }
    }

    private var remainder: ManagedPlatformAddressWallet.FundFromAssetLockRecipient {
        .init(addressType: 0, hash: ownAddresses.remainderHash, credits: nil)
    }

    private func credits(_ duffs: UInt64) throws -> UInt64 {
        let (value, overflow) = duffs.multipliedReportingOverflow(by: 1000)
        guard !overflow else { throw ResumeError.invalidAmount }
        return value
    }
}
