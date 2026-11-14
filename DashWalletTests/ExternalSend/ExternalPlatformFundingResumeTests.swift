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

    private final class FakeEdge: AssetLockResumeEdge, AssetLockFundingEdge, @unchecked Sendable {
        enum Call: Equatable {
            case own(Data, UInt32, UInt32, [Recipient])
            case external(Data, UInt32, UInt32, [Recipient])
            case fundOwn(UInt64, [Recipient])
            case fundExternal(UInt64, [Recipient])
        }
        struct Recipient: Equatable {
            let addressType: UInt8
            let hash: Data
            let credits: UInt64?
        }

        private(set) var calls: [Call] = []
        var failure: Error?
        /// What the SDK reports to `onAssetLockBuilt` before the funding call returns or throws.
        var built: AssetLockBuiltOutPoint?

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

        func fundOwn(
            lockValueDuffs: UInt64, platformAccountIndex: UInt32,
            recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
            onAssetLockBuilt: AssetLockBuiltHandler?
        ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
            calls.append(.fundOwn(lockValueDuffs, Self.map(recipients)))
            if let built { onAssetLockBuilt?(built) }
            if let failure { throw failure }
            return []
        }

        func fundExternal(
            lockValueDuffs: UInt64, platformAccountIndex: UInt32,
            recipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient],
            onAssetLockBuilt: AssetLockBuiltHandler?
        ) async throws -> [ManagedPlatformAddressWallet.UpdatedBalance] {
            calls.append(.fundExternal(lockValueDuffs, Self.map(recipients)))
            if let built { onAssetLockBuilt?(built) }
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

        private var ownMarks: Set<String> = []
        var ownMarkingStart: Date?

        func markOwn(outPointHex: String) {
            lock.lock()
            defer { lock.unlock() }
            ownMarks.insert(outPointHex)
        }

        func isMarkedOwn(outPointHex: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return ownMarks.contains(outPointHex)
        }

        func removeRecipient(outPointHex: String) {
            lock.lock()
            defer { lock.unlock() }
            records[outPointHex] = nil
            ownMarks.remove(outPointHex)
        }

        func entryOutPointHexes() -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            return Set(records.keys).union(ownMarks)
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

    private func insertLock(
        isExternal: Bool?, hash: Data? = nil, type: UInt8? = nil, createdAt: Date? = nil, statusRaw: Int = 2
    ) throws {
        let row = PersistentAssetLock(
            outPointHex: outPointHex,
            walletId: Data(repeating: 0x77, count: 32),
            transactionBytes: Data(),
            fundingTypeRaw: 4,
            identityIndexRaw: -1,
            amountDuffs: 200_000_000,
            statusRaw: statusRaw)
        row.recipientIsExternal = isExternal
        row.recipientPlatformAddressHash = hash
        row.recipientPlatformAddressType = type
        if let createdAt { row.createdAt = createdAt }
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

    // MARK: Destination network

    /// `fundExternalFromCore` runs this check before it builds the lock.
    func testAnExternalDestinationOfTheOtherNetworkIsRefusedAsNotSent() throws {
        let payload = Data([0xb0] + Array(repeating: 0x02, count: 20))
        let mainnet = try XCTUnwrap(Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: true), data: payload))
        let testnet = try XCTUnwrap(Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: false), data: payload))
        let check = PlatformAddressSyncCoordinator.requireExternalDestination

        for (destination, network) in [(testnet, Network.mainnet), (mainnet, .testnet)] {
            XCTAssertThrowsError(try check(destination, network)) {
                guard case PlatformAddressSyncCoordinator.SendError.invalidDestination = $0 else {
                    return XCTFail("unexpected error \($0)")
                }
                guard case .notSent = SendOutcome(error: $0) else {
                    return XCTFail("a refused destination is not sent")
                }
            }
        }
        XCTAssertNoThrow(try check(mainnet, .mainnet))
        XCTAssertNoThrow(try check(testnet, .testnet))
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

    func testOwnBuiltHandlerMarksTheLockOwnAndChains() throws {
        var raw = txid
        var le = vout.littleEndian
        withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) }
        let built = try XCTUnwrap(AssetLockBuiltOutPoint(rawBytes: raw))
        var chained = 0

        let handler = store.ownBuiltHandler(then: { _ in chained += 1 })
        XCTAssertFalse(store.isMarkedOwn(outPointHex: outPointHex), "nothing is marked before the lock is built")
        handler(built)

        XCTAssertTrue(store.isMarkedOwn(outPointHex: outPointHex))
        XCTAssertNil(store.record(forOutPointHex: outPointHex), "an own lock has no external record")
        XCTAssertEqual(chained, 1, "the caller's own built handler still runs")
    }

    func testUnmarkedRowMarkedOwnAtBuildResumesToTheOwnAddress() async throws {
        // In flight the SDK row carries no recipient fields; the own mark saved at build is the proof.
        try insertLock(isExternal: nil, hash: nil, type: nil)
        store.markOwn(outPointHex: outPointHex)

        try await resume()

        guard case .own? = edge.calls.first, edge.calls.count == 1 else {
            return XCTFail("expected the own-address resume, got \(edge.calls)")
        }
    }

    func testLockWithNeitherARecordNorProofItIsOwnIsRefused() async throws {
        // An external lock whose record was lost looks exactly like this: no record, no own mark, an unmarked row.
        try insertLock(isExternal: nil, hash: nil, type: nil)

        do {
            try await resume()
            XCTFail("a lock whose recipient is unknown must not resume")
        } catch let error as CoreFundingResumer.ResumeError {
            XCTAssertEqual(error, .recipientUnknown)
        }

        XCTAssertTrue(edge.calls.isEmpty, "neither resume may run: \(edge.calls)")
        let row = try XCTUnwrap(container().mainContext.fetch(FetchDescriptor<PersistentAssetLock>()).first)
        XCTAssertEqual(row.statusRaw, 2, "the lock stays pending")
        XCTAssertFalse(logged.isEmpty, "the refusal is logged")
    }

    func testUndecodableRecordWithoutOwnMarkIsRefused() async throws {
        let suite = "ExternalPlatformFundingResumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "externalFundingRecipient." + outPointHex)
        let userDefaultsStore = UserDefaultsFundingRecipientStore(defaults: defaults)
        XCTAssertThrowsError(try userDefaultsStore.record(forOutPointHex: outPointHex))
        XCTAssertFalse(userDefaultsStore.isMarkedOwn(outPointHex: outPointHex))
        try insertLock(isExternal: nil, hash: nil, type: nil)

        let resumer = try CoreFundingResumer(
            edge: edge,
            recipientStore: userDefaultsStore,
            container: container(),
            ownAddresses: .init(
                recipientHash: ownRecipientHash, remainderHash: ownRemainderHash, accountIndex: accountIndex),
            log: { [self] message in logged.append(message) })
        do {
            _ = try await resumer.resume(
                outPointTxid: txid, outPointVout: vout, ownRecipientAmountDuffs: derivedOwnAmountDuffs)
            XCTFail("a corrupt record must not fall through to the own resume")
        } catch let error as CoreFundingResumer.ResumeError {
            XCTAssertEqual(error, .recipientUnknown)
        }
        XCTAssertTrue(edge.calls.isEmpty, "neither resume may run: \(edge.calls)")
    }

    func testAnUnreadableRecordIsRefusedEvenWhenTheLockIsMarkedOwn() async throws {
        // Something was saved as an external record: an own mark next to it proves nothing about who the lock pays.
        let suite = "ExternalPlatformFundingResumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "externalFundingRecipient." + outPointHex)
        let userDefaultsStore = UserDefaultsFundingRecipientStore(defaults: defaults)
        userDefaultsStore.markOwn(outPointHex: outPointHex)
        try insertLock(isExternal: nil, hash: nil, type: nil)

        let resumer = try CoreFundingResumer(
            edge: edge,
            recipientStore: userDefaultsStore,
            container: container(),
            ownAddresses: .init(
                recipientHash: ownRecipientHash, remainderHash: ownRemainderHash, accountIndex: accountIndex),
            log: { [self] message in logged.append(message) })
        do {
            _ = try await resumer.resume(
                outPointTxid: txid, outPointVout: vout, ownRecipientAmountDuffs: derivedOwnAmountDuffs)
            XCTFail("an unreadable record must not resume to the own address")
        } catch let error as CoreFundingResumer.ResumeError {
            XCTAssertEqual(error, .recipientUnknown)
        }
        XCTAssertTrue(edge.calls.isEmpty, "neither resume may run: \(edge.calls)")
        XCTAssertFalse(logged.isEmpty, "the refusal is logged")
    }

    func testUserDefaultsStoreKeepsTheOwnMarkAcrossInstances() throws {
        let suite = "ExternalPlatformFundingResumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        UserDefaultsFundingRecipientStore(defaults: defaults).markOwn(outPointHex: outPointHex)

        XCTAssertTrue(UserDefaultsFundingRecipientStore(defaults: defaults).isMarkedOwn(outPointHex: outPointHex))
        XCTAssertFalse(UserDefaultsFundingRecipientStore(defaults: defaults).isMarkedOwn(outPointHex: "00:0"))
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

    // MARK: Funding: what the lock is known as once it is built

    private func builtOutPoint() throws -> AssetLockBuiltOutPoint {
        var raw = txid
        var le = vout.littleEndian
        withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) }
        return try XCTUnwrap(AssetLockBuiltOutPoint(rawBytes: raw))
    }

    private var ownFundingRecipients: [ManagedPlatformAddressWallet.FundFromAssetLockRecipient] {
        [
            .init(addressType: 0, hash: ownRecipientHash, credits: derivedOwnAmountDuffs * 1000),
            .init(addressType: 0, hash: ownRemainderHash, credits: nil)
        ]
    }

    func testAnOwnTopUpMarksItsBuiltLockOwnSoRecoveryResumesIt() async throws {
        edge.built = try builtOutPoint()
        edge.failure = PlatformWalletError.transactionBroadcastUnconfirmed("unconfirmed")
        var chained = 0

        do {
            _ = try await CoreFunder(edge: edge, recipientStore: store).fundOwn(
                lockValueDuffs: 200_000_000, platformAccountIndex: accountIndex, recipients: ownFundingRecipients,
                onAssetLockBuilt: { _ in chained += 1 })
            XCTFail("the scripted funding call fails after the build")
        } catch PlatformWalletError.transactionBroadcastUnconfirmed {}

        XCTAssertTrue(store.isMarkedOwn(outPointHex: outPointHex))
        XCTAssertEqual(chained, 1, "the caller's handler still runs")
        edge.failure = nil
        try insertLock(isExternal: nil)
        try await resume()
        guard case .own? = edge.calls.last else { return XCTFail("expected the own resume, got \(edge.calls)") }
    }

    func testAnExternalPaymentRecordsItsRecipientWhenTheLockIsBuilt() async throws {
        edge.built = try builtOutPoint()
        edge.failure = PlatformWalletError.transactionBroadcastUnconfirmed("unconfirmed")

        do {
            _ = try await CoreFunder(edge: edge, recipientStore: store).fundExternal(
                record: recordedExternal, lockValueDuffs: 200_000_000, platformAccountIndex: accountIndex,
                recipients: ownFundingRecipients, onAssetLockBuilt: nil)
            XCTFail("the scripted funding call fails after the build")
        } catch PlatformWalletError.transactionBroadcastUnconfirmed {}

        XCTAssertEqual(store.record(forOutPointHex: outPointHex), recordedExternal)
        XCTAssertFalse(store.isMarkedOwn(outPointHex: outPointHex))
    }

    // MARK: Forgetting a finished lock's recipient

    private func insertRow(outPointHex: String, statusRaw: Int) throws {
        let context = try container().mainContext
        context.insert(PersistentAssetLock(
            outPointHex: outPointHex, walletId: Data(repeating: 0x77, count: 32), transactionBytes: Data(),
            fundingTypeRaw: 4, identityIndexRaw: -1, amountDuffs: 200_000_000, statusRaw: statusRaw))
        try context.save()
    }

    func testTheSweepRemovesOnlyTheEntriesOfConsumedLocks() throws {
        store.save(recordedExternal, forOutPointHex: "consumed-external:0")
        store.markOwn(outPointHex: "consumed-own:0")
        store.markOwn(outPointHex: "pending:0")
        store.markOwn(outPointHex: "no-row-yet:0")
        try insertRow(outPointHex: "consumed-external:0", statusRaw: AssetLockRecoveryService.consumedStatus)
        try insertRow(outPointHex: "consumed-own:0", statusRaw: AssetLockRecoveryService.consumedStatus)
        try insertRow(outPointHex: "pending:0", statusRaw: 2)

        try CoreFundingRecipientSweep(recipientStore: store, container: container()).removeFinished()

        XCTAssertEqual(store.entryOutPointHexes(), ["pending:0", "no-row-yet:0"])
    }

    /// A resume that finished leaves the entry while the row still reads as unfinished, so a second pass reaches the
    /// SDK and is told the lock is already consumed (`testRunningRecoveryTwiceSurfacesTheConsumedLockErrorAsToday`).
    func testTheSweepKeepsTheEntryOfALockWhoseRowStillReadsUnfinished() async throws {
        try insertLock(isExternal: nil)
        store.save(recordedExternal, forOutPointHex: outPointHex)

        try await resume()
        try CoreFundingRecipientSweep(recipientStore: store, container: container()).removeFinished()

        XCTAssertEqual(store.record(forOutPointHex: outPointHex), recordedExternal)
    }

    func testAFailedResumeKeepsTheRecipientForTheNextTry() async throws {
        try insertLock(isExternal: nil)
        store.save(recordedExternal, forOutPointHex: outPointHex)
        edge.failure = PlatformWalletError.transactionBroadcastUnconfirmed("unconfirmed")

        do {
            try await resume()
            XCTFail("the scripted resume fails")
        } catch PlatformWalletError.transactionBroadcastUnconfirmed {}

        XCTAssertEqual(store.record(forOutPointHex: outPointHex), recordedExternal)
    }

    func testUserDefaultsStoreRemovesOneLocksRecipientAndKeepsTheOthers() throws {
        let suite = "ExternalPlatformFundingResumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsFundingRecipientStore(defaults: defaults)
        store.save(recordedExternal, forOutPointHex: outPointHex)
        store.markOwn(outPointHex: outPointHex)
        store.markOwn(outPointHex: "other:0")

        XCTAssertEqual(store.entryOutPointHexes(), [outPointHex, "other:0"])

        store.removeRecipient(outPointHex: outPointHex)

        XCTAssertNil(try store.record(forOutPointHex: outPointHex))
        XCTAssertFalse(store.isMarkedOwn(outPointHex: outPointHex))
        XCTAssertTrue(store.isMarkedOwn(outPointHex: "other:0"))
        XCTAssertEqual(store.entryOutPointHexes(), ["other:0"])
    }

    func testTheFullWipeRemovesEveryRecipientRecordAndOwnMarkButNotTheStartOfOwnMarks() {
        let defaults = UserDefaults.standard
        let outPoint = "wipe-test-\(UUID().uuidString):0"
        let store = UserDefaultsFundingRecipientStore(defaults: defaults)
        store.save(recordedExternal, forOutPointHex: outPoint)
        store.markOwn(outPointHex: outPoint)
        let startBefore = store.ownMarkingStart

        SwiftDashSDKWalletWiper.resetUserDefaultsStoresForWipe()

        XCTAssertNil(defaults.object(forKey: "externalFundingRecipient." + outPoint))
        XCTAssertNil(defaults.object(forKey: "ownFundingLock." + outPoint))
        XCTAssertEqual(store.ownMarkingStart, startBefore, "the start describes the build, not the wallet")
    }

    // MARK: Own locks left by builds before own marks

    private let markingStart = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnUnmarkedLockCreatedBeforeOwnMarksBeganResumesToTheOwnAddress() async throws {
        // External Core → Platform never shipped before own marks, so such a lock is the wallet's own top-up.
        store.ownMarkingStart = markingStart
        try insertLock(isExternal: nil, createdAt: markingStart.addingTimeInterval(-60))

        try await resume()

        guard case .own? = edge.calls.first, edge.calls.count == 1 else {
            return XCTFail("expected the own-address resume, got \(edge.calls)")
        }
    }

    func testAnUnmarkedLockCreatedSinceOwnMarksBeganIsRefused() async throws {
        // A lock rebuilt from chain after a restore gets a new row: nothing proves it is own.
        store.ownMarkingStart = markingStart
        try insertLock(isExternal: nil, createdAt: markingStart.addingTimeInterval(60))

        do {
            try await resume()
            XCTFail("an unmarked lock created since own marks began must not resume")
        } catch let error as CoreFundingResumer.ResumeError {
            XCTAssertEqual(error, .recipientUnknown)
        }
        XCTAssertTrue(edge.calls.isEmpty)
    }

    func testRowRebuiltFromChainIsRefusedWhateverItsAge() async throws {
        // A restore rebuilds the lock row from the chain; its age says nothing about who the lock pays.
        store.ownMarkingStart = markingStart
        try insertLock(
            isExternal: nil, createdAt: markingStart.addingTimeInterval(-60),
            statusRaw: AssetLockRecoveryService.recoveredFromChainStatus)

        do {
            try await resume()
            XCTFail("a row rebuilt from the chain is not proven own by its age")
        } catch let error as CoreFundingResumer.ResumeError {
            XCTAssertEqual(error, .recipientUnknown)
        }
        XCTAssertTrue(edge.calls.isEmpty)
    }

    func testWithoutAKnownStartOfOwnMarksAnUnmarkedLockIsRefused() async throws {
        try insertLock(isExternal: nil, createdAt: .distantPast)

        do {
            try await resume()
            XCTFail("nothing proves the lock is own")
        } catch let error as CoreFundingResumer.ResumeError {
            XCTAssertEqual(error, .recipientUnknown)
        }
    }

    func testAnExternalRecordWinsOverTheStartOfOwnMarks() async throws {
        store.ownMarkingStart = markingStart
        try insertLock(isExternal: nil, createdAt: markingStart.addingTimeInterval(-60))
        store.save(recordedExternal, forOutPointHex: outPointHex)

        try await resume()

        XCTAssertEqual(edge.calls, [.external(txid, vout, accountIndex, expectedExternalRecipients)])
    }

    func testUserDefaultsStoreRecordsTheStartOfOwnMarksOnce() throws {
        let suite = "ExternalPlatformFundingResumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertNil(UserDefaultsFundingRecipientStore(defaults: defaults).ownMarkingStart)
        UserDefaultsFundingRecipientStore.recordOwnMarkingStartIfNeeded(defaults: defaults, now: first)
        UserDefaultsFundingRecipientStore.recordOwnMarkingStartIfNeeded(
            defaults: defaults, now: first.addingTimeInterval(3600))

        XCTAssertEqual(UserDefaultsFundingRecipientStore(defaults: defaults).ownMarkingStart, first)
    }

    // MARK: The recipient check before the PIN

    private func makeCheck() throws -> CoreFundingRecipientCheck {
        try CoreFundingRecipientCheck(
            recipientStore: store, container: container(), log: { [self] message in logged.append(message) })
    }

    func testTheCheckRefusesALockWithNeitherARecordNorProofItIsOwnWithoutCallingTheSDK() throws {
        try insertLock(isExternal: nil, hash: nil, type: nil)

        XCTAssertThrowsError(try makeCheck().recipient(outPointTxid: txid, outPointVout: vout)) { error in
            XCTAssertEqual(error as? CoreFundingResumer.ResumeError, .recipientUnknown)
        }
        XCTAssertTrue(edge.calls.isEmpty)
    }

    // MARK: The retry the transaction details offer

    func testTxDetailsOffersNoRetryForACoreToPlatformLockWhoseRecipientIsUnknown() throws {
        try insertLock(isExternal: nil, hash: nil, type: nil)
        let check = try makeCheck()
        func knows(_ fundingTypeRaw: Int) -> Bool {
            TxDetailModel.recoveryKnowsRecipient(
                fundingTypeRaw: fundingTypeRaw, txidWire: txid, vout: vout,
                checkResumable: { _ = try check.recipient(outPointTxid: $0, outPointVout: $1) })
        }

        XCTAssertFalse(knows(4), "its resume would only refuse")
        XCTAssertTrue(knows(5), "a Core → Shielded lock is not decided here")
        XCTAssertTrue(knows(1), "an identity lock is not decided here")

        store.markOwn(outPointHex: outPointHex)
        XCTAssertTrue(knows(4), "an own lock is offered its retry")
    }

    func testTheCoordinatorCheckThrowsNotReadyBeforeItHasStartedAndTxDetailsOffersNoRetry() throws {
        let coordinator = PlatformAddressSyncCoordinator.shared
        try XCTSkipIf(coordinator.isRunning, "the shared coordinator is already started")

        XCTAssertThrowsError(try coordinator.checkFundFromCoreResumable(outPointTxid: txid, outPointVout: vout)) {
            guard case PlatformAddressSyncCoordinator.SendError.coordinatorNotReady = $0 else {
                return XCTFail("unexpected error \($0)")
            }
        }
        XCTAssertFalse(TxDetailModel.recoveryKnowsRecipient(
            fundingTypeRaw: 4, txidWire: txid, vout: vout,
            checkResumable: { try coordinator.checkFundFromCoreResumable(outPointTxid: $0, outPointVout: $1) }))
    }

    func testTxDetailsOffersARetryForARecordedExternalLock() throws {
        try insertLock(isExternal: nil, hash: nil, type: nil)
        store.save(recordedExternal, forOutPointHex: outPointHex)
        let check = try makeCheck()

        XCTAssertTrue(TxDetailModel.recoveryKnowsRecipient(
            fundingTypeRaw: 4, txidWire: txid, vout: vout,
            checkResumable: { _ = try check.recipient(outPointTxid: $0, outPointVout: $1) }))
    }

    func testTheCheckRefusesAnExternalLockWithoutItsRecord() throws {
        try insertLock(isExternal: true, hash: externalHash, type: 0)

        XCTAssertThrowsError(try makeCheck().recipient(outPointTxid: txid, outPointVout: vout)) { error in
            XCTAssertEqual(error as? CoreFundingResumer.ResumeError, .externalRecipientRecordMissing)
        }
    }

    func testTheCheckNamesTheRecordedRecipientOrTheOwnAddresses() throws {
        try insertLock(isExternal: nil, hash: nil, type: nil)
        store.markOwn(outPointHex: outPointHex)
        XCTAssertEqual(try makeCheck().recipient(outPointTxid: txid, outPointVout: vout), .own)

        store.save(recordedExternal, forOutPointHex: outPointHex)
        XCTAssertEqual(
            try makeCheck().recipient(outPointTxid: txid, outPointVout: vout), .external(recordedExternal),
            "an external record wins over an own mark")
    }

    /// The refusal reaches the screen through `ShieldedTransferCoordinator.failureMessage`, which shows a
    /// `LocalizedError`'s description; without one the user reads a generic "operation couldn't be completed".
    func testBothRefusalsExplainThatThePaymentCannotBeFinishedAutomatically() {
        for refusal in [CoreFundingResumer.ResumeError.recipientUnknown, .externalRecipientRecordMissing] {
            let message = ShieldedTransferCoordinator.failureMessage(for: refusal)
            XCTAssertEqual(message, CoreFundingResumer.ResumeError.cannotFinishMessage, "\(refusal)")
            XCTAssertFalse(message.contains("ResumeError"), message)
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
