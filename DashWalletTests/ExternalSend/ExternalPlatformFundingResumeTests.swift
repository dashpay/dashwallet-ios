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

@testable import dashpay
import SwiftDashSDK
import SwiftData
import XCTest

/// AC-19: a Core → someone else's Platform payment interrupted after the asset lock left finishes to the recorded
/// recipient, never to the sender's own address. Only the SDK edge (`AssetLockResumeEdge`) and the recipient record
/// store are scripted; the lock rows live in a real in-memory SwiftData container.
@MainActor
final class ExternalPlatformFundingResumeTests: XCTestCase {
    private let txid = Data((0..<32).map { UInt8($0) })
    private let vout: UInt32 = 1
    private let externalHash = Data(repeating: 0xE1, count: 20)
    private let ownRecipientHash = Data(repeating: 0xA1, count: 20)
    private let ownRemainderHash = Data(repeating: 0xA2, count: 20)
    private let accountIndex: UInt32 = 0
    private let externalAmountDuffs: UInt64 = 123_456_789
    /// What today's recovery derives from the lock value minus the reserve.
    private let derivedOwnAmountDuffs: UInt64 = 55_555_555

    private var outPointHex: String {
        var raw = txid
        var le = vout.littleEndian
        withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) }
        return PersistentAssetLock.encodeOutPoint(rawBytes: raw)
    }

    // MARK: Scripted edges

    private final class FakeEdge: AssetLockResumeEdge, @unchecked Sendable {
        enum Call: Equatable {
            case own(Data, UInt32, UInt32, [Recipient])
            case external(Data, UInt32, UInt32, [Recipient])
        }
        struct Recipient: Equatable {
            let addressType: UInt8
            let hash: Data
            let credits: UInt64?
        }

        private(set) var calls: [Call] = []
        var failure: Error?

        private static func map(
            _ recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]
        ) -> [Recipient] {
            recipients.map { Recipient(addressType: $0.addressType, hash: $0.hash, credits: $0.credits) }
        }

        func resumeOwn(
            outPointTxid: Data, outPointVout: UInt32, platformAccountIndex: UInt32,
            recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]
        ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
            calls.append(.own(outPointTxid, outPointVout, platformAccountIndex, Self.map(recipients)))
            if let failure { throw failure }
            return []
        }

        func resumeExternal(
            outPointTxid: Data, outPointVout: UInt32, platformAccountIndex: UInt32,
            recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient]
        ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
            calls.append(.external(outPointTxid, outPointVout, platformAccountIndex, Self.map(recipients)))
            if let failure { throw failure }
            return []
        }
    }

    private final class InMemoryRecipientStore: ExternalFundingRecipientStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var records: [String: ExternalFundingRecipientRecord] = [:]

        func save(_ record: ExternalFundingRecipientRecord, forOutPointHex outPointHex: String) {
            lock.lock()
            defer { lock.unlock() }
            records[outPointHex] = record
        }

        func record(forOutPointHex outPointHex: String) -> ExternalFundingRecipientRecord? {
            lock.lock()
            defer { lock.unlock() }
            return records[outPointHex]
        }
    }

    private var edge = FakeEdge()
    private var store = InMemoryRecipientStore()
    private var logged: [String] = []
    private var storedContainer: ModelContainer?

    override func setUpWithError() throws {
        try super.setUpWithError()
        edge = FakeEdge()
        store = InMemoryRecipientStore()
        logged = []
        storedContainer = try DashModelContainer.inMemoryWithoutCloudKit()
    }

    private func container() throws -> ModelContainer {
        try XCTUnwrap(storedContainer)
    }

    private func insertLock(isExternal: Bool?, hash: Data? = nil, type: UInt8? = nil) throws {
        let row = PersistentAssetLock(
            outPointHex: outPointHex,
            walletId: Data(repeating: 0x77, count: 32),
            transactionBytes: Data(),
            fundingTypeRaw: 4,
            identityIndexRaw: -1,
            amountDuffs: 200_000_000,
            statusRaw: 2)
        row.recipientIsExternal = isExternal
        row.recipientPlatformAddressHash = hash
        row.recipientPlatformAddressType = type
        let context = try container().mainContext
        context.insert(row)
        try context.save()
    }

    private func makeResumer() throws -> CoreFundingResumer {
        try CoreFundingResumer(
            edge: edge,
            recipientStore: store,
            container: container(),
            ownAddresses: .init(
                recipientHash: ownRecipientHash, remainderHash: ownRemainderHash, accountIndex: accountIndex),
            log: { [self] message in logged.append(message) })
    }

    private func resume() async throws {
        _ = try await makeResumer().resume(
            outPointTxid: txid, outPointVout: vout, ownRecipientAmountDuffs: derivedOwnAmountDuffs)
    }

    private var recordedExternal: ExternalFundingRecipientRecord {
        ExternalFundingRecipientRecord(addressType: 0, hash: externalHash, recipientAmountDuffs: externalAmountDuffs)
    }

    private var expectedExternalRecipients: [FakeEdge.Recipient] {
        [
            .init(addressType: 0, hash: externalHash, credits: externalAmountDuffs * 1000),
            .init(addressType: 0, hash: ownRemainderHash, credits: nil)
        ]
    }

    // MARK: Recording before broadcast

    func testBuiltHandlerRecordsTheRecipientAndAmountForTheLocksOutpoint() throws {
        var raw = txid
        var le = vout.littleEndian
        withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) }
        let built = try XCTUnwrap(AssetLockBuiltOutPoint(rawBytes: raw))
        var chained = 0

        let handler = recordedExternal.builtHandler(store: store, then: { _ in chained += 1 })
        XCTAssertNil(store.record(forOutPointHex: outPointHex), "nothing is recorded before the lock is built")
        handler(built)

        XCTAssertEqual(store.record(forOutPointHex: outPointHex), recordedExternal)
        XCTAssertEqual(chained, 1, "the caller's own built handler still runs")
    }

    // MARK: Recovery

    func testExternalLockResumesWithTheExternalResumeToItsRecordedRecipientAndAmount() async throws {
        try insertLock(isExternal: true, hash: externalHash, type: 0)
        store.save(recordedExternal, forOutPointHex: outPointHex)

        try await resume()

        XCTAssertEqual(edge.calls, [.external(txid, vout, accountIndex, expectedExternalRecipients)])
    }

    func testLockWithARecordButNoRowMarkIsStillExternal() async throws {
        // The app was killed after the built handler saved the record and before the lock row got its mark.
        try insertLock(isExternal: nil)
        store.save(recordedExternal, forOutPointHex: outPointHex)

        try await resume()

        XCTAssertEqual(edge.calls, [.external(txid, vout, accountIndex, expectedExternalRecipients)])
    }

    func testOwnLockKeepsTodaysPath() async throws {
        try insertLock(isExternal: false, hash: ownRecipientHash, type: 0)

        try await resume()

        XCTAssertEqual(edge.calls, [
            .own(txid, vout, accountIndex, [
                .init(addressType: 0, hash: ownRecipientHash, credits: derivedOwnAmountDuffs * 1000),
                .init(addressType: 0, hash: ownRemainderHash, credits: nil)
            ])
        ])
    }

    func testOldRowWithoutTheExternalFieldsIsAnOwnAddressLock() async throws {
        try insertLock(isExternal: nil, hash: nil, type: nil)

        try await resume()

        guard case .own? = edge.calls.first, edge.calls.count == 1 else {
            return XCTFail("expected the own-address resume, got \(edge.calls)")
        }
    }

    func testExternalLockWithoutARecipientRecordIsNeverResumedToTheOwnAddress() async throws {
        try insertLock(isExternal: true, hash: externalHash, type: 0)

        do {
            try await resume()
            XCTFail("an external lock without its recipient record must not resume")
        } catch let error as CoreFundingResumer.ResumeError {
            XCTAssertEqual(error, .externalRecipientRecordMissing)
        }

        XCTAssertTrue(edge.calls.isEmpty, "neither resume may run: \(edge.calls)")
        let row = try XCTUnwrap(container().mainContext.fetch(FetchDescriptor<PersistentAssetLock>()).first)
        XCTAssertEqual(row.statusRaw, 2, "the lock stays pending")
        XCTAssertTrue(try XCTUnwrap(row.recipientIsExternal))
        XCTAssertFalse(logged.isEmpty, "the refusal is logged")
        for line in logged {
            let hashHex = externalHash.map { String(format: "%02x", $0) }.joined()
            XCTAssertFalse(line.contains(hashHex), "no address in the log")
            XCTAssertFalse(line.contains(String(externalAmountDuffs)), "no amount in the log")
            XCTAssertFalse(line.contains(String(derivedOwnAmountDuffs)), "no amount in the log")
        }
    }

    func testRunningRecoveryTwiceSurfacesTheConsumedLockErrorAsToday() async throws {
        try insertLock(isExternal: true, hash: externalHash, type: 0)
        store.save(recordedExternal, forOutPointHex: outPointHex)

        try await resume()
        edge.failure = PlatformWalletError.assetLockAlreadyConsumed("already consumed")
        do {
            try await resume()
            XCTFail("the second pass must surface the SDK's consumed-lock error")
        } catch PlatformWalletError.assetLockAlreadyConsumed {
            // Same typed error the own-address path throws; the caller classifies it.
        }

        XCTAssertEqual(edge.calls.count, 2)
        XCTAssertEqual(edge.calls.last, .external(txid, vout, accountIndex, expectedExternalRecipients))
    }
}
