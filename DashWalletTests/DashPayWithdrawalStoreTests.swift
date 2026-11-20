import Foundation
import SwiftDashSDK
import SwiftData
import XCTest
@testable import dashpay

final class DashPayWithdrawalStoreTests: XCTestCase {
    private var directory: URL!
    private var store: DashPayWithdrawalStore!
    /// Fresh per test: an unknown outcome is remembered process-wide.
    private let contact = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
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

    /// A journal whose directory can't be inspected is not mistaken for an
    /// absent one: clearing it fails, so neither a removal nor a wipe reports
    /// success while its records survive.
    func testClearingAJournalThatCannotBeInspectedThrows() throws {
        let parent = directory!
        let nested = DashPayWithdrawalStore(directory: parent.appendingPathComponent("journal"))
        _ = try nested.begin(
            scope: scope, contactIdentityId: contact, address: "yAddress",
            amountDuffs: 1_000, source: .shielded)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: parent.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        }
        XCTAssertThrowsError(try nested.files(ofWallet: scope.walletId))
        XCTAssertThrowsError(try nested.clearForWallet(walletId: scope.walletId))
        XCTAssertThrowsError(try nested.resetForWipe())
    }

    /// A deletion that fails leaves the records where they are read, and the
    /// clear or wipe throws, so neither reports success while they survive.
    func testFailedDeletionKeepsRecordsReadableAndThrows() throws {
        struct RemovalFailed: Error {}
        let journal = directory.appendingPathComponent("journal")
        let failing = DashPayWithdrawalStore(directory: journal, removeItem: { _ in throw RemovalFailed() })
        let entry = try failing.begin(
            scope: scope, contactIdentityId: contact, address: "yAddress",
            amountDuffs: 1_000, source: .shielded)
        let since = Date.distantPast

        XCTAssertThrowsError(try failing.clearForWallet(walletId: scope.walletId)) {
            XCTAssertTrue($0 is RemovalFailed, "\($0)")
        }
        XCTAssertEqual(try failing.entries(scope: scope, contactIdentityId: contact), [entry])
        XCTAssertTrue(try failing.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: since))

        XCTAssertThrowsError(try failing.resetForWipe()) {
            XCTAssertTrue($0 is RemovalFailed, "\($0)")
        }
        XCTAssertEqual(try failing.entries(scope: scope, contactIdentityId: contact), [entry])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["journal"])

        let working = DashPayWithdrawalStore(directory: journal)
        try working.resetForWipe()
        XCTAssertTrue(try working.entries(scope: scope, contactIdentityId: contact).isEmpty)
    }

    /// A deletion failing with "no such file" is still a failure, not a
    /// journal that was never created.
    func testWipeWhoseDeletionFindsAFileMissingThrows() throws {
        let journal = directory.appendingPathComponent("journal")
        let failing = DashPayWithdrawalStore(
            directory: journal, removeItem: { _ in throw CocoaError(.fileNoSuchFile) })
        let entry = try failing.begin(
            scope: scope, contactIdentityId: contact, address: "yAddress",
            amountDuffs: 1_000, source: .shielded)

        XCTAssertThrowsError(try failing.resetForWipe())
        XCTAssertEqual(try failing.entries(scope: scope, contactIdentityId: contact), [entry])
    }

    /// A retired copy the sweep cannot delete fails the clear and the wipe:
    /// its records would otherwise survive both.
    func testUndeletableRetiredCopyFailsTheClearAndTheWipe() throws {
        struct RemovalFailed: Error {}
        let journal = directory.appendingPathComponent("journal")
        let failing = DashPayWithdrawalStore(directory: journal, removeItem: { _ in throw RemovalFailed() })
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".journal-retired-left-by-a-crash"),
            withIntermediateDirectories: true)

        XCTAssertThrowsError(try failing.clearForWallet(walletId: scope.walletId)) {
            XCTAssertTrue($0 is RemovalFailed, "\($0)")
        }
        XCTAssertThrowsError(try failing.resetForWipe()) {
            XCTAssertTrue($0 is RemovalFailed, "\($0)")
        }
        try DashPayWithdrawalStore(directory: journal).resetForWipe()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    /// A clear interrupted after staging some files leaves their records
    /// counted, and the next clear retires them with the rest.
    func testInterruptedClearKeepsLocksUntilTheNextClearRetiresThem() throws {
        let pending = try begin()
        try store.update(pending, status: .unconfirmed)
        let live = try XCTUnwrap(try store.files(ofWallet: scope.walletId).first)
        let staging = directory.appendingPathComponent(
            ".clearing-" + scope.walletId.map { String(format: "%02x", $0) }.joined(), isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: live, to: staging.appendingPathComponent(live.lastPathComponent))

        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertTrue(try reopened.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
        try reopened.clearForWallet(walletId: scope.walletId)
        XCTAssertFalse(try reopened.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    /// A payment journaled after an interrupted clear lands in the live
    /// file, which the next clear retires with the staged copy.
    func testRecordWrittenAfterAnInterruptedClearIsRetiredWithIt() throws {
        _ = try begin()
        let live = try XCTUnwrap(try store.files(ofWallet: scope.walletId).first)
        let staging = directory.appendingPathComponent(
            ".clearing-" + scope.walletId.map { String(format: "%02x", $0) }.joined(), isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: live, to: staging.appendingPathComponent(live.lastPathComponent))
        _ = try begin()
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact).count, 2)
        try store.clearForWallet(walletId: scope.walletId)
        XCTAssertTrue(try store.entries(scope: scope, contactIdentityId: contact).isEmpty)
    }

    /// A logical wallet's ids, one per network, are cleared together; other
    /// wallets keep their records.
    func testClearingSeveralWalletsTogetherKeepsOthers() throws {
        let testnet = DashPayWithdrawalStore.Scope(
            networkRaw: 1, walletId: Data(repeating: 1, count: 32), ownerIdentityId: scope.ownerIdentityId)
        let mainnet = DashPayWithdrawalStore.Scope(
            networkRaw: 0, walletId: Data(repeating: 5, count: 32), ownerIdentityId: scope.ownerIdentityId)
        let other = DashPayWithdrawalStore.Scope(
            networkRaw: 1, walletId: Data(repeating: 8, count: 32), ownerIdentityId: scope.ownerIdentityId)
        _ = try begin(scope: testnet)
        _ = try begin(scope: mainnet)
        let survivor = try begin(scope: other)
        try store.clearForWallets(walletIds: [testnet.walletId, mainnet.walletId])
        XCTAssertTrue(try store.entries(scope: testnet, contactIdentityId: contact).isEmpty)
        XCTAssertTrue(try store.entries(scope: mainnet, contactIdentityId: contact).isEmpty)
        XCTAssertEqual(try store.entries(scope: other, contactIdentityId: contact), [survivor])
    }

    func testClearingAnAbsentJournalSucceeds() throws {
        XCTAssertEqual(try store.files(ofWallet: scope.walletId), [])
        try store.clearForWallet(walletId: scope.walletId)
        try store.resetForWipe()
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

    func testRemovedRecordDoesNotLock() throws {
        try store.remove(try begin())
        XCTAssertFalse(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart))
    }

    func testUnresolvedPlatformRecordOutsideWindowDoesNotLock() throws {
        _ = try begin(source: .platform)
        XCTAssertFalse(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: Date().addingTimeInterval(60)))
    }

    /// The SDK keeps the signed Shielded spend and re-broadcasts it on later
    /// syncs whatever the device clock says, so age alone never unlocks it.
    func testAgedShieldedRecordLocksUntilTheSDKSettlesIt() throws {
        try store.update(try begin(source: .shielded), status: .unconfirmed)
        let reopened = DashPayWithdrawalStore(directory: directory)
        let afterTheWindow = Date().addingTimeInterval(60)
        XCTAssertTrue(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow))
        XCTAssertTrue(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow,
            shieldedOutcomeIsSettled: { _ in false }))
        var asked: [String] = []
        XCTAssertFalse(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow,
            shieldedOutcomeIsSettled: { asked.append($0.address); return true }))
        XCTAssertEqual(asked, ["reserved-contact-address"])
    }

    /// Only a Confirmed or Failed withdrawal row for the reserved address
    /// settles it: a Pending or Unknown one may still be re-broadcast or land,
    /// and a missing one is no proof nothing was sent.
    @MainActor
    func testOnlyATerminalShieldedWithdrawalRowSettlesTheAddress() throws {
        let container = try ShieldedWithdrawalHistoryFixture.makeContainer()
        let walletId = Data(repeating: 0x41, count: 32)
        let script = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0x52), count: 20) + [0x88, 0xac])
        let otherScript = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0x53), count: 20) + [0x88, 0xac])
        let address = try XCTUnwrap(ScriptAddressCodec.address(forScript: script, network: .testnet))
        var nextId: UInt8 = 0
        func insert(status: Int, kind: Int = 5, wallet: Data = walletId, counterparty: Data = script) throws {
            nextId += 1
            container.mainContext.insert(PersistentShieldedActivity(
                walletId: wallet, accountIndex: 0, entryId: Data(repeating: nextId, count: 32),
                kindTag: kind, direction: 1, status: status, amount: 1_000_000, fee: 1000, hasFee: true,
                blockHeight: 0, hasBlockHeight: false, createdAtMs: 1_800_000_000_000,
                identityId: Data(), counterparty: counterparty, memo: Data(), noteCmxs: Data(),
                spentNullifiers: Data(repeating: nextId, count: 32)))
            try container.mainContext.save()
        }
        func settled() -> Bool {
            WalletSendService.shieldedWithdrawalIsSettled(
                to: address, walletId: walletId, network: .testnet, in: container)
        }

        XCTAssertFalse(settled(), "no row")
        try insert(status: 0)
        XCTAssertFalse(settled(), "pending")
        try insert(status: 3)
        XCTAssertFalse(settled(), "unknown")
        try insert(status: 1, kind: 4)
        XCTAssertFalse(settled(), "confirmed, but not a withdrawal")
        try insert(status: 1, wallet: Data(repeating: 0x42, count: 32))
        XCTAssertFalse(settled(), "confirmed, another wallet")
        try insert(status: 2, counterparty: otherScript)
        XCTAssertFalse(settled(), "failed, another address")
        XCTAssertFalse(WalletSendService.shieldedWithdrawalIsSettled(
            to: "", walletId: walletId, network: .testnet, in: container), "no address recorded")
        try insert(status: 2)
        XCTAssertTrue(settled(), "failed")

        let confirmedOnly = try ShieldedWithdrawalHistoryFixture.makeContainer()
        confirmedOnly.mainContext.insert(PersistentShieldedActivity(
            walletId: walletId, accountIndex: 0, entryId: Data(repeating: 0xEE, count: 32),
            kindTag: 5, direction: 1, status: 1, amount: 1_000_000, fee: 1000, hasFee: true,
            blockHeight: 0, hasBlockHeight: false, createdAtMs: 1_800_000_000_000,
            identityId: Data(), counterparty: script, memo: Data(), noteCmxs: Data(),
            spentNullifiers: Data(repeating: 0xEE, count: 32)))
        try confirmedOnly.mainContext.save()
        XCTAssertTrue(WalletSendService.shieldedWithdrawalIsSettled(
            to: address, walletId: walletId, network: .testnet, in: confirmedOnly))
    }

    // MARK: - Addresses reserved without a payment

    private func reservation() throws -> DashPayWithdrawalStore.Entry {
        try store.beginReservation(scope: scope, contactIdentityId: contact, amountDuffs: 10_000, source: .shielded)
    }

    private var unpaidStreak: Int {
        get throws { try store.unpaidReservationStreak(scope: scope, contactIdentityId: contact) }
    }

    /// A reservation whose address could not be recorded is still counted,
    /// but it locks nothing and is not shown as a payment.
    func testReservationWithoutARecordedAddressCountsButNeitherLocksNorShows() throws {
        _ = try reservation()
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertEqual(try reopened.unpaidReservationStreak(scope: scope, contactIdentityId: contact), 1)
        XCTAssertFalse(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: .distantPast))
        XCTAssertEqual(try reopened.entries(scope: scope, contactIdentityId: contact).map(\.mayHaveBeenSubmitted), [false])
    }

    func testRecordingTheAddressMakesTheReservationAnAttempt() throws {
        let attempt = try store.recordReservedAddress(try reservation(), address: "reserved-contact-address")
        XCTAssertEqual(attempt.status, .submitting)
        XCTAssertEqual(attempt.address, "reserved-contact-address")
        XCTAssertEqual(try unpaidStreak, 0)
        XCTAssertTrue(try store.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
        XCTAssertThrowsError(try store.recordReservedAddress(attempt, address: "another"))
    }

    /// Only the newest unpaid reservations count: a submitted payment after
    /// them gives the contact's wallet a new address to look past.
    func testUnpaidStreakCountsOnlyReservationsSinceTheLastPayment() throws {
        try store.update(try begin(), status: .unused)
        try store.update(try begin(), status: .submitted)
        XCTAssertEqual(try unpaidStreak, 0)
        try store.update(try begin(), status: .unused)
        _ = try reservation()
        try store.update(try begin(), status: .unused)
        XCTAssertEqual(try unpaidStreak, 3)
        XCTAssertEqual(try store.unpaidReservationStreak(
            scope: scope, contactIdentityId: Data(repeating: 9, count: 32)), 0)
        try store.update(try begin(), status: .submitted)
        XCTAssertEqual(try unpaidStreak, 0)
    }

    func testTooManyUnpaidReservationsRefuseTheNextOne() throws {
        let recipient = ContactPaymentRecipient(
            identityId: contact, displayName: "contact", walletId: scope.walletId,
            ownerIdentityId: scope.ownerIdentityId, network: .testnet)
        for _ in 1..<WalletSendService.maxUnpaidContactReservations {
            try store.update(try begin(), status: .unused)
        }
        XCTAssertNoThrow(try WalletSendService.rejectIfTooManyUnpaidReservations(recipient, store: store))
        _ = try reservation()
        XCTAssertThrowsError(try WalletSendService.rejectIfTooManyUnpaidReservations(recipient, store: store))
        try Data("not json".utf8).write(to: try XCTUnwrap(FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first))
        XCTAssertThrowsError(try WalletSendService.rejectIfTooManyUnpaidReservations(recipient, store: store))
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

    // MARK: - What the coordinator does with a failed contact withdrawal

    @MainActor
    private func coordinatorAndAttempt() throws -> (ShieldedTransferCoordinator, DashPayWithdrawalStore.Entry) {
        (ShieldedTransferCoordinator(contactWithdrawalStore: store), try begin())
    }

    @MainActor
    func testProvenNonSubmissionDropsTheAttemptAndAllowsRetry() throws {
        let (coordinator, attempt) = try coordinatorAndAttempt()
        let concluded = coordinator.concludeUncertainContactWithdrawal(
            attempt, error: PlatformWalletError.shieldedBroadcastFailed("rejected"))
        XCTAssertFalse(concluded)
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact).map(\.status), [.unused])
        XCTAssertFalse(try store.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
        XCTAssertEqual(try unpaidStreak, 1)
        XCTAssertFalse(coordinator.contactWithdrawalOutcomeUnknown)
        XCTAssertNotEqual(coordinator.phase, .submittedUnconfirmed)
    }

    @MainActor
    func testAmbiguousFailureKeepsAnUnconfirmedAttemptAndEndsUnknown() throws {
        let (coordinator, attempt) = try coordinatorAndAttempt()
        let concluded = coordinator.concludeUncertainContactWithdrawal(attempt, error: URLError(.timedOut))
        XCTAssertTrue(concluded)
        XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
        XCTAssertTrue(coordinator.contactWithdrawalOutcomeUnknown)
        XCTAssertTrue(WalletSendService.shared.unknownContactPaymentOutcomes.contains(contactIdentityId: contact))
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertEqual(try reopened.entries(scope: scope, contactIdentityId: contact).map(\.status), [.unconfirmed])
        XCTAssertTrue(try reopened.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
    }

    /// The journal can't be written: the attempt that proves it never left
    /// can't be dropped, and the `.unconfirmed` update fails too. The
    /// `.submitting` record still locks the contact, and nothing is retried.
    @MainActor
    func testUnwritableJournalEndsUnknownAndTheSubmittingRecordStillLocks() throws {
        try XCTSkipIf(getuid() == 0, "root writes through the read-only permissions")
        let (coordinator, attempt) = try coordinatorAndAttempt()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let concluded: Bool
        do {
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            }
            concluded = coordinator.concludeUncertainContactWithdrawal(
                attempt, error: PlatformWalletError.shieldedBroadcastFailed("rejected"))
        }
        XCTAssertTrue(concluded)
        XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertEqual(try reopened.entries(scope: scope, contactIdentityId: contact).map(\.status), [.submitting])
        XCTAssertTrue(try reopened.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
    }

    /// Refused after its record was written but before the SDK was called:
    /// the record is dropped and the transfer fails as retryable.
    @MainActor
    func testRefusalBeforeSubmissionFailsRetryably() throws {
        let (coordinator, attempt) = try coordinatorAndAttempt()
        coordinator.failUnsubmittedContactWithdrawal(
            attempt, error: PlatformAddressSyncCoordinator.SendError.coordinatorNotReady)
        guard case .failed = coordinator.phase else {
            return XCTFail("expected a retryable failure, got \(coordinator.phase)")
        }
        XCTAssertFalse(coordinator.contactWithdrawalOutcomeUnknown)
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact).map(\.status), [.unused])
        XCTAssertEqual(try unpaidStreak, 1)
    }
}

/// Which balance a DashPay contact payment opens on, and when the From step
/// is offered.
@MainActor
final class ContactPaymentSourceTests: XCTestCase {
    private func plan(
        hasWalletContext: Bool = true,
        _ balances: [ChainNetwork: UInt64]
    ) -> (sources: [ChainNetwork], initialSource: ChainNetwork, offersChoice: Bool) {
        SendViewModel.contactSourcePlan(
            validSources: SendViewModel.contactValidSources(hasWalletContext: hasWalletContext),
            balanceDuffs: { balances[$0] ?? 0 })
    }

    /// A Platform or Shielded balance counts only for what a contact
    /// withdrawal from it pays: past the Core fee and at the floor.
    func testWithdrawalSourceCountsOnlyWhatAContactPaymentCanSend() {
        XCTAssertEqual(SendViewModel.contactPayableDuffs(envelopeCredits: 1_190_000), 1_000)
        XCTAssertEqual(SendViewModel.contactPayableDuffs(envelopeCredits: 1_189_999), 0)
        XCTAssertEqual(SendViewModel.contactPayableDuffs(envelopeCredits: 100_000), 0)
        XCTAssertEqual(SendViewModel.contactPayableDuffs(envelopeCredits: 2_000_190_000), 2_000_000)
    }

    func testOnlyPlatformFundedOpensOnPlatformWithoutChoice() {
        let result = plan([.platform: 2_000_000])
        XCTAssertEqual(result.initialSource, .platform)
        XCTAssertFalse(result.offersChoice)
    }

    func testOnlyShieldedFundedOpensOnShieldedWithoutChoice() {
        let result = plan([.shielded: 2_000_000])
        XCTAssertEqual(result.initialSource, .shielded)
        XCTAssertFalse(result.offersChoice)
    }

    func testSeveralFundedBalancesOfferChoiceStartingWithTransparent() {
        let result = plan([.core: 1, .platform: 2_000_000, .shielded: 3_000_000])
        XCTAssertEqual(result.initialSource, .core)
        XCTAssertTrue(result.offersChoice)
    }

    /// The caller passes Transparent's fee-aware spendable amount, which is
    /// zero for dust: Platform is then the only usable balance.
    func testUnspendableTransparentDustDefersToPlatform() {
        let result = plan([.core: 0, .platform: 2_000_000])
        XCTAssertEqual(result.initialSource, .platform)
        XCTAssertFalse(result.offersChoice)
    }

    func testNothingFundedFallsBackToTransparent() {
        let result = plan([:])
        XCTAssertEqual(result.initialSource, .core)
        XCTAssertFalse(result.offersChoice)
    }

    /// Without a wallet context there is nothing to check a reservation
    /// against, so only the Transparent send is offered.
    func testMissingWalletContextLeavesOnlyTransparent() {
        XCTAssertEqual(SendViewModel.contactValidSources(hasWalletContext: false), [.core])
        let result = plan(hasWalletContext: false, [.platform: 2_000_000, .shielded: 3_000_000])
        XCTAssertEqual(result.initialSource, .core)
        XCTAssertFalse(result.offersChoice)
    }

    private func capturedRecipient(for contact: ContactItem) -> ContactPaymentRecipient {
        ContactPaymentRecipient(
            identityId: contact.contactIdentityId,
            displayName: "",
            walletId: Data(repeating: 1, count: 32),
            ownerIdentityId: Data(repeating: 2, count: 32),
            network: .testnet)
    }

    /// The contact profile's Pay hosts the amount step without a From step or
    /// a withdrawal confirmation, so it pays only from Transparent even with a
    /// wallet context that would admit every balance.
    func testTransparentOnlyHostOffersOnlyTransparent() {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let captured = capturedRecipient(for: contact)

        let profile = SendViewModel(contactLookup: { _ in contact })
        profile.setContactRecipient(contact, paymentRecipient: captured, transparentOnly: true)
        XCTAssertEqual(profile.contactPaymentRecipient, captured)
        XCTAssertEqual(profile.validSources, [.core])
        XCTAssertEqual(profile.source, .core)
        XCTAssertEqual(profile.route, .coreToCore)
        XCTAssertFalse(profile.contactOffersSourceChoice)

        let picker = SendViewModel(contactLookup: { _ in contact }, contactPayableDuffs: { _ in 1_000 })
        picker.setContactRecipient(contact, paymentRecipient: captured)
        XCTAssertEqual(picker.validSources, [.core, .platform, .shielded])
    }

    /// The From step lists only the balances one contact payment can be
    /// paid from; a Platform balance whose largest address can't cover the
    /// fees and the floor is not offered.
    func testFromStepOffersOnlyBalancesThatCanPayTheContact() {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let payable: [ChainNetwork: UInt64] = [.core: 5_000, .platform: 0, .shielded: 2_000]
        let viewModel = SendViewModel(contactLookup: { _ in contact }, contactPayableDuffs: { payable[$0] ?? 0 })
        viewModel.setContactRecipient(contact, paymentRecipient: capturedRecipient(for: contact))
        XCTAssertEqual(viewModel.validSources, [.core, .shielded])
        XCTAssertTrue(viewModel.contactOffersSourceChoice)
        XCTAssertEqual(viewModel.source, .core)
        viewModel.source = .platform
        XCTAssertNil(viewModel.route)
    }

    /// Nothing can pay: Transparent alone, so the amount step still opens
    /// and says what is short.
    func testFromStepFallsBackToTransparentWhenNothingCanPay() {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let viewModel = SendViewModel(contactLookup: { _ in contact }, contactPayableDuffs: { _ in 0 })
        viewModel.setContactRecipient(contact, paymentRecipient: capturedRecipient(for: contact))
        XCTAssertEqual(viewModel.validSources, [.core])
        XCTAssertFalse(viewModel.contactOffersSourceChoice)
        XCTAssertEqual(viewModel.route, .coreToCore)
    }

    /// Without a captured context the payment is not bound to whatever wallet
    /// is active later: no context is taken from the active wallet, and only
    /// Transparent is listed, however much the other balances could pay.
    func testMissingCapturedContextIsNotFilledInFromTheActiveWallet() {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let viewModel = SendViewModel(contactLookup: { _ in contact }, contactPayableDuffs: { _ in 1_000 })
        viewModel.setContactRecipient(contact)
        XCTAssertNil(viewModel.contactPaymentRecipient)
        XCTAssertEqual(viewModel.validSources, [.core])
        XCTAssertEqual(viewModel.contactUnavailableMessage, WalletSendService.contactContextChangedMessage)
    }

    /// The send boundary refuses a context captured for another contact with
    /// the "not ready" error, before any PIN prompt or signing, rather than
    /// taking the wallet and identity active now.
    func testPrepareRefusesAContextCapturedForAnotherContact() async {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let other = ContactItem.fixture(idByte: 0xbb, relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        do {
            _ = try await WalletSendService.shared.prepareContactPayment(
                contactIdentityId: contact.contactIdentityId,
                amount: 1_000,
                recipient: capturedRecipient(for: other))
            XCTFail("a payment bound to another contact's context was prepared")
        } catch {
            let expected = WalletSendService.contactPaymentUnavailableError()
            XCTAssertEqual((error as NSError).domain, expected.domain)
            XCTAssertEqual((error as NSError).code, expected.code)
            XCTAssertEqual(error.localizedDescription, expected.localizedDescription)
        }
    }

    /// A context whose wallet is not the one active is refused, not replaced.
    func testPrepareRefusesAContextFromAnotherWallet() async {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        do {
            _ = try await WalletSendService.shared.prepareContactPayment(
                contactIdentityId: contact.contactIdentityId,
                amount: 1_000,
                recipient: capturedRecipient(for: contact))
            XCTFail("a payment bound to an inactive wallet was prepared")
        } catch {
            XCTAssertEqual((error as NSError).code, WalletSendService.contactPaymentUnavailableError().code)
        }
    }

    /// A context captured for another contact never binds this payment.
    func testRecipientCapturedForAnotherContactIsNotUsed() {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let other = ContactItem.fixture(idByte: 0xbb, relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let viewModel = SendViewModel(contactLookup: { _ in contact })
        viewModel.setContactRecipient(contact, paymentRecipient: capturedRecipient(for: other))
        XCTAssertNotEqual(viewModel.contactPaymentRecipient?.identityId, other.contactIdentityId)
    }
}

/// The Total a contact payment from Platform or Shielded confirms.
final class ContactWithdrawalTotalTests: XCTestCase {
    func testCreditsSaturateInsteadOfWrapping() {
        XCTAssertEqual(SendViewModel.credits(fromDuffs: 150_000), 150_000_000)
        XCTAssertEqual(SendViewModel.credits(fromDuffs: UInt64.max / 1000), UInt64.max / 1000 * 1000)
        XCTAssertEqual(SendViewModel.credits(fromDuffs: UInt64.max / 1000 + 1), .max)
        XCTAssertEqual(SendViewModel.credits(fromDuffs: .max), .max)
    }

    func testTotalAddsTheFee() {
        // 0.02 DASH plus a 0.0001 DASH fee (1e7 credits).
        XCTAssertEqual(SendConfirmSheet.withdrawalDebitDuffs(amountDuffs: 2_000_000, feeCredits: 10_000_000), 2_010_000)
    }

    func testPartialDuffOfFeeRoundsUp() {
        XCTAssertEqual(SendConfirmSheet.withdrawalDebitDuffs(amountDuffs: 100, feeCredits: 1_001), 102)
    }

    /// The asset unlock's Core fee (190 bytes at 1 duff/byte), added on top of
    /// every contact withdrawal: from protocol 14 the network carves it out.
    func testCoreFeeIsTheAssetUnlockFee() {
        XCTAssertEqual(ShieldedTransferCoordinator.contactCoreFeeCredits, 190_000)
    }

    func testContactWithdrawalCarriesAmountPlusCoreFee() throws {
        XCTAssertEqual(
            try ShieldedTransferCoordinator.contactWithdrawalCredits(recipientCredits: 2_000_000_000),
            2_000_190_000)
    }

    /// The consensus floor is 1000 duffs; from v14 it covers amount plus Core
    /// fee, which is added on top, so the contact-side floor stays 1000 duffs.
    func testContactMinimumIsTheConsensusFloor() throws {
        XCTAssertEqual(ShieldedTransferCoordinator.contactWithdrawalMinimumCredits, 1_000_000)
        XCTAssertEqual(
            try ShieldedTransferCoordinator.contactWithdrawalCredits(recipientCredits: 1_000_000), 1_190_000)
        XCTAssertThrowsError(
            try ShieldedTransferCoordinator.contactWithdrawalCredits(recipientCredits: 999_000))
    }

    /// The PIN authorizes everything a contact payment takes: what it submits
    /// plus its network fee, rounded up to a whole duff.
    func testContactAuthorizationCoversSubmittedAmountAndFee() throws {
        let recipient = ContactPaymentRecipient(
            identityId: Data(repeating: 3, count: 32), displayName: "c",
            walletId: Data(repeating: 1, count: 32), ownerIdentityId: Data(repeating: 2, count: 32),
            network: .testnet)
        XCTAssertEqual(
            try ShieldedTransferCoordinator.contactSpendDuffs(
                recipient, submittedCredits: 2_000_190_000, networkFeeCredits: 1_500),
            2_000_192)
        XCTAssertNil(
            try ShieldedTransferCoordinator.contactSpendDuffs(nil, submittedCredits: 1_000, networkFeeCredits: nil))
        // An unknown fee refuses the payment rather than authorizing without it.
        XCTAssertThrowsError(
            try ShieldedTransferCoordinator.contactSpendDuffs(
                recipient, submittedCredits: 2_000_190_000, networkFeeCredits: nil))
    }

    /// Right before the PIN and again before submission, a Shielded contact
    /// payment is held to the fee it was confirmed with.
    func testContactShieldedFeeIsHeldToTheConfirmedFee() {
        typealias Coordinator = ShieldedTransferCoordinator
        XCTAssertNil(Coordinator.contactShieldedFeeRefusal(
            confirmedFeeCredits: 2_000, notesReady: true, liveFeeCredits: 2_000))
        XCTAssertNil(Coordinator.contactShieldedFeeRefusal(
            confirmedFeeCredits: 6_000, notesReady: true, liveFeeCredits: 2_000))
        let refusals: [(UInt64?, Bool, UInt64?, String)] = [
            (2_000, true, 3_000, "contactFeeChanged"),
            (2_000, false, nil, "shieldedBalanceUnavailable"),
            (2_000, true, nil, "contactPaymentNotPriced"),
            (nil, true, 2_000, "contactPaymentNotPriced"),
        ]
        for (confirmed, ready, live, expected) in refusals {
            let refusal = Coordinator.contactShieldedFeeRefusal(
                confirmedFeeCredits: confirmed, notesReady: ready, liveFeeCredits: live)
            XCTAssertEqual(refusal.map { "\($0)" }, expected)
        }
    }

    /// Platform rejects a Shielded withdrawal above 500 DASH, Core fee
    /// included, so a contact can be paid at most 499.9999981 DASH from it.
    func testContactShieldedMaximumLeavesRoomForTheCoreFee() throws {
        XCTAssertEqual(ShieldedTransferCoordinator.withdrawalMaximumCredits, 50_000_000_000_000)
        XCTAssertEqual(ShieldedTransferCoordinator.contactWithdrawalMaximumCredits, 49_999_999_810_000)
        XCTAssertEqual(
            try ShieldedTransferCoordinator.contactWithdrawalCredits(
                recipientCredits: ShieldedTransferCoordinator.contactWithdrawalMaximumCredits),
            ShieldedTransferCoordinator.withdrawalMaximumCredits)
    }

    /// A contact's Platform withdrawal spends one explicit input, so it is
    /// priced with Platform's minimum fee for one input and no change output
    /// (`AddressCreditWithdrawalTransition::estimate_min_fee(1, false)`):
    /// 400_000_000 for the withdrawal plus 500_000 for the input.
    func testContactPlatformFeeIsTheSingleInputWithdrawalFee() {
        XCTAssertEqual(ShieldedTransferCoordinator.platformSingleInputWithdrawalFeeCredits, 400_500_000)
    }

    func testContactPlatformPaymentIsHeldToItsConfirmedFeeAndTheMaximum() {
        typealias Coordinator = ShieldedTransferCoordinator
        let fee = Coordinator.platformSingleInputWithdrawalFeeCredits
        XCTAssertNil(Coordinator.contactPlatformRefusal(submittedCredits: 5_000_000, confirmedFeeCredits: fee))
        XCTAssertEqual(
            Coordinator.contactPlatformRefusal(submittedCredits: 5_000_000, confirmedFeeCredits: fee - 1)
                .map { "\($0)" },
            "contactFeeChanged")
        XCTAssertEqual(
            Coordinator.contactPlatformRefusal(submittedCredits: 5_000_000, confirmedFeeCredits: nil).map { "\($0)" },
            "contactPaymentNotPriced")
        XCTAssertNil(Coordinator.contactPlatformRefusal(
            submittedCredits: Coordinator.withdrawalMaximumCredits, confirmedFeeCredits: fee))
        XCTAssertEqual(
            Coordinator.contactPlatformRefusal(
                submittedCredits: Coordinator.withdrawalMaximumCredits + 1, confirmedFeeCredits: fee)
                .map { "\($0)" },
            "contactAbovePlatformWithdrawalMaximum")
    }

    /// What a contact can be paid from Platform depends only on the largest
    /// address, never on the whole-account preflight: an account whose AUTO
    /// withdrawal can't be planned (more than 16 addresses, or a total above
    /// the withdrawal maximum) still pays a contact from one address.
    func testContactPlatformCapComesFromTheLargestAddressAlone() {
        let reserved = ShieldedTransferCoordinator.platformSingleInputWithdrawalFeeCredits
            + ShieldedTransferCoordinator.contactCoreFeeCredits
        XCTAssertEqual(SendViewModel.contactPlatformCapCredits(largestAddressCredits: 0), 0)
        XCTAssertEqual(SendViewModel.contactPlatformCapCredits(largestAddressCredits: reserved), 0)
        XCTAssertEqual(SendViewModel.contactPlatformCapCredits(largestAddressCredits: reserved + 1), 1)
        XCTAssertEqual(
            SendViewModel.contactPlatformCapCredits(largestAddressCredits: 1_000_000_000_000),
            1_000_000_000_000 - 400_690_000)
        XCTAssertEqual(
            SendViewModel.contactPlatformCapCredits(largestAddressCredits: 60_000_000_000_000),
            ShieldedTransferCoordinator.contactWithdrawalMaximumCredits)
    }

    /// A Platform or Shielded payment claims the contact for its whole run:
    /// meanwhile no other payment to it can start, and once it ends one can.
    @MainActor
    func testContactPaymentHoldsTheClaimUntilItEnds() throws {
        let recipient = ContactPaymentRecipient(
            identityId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), displayName: "c",
            walletId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            ownerIdentityId: Data(repeating: 2, count: 32), network: .testnet)
        let service = WalletSendService.shared
        let current: @MainActor (ContactPaymentRecipient) throws -> Void = { _ in }
        try service.beginContactPayment(recipient, validate: current)
        XCTAssertThrowsError(try service.beginContactPayment(recipient, validate: current))
        service.endContactPayment(recipient)
        try service.beginContactPayment(recipient, validate: current)
        service.endContactPayment(recipient)
        XCTAssertFalse(service.contactPaymentClaims.isClaimed(contactIdentityId: recipient.identityId))
    }

    /// A recipient captured for a wallet or identity that is no longer active
    /// is refused before authorization, and the claim is let go.
    @MainActor
    func testContactPaymentRefusesAStaleRecipientBeforeAuthorization() {
        let recipient = ContactPaymentRecipient(
            identityId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), displayName: "c",
            walletId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            ownerIdentityId: Data(repeating: 2, count: 32), network: .testnet)
        let service = WalletSendService.shared
        XCTAssertThrowsError(try service.beginContactPayment(recipient))
        XCTAssertFalse(service.contactPaymentClaims.isClaimed(contactIdentityId: recipient.identityId))
    }

    /// Only one payment to a contact at a time, from any balance.
    func testContactPaymentClaimIsExclusiveUntilReleased() {
        let claims = ContactPaymentClaims()
        let contact = Data(repeating: 3, count: 32)
        XCTAssertTrue(claims.claim(contactIdentityId: contact))
        XCTAssertFalse(claims.claim(contactIdentityId: contact))
        XCTAssertTrue(claims.claim(contactIdentityId: Data(repeating: 4, count: 32)))
        claims.release(contactIdentityId: contact)
        XCTAssertTrue(claims.claim(contactIdentityId: contact))
    }

    /// A prepared payment's hold releases its contact once, never a later
    /// payment's claim, and is released if the payment is dropped unsent.
    func testClaimHoldReleasesOnlyItsOwnClaimOnce() {
        let claims = ContactPaymentClaims()
        let contact = Data(repeating: 3, count: 32)
        XCTAssertTrue(claims.claim(contactIdentityId: contact))
        let hold = ContactPaymentClaimHold(contactIdentityId: contact, claims: claims)
        XCTAssertFalse(claims.claim(contactIdentityId: contact), "held while the payment waits")
        hold.release()
        XCTAssertTrue(claims.claim(contactIdentityId: contact), "a later payment")
        hold.release()
        XCTAssertTrue(claims.isClaimed(contactIdentityId: contact), "the later claim stands")
        claims.release(contactIdentityId: contact)

        XCTAssertTrue(claims.claim(contactIdentityId: contact))
        var dropped: ContactPaymentClaimHold? = ContactPaymentClaimHold(contactIdentityId: contact, claims: claims)
        XCTAssertNotNil(dropped)
        dropped = nil
        XCTAssertFalse(claims.isClaimed(contactIdentityId: contact))
    }

    /// Wallet deletion waits for no payment: it is refused while one holds a
    /// claim, and no payment starts while it runs.
    func testWalletDeletionAndContactPaymentsExcludeEachOther() {
        let claims = ContactPaymentClaims()
        let contact = Data(repeating: 3, count: 32)
        XCTAssertTrue(claims.claim(contactIdentityId: contact))
        XCTAssertFalse(claims.suspendForWalletDeletion())
        claims.release(contactIdentityId: contact)

        XCTAssertTrue(claims.suspendForWalletDeletion())
        XCTAssertFalse(claims.claim(contactIdentityId: contact))
        XCTAssertFalse(claims.suspendForWalletDeletion())
        claims.resumeAfterWalletDeletion()
        XCTAssertTrue(claims.claim(contactIdentityId: contact))
    }

    /// A contact payment suspended in the SDK keeps its wallet: removal is
    /// refused before anything is deleted.
    @MainActor
    func testWalletRemovalIsRefusedWhileAContactPaymentIsInFlight() async {
        let claims = WalletSendService.shared.contactPaymentClaims
        let contact = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        XCTAssertTrue(claims.claim(contactIdentityId: contact))
        defer { claims.release(contactIdentityId: contact) }
        do {
            try await SwiftDashSDKWalletWiper.deleteLogicalWallet(mnemonic: "not a recovery phrase")
            XCTFail("the removal ran while a payment was in flight")
        } catch {
            XCTAssertEqual(error as? SwiftDashSDKWalletDeletionError, .walletDeletionIncomplete)
        }
        XCTAssertFalse(claims.suspendForWalletDeletion(), "the claim is still held")
    }

    /// A non-sweep Shielded payment is priced from the notes Rust would select,
    /// with change allowed, not from a fixed two-action estimate.
    func testSelectionPricesTheNotesItSpends() throws {
        let fee: (Int) -> UInt64? = { UInt64($0) * 1_000 }
        let two = try XCTUnwrap(ShieldedSweepPlanner.selection(
            noteValues: [50_000, 40_000, 30_000], amountCredits: 60_000, feeForActions: fee))
        XCTAssertEqual(two.noteCount, 2)
        XCTAssertEqual(two.feeCredits, 2_000)
        let three = try XCTUnwrap(ShieldedSweepPlanner.selection(
            noteValues: [50_000, 40_000, 30_000], amountCredits: 95_000, feeForActions: fee))
        XCTAssertEqual(three.noteCount, 3)
        XCTAssertEqual(three.feeCredits, 3_000)
        XCTAssertNil(ShieldedSweepPlanner.selection(
            noteValues: [50_000, 40_000, 30_000], amountCredits: 118_000, feeForActions: fee))
    }

    func testOverflowIsUnavailable() {
        XCTAssertNil(SendConfirmSheet.withdrawalDebitDuffs(amountDuffs: .max, feeCredits: 1_000))
    }
}
