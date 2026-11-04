import XCTest
import SwiftData
import SwiftDashSDK
@testable import dashpay

#if targetEnvironment(simulator)
@MainActor
final class ShieldedWithdrawalHistoryTests: XCTestCase {
    /// Every fixture exercises the real store in its own removable defaults domain.
    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "shielded-history-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func fixture() throws -> ShieldedWithdrawalHistoryFixture {
        try ShieldedWithdrawalHistoryFixture(
            container: ShieldedWithdrawalHistoryFixture.makeContainer(),
            withdrawalStore: ShieldedWithdrawalStore(defaults: isolatedDefaults()))
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
            XCTAssertEqual(item.title, "Internal Transfer")
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
            XCTAssertEqual(fixture.items.count, 1)
            XCTAssertEqual(fixture.items.first?.status, .failed)
            XCTAssertFalse(fixture.destinationTagged, "A failed withdrawal cannot identify a future receipt as its payout")
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

    func testPendingToFailedRetractsDestinationTagForLiveAndRestoredWithdrawals() throws {
        for kind in [5, 7] {
            let fixture = try fixture()
            try fixture.insertActivity(id: 1, kind: kind)
            XCTAssertTrue(fixture.destinationTagged)
            try fixture.setStatus(2)
            XCTAssertFalse(fixture.destinationTagged)
            try fixture.insertReceipt()
            XCTAssertFalse(fixture.destinationTagged, "An unrelated receipt must not revive a rejected withdrawal's tag")
            XCTAssertEqual(fixture.items.first?.status, .failed)
        }
    }

    func testNonFailedAttemptSharingDestinationKeepsItsTag() throws {
        for kind in [5, 7] {
            for otherStatus in [0, 1] {
                let fixture = try fixture()
                try fixture.insertActivity(id: 1, kind: kind)
                try fixture.insertActivity(id: 2, status: otherStatus, amount: 5_000_000_000)
                try fixture.setStatus(2)
                XCTAssertTrue(fixture.destinationTagged)
                try fixture.insertReceipt()
                XCTAssertTrue(fixture.destinationTagged)
                XCTAssertEqual(fixture.items.count, 1)
                XCTAssertEqual(fixture.items.first?.status, .failed)
            }
        }
    }

    func testReconciliationPreservesUnobservedTagsAndOtherWallets() throws {
        let defaults = try isolatedDefaults()
        let store = ShieldedWithdrawalStore(defaults: defaults)
        let wallet = ShieldedWithdrawalHistoryFixture.walletIdHex
        let otherWallet = String(repeating: "72", count: 32)
        let address = ShieldedWithdrawalHistoryFixture.address
        store.reconcile(walletIdHex: wallet, failed: [], nonFailed: ["unobserved-destination"])
        store.reconcile(walletIdHex: otherWallet, failed: [], nonFailed: [address])
        let fixture = try ShieldedWithdrawalHistoryFixture(
            container: ShieldedWithdrawalHistoryFixture.makeContainer(), withdrawalStore: store)
        try fixture.insertActivity(id: 1)
        XCTAssertTrue(store.contains(address, walletIdHex: wallet))
        try fixture.setStatus(2)
        // A new instance checks persisted defaults, not only the first store's cache.
        let reopenedStore = ShieldedWithdrawalStore(defaults: defaults)
        XCTAssertFalse(reopenedStore.contains(address, walletIdHex: wallet))
        XCTAssertTrue(reopenedStore.contains("unobserved-destination", walletIdHex: wallet))
        XCTAssertTrue(reopenedStore.contains(address, walletIdHex: otherWallet))
        XCTAssertFalse(reopenedStore.contains("unobserved-destination", walletIdHex: otherWallet))
    }

    func testExternalWithdrawalAndPlatformUnshieldKeepFailureStatus() throws {
        let fixture = try fixture()
        let externalScript = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0x45), count: 20) + [0x88, 0xac])
        try fixture.insertActivity(id: 1, status: 2, counterparty: externalScript)
        try fixture.insertActivity(id: 2, kind: 4, status: 2, counterparty: Data([0] + Array(repeating: UInt8(0x45), count: 20)))
        XCTAssertEqual(fixture.items.count, 2)
        XCTAssertTrue(fixture.items.allSatisfy { $0.status == .failed && !$0.isAwaitingTransparentReceipt })
        XCTAssertEqual(fixture.items.first?.isExternalDestination, true)
        XCTAssertEqual(fixture.items.first?.title, "Sent")
    }

    func testUnknownAndUnrecognizedStatusNeverClaimConfirmationOrAwaitingReceipt() throws {
        for kind in [3, 5, 7] {
            for status in [3, 99] {
                let fixture = try fixture()
                let row = try fixture.insertActivity(id: 1, kind: kind, status: status)
                let item = ShieldedActivityItem(row: row, isAwaitingTransparentReceipt: true)
                XCTAssertEqual(item.status, .unknown)
                XCTAssertEqual(item.trailingStatusText, "Unknown")
                XCTAssertFalse(item.isAwaitingTransparentReceipt)
                XCTAssertEqual(fixture.items.first?.status, .unknown)
                XCTAssertEqual(fixture.items.first?.trailingStatusText, "Unknown")
            }
        }
    }

    func testUnknownOwnWithdrawalRetainsDestinationTagAndCanMatchReceipt() throws {
        for kind in [5, 7] {
            for status in [3, 99] {
                let fixture = try fixture()
                try fixture.insertActivity(id: 1, kind: kind, status: status)
                let item = try XCTUnwrap(fixture.items.first)
                XCTAssertEqual(item.status, .unknown)
                XCTAssertFalse(item.isAwaitingTransparentReceipt)
                XCTAssertEqual(item.title, "Internal Transfer")
                XCTAssertTrue(fixture.destinationTagged)
                try fixture.insertReceipt()
                XCTAssertTrue(fixture.items.isEmpty)
                XCTAssertTrue(fixture.destinationTagged)
            }
        }
    }

    func testSDKCorrectionFromFailedToConfirmedRestoresReceiptMatching() throws {
        for kind in [5, 7] {
            let fixture = try fixture()
            let row = try fixture.insertActivity(id: 1, kind: kind, status: 2)
            XCTAssertEqual(fixture.items.first?.status, .failed)
            XCTAssertFalse(fixture.destinationTagged)
            // A scan can correct a height-less Failed row after observing its
            // commitments on chain. Persist the corrected SDK snapshot directly.
            row.status = 1
            row.hasBlockHeight = true
            row.blockHeight = 100
            try fixture.container.mainContext.save()
            try fixture.reload()
            XCTAssertEqual(fixture.items.first?.entryId, row.entryId)
            XCTAssertEqual(fixture.items.first?.blockHeight, 100)
            XCTAssertEqual(fixture.items.first?.status, .pending)
            XCTAssertEqual(fixture.items.first?.isAwaitingTransparentReceipt, true)
            XCTAssertTrue(fixture.destinationTagged)
            try fixture.insertReceipt()
            XCTAssertTrue(fixture.items.isEmpty)
            XCTAssertTrue(fixture.destinationTagged)
        }
    }

    func testSavedFailureSurvivesStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        let defaults = try isolatedDefaults()
        do {
            let fixture = try ShieldedWithdrawalHistoryFixture(
                container: ShieldedWithdrawalHistoryFixture.makeContainer(url: url),
                withdrawalStore: ShieldedWithdrawalStore(defaults: defaults))
            let row = try fixture.insertActivity(id: 1)
            XCTAssertTrue(fixture.destinationTagged)
            // Simulate termination after the SDK persists Failed but before a
            // history refresh retracts the previous Pending destination tag.
            row.status = 2
            try fixture.container.mainContext.save()
            XCTAssertTrue(fixture.withdrawalStore.contains(
                ShieldedWithdrawalHistoryFixture.address, walletIdHex: ShieldedWithdrawalHistoryFixture.walletIdHex))
        }
        let reopened = try ShieldedWithdrawalHistoryFixture(
                container: ShieldedWithdrawalHistoryFixture.makeContainer(url: url),
                withdrawalStore: ShieldedWithdrawalStore(defaults: defaults))
        XCTAssertEqual(reopened.items.count, 1)
        XCTAssertEqual(reopened.items.first?.status, .failed)
        XCTAssertEqual(reopened.balance, ShieldedWithdrawalHistoryFixture.originalCredits)
        XCTAssertFalse(reopened.destinationTagged)
    }
}
#endif
