//
//  AssetLockDiagnosticsTests.swift
//  DashWalletTests
//
//  What a diagnostic export says about tracked asset locks, and what the app
//  remembers about a lock's last failed retry. Ticket 32104: a CoinJoin →
//  Shielded lock with 121 inputs was refused by Platform on every retry
//  (consensus 10534, too many inputs), and five log exports contained no line
//  about it — the txid, the input count and the error reached support only
//  when the user pasted the alert text.
//

import Foundation
import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class AssetLockDiagnosticsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AssetLockDiagnosticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: fixtures

    /// Wire-order txid 0x01, 0x02, … 0x20 — display order is the reverse.
    private let txidWire = Data((1...32).map { UInt8($0) })
    private var txidDisplay: String {
        (1...32).reversed().map { String(format: "%02x", $0) }.joined()
    }

    /// A consensus-encoded DIP-2 type-8 (asset lock) transaction with
    /// `inputCount` inputs, one output and a two-byte payload.
    private func assetLockTransaction(inputCount: UInt8) -> Data {
        var bytes = Data()
        let versionField: UInt32 = 3 | (8 << 16)
        withUnsafeBytes(of: versionField.littleEndian) { bytes.append(contentsOf: $0) }
        bytes.append(inputCount) // varint < 0xfd
        for index in 0..<inputCount {
            bytes.append(Data(repeating: index, count: 32)) // prev txid
            withUnsafeBytes(of: UInt32(0).littleEndian) { bytes.append(contentsOf: $0) } // prev vout
            bytes.append(0) // empty scriptSig
            withUnsafeBytes(of: UInt32.max.littleEndian) { bytes.append(contentsOf: $0) } // sequence
        }
        bytes.append(1) // one output
        withUnsafeBytes(of: UInt64(250_000_000).littleEndian) { bytes.append(contentsOf: $0) }
        bytes.append(1)
        bytes.append(0x6a) // OP_RETURN
        withUnsafeBytes(of: UInt32(0).littleEndian) { bytes.append(contentsOf: $0) } // locktime
        bytes.append(2) // payload length
        bytes.append(contentsOf: [0x01, 0x00])
        return bytes
    }

    private func record(
        statusRaw: Int = 5,
        fundingTypeRaw: Int = 5,
        transactionBytes: Data = Data(),
        lastFailure: AssetLockFailureRecord? = nil
    ) -> AssetLockDiagnosticRecord {
        AssetLockDiagnosticRecord(
            txidDisplayHex: txidDisplay,
            vout: 0,
            fundingTypeRaw: fundingTypeRaw,
            statusRaw: statusRaw,
            amountDuffs: 250_000_000,
            createdAt: Date(timeIntervalSince1970: 1_755_820_800), // 2025-08-22T00:00:00Z
            updatedAt: Date(timeIntervalSince1970: 1_755_907_200), // 2025-08-23T00:00:00Z
            transactionBytes: transactionBytes,
            lastFailure: lastFailure)
    }

    // MARK: summary section

    func testSectionSaysUnavailableWhenTheCaptureCouldNotRun() {
        let lines = DiagnosticLogExporter.assetLockSection(nil)
        XCTAssertEqual(lines.count, 2)
        // "Unavailable" must never read as "this wallet has no stuck locks".
        XCTAssertTrue(lines[1].contains("unavailable"))
        XCTAssertFalse(lines[1].contains("none"))
    }

    func testSectionSaysNoneWhenNothingIsTracked() {
        XCTAssertEqual(DiagnosticLogExporter.assetLockSection([]).last, "  none")
    }

    func testRestoredLockPrintsExplorerTxidStatusNameInputsSizeAndLastFailure() {
        let transaction = assetLockTransaction(inputCount: 121)
        let failure = AssetLockFailureRecord(
            errorCase: "assetLockTooManyInputs",
            detail: "too many inputs: 121 (max 100)",
            recordedAt: Date(timeIntervalSince1970: 1_761_782_400)) // 2025-10-30T00:00:00Z
        let text = DiagnosticLogExporter
            .assetLockSection([record(transactionBytes: transaction, lastFailure: failure)])
            .joined(separator: "\n")

        // Display order: what a block explorer shows and support searches for.
        XCTAssertTrue(text.contains("\(txidDisplay):0"))
        XCTAssertFalse(text.contains(txidWire.map { String(format: "%02x", $0) }.joined()))
        XCTAssertTrue(text.contains("type=5 (assetLockShieldedAddressTopUp)"))
        // RecoveredFromChain (a restore) is in the section, by number and name.
        XCTAssertTrue(text.contains("status=5 (recoveredFromChain)"))
        XCTAssertTrue(text.contains("amount=250000000 duffs"))
        XCTAssertTrue(text.contains("created=2025-08-22T00:00:00Z"))
        XCTAssertTrue(text.contains("updated=2025-08-23T00:00:00Z"))
        XCTAssertTrue(text.contains("inputs=121 outputs=1 size=\(transaction.count) bytes"))
        XCTAssertTrue(text.contains(
            "last failure (2025-10-30T00:00:00Z): case=assetLockTooManyInputs detail=too many inputs: 121 (max 100)"))
    }

    func testMissingTransactionBytesAreReportedAsUnknownNotZero() {
        let text = DiagnosticLogExporter.assetLockSection([record()]).joined(separator: "\n")
        XCTAssertTrue(text.contains("inputs=? size=? (transaction bytes not stored locally)"))
        XCTAssertFalse(text.contains("inputs=0"))
        XCTAssertTrue(text.contains("last failure: none recorded"))
    }

    func testUnparseableTransactionBytesKeepTheirSizeButNoInputCount() {
        let garbage = Data([0x03, 0x00])
        let text = DiagnosticLogExporter
            .assetLockSection([record(transactionBytes: garbage)])
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("inputs=? size=2 bytes (stored transaction bytes did not parse)"))
    }

    func testEveryLockGetsItsOwnBlock() {
        let lines = DiagnosticLogExporter.assetLockSection([
            record(statusRaw: 2, fundingTypeRaw: 1),
            record(statusRaw: 3, fundingTypeRaw: 4),
        ])
        // Header + four lines per lock.
        XCTAssertEqual(lines.count, 1 + 2 * 4)
        XCTAssertTrue(lines[1].contains("type=1 (identityTopUp)"))
        XCTAssertTrue(lines[1].contains("status=2 (instantSendLocked)"))
        XCTAssertTrue(lines[5].contains("type=4 (assetLockAddressTopUp)"))
        XCTAssertTrue(lines[5].contains("status=3 (chainLocked)"))
    }

    func testUnknownDiscriminantsStayNumericAndAreNotGuessed() {
        XCTAssertEqual(DiagnosticLogExporter.assetLockStatusName(99), "unknown")
        XCTAssertEqual(DiagnosticLogExporter.assetLockStatusName(-1), "unknown")
        XCTAssertEqual(DiagnosticLogExporter.fundingTypeName(42), "unknown")
        XCTAssertEqual(DiagnosticLogExporter.assetLockStatusName(6), "drainCompleted")
    }

    func testConsumedIsTheStatusTheSectionLeavesOut() {
        XCTAssertEqual(DiagnosticLogExporter.consumedAssetLockStatus, 4)
    }

    // MARK: describing a failure

    func testPlatformErrorIsNamedByItsTypedCase() {
        let record = AssetLockFailureRecord.describe(
            PlatformWalletError.assetLockTooManyInputs("too many inputs: 121 (max 100)"))
        XCTAssertEqual(record.errorCase, "assetLockTooManyInputs")
        XCTAssertEqual(record.detail, "too many inputs: 121 (max 100)")
    }

    func testConsensusRejectionCarriesItsCodeIntoTheDetail() {
        let error = PlatformWalletError.consensusRejection(
            PlatformConsensusError(code: 10534, kind: .basic),
            "asset lock transaction has too many inputs")
        let record = AssetLockFailureRecord.describe(error)
        XCTAssertEqual(record.errorCase, "consensusRejection")
        // "10534" is what support greps for.
        XCTAssertTrue(record.detail.contains("code=10534"), record.detail)
        XCTAssertTrue(record.detail.contains("asset lock transaction has too many inputs"))
    }

    func testCoordinatorEnvelopeIsUnwrappedToThePlatformError() {
        let error = ShieldedTransferCoordinator.CoordinatorError.transferFailed(
            PlatformWalletError.assetLockTooManyInputs("too many inputs: 121 (max 100)"))
        XCTAssertEqual(AssetLockFailureRecord.describe(error).errorCase, "assetLockTooManyInputs")
    }

    func testRecoveryServiceFailureIsUnwrappedThroughBothEnvelopes() {
        // What the tx-detail and bulk retries actually catch for a type-5 lock:
        // the service's text-only failure, carrying the coordinator's typed one.
        let error = AssetLockRecoveryService.RecoveryError.failed(
            "Couldn't complete the transfer",
            underlying: ShieldedTransferCoordinator.CoordinatorError.transferFailed(
                PlatformWalletError.assetLockTooManyInputs("too many inputs: 121 (max 100)")))
        let record = AssetLockFailureRecord.describe(error)
        XCTAssertEqual(record.errorCase, "assetLockTooManyInputs")
        XCTAssertEqual(record.detail, "too many inputs: 121 (max 100)")
    }

    func testAppErrorIsNamedByTypeAndCase() {
        let record = AssetLockFailureRecord.describe(AssetLockRecoveryService.RecoveryError.notReady)
        XCTAssertEqual(record.errorCase, "RecoveryError.notReady")
        XCTAssertEqual(record.detail, "Wallet is not ready")

        let bare = AssetLockFailureRecord.describe(
            AssetLockRecoveryService.RecoveryError.failed("Network unreachable"))
        XCTAssertEqual(bare.errorCase, "RecoveryError.failed")
        XCTAssertEqual(bare.detail, "Network unreachable")
    }

    /// A Swift struct error: its first mirror child is the stored property
    /// `code`, which is not a case name.
    private struct SampleStructError: LocalizedError {
        let code: Int
        var errorDescription: String? { "sample failure \(code)" }
    }

    func testNonEnumErrorsAreNamedByTheirTypeAlone() {
        let structError = AssetLockFailureRecord.describe(SampleStructError(code: 7))
        XCTAssertEqual(structError.errorCase, "SampleStructError")
        XCTAssertEqual(structError.detail, "sample failure 7")

        // An NSError's description is its whole domain/userInfo dump; it
        // belongs in the detail, never in the searchable case.
        let nsError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        let record = AssetLockFailureRecord.describe(nsError)
        XCTAssertEqual(record.errorCase, "NSError")
        XCTAssertEqual(record.detail, "The Internet connection appears to be offline.")
    }

    // MARK: failure store

    func testOutPointKeyMatchesThePersistentAssetLockForm() {
        // `PersistentAssetLock.outPointHex` is `<display hex>:<vout>`.
        XCTAssertEqual(AssetLockFailureStore.outPointKey(txidWire: txidWire, vout: 3), "\(txidDisplay):3")
    }

    func testRecordedFailureSurvivesANewStoreInstance() {
        let date = Date(timeIntervalSince1970: 1_761_782_400)
        AssetLockFailureStore(defaults: defaults).record(
            txidWire: txidWire, vout: 0,
            error: PlatformWalletError.assetLockTooManyInputs("too many inputs: 121 (max 100)"),
            at: date)

        // The summary reads it on a later launch, without re-running a retry.
        let reloaded = AssetLockFailureStore(defaults: defaults)
        let stored = reloaded.failure(txidWire: txidWire, vout: 0)
        XCTAssertEqual(stored?.errorCase, "assetLockTooManyInputs")
        XCTAssertEqual(stored?.recordedAt, date)
        XCTAssertEqual(reloaded.allFailures().keys.sorted(), ["\(txidDisplay):0"])
        XCTAssertNil(reloaded.failure(txidWire: txidWire, vout: 1))
    }

    func testLaterFailureReplacesTheEarlierOneForTheSameLock() {
        let store = AssetLockFailureStore(defaults: defaults)
        store.record(txidWire: txidWire, vout: 0, error: AssetLockRecoveryService.RecoveryError.notReady,
                     at: Date(timeIntervalSince1970: 1))
        store.record(txidWire: txidWire, vout: 0,
                     error: PlatformWalletError.assetLockTooManyInputs("too many inputs"),
                     at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(store.allFailures().count, 1)
        XCTAssertEqual(store.failure(txidWire: txidWire, vout: 0)?.errorCase, "assetLockTooManyInputs")
    }

    func testStoreKeepsOnlyTheNewestEntriesPastItsLimit() {
        let store = AssetLockFailureStore(defaults: defaults, limit: 3)
        for index in 0..<5 {
            store.record(
                AssetLockFailureRecord(errorCase: "unknown", detail: "\(index)",
                                       recordedAt: Date(timeIntervalSince1970: TimeInterval(index))),
                forOutPointKey: "lock\(index):0")
        }
        XCTAssertEqual(store.allFailures().keys.sorted(), ["lock2:0", "lock3:0", "lock4:0"])
        // The cap holds on disk too, not only in the cache.
        XCTAssertEqual(AssetLockFailureStore(defaults: defaults, limit: 3).allFailures().count, 3)
    }

    func testDefaultLimitCoversARestoredWalletsWorkingSet() {
        XCTAssertEqual(AssetLockFailureStore.defaultLimit, 50)
    }

    func testBoundedLeavesASmallMapUntouched() {
        let one = ["a:0": AssetLockFailureRecord(errorCase: "x", detail: "y", recordedAt: Date())]
        XCTAssertEqual(AssetLockFailureStore.bounded(one, limit: 50), one)
    }

    func testWipeForgetsEveryFailure() {
        let store = AssetLockFailureStore(defaults: defaults)
        store.record(txidWire: txidWire, vout: 0, error: AssetLockRecoveryService.RecoveryError.notReady)
        store.resetForWipe()
        XCTAssertTrue(store.allFailures().isEmpty)
        XCTAssertTrue(AssetLockFailureStore(defaults: defaults).allFailures().isEmpty)
    }

    // MARK: export content rule

    func testTrackedLocksAloneMakeAnExportWorthWriting() {
        // The support email attaches app logs loose, so with no SDK session
        // on disk the summary is the only thing its zip can carry.
        XCTAssertTrue(DiagnosticLogExporter.hasContentToExport(
            sessionCount: 0, appLogCount: 0, assetLocks: [record()]))
        XCTAssertTrue(DiagnosticLogExporter.hasContentToExport(
            sessionCount: 1, appLogCount: 0, assetLocks: nil))
        XCTAssertTrue(DiagnosticLogExporter.hasContentToExport(
            sessionCount: 0, appLogCount: 1, assetLocks: []))
    }

    func testNoLogsAndNoLocksIsStillNothingToExport() {
        XCTAssertFalse(DiagnosticLogExporter.hasContentToExport(
            sessionCount: 0, appLogCount: 0, assetLocks: []))
        XCTAssertFalse(DiagnosticLogExporter.hasContentToExport(
            sessionCount: 0, appLogCount: 0, assetLocks: nil))
    }

    // MARK: coordinator resume

    func testRefusalBeforeTheResumeCallIsRecordedAsTheLocksLastFailure() async {
        // A random outpoint has no SDK row, so whatever the test host's wallet
        // state, the resume stops before the PIN prompt: no manager/wallet, or
        // no drain-row identity for the lock.
        let store = AssetLockFailureStore(defaults: defaults)
        let coordinator = ShieldedTransferCoordinator(failureStore: store)
        let txid = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        await coordinator.resumeAssetLock(outPointTxidWire: txid, outPointVout: 7)

        guard case .failed = coordinator.phase, let reported = coordinator.lastFailure else {
            return XCTFail("expected a refused resume, got \(coordinator.phase)")
        }
        let recorded = store.failure(txidWire: txid, vout: 7)
        XCTAssertNotNil(recorded, "a refusal on the direct resume path left no last failure")
        XCTAssertEqual(recorded?.errorCase, AssetLockFailureRecord.describe(reported).errorCase)
    }

    // MARK: retry log line

    func testRetryLogLineCarriesTxidTypeStatusAndResult() {
        let line = AssetLockRetryLog.line(
            prefix: AssetLockRetryLog.lockRetryPrefix,
            event: "single",
            txidWire: txidWire,
            vout: 0,
            fundingTypeRaw: 5,
            statusBeforeRaw: 5,
            result: "FAILED case=assetLockTooManyInputs detail=too many inputs: 121 (max 100)")
        XCTAssertEqual(
            line,
            "🔁 LOCK-RETRY :: single txid=\(txidDisplay):0 "
                + "type=5 (assetLockShieldedAddressTopUp) statusBefore=5 (recoveredFromChain) "
                + "FAILED case=assetLockTooManyInputs detail=too many inputs: 121 (max 100)")
    }

    func testRetryLogLineSaysUnknownWhenTheStatusBeforeWasNotRead() {
        let line = AssetLockRetryLog.line(
            prefix: AssetLockRetryLog.shieldPrefix,
            event: "resume",
            txidWire: txidWire,
            vout: 1,
            fundingTypeRaw: 5,
            statusBeforeRaw: nil,
            result: "outcome=completed")
        XCTAssertTrue(line.hasPrefix("🛡️ SHIELD-TX :: resume txid=\(txidDisplay):1 "))
        XCTAssertTrue(line.contains("statusBefore=unknown outcome=completed"))
    }
}
