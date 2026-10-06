import Foundation
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
}
