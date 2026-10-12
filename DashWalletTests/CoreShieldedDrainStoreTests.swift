import Foundation
import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
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
}
