import XCTest
import SwiftData
import SwiftDashSDK
@testable import dashpay

#if targetEnvironment(simulator)
@MainActor
final class ShieldedWithdrawalHistoryTests: XCTestCase {
    private func fixture() throws -> ShieldedWithdrawalHistoryFixture {
        try ShieldedWithdrawalHistoryFixture(container: ShieldedWithdrawalHistoryFixture.makeContainer())
    }

    func testFailedWithdrawalNeverAwaitsReceiptEvenWhenCallerRequestsIt() throws {
        let fixture = try fixture()
        let row = try fixture.insertActivity(id: 1, status: 2)
        let item = ShieldedActivityItem(row: row, isAwaitingTransparentReceipt: true)
        XCTAssertEqual(item.status, .failed)
        XCTAssertFalse(item.isAwaitingTransparentReceipt)
        XCTAssertEqual(item.trailingStatusText, "Failed")
    }

    func testFailedLiveAndRestoredWithdrawalsRemainVisibleWithoutReceipt() throws {
        for kind in [5, 7] {
            let fixture = try fixture()
            try fixture.insertActivity(id: 1, kind: kind, status: 2)
            let item = try XCTUnwrap(fixture.items.first)
            XCTAssertEqual(fixture.items.count, 1)
            XCTAssertEqual(item.kind, .withdrawal)
            XCTAssertEqual(item.status, .failed)
            XCTAssertFalse(item.isAwaitingTransparentReceipt)
            XCTAssertEqual(fixture.balance, ShieldedWithdrawalHistoryFixture.originalCredits)
        }
    }

    func testLaterReceiptCannotHideFailedAttemptOrTagItsDestination() throws {
        for kind in [5, 7] {
            let fixture = try fixture()
            try fixture.insertActivity(id: 1, kind: kind, status: 2)
            try fixture.insertReceipt()
            let context = fixture.container.mainContext
            let receipts = try context.fetch(FetchDescriptor<PersistentTransaction>())
                .map { Transaction(persistentTransaction: $0, walletId: ShieldedWithdrawalHistoryFixture.walletId) }
            var tags: [String] = []
            let items = SwiftDashSDKWalletSource.fetchShieldedActivity(
                container: fixture.container, walletId: ShieldedWithdrawalHistoryFixture.walletId,
                coreTransactions: receipts, recordWithdrawalDestination: { tags.append($0) })
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.status, .failed)
            XCTAssertTrue(tags.isEmpty, "A failed withdrawal cannot identify a future receipt as its payout")
        }
    }

    func testFailedAttemptAndSmallerSuccessfulAttemptToSameAddressStayDistinct() throws {
        let fixture = try fixture()
        try fixture.insertActivity(id: 1, status: 2)
        try fixture.insertActivity(id: 2, status: 1, amount: 5_000_000_000)
        XCTAssertEqual(fixture.items.count, 2)
        try fixture.insertReceipt()
        XCTAssertEqual(fixture.items.count, 1)
        XCTAssertEqual(fixture.items.first?.entryId, Data(repeating: 1, count: 32))
        XCTAssertEqual(fixture.items.first?.status, .failed)
        XCTAssertEqual(fixture.receiptCount, 1)
    }

    func testPendingAndConfirmedOwnWithdrawalsWaitForCoreReceipt() throws {
        for kind in [5, 7] {
            for status in [0, 1] {
                let fixture = try fixture()
                try fixture.insertActivity(id: 1, kind: kind, status: status)
                XCTAssertEqual(fixture.items.first?.status, .pending)
                XCTAssertEqual(fixture.items.first?.isAwaitingTransparentReceipt, true)
                try fixture.insertReceipt()
                XCTAssertTrue(fixture.items.isEmpty)
            }
        }
    }

    func testPendingToFailedTransitionIsReadFromSavedActivity() throws {
        let fixture = try fixture()
        try fixture.insertActivity(id: 1)
        XCTAssertEqual(fixture.items.first?.status, .pending)
        try fixture.setStatus(2)
        XCTAssertEqual(fixture.items.first?.status, .failed)
        XCTAssertEqual(fixture.balance, ShieldedWithdrawalHistoryFixture.originalCredits)
        XCTAssertEqual(fixture.receiptCount, 0)
    }

    func testExternalWithdrawalAndPlatformUnshieldKeepFailureStatus() throws {
        let fixture = try fixture()
        let externalScript = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0x45), count: 20) + [0x88, 0xac])
        try fixture.insertActivity(id: 1, status: 2, counterparty: externalScript)
        try fixture.insertActivity(id: 2, kind: 4, status: 2, counterparty: Data([0] + Array(repeating: UInt8(0x45), count: 20)))
        XCTAssertEqual(fixture.items.count, 2)
        XCTAssertTrue(fixture.items.allSatisfy { $0.status == .failed && !$0.isAwaitingTransparentReceipt })
        XCTAssertEqual(fixture.items.first?.isExternalDestination, true)
    }

    func testSavedFailureSurvivesStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        do {
            let fixture = try ShieldedWithdrawalHistoryFixture(container: ShieldedWithdrawalHistoryFixture.makeContainer(url: url))
            try fixture.insertActivity(id: 1)
            try fixture.setStatus(2)
        }
        let reopened = try ShieldedWithdrawalHistoryFixture(container: ShieldedWithdrawalHistoryFixture.makeContainer(url: url))
        XCTAssertEqual(reopened.items.count, 1)
        XCTAssertEqual(reopened.items.first?.status, .failed)
        XCTAssertEqual(reopened.balance, ShieldedWithdrawalHistoryFixture.originalCredits)
    }
}
#endif
