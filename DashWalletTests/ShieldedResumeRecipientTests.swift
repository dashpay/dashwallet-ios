//
//  ShieldedResumeRecipientTests.swift
//  DashWalletTests
//
//  Which recipient a resume of an existing Core → Shielded asset lock pays,
//  whichever surface resumes it: the recipient the SDK recorded on the lock's
//  row decides, and a caller's recipient must agree with it; a row tracked
//  before the SDK recorded recipients falls back to the Max drain marker, the
//  caller's recipient, then the wallet's own address. Also the row read the
//  resume does, and what an SDK recipient-mismatch refusal shows and records.
//

import Foundation
import SwiftData
import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class ShieldedResumeRecipientTests: XCTestCase {

    private typealias Resolver = ShieldedResumeRecipient

    private let context = CoreShieldedDrainContext(walletId: Data(repeating: 7, count: 32), networkScope: "testnet")
    private let recorded = Data(repeating: 0xA1, count: 43)
    private let other = Data(repeating: 0xB2, count: 43)
    private let own = Data(repeating: 0xEE, count: 43)

    /// The shape of the SDK's code-61 text: both addresses, in hex.
    private var sdkMismatchDetail: String {
        "Asset lock 00:0 was built to pay shielded recipient \(hex(recorded)) and cannot be resumed to \(hex(other))"
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func resolve(
        recorded: Data?,
        row: CoreShieldedDrainRowIdentity = .none,
        marker: CoreShieldedDrainMarkerLookup = .loaded(nil),
        caller: Data? = nil
    ) -> Resolver {
        Resolver.resolve(recordedRaw43: recorded, row: row, marker: { marker }, callerRaw43: caller, ownRaw43: own)
    }

    // MARK: - A recorded recipient decides

    func testRecordedRecipientIsPaidWhenTheCallerNamesNone() {
        XCTAssertEqual(resolve(recorded: recorded), .pay(recorded, source: .recorded))
    }

    func testCallerAgreeingWithTheRecordIsPaidTheRecord() {
        XCTAssertEqual(resolve(recorded: recorded, caller: recorded), .pay(recorded, source: .recorded))
    }

    func testCallerDifferingFromTheRecordIsRefused() {
        XCTAssertEqual(resolve(recorded: recorded, caller: other), .refuse(.mismatch))
        // The redirect ios#1253 described: the wallet's own address in place
        // of the recorded external one.
        XCTAssertEqual(resolve(recorded: recorded, caller: own), .refuse(.mismatch))
    }

    func testRecordedOwnAddressIsPaidAsRecorded() {
        XCTAssertEqual(resolve(recorded: own), .pay(own, source: .recorded))
    }

    func testRecordedRecipientOnADrainRowNeverReadsTheMarker() {
        let id = UUID()
        let markers: [CoreShieldedDrainMarkerLookup] = [
            .unavailable,
            .corrupt,
            .loaded(nil),
            .loaded(CoreShieldedDrainOperation(id: UUID(), context: context, recipient: .external(raw43: other))),
            .loaded(CoreShieldedDrainOperation(id: id, context: context, recipient: .external(raw43: other))),
        ]
        for marker in markers {
            var reads = 0
            let resolution = Resolver.resolve(
                recordedRaw43: recorded,
                row: .operation(id),
                marker: { reads += 1; return marker },
                callerRaw43: nil,
                ownRaw43: own)
            XCTAssertEqual(resolution, .pay(recorded, source: .recorded))
            XCTAssertEqual(reads, 0)
        }
    }

    func testRecordedRecipientOfTheWrongSizeIsRefused() {
        for size in [0, 42, 44] {
            XCTAssertEqual(resolve(recorded: Data(repeating: 0xA1, count: size)), .refuse(.mismatch))
        }
    }

    // MARK: - Rows tracked before the SDK recorded recipients

    func testLegacyRowNoDrainBuiltPaysTheCallerElseTheOwnAddress() {
        XCTAssertEqual(resolve(recorded: nil), .pay(own, source: .ownLegacy))
        XCTAssertEqual(resolve(recorded: nil, caller: other), .pay(other, source: .caller))
    }

    func testLegacyRowNoDrainBuiltNeverReadsTheMarker() {
        var reads = 0
        _ = Resolver.resolve(
            recordedRaw43: nil, row: .none,
            marker: { reads += 1; return .unavailable },
            callerRaw43: nil, ownRaw43: own)
        XCTAssertEqual(reads, 0)
    }

    func testLegacyDrainRowPaysItsMarkersRecipient() {
        let id = UUID()
        let external = CoreShieldedDrainOperation(id: id, context: context, recipient: .external(raw43: other))
        let ownDrain = CoreShieldedDrainOperation(id: id, context: context)
        XCTAssertEqual(resolve(recorded: nil, row: .operation(id), marker: .loaded(external)), .pay(other, source: .marker))
        XCTAssertEqual(resolve(recorded: nil, row: .operation(id), marker: .loaded(ownDrain)), .pay(own, source: .marker))
    }

    func testLegacyDrainRowWithUnreadableMarkerAsksForARetry() {
        XCTAssertEqual(resolve(recorded: nil, row: .operation(UUID()), marker: .unavailable), .refuse(.drainRecipientUnavailable))
    }

    func testLegacyDrainRowWithoutItsMarkerIsRefused() {
        let id = UUID()
        let another = CoreShieldedDrainOperation(id: UUID(), context: context, recipient: .external(raw43: other))
        XCTAssertEqual(resolve(recorded: nil, row: .operation(id), marker: .corrupt), .refuse(.drainRecipientUnknown))
        XCTAssertEqual(resolve(recorded: nil, row: .operation(id), marker: .loaded(nil)), .refuse(.drainRecipientUnknown))
        XCTAssertEqual(resolve(recorded: nil, row: .operation(id), marker: .loaded(another)), .refuse(.drainRecipientUnknown))
        XCTAssertEqual(resolve(recorded: nil, row: .malformed, marker: .loaded(another)), .refuse(.drainRecipientUnknown))
    }

    func testLegacyDrainRowChecksTheCallerAgainstItsMarker() {
        let id = UUID()
        let external = CoreShieldedDrainOperation(id: id, context: context, recipient: .external(raw43: other))
        XCTAssertEqual(resolve(recorded: nil, row: .operation(id), marker: .loaded(external), caller: other), .pay(other, source: .marker))
        XCTAssertEqual(resolve(recorded: nil, row: .operation(id), marker: .loaded(external), caller: own), .refuse(.mismatch))
    }

    // MARK: - The row the resume reads

    func testResumeRowReadsThisWalletsRowAndItsRecordedRecipient() throws {
        let configuration = ModelConfiguration(
            schema: DashModelContainer.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none)
        let container = try ModelContainer(for: DashModelContainer.schema, configurations: [configuration])
        let walletId = Data(repeating: 0xA1, count: 32)
        let otherWalletId = Data(repeating: 0xB2, count: 32)
        let drainTxid = Data((0..<32).map { UInt8($0) })
        let legacyTxid = Data((32..<64).map { UInt8($0) })
        let otherWalletTxid = Data((64..<96).map { UInt8($0) })
        let drainId = UUID()
        func lock(_ txidWire: Data, vout: UInt32, wallet: Data, operationId: Data?, recipient: Data?) -> PersistentAssetLock {
            PersistentAssetLock(
                outPointHex: "\(AssetLockFailureStore.displayHex(txidWire: txidWire)):\(vout)",
                walletId: wallet,
                transactionBytes: Data(),
                fundingTypeRaw: 5,
                identityIndexRaw: -1,
                amountDuffs: 250_000_000,
                statusRaw: 2,
                operationId: operationId,
                shieldedRecipientRaw43: recipient)
        }
        let modelContext = container.mainContext
        modelContext.insert(lock(drainTxid, vout: 0, wallet: walletId,
                                 operationId: withUnsafeBytes(of: drainId.uuid) { Data($0) }, recipient: recorded))
        modelContext.insert(lock(legacyTxid, vout: 1, wallet: walletId, operationId: nil, recipient: nil))
        modelContext.insert(lock(otherWalletTxid, vout: 0, wallet: otherWalletId, operationId: nil, recipient: other))
        try modelContext.save()

        typealias Row = ShieldedTransferCoordinator.ResumeRow
        XCTAssertEqual(
            ShieldedTransferCoordinator.resumeRow(outPointTxidWire: drainTxid, vout: 0, walletId: walletId, in: container),
            Row(identity: .operation(drainId), recordedRecipientRaw43: recorded))
        XCTAssertEqual(
            ShieldedTransferCoordinator.resumeRow(outPointTxidWire: legacyTxid, vout: 1, walletId: walletId, in: container),
            Row(identity: .none, recordedRecipientRaw43: nil))
        // Another wallet's row is not this wallet's, whatever it recorded.
        XCTAssertNil(ShieldedTransferCoordinator.resumeRow(
            outPointTxidWire: otherWalletTxid, vout: 0, walletId: walletId, in: container))
        // Same txid, another output: no row.
        XCTAssertNil(ShieldedTransferCoordinator.resumeRow(
            outPointTxidWire: drainTxid, vout: 1, walletId: walletId, in: container))
    }

    /// AC-19: ExternalSend's non-Max Core → Shielded lock is a plain row (no drain operation) with the SDK's recorded
    /// external recipient. Generic recovery resumes it with no caller recipient and pays that recipient, never the
    /// wallet's own address; the recipient is decided through the same `ResumeRow.recipient` call `resumeAssetLock`
    /// makes.
    func testGenericRecoveryOfAnUnfinishedExternalSendLockPaysItsRecordedRecipient() throws {
        let container = try DashModelContainer.inMemoryWithoutCloudKit()
        let walletId = Data(repeating: 0xA1, count: 32)
        let txid = Data((0..<32).map { UInt8($0) })
        container.mainContext.insert(PersistentAssetLock(
            outPointHex: "\(AssetLockFailureStore.displayHex(txidWire: txid)):0",
            walletId: walletId,
            transactionBytes: Data(),
            fundingTypeRaw: 5,
            identityIndexRaw: -1,
            amountDuffs: 250_000_000,
            statusRaw: 2,
            operationId: nil,
            shieldedRecipientRaw43: recorded))
        try container.mainContext.save()

        let row = try XCTUnwrap(ShieldedTransferCoordinator.resumeRow(
            outPointTxidWire: txid, vout: 0, walletId: walletId, in: container))
        var markerReads = 0
        let resolution = row.recipient(
            marker: {
                markerReads += 1
                return .loaded(nil)
            },
            callerRaw43: nil,
            ownRaw43: own)

        XCTAssertEqual(resolution, .pay(recorded, source: .recorded))
        XCTAssertEqual(markerReads, 0)
    }

    // MARK: - What a mismatch refusal shows and records

    func testSDKMismatchShowsTheAppsMessageNotTheSDKText() {
        let expected = ShieldedTransferCoordinator.CoordinatorError.resumeRecipientMismatch.localizedDescription
        let sdkError = PlatformWalletError.assetLockRecipientMismatch(sdkMismatchDetail)
        for error in [sdkError, ShieldedTransferCoordinator.CoordinatorError.transferFailed(sdkError)] as [Error] {
            let message = ShieldedTransferCoordinator.failureMessage(for: error)
            XCTAssertEqual(message, expected)
            XCTAssertFalse(message.contains(hex(recorded)))
            XCTAssertFalse(message.contains(hex(other)))
        }
    }

    func testOtherFailuresKeepTheirMessages() {
        XCTAssertEqual(
            ShieldedTransferCoordinator.failureMessage(
                for: ShieldedTransferCoordinator.CoordinatorError.transferFailed(
                    PlatformWalletError.assetLockTooManyInputs("too many inputs: 121 (max 100)"))),
            AssetLockInputLimit.message)
        let unknown = ShieldedTransferCoordinator.CoordinatorError.drainRecipientUnknown
        XCTAssertEqual(ShieldedTransferCoordinator.failureMessage(for: unknown), unknown.localizedDescription)
        let wrapped = ShieldedTransferCoordinator.CoordinatorError.transferFailed(
            PlatformWalletError.walletOperation("operation failed"))
        XCTAssertEqual(ShieldedTransferCoordinator.failureMessage(for: wrapped), wrapped.localizedDescription)
    }

    func testRecipientRefusalsAreRecognisedBareAndWrapped() {
        let sdkError = PlatformWalletError.assetLockRecipientMismatch(sdkMismatchDetail)
        let refusals: [Error] = [
            sdkError,
            ShieldedTransferCoordinator.CoordinatorError.transferFailed(sdkError),
            ShieldedTransferCoordinator.CoordinatorError.resumeRecipientMismatch,
        ]
        for error in refusals {
            XCTAssertTrue(ShieldedTransferCoordinator.isRecipientMismatch(error), "\(error)")
        }
        let others: [Error] = [
            ShieldedTransferCoordinator.CoordinatorError.drainRecipientUnknown,
            ShieldedTransferCoordinator.CoordinatorError.transferFailed(
                PlatformWalletError.assetLockTooManyInputs("too many inputs: 121 (max 100)")),
            PlatformWalletError.walletOperation("operation failed"),
        ]
        for error in others {
            XCTAssertFalse(ShieldedTransferCoordinator.isRecipientMismatch(error), "\(error)")
        }
    }

    func testFailureRecordNamesTheMismatchWithoutTheAddresses() {
        let sdkError = PlatformWalletError.assetLockRecipientMismatch(sdkMismatchDetail)
        let envelopes: [Error] = [
            sdkError,
            ShieldedTransferCoordinator.CoordinatorError.transferFailed(sdkError),
            AssetLockRecoveryService.RecoveryError.failed("shown text", underlying: sdkError),
        ]
        for error in envelopes {
            let record = AssetLockFailureRecord.describe(error)
            XCTAssertEqual(record.errorCase, "assetLockRecipientMismatch")
            XCTAssertEqual(record.detail, AssetLockFailureRecord.recipientMismatchDetail)
            XCTAssertFalse(record.logDescription.contains(hex(recorded)))
        }
    }

    func testRecipientMismatchResultCodeIs61() {
        XCTAssertEqual(PlatformWalletResultCode.errorAssetLockRecipientMismatch.rawValue, 61)
    }
}
