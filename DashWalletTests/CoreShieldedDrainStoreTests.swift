import Foundation
import XCTest
#if canImport(dashpay)
@testable import dashpay
#else
@testable import CoreDrainHarness
#endif

final class CoreShieldedDrainStoreTests: XCTestCase {
    private var directory: URL!
    private var store: CoreShieldedDrainFileStore!
    private let context = CoreShieldedDrainContext(walletId: Data(repeating: 7, count: 32), networkScope: "testnet")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = CoreShieldedDrainFileStore(directory: directory)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func testMarkerSurvivesReopeningUntilExactOperationIsRemoved() throws {
        let operation = CoreShieldedDrainOperation(id: UUID(), context: context)
        XCTAssertNil(try store.load(context))
        try store.save(operation)
        let reopened = CoreShieldedDrainFileStore(directory: directory)
        XCTAssertEqual(try reopened.load(context), operation)
        try reopened.save(operation)
        try reopened.remove(operation)
        XCTAssertNil(try store.load(context))
    }
    func testAnotherUUIDCannotOverwriteOrClearPendingTransfer() throws {
        let pending = CoreShieldedDrainOperation(id: UUID(), context: context)
        let another = CoreShieldedDrainOperation(id: UUID(), context: context)
        try store.save(pending)
        XCTAssertThrowsError(try store.save(another))
        XCTAssertThrowsError(try store.remove(another))
        XCTAssertEqual(try store.load(context), pending)
    }
    func testNetworkAndWalletIsolationIncludingDevnetNames() throws {
        let otherNetwork = CoreShieldedDrainContext(walletId: context.walletId, networkScope: "devnet/../a")
        let otherWallet = CoreShieldedDrainContext(walletId: Data(repeating: 8, count: 32), networkScope: context.networkScope)
        let original = CoreShieldedDrainOperation(id: UUID(), context: context)
        let networkOperation = CoreShieldedDrainOperation(id: UUID(), context: otherNetwork)
        let walletOperation = CoreShieldedDrainOperation(id: UUID(), context: otherWallet)
        for operation in [original, networkOperation, walletOperation] { try store.save(operation) }
        XCTAssertEqual(try store.load(otherNetwork), networkOperation)
        try store.clear(walletId: context.walletId)
        XCTAssertNil(try store.load(context))
        XCTAssertNil(try store.load(otherNetwork))
        XCTAssertEqual(try store.load(otherWallet), walletOperation)
        try store.clear()
        XCTAssertNil(try store.load(otherWallet))
    }
    func testCorruptionIsAnErrorAndCannotBeOverwrittenAsAbsent() throws {
        let operation = CoreShieldedDrainOperation(id: UUID(), context: context)
        try store.save(operation)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try Data("invalid".utf8).write(to: XCTUnwrap(files.first))
        XCTAssertThrowsError(try store.load(context))
        XCTAssertThrowsError(try store.save(operation))
        XCTAssertThrowsError(try store.remove(operation))
    }
    func testStorageFailureCannotReportSuccessfulPreparation() throws {
        try Data().write(to: directory)
        XCTAssertThrowsError(try store.save(CoreShieldedDrainOperation(id: UUID(), context: context)))
    }
    func testSaveFlushesMarkerAndDirectoryAncestorsBeforeReturning() throws {
        let nested = directory.appendingPathComponent("new-parent/markers", isDirectory: true)
        var flushed: [URL] = []
        let store = CoreShieldedDrainFileStore(directory: nested) { url in
            // Exercise the real barrier, recording only successfully flushed paths.
            try DurableFileStorage.flush(url)
            flushed.append(url.standardizedFileURL)
        }
        try store.save(CoreShieldedDrainOperation(id: UUID(), context: context))
        XCTAssertEqual(flushed.first?.pathExtension, "json")
        XCTAssertEqual(Array(flushed.dropFirst().prefix(3)), [nested, nested.deletingLastPathComponent(), directory!].map(\.standardizedFileURL))
    }

    func testEveryDurabilityFailurePreventsDispatchAndRetryKeepsSameUUID() throws {
        enum Failure: Error { case flush }
        let operation = CoreShieldedDrainOperation(id: UUID(), context: context)
        // File, containing directory, and newly-created directory's parent.
        for failureIndex in 0..<3 {
            var calls = 0
            let failing = CoreShieldedDrainFileStore(directory: directory) { _ in
                defer { calls += 1 }
                if calls == failureIndex { throw Failure.flush }
            }
            var dispatched = false
            XCTAssertThrowsError(try { try failing.save(operation); dispatched = true }())
            XCTAssertFalse(dispatched)
            XCTAssertEqual(try store.load(context), operation)
            try store.save(operation)
            XCTAssertEqual(try store.load(context), operation)
        }
    }

    // MARK: - Recipient codec

    private var externalRaw43: Data { Data((0..<43).map { UInt8($0) }) }

    /// Written before the recipient existed, by the own-wallet Max alone.
    private func legacyMarkerJSON(id: UUID) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString,
            "context": ["walletId": context.walletId.base64EncodedString(), "networkScope": context.networkScope],
        ])
    }

    func testMarkerWrittenBeforeRecipientsDecodesAsOwnWallet() throws {
        let id = UUID()
        let decoded = try JSONDecoder().decode(CoreShieldedDrainOperation.self, from: legacyMarkerJSON(id: id))
        XCTAssertEqual(decoded, CoreShieldedDrainOperation(id: id, context: context, recipient: .ownWallet))
        XCTAssertNil(decoded.recipient.externalRaw43)
    }

    func testExternalRecipientSurvivesTheStoreRoundTrip() throws {
        let operation = CoreShieldedDrainOperation(id: UUID(), context: context, recipient: .external(raw43: externalRaw43))
        try store.save(operation)
        let reopened = try CoreShieldedDrainFileStore(directory: directory).load(context)
        XCTAssertEqual(reopened, operation)
        XCTAssertEqual(reopened?.recipient.externalRaw43, externalRaw43)
        let own = CoreShieldedDrainOperation(id: UUID(), context: context)
        try store.remove(operation)
        try store.save(own)
        XCTAssertEqual(try CoreShieldedDrainFileStore(directory: directory).load(context)?.recipient, .ownWallet)
    }

    func testExternalRecipientOfTheWrongSizeIsCorruption() throws {
        let operation = CoreShieldedDrainOperation(id: UUID(), context: context, recipient: .external(raw43: externalRaw43))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(operation)) as! [String: Any]
        json["recipientRaw43"] = externalRaw43.dropLast().base64EncodedString()
        let truncated = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try JSONDecoder().decode(CoreShieldedDrainOperation.self, from: truncated))
        json.removeValue(forKey: "recipientRaw43")
        let missing = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try JSONDecoder().decode(CoreShieldedDrainOperation.self, from: missing))
    }

    func testInconsistentRecipientKeysAreCorruptionNotOwnWallet() throws {
        let id = UUID()
        var json = try JSONSerialization.jsonObject(with: legacyMarkerJSON(id: id)) as! [String: Any]
        // A payload with no kind: a partially written or edited external marker.
        json["recipientRaw43"] = externalRaw43.base64EncodedString()
        XCTAssertThrowsError(try JSONDecoder().decode(
            CoreShieldedDrainOperation.self, from: JSONSerialization.data(withJSONObject: json)))
        // An own kind carrying a payload.
        json["recipientKind"] = "own"
        XCTAssertThrowsError(try JSONDecoder().decode(
            CoreShieldedDrainOperation.self, from: JSONSerialization.data(withJSONObject: json)))
        // An unknown kind.
        json["recipientKind"] = "someone"
        XCTAssertThrowsError(try JSONDecoder().decode(
            CoreShieldedDrainOperation.self, from: JSONSerialization.data(withJSONObject: json)))
        // Explicit nulls are present keys without a value, not the legacy absence.
        json["recipientKind"] = NSNull()
        json["recipientRaw43"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(
            CoreShieldedDrainOperation.self, from: JSONSerialization.data(withJSONObject: json)))
        json.removeValue(forKey: "recipientKind")
        XCTAssertThrowsError(try JSONDecoder().decode(
            CoreShieldedDrainOperation.self, from: JSONSerialization.data(withJSONObject: json)))
        // The two consistent own-wallet spellings still decode.
        json.removeValue(forKey: "recipientRaw43")
        json["recipientKind"] = "own"
        XCTAssertEqual(
            try JSONDecoder().decode(CoreShieldedDrainOperation.self, from: JSONSerialization.data(withJSONObject: json)),
            CoreShieldedDrainOperation(id: id, context: context))
    }

    func testSameUUIDWithAnotherRecipientIsAnotherOperation() throws {
        let id = UUID()
        let external = CoreShieldedDrainOperation(id: id, context: context, recipient: .external(raw43: externalRaw43))
        let own = CoreShieldedDrainOperation(id: id, context: context)
        try store.save(external)
        XCTAssertThrowsError(try store.save(own))
        XCTAssertThrowsError(try store.remove(own))
        XCTAssertEqual(try store.load(context), external)
    }

    func testOperationIdBytesRoundTrip() {
        let id = UUID()
        XCTAssertEqual(UUID(drainOperationIdBytes: withUnsafeBytes(of: id.uuid) { Data($0) }), id)
        XCTAssertNil(UUID(drainOperationIdBytes: Data(repeating: 0, count: 15)))
    }

    @MainActor
    func testFailedConfiguredDevnetDeletionKeepsItsMarkerAfterExtraScopeSucceeds() throws {
        try checkPartialDevnetDeletion(extraScopeFails: false)
    }

    @MainActor
    func testFailedExtraDevnetDeletionKeepsItsMarkerAfterConfiguredScopeSucceeds() throws {
        try checkPartialDevnetDeletion(extraScopeFails: true)
    }

    @MainActor
    private func checkPartialDevnetDeletion(extraScopeFails: Bool) throws {
        enum DeletionFailure: Error { case unavailable }
        let walletId = context.walletId
        let a = CoreShieldedDrainContext(walletId: walletId, networkScope: "devnet-a")
        let b = CoreShieldedDrainContext(walletId: walletId, networkScope: "devnet-b")
        let other = CoreShieldedDrainContext(walletId: Data([99]), networkScope: "devnet-b")
        let operations = [a, b, other].map { CoreShieldedDrainOperation(id: UUID(), context: $0) }
        for operation in operations { try store.save(operation) }
        var remainingScopes = Set([a.networkScope, b.networkScope])

        // Match the full wipe's order: extra scope first, configured scope
        // second, continuing even after a failure in the first scope.
        for (scope, fails, extra) in [(a, extraScopeFails, true), (b, !extraScopeFails, false)] {
            let delete = {
                try SwiftDashSDKWalletWiper.deleteWalletFromSDK(
                    walletId,
                    deleteWallet: { _ in
                        if fails { throw DeletionFailure.unavailable }
                        remainingScopes.remove(scope.networkScope)
                    }, keepsWalletOnAnotherScope: extra, scope: scope.networkScope, drainStore: self.store)
            }
            if fails { XCTAssertThrowsError(try delete()) }
            else { XCTAssertNoThrow(try delete()) }
        }

        let reopened = CoreShieldedDrainFileStore(directory: directory)
        let failedIndex = extraScopeFails ? 0 : 1
        let failed = operations[failedIndex]
        let succeeded = operations[1 - failedIndex]
        XCTAssertEqual(remainingScopes, [failed.context.networkScope])
        XCTAssertEqual(try reopened.load(failed.context), failed)
        XCTAssertNil(try reopened.load(succeeded.context))
        XCTAssertEqual(try reopened.load(other), operations[2])

        // A retry only clears the scope that has now been deleted. Repeating
        // cleanup is harmless, and another wallet's marker remains intact.
        for _ in 0..<2 {
            try SwiftDashSDKWalletWiper.deleteWalletFromSDK(
                walletId,
                deleteWallet: { _ in remainingScopes.remove(failed.context.networkScope) },
                keepsWalletOnAnotherScope: extraScopeFails, scope: failed.context.networkScope,
                drainStore: reopened)
        }
        XCTAssertTrue(remainingScopes.isEmpty)
        XCTAssertNil(try reopened.load(a))
        XCTAssertNil(try reopened.load(b))
        XCTAssertEqual(try reopened.load(other), operations[2])
    }

}
