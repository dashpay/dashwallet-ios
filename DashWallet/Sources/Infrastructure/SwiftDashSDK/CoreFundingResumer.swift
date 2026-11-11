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

protocol ExternalFundingRecipientStoring: Sendable {
    func save(_ record: ExternalFundingRecipientRecord, forOutPointHex outPointHex: String)
    /// `nil` when nothing was saved for the outpoint or the saved entry cannot be decoded.
    func record(forOutPointHex outPointHex: String) -> ExternalFundingRecipientRecord?
}

/// Records survive a restart as JSON in `UserDefaults`.
final class UserDefaultsFundingRecipientStore: ExternalFundingRecipientStoring, @unchecked Sendable {
    private static let keyPrefix = "externalFundingRecipient."
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ record: ExternalFundingRecipientRecord, forOutPointHex outPointHex: String) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.keyPrefix + outPointHex)
    }

    func record(forOutPointHex outPointHex: String) -> ExternalFundingRecipientRecord? {
        guard let data = defaults.data(forKey: Self.keyPrefix + outPointHex) else { return nil }
        return try? JSONDecoder().decode(ExternalFundingRecipientRecord.self, from: data)
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

/// `ManagedPlatformAddressWallet` with the signer its resume calls take.
struct SignedPlatformAddressWallet: AssetLockResumeEdge {
    let wallet: ManagedPlatformAddressWallet
    let signer: KeychainSigner

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

/// Resumes an asset lock that funded Platform: to the recorded recipient when the lock was an external payment, to
/// the wallet's own addresses otherwise. An external lock without its record is refused, never paid to the sender.
struct CoreFundingResumer {
    enum ResumeError: Error, Equatable {
        case externalRecipientRecordMissing
        case invalidAmount
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
        var raw = outPointTxid
        var le = outPointVout.littleEndian
        withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) }
        let outPointHex = PersistentAssetLock.encodeOutPoint(rawBytes: raw)

        let record = recipientStore.record(forOutPointHex: outPointHex)
        let isExternal = try record != nil || markedExternal(outPointHex: outPointHex)
        if isExternal {
            guard let record else {
                log("External asset lock has no recipient record; not resumed")
                throw ResumeError.externalRecipientRecordMissing
            }
            return try await edge.resumeExternal(
                outPointTxid: outPointTxid, outPointVout: outPointVout, platformAccountIndex: ownAddresses.accountIndex,
                recipients: [
                    .init(
                        addressType: record.addressType, hash: record.hash,
                        credits: try credits(record.recipientAmountDuffs)),
                    remainder
                ])
        }
        return try await edge.resumeOwn(
            outPointTxid: outPointTxid, outPointVout: outPointVout, platformAccountIndex: ownAddresses.accountIndex,
            recipients: [
                .init(addressType: 0, hash: ownAddresses.recipientHash, credits: try credits(ownRecipientAmountDuffs)),
                remainder
            ])
    }

    private var remainder: ManagedPlatformAddressWallet.FundFromAssetLockRecipient {
        .init(addressType: 0, hash: ownAddresses.remainderHash, credits: nil)
    }

    private func credits(_ duffs: UInt64) throws -> UInt64 {
        let (value, overflow) = duffs.multipliedReportingOverflow(by: 1000)
        guard !overflow else { throw ResumeError.invalidAmount }
        return value
    }

    @MainActor
    private func markedExternal(outPointHex: String) throws -> Bool {
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { $0.outPointHex == outPointHex })
        descriptor.fetchLimit = 1
        return try container.mainContext.fetch(descriptor).first?.recipientIsExternal == true
    }
}
