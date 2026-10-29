import Foundation
import SwiftDashSDK
import XCTest
@testable import dashpay

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

    /// A wallet whose deletion fails after its journal was cleared gets the
    /// journal, and with it its unresolved-payment lock, back.
    func testRestorePutsBackAClearedWalletsJournal() throws {
        let pending = try begin()
        try store.update(pending, status: .unconfirmed)
        let removed = try store.clearForWallet(walletId: scope.walletId)
        XCTAssertFalse(try store.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
        try store.restore(removed)
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertTrue(try reopened.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: .distantPast))
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

/// Which balance a DashPay contact payment opens on, and when the From step
/// is offered.
@MainActor
final class ContactPaymentSourceTests: XCTestCase {
    private func plan(
        hasWalletContext: Bool = true,
        _ balances: [ChainNetwork: UInt64]
    ) -> (initialSource: ChainNetwork, offersChoice: Bool) {
        SendViewModel.contactSourcePlan(
            validSources: SendViewModel.contactValidSources(hasWalletContext: hasWalletContext),
            balanceDuffs: { balances[$0] ?? 0 })
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
}

/// The Total a contact payment from Platform or Shielded confirms.
final class ContactWithdrawalTotalTests: XCTestCase {
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
