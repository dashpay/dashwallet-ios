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
        XCTAssertEqual(ShieldedTransferCoordinator.shieldedWithdrawalMaximumCredits, 50_000_000_000_000)
        XCTAssertEqual(ShieldedTransferCoordinator.contactShieldedMaximumCredits, 49_999_999_810_000)
        XCTAssertEqual(
            try ShieldedTransferCoordinator.contactWithdrawalCredits(
                recipientCredits: ShieldedTransferCoordinator.contactShieldedMaximumCredits),
            ShieldedTransferCoordinator.shieldedWithdrawalMaximumCredits)
    }

    func testContactPlatformFeeIsHeldToTheConfirmedFee() {
        typealias Coordinator = ShieldedTransferCoordinator
        XCTAssertNil(Coordinator.contactPlatformFeeRefusal(confirmedFeeCredits: 5_000, liveFeeCredits: 5_000))
        XCTAssertEqual(
            Coordinator.contactPlatformFeeRefusal(confirmedFeeCredits: 5_000, liveFeeCredits: 6_000).map { "\($0)" },
            "contactFeeChanged")
        XCTAssertEqual(
            Coordinator.contactPlatformFeeRefusal(confirmedFeeCredits: 5_000, liveFeeCredits: nil).map { "\($0)" },
            "contactPaymentNotPriced")
        XCTAssertEqual(
            Coordinator.contactPlatformFeeRefusal(confirmedFeeCredits: nil, liveFeeCredits: 5_000).map { "\($0)" },
            "contactPaymentNotPriced")
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
        try service.beginContactPayment(recipient)
        XCTAssertThrowsError(try service.beginContactPayment(recipient))
        service.endContactPayment(recipient)
        try service.beginContactPayment(recipient)
        service.endContactPayment(recipient)
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
