import Foundation
import SwiftDashSDK
import XCTest
@testable import dashwallet

final class DashPayWithdrawalStoreTests: XCTestCase {
    private var directory: URL!
    private var store: DashPayWithdrawalStore!
    private let contact = Data(repeating: 3, count: 32)
    private let scope = DashPayWithdrawalStore.Scope(
        networkRaw: 1, walletId: Data(repeating: 1, count: 32),
        ownerIdentityId: Data(repeating: 2, count: 32))

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = DashPayWithdrawalStore(directory: directory)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func begin(
        scope: DashPayWithdrawalStore.Scope? = nil,
        source: DashPayWithdrawalStore.Source = .shielded
    ) throws -> DashPayWithdrawalStore.Entry {
        try store.begin(
            scope: scope ?? self.scope, contactIdentityId: contact,
            address: "reserved-contact-address", amountDuffs: 10_000, source: source)
    }

    func testAttemptSurvivesRestartWithoutClaimingSubmissionSucceeded() throws {
        let entry = try begin()
        let reopened = DashPayWithdrawalStore(directory: directory)
        let entries = try reopened.entries(scope: scope, contactIdentityId: contact)
        XCTAssertEqual(entries, [entry])
        XCTAssertEqual(entries.first?.status, .submitting)
    }

    func testSubmittedAndUnconfirmedOutcomesStayDistinctAfterRestart() throws {
        let submitted = try begin(source: .platform)
        let uncertain = try begin()
        try store.update(submitted, status: .submitted)
        try store.update(uncertain, status: .unconfirmed)
        let reopened = DashPayWithdrawalStore(directory: directory)
        let entries = try reopened.entries(scope: scope, contactIdentityId: contact)
        XCTAssertEqual(entries.first(where: { $0.id == submitted.id })?.status, .submitted)
        XCTAssertEqual(entries.first(where: { $0.id == uncertain.id })?.status, .unconfirmed)
        XCTAssertEqual(entries.count, 2)
    }

    func testMaximumWithdrawalKeepsItsAmountEstimateAcrossRestart() throws {
        let estimated = try store.begin(
            scope: scope, contactIdentityId: contact, address: "reserved-contact-address",
            amountDuffs: 10_000, amountIsEstimate: true, source: .platform)
        try store.update(estimated, status: .submitted)
        let reopened = DashPayWithdrawalStore(directory: directory)
        let entry = try XCTUnwrap(reopened.entries(scope: scope, contactIdentityId: contact).first)
        XCTAssertTrue(entry.amountIsEstimate)
        XCTAssertEqual(entry.amountDuffs, 10_000)
    }

    func testNetworkWalletOwnerAndContactIsolation() throws {
        let original = try begin()
        let scopes = [
            DashPayWithdrawalStore.Scope(networkRaw: 0, walletId: scope.walletId,
                                         ownerIdentityId: scope.ownerIdentityId),
            DashPayWithdrawalStore.Scope(networkRaw: 1, walletId: Data(repeating: 8, count: 32),
                                         ownerIdentityId: scope.ownerIdentityId),
            DashPayWithdrawalStore.Scope(networkRaw: 1, walletId: scope.walletId,
                                         ownerIdentityId: Data(repeating: 9, count: 32)),
        ]
        for other in scopes {
            XCTAssertTrue(try store.entries(scope: other, contactIdentityId: contact).isEmpty)
            _ = try begin(scope: other)
        }
        XCTAssertTrue(try store.entries(scope: scope, contactIdentityId: Data(repeating: 4, count: 32)).isEmpty)
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact), [original])
    }

    func testFailedPersistencePreventsCreatingAnAttempt() throws {
        // A file where the journal directory belongs makes atomic persistence
        // fail, just like an inaccessible/full storage location at send time.
        try Data([1]).write(to: directory)
        XCTAssertThrowsError(try begin())
    }

    func testCorruptHistoryIsNotSilentlyOverwrittenByAnotherSend() throws {
        _ = try begin()
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil).first)
        let corrupt = Data("incomplete journal".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try begin())
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testWalletRemovalPreservesOtherWalletAndFullWipeRemovesAll() throws {
        _ = try begin()
        let other = DashPayWithdrawalStore.Scope(
            networkRaw: 1, walletId: Data(repeating: 8, count: 32),
            ownerIdentityId: scope.ownerIdentityId)
        let survivor = try begin(scope: other)
        try store.clearForWallet(walletId: scope.walletId)
        XCTAssertTrue(try store.entries(scope: scope, contactIdentityId: contact).isEmpty)
        XCTAssertEqual(try store.entries(scope: other, contactIdentityId: contact), [survivor])
        try store.resetForWipe()
        XCTAssertTrue(try store.entries(scope: other, contactIdentityId: contact).isEmpty)
    }

    func testNeverSubmittedAttemptCanBeRemovedWithoutDroppingOtherRecords() throws {
        let aborted = try begin()
        let survivor = try begin()
        try store.remove(aborted)
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact), [survivor])
        XCTAssertThrowsError(try store.update(aborted, status: .submitted))
    }

    // MARK: - Restart-proof contact lock

    private var lockWindowStart: Date { Date().addingTimeInterval(-24 * 60 * 60) }

    /// The `.unconfirmed` update after an ambiguous failure is best-effort:
    /// the `.submitting` record written before submission must lock on its own.
    func testSubmittingRecordAloneLocksAfterRestart() throws {
        _ = try begin()
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertTrue(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    func testUnconfirmedRecordLocks() throws {
        try store.update(try begin(), status: .unconfirmed)
        XCTAssertTrue(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    func testSubmittedRecordDoesNotLock() throws {
        try store.update(try begin(), status: .submitted)
        XCTAssertFalse(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    /// A definite non-submission drops its record, so the retry is not locked.
    func testRemovedRecordDoesNotLock() throws {
        try store.remove(try begin())
        XCTAssertFalse(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    func testUnresolvedRecordOutsideWindowDoesNotLock() throws {
        _ = try begin()
        XCTAssertFalse(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: Date().addingTimeInterval(60)))
    }

    func testUnresolvedRecordLocksOnlyItsContact() throws {
        _ = try begin()
        XCTAssertFalse(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: Data(repeating: 9, count: 32), since: lockWindowStart))
    }

    /// Callers treat a throw as locked (fail closed), so it must not read as empty.
    func testUnreadableJournalThrowsRatherThanReportingNoLock() throws {
        _ = try begin()
        let file = try XCTUnwrap(FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("not json".utf8).write(to: file)
        XCTAssertThrowsError(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    func testInaccessibleJournalDirectoryThrowsRatherThanReportingNoLock() throws {
        _ = try begin()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }
        XCTAssertThrowsError(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    func testMissingJournalReportsNoLock() throws {
        XCTAssertFalse(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    // MARK: - Which failures prove a withdrawal never left

    @MainActor
    func testDefiniteFailuresAllowRetry() {
        let definite: [Error] = [
            PlatformAddressSyncCoordinator.SendError.coordinatorNotReady,
            PlatformAddressSyncCoordinator.SendError.noFundedAddress,
            PlatformWalletError.shieldedNoRecordedAnchor("mid-block"),
            PlatformWalletError.shieldedBroadcastFailed("rejected"),
            PlatformWalletError.shieldedInsufficientBalance("short"),
        ]
        for error in definite {
            XCTAssertTrue(ShieldedTransferCoordinator.provesWithdrawalNotSubmitted(error), "\(error)")
        }
    }

    @MainActor
    func testAmbiguousFailuresStayUnknown() {
        let ambiguous: [Error] = [
            PlatformWalletError.shieldedSpendUnconfirmed("timeout"),
            PlatformWalletError.transactionBroadcastUnconfirmed("timeout"),
            PlatformWalletError.walletOperation("unexpected"),
            URLError(.timedOut),
        ]
        for error in ambiguous {
            XCTAssertFalse(ShieldedTransferCoordinator.provesWithdrawalNotSubmitted(error), "\(error)")
        }
    }
}
