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
        source: DashPayWithdrawalStore.Source = .shielded,
        coreHeight: UInt32? = nil
    ) throws -> DashPayWithdrawalStore.Entry {
        try store.begin(
            scope: scope ?? self.scope, contactIdentityId: contact,
            address: "reserved-contact-address", amountDuffs: 10_000, source: source, coreHeight: coreHeight)
    }

    private static let recordedTip: UInt32 = 1_000
    private static let agedTip = recordedTip + DashPayWithdrawalStore.lockBlocks

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

    /// A deletion that fails throws, so neither a clear nor a wipe reports
    /// success while records survive, and every read fails until a sweep
    /// finishes it: the records it dropped are dropped all at once.
    func testFailedDeletionFailsEveryReadUntilASweepFinishesIt() throws {
        struct RemovalFailed: Error {}
        let journal = directory.appendingPathComponent("journal")
        let failing = DashPayWithdrawalStore(directory: journal, removeItem: { _ in throw RemovalFailed() })
        _ = try failing.begin(
            scope: scope, contactIdentityId: contact, address: "yAddress",
            amountDuffs: 1_000, source: .shielded)
        let since = Date.distantPast

        XCTAssertThrowsError(try failing.clearForWallet(walletId: scope.walletId)) {
            XCTAssertTrue($0 is RemovalFailed, "\($0)")
        }
        XCTAssertThrowsError(try failing.entries(scope: scope, contactIdentityId: contact))
        XCTAssertThrowsError(try failing.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: since))
        XCTAssertThrowsError(try failing.files(ofWallet: scope.walletId))
        XCTAssertThrowsError(try failing.begin(
            scope: scope, contactIdentityId: contact, address: "yAddress",
            amountDuffs: 1_000, source: .shielded), "nor can a new attempt start")
        XCTAssertThrowsError(try failing.resetForWipe()) {
            XCTAssertTrue($0 is RemovalFailed, "\($0)")
        }
        XCTAssertThrowsError(try failing.entries(scope: scope, contactIdentityId: contact))

        let working = DashPayWithdrawalStore(directory: journal)
        XCTAssertTrue(try working.entries(scope: scope, contactIdentityId: contact).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    /// A deletion that removes some records before it fails leaves none of
    /// the cleared wallet's records reading as gone while another still
    /// counts: every read fails until the rest is deleted.
    func testDeletionFailingPartWayDropsNoRecordAlone() throws {
        struct RemovalFailed: Error {}
        let journal = directory.appendingPathComponent("journal")
        let partial = DashPayWithdrawalStore(directory: journal, removeItem: { url in
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil)) ?? []
            if let first = children.min(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try FileManager.default.removeItem(at: first)
            }
            throw RemovalFailed()
        })
        let otherOwner = DashPayWithdrawalStore.Scope(
            networkRaw: scope.networkRaw, walletId: scope.walletId, ownerIdentityId: Data(repeating: 3, count: 32))
        for owner in [scope, otherOwner] {
            _ = try partial.begin(
                scope: owner, contactIdentityId: contact, address: "yAddress",
                amountDuffs: 1_000, source: .platform)
        }

        XCTAssertThrowsError(try partial.clearForWallet(walletId: scope.walletId))
        for owner in [scope, otherOwner] {
            XCTAssertThrowsError(try partial.lockState(
                scope: owner, contactIdentityId: contact, since: .distantPast))
        }
        XCTAssertTrue(try DashPayWithdrawalStore(directory: journal)
            .entries(scope: otherOwner, contactIdentityId: contact).isEmpty)
    }

    /// A deletion failing with "no such file" is still a failure, not a
    /// journal that was never created.
    func testWipeWhoseDeletionFindsAFileMissingThrows() throws {
        let journal = directory.appendingPathComponent("journal")
        let failing = DashPayWithdrawalStore(
            directory: journal, removeItem: { _ in throw CocoaError(.fileNoSuchFile) })
        _ = try failing.begin(
            scope: scope, contactIdentityId: contact, address: "yAddress",
            amountDuffs: 1_000, source: .shielded)

        XCTAssertThrowsError(try failing.resetForWipe())
        XCTAssertThrowsError(try failing.entries(scope: scope, contactIdentityId: contact))
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

    /// Past the window a Platform payout may still be queued: the attempt
    /// stays unresolved until the user, told so, chooses to pay again.
    func testAnAgedPlatformRecordAwaitsTheUsersDecision() throws {
        _ = try begin(source: .platform, coreHeight: Self.recordedTip)
        let afterTheWindow = Date().addingTimeInterval(60)
        XCTAssertEqual(try store.lockState(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip),
            .awaitingDecision)
        XCTAssertTrue(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip))
        XCTAssertFalse(try store.releaseAgedEntries(
            scope: scope, contactIdentityId: contact, since: lockWindowStart, coreHeight: Self.agedTip),
            "a lock still within its window is not released")
        XCTAssertTrue(try store.releaseAgedEntries(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip))
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertEqual(try reopened.lockState(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip), .none)
        XCTAssertEqual(try reopened.unpaidReservationStreak(scope: scope, contactIdentityId: contact), 1,
                       "released, it still counts against the address budget")
    }

    /// An unreadable journal makes the contact's history incomplete, never
    /// an empty or complete one.
    func testAnUnreadableJournalMakesTheHistoryIncomplete() throws {
        struct Unreadable: Error {}
        let failed = SwiftDashSDKContactsService.withdrawalPayments(
            reading: { throw Unreadable() }, shieldedSpendState: { _ in .pending })
        XCTAssertTrue(failed.isIncomplete)
        XCTAssertTrue(failed.payments.isEmpty)

        try store.update(try begin(source: .platform), status: .submitted)
        let read = SwiftDashSDKContactsService.withdrawalPayments(
            reading: { try self.store.entries(scope: self.scope, contactIdentityId: self.contact) },
            shieldedSpendState: { _ in .pending })
        XCTAssertFalse(read.isIncomplete)
        XCTAssertEqual(read.payments.count, 1)
    }

    /// A history read without the identity, store or wallet it goes through
    /// is incomplete: only a lookup that ran can show there were no payments.
    @MainActor
    func testAHistoryWithoutItsContextIsIncomplete() throws {
        let config = ModelConfiguration(schema: DashModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: DashModelContainer.schema, configurations: [config])
        let service = SwiftDashSDKContactsService.shared
        let owner = scope.ownerIdentityId
        XCTAssertTrue(service.paymentHistory(
            with: contact, ownerId: nil, modelContainer: container, walletId: scope.walletId).isIncomplete)
        XCTAssertTrue(service.paymentHistory(
            with: contact, ownerId: owner, modelContainer: nil, walletId: scope.walletId).isIncomplete)
        XCTAssertTrue(service.paymentHistory(
            with: contact, ownerId: owner, modelContainer: container, walletId: nil).isIncomplete)
        let read = service.paymentHistory(
            with: contact, ownerId: owner, modelContainer: container, walletId: scope.walletId)
        XCTAssertFalse(read.isIncomplete)
        XCTAssertTrue(read.payments.isEmpty)
    }

    /// Pay again releases only the active sender's attempts: a captured
    /// wallet that is no longer active is refused before the journal changes.
    @MainActor
    func testPayAgainRefusesASenderNoLongerActive() {
        let recipient = ContactPaymentRecipient(
            identityId: contact, displayName: "c", walletId: Data(repeating: 0xEE, count: 32),
            ownerIdentityId: scope.ownerIdentityId, network: .testnet)
        XCTAssertThrowsError(try WalletSendService.shared.releaseAgedContactPayments(recipient))
    }

    /// Only a tip from a tick that finds the client caught up with a peer
    /// connected counts: `.synced`, or the steady `.waitForEvents` at full
    /// progress, which never needs a transient `.synced` tick. An earlier tip
    /// is not carried into a later catch-up, so an attempt begun then is left
    /// unstamped and counts from the next caught-up tip.
    func testOnlyACurrentCaughtUpTipCounts() throws {
        func live(
            _ state: SPVSyncState, progress: Double = 1, peer: Bool = true,
            _ current: UInt32, target: UInt32? = nil
        ) -> UInt32? {
            SwiftDashSDKSPVCoordinator.liveSyncedTip(
                state: state, progress: progress, hasConnectedPeer: peer,
                headersCurrent: current, headersTarget: target ?? current)
        }
        XCTAssertNil(live(.synced, peer: false, Self.agedTip), "persisted heights before any peer answers")
        XCTAssertNil(live(.syncing, progress: 0.5, Self.agedTip), "still catching up")
        XCTAssertNil(live(.waitingForConnections, progress: 0, peer: false, Self.agedTip))
        XCTAssertNil(live(.waitForEvents, progress: 0, Self.agedTip), "the pre-start default")
        XCTAssertNil(live(.waitForEvents, Self.agedTip, target: Self.agedTip + 1), "a taller header is known")
        XCTAssertNil(live(.waitForEvents, peer: false, Self.agedTip))
        XCTAssertEqual(live(.synced, Self.agedTip), Self.agedTip)
        XCTAssertEqual(live(.waitForEvents, Self.agedTip), Self.agedTip)
        XCTAssertEqual(live(.waitForEvents, progress: 0.999, Self.agedTip), Self.agedTip)
        XCTAssertNil(live(.waitForEvents, progress: 0.9989, Self.agedTip))
        XCTAssertNil(live(.syncing, progress: 0.99, Self.agedTip + 5, target: Self.agedTip + 6),
                     "the last caught-up tip does not stand through a catch-up")

        _ = try begin(source: .platform, coreHeight: live(.syncing, progress: 0.9, Self.recordedTip))
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact).map(\.coreHeight), [nil])
        let afterTheWindow = Date().addingTimeInterval(60)
        let caughtUp = live(.waitForEvents, Self.agedTip)
        XCTAssertEqual(try store.lockState(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: caughtUp), .locked)
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact).map(\.coreHeight), [Self.agedTip])
        XCTAssertEqual(try store.lockState(
            scope: scope, contactIdentityId: contact, since: afterTheWindow,
            coreHeight: live(.waitForEvents, Self.agedTip + DashPayWithdrawalStore.lockBlocks)), .awaitingDecision)
    }

    /// Attaching replays the manager's cached value, and a poll already in flight may publish a
    /// read from before the attachment next: neither stamps a payment.
    func testResubscribingRefusesTheReplayAndTheInFlightPoll() {
        var lifetime = ContactPaymentTipLifetime()
        lifetime.invalidate(at: 1, refusing: 2)
        XCTAssertNil(lifetime.tip(Self.recordedTip, observedAt: 2, isActive: true))
        XCTAssertNil(lifetime.tip(Self.recordedTip, observedAt: 3, isActive: true))
        XCTAssertEqual(lifetime.tip(Self.agedTip, observedAt: 4, isActive: true), Self.agedTip)
    }

    func testBackgroundTickCannotAgeANewPlatformPaymentOnResume() throws {
        var lifetime = ContactPaymentTipLifetime()
        XCTAssertEqual(lifetime.tip(Self.recordedTip, observedAt: 1, isActive: true), Self.recordedTip)
        lifetime.invalidate(at: 2)
        XCTAssertNil(lifetime.tip(Self.recordedTip, observedAt: 3, isActive: false))
        lifetime.invalidate(at: 4)
        let queuedBackgroundTip = lifetime.tip(Self.recordedTip, observedAt: 3, isActive: true)
        XCTAssertNil(queuedBackgroundTip)

        _ = try begin(source: .platform, coreHeight: queuedBackgroundTip)
        let reopened = DashPayWithdrawalStore(directory: directory)
        let clockJump = Date().addingTimeInterval(60)
        XCTAssertEqual(try reopened.lockState(
            scope: scope, contactIdentityId: contact, since: clockJump,
            coreHeight: queuedBackgroundTip), .locked)
        XCTAssertEqual(try reopened.entries(scope: scope, contactIdentityId: contact).map(\.coreHeight), [nil])

        // Published after the resume, but possibly read before it.
        XCTAssertNil(lifetime.tip(Self.agedTip, observedAt: 5, isActive: true))
        let freshTip = lifetime.tip(Self.agedTip, observedAt: 6, isActive: true)
        XCTAssertEqual(freshTip, Self.agedTip)
        XCTAssertEqual(try reopened.lockState(
            scope: scope, contactIdentityId: contact, since: clockJump, coreHeight: freshTip), .locked)
        XCTAssertEqual(try reopened.entries(scope: scope, contactIdentityId: contact).map(\.coreHeight), [Self.agedTip])
        XCTAssertEqual(try reopened.lockState(
            scope: scope, contactIdentityId: contact, since: clockJump,
            coreHeight: lifetime.tip(Self.agedTip + DashPayWithdrawalStore.lockBlocks,
                                     observedAt: 6, isActive: true)), .awaitingDecision)
    }

    /// A device clock moved forward does not move the chain: until the Core
    /// tip has advanced too, or while it is unknown, the lock holds.
    func testAClockJumpAloneDoesNotExpireAPlatformLock() throws {
        _ = try begin(source: .platform, coreHeight: Self.recordedTip)
        let reopened = DashPayWithdrawalStore(directory: directory)
        let afterTheWindow = Date().addingTimeInterval(60)
        XCTAssertTrue(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip - 1))
        XCTAssertTrue(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: nil))
        XCTAssertTrue(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: lockWindowStart, coreHeight: Self.agedTip))
    }

    /// An attempt recorded before the tip was known starts counting from the
    /// first check that knows it.
    func testAnAttemptWithoutATipCountsFromTheFirstKnownTip() throws {
        _ = try begin(source: .platform)
        let afterTheWindow = Date().addingTimeInterval(60)
        XCTAssertTrue(try store.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip))
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertEqual(try reopened.entries(scope: scope, contactIdentityId: contact).map(\.coreHeight), [Self.agedTip])
        XCTAssertTrue(try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip + 1))
        XCTAssertEqual(try reopened.lockState(
            scope: scope, contactIdentityId: contact, since: afterTheWindow,
            coreHeight: Self.agedTip + DashPayWithdrawalStore.lockBlocks), .awaitingDecision)
    }

    /// The SDK keeps the signed Shielded spend and re-broadcasts it on later
    /// syncs while its row is Pending, whatever the device clock says. A
    /// Confirmed or Failed row resolves it at any age; with no row, or an
    /// Unknown one, nothing is re-broadcast and the window applies.
    func testShieldedRecordLocksWhileTheSDKHoldsItPending() throws {
        try store.update(try begin(source: .shielded, coreHeight: Self.recordedTip), status: .unconfirmed)
        let reopened = DashPayWithdrawalStore(directory: directory)
        func locked(_ state: DashPayWithdrawalStore.ShieldedSpendState, since: Date) throws -> Bool {
            try reopened.hasUnresolvedEntry(
                scope: scope, contactIdentityId: contact, since: since, coreHeight: Self.agedTip,
                shieldedSpendState: { _ in state })
        }
        let afterTheWindow = Date().addingTimeInterval(60)
        XCTAssertTrue(try reopened.hasUnresolvedEntry(scope: scope, contactIdentityId: contact, since: afterTheWindow),
                      "an unreadable state holds the lock")
        XCTAssertTrue(try locked(.pending, since: afterTheWindow))
        XCTAssertEqual(try reopened.lockState(
            scope: scope, contactIdentityId: contact, since: afterTheWindow, coreHeight: Self.agedTip,
            shieldedSpendState: { _ in .unrecorded }), .awaitingDecision)
        XCTAssertTrue(try locked(.unrecorded, since: lockWindowStart))
        XCTAssertFalse(try locked(.confirmed, since: lockWindowStart))
        XCTAssertFalse(try locked(.failed, since: lockWindowStart))
        var asked: [String] = []
        _ = try reopened.hasUnresolvedEntry(
            scope: scope, contactIdentityId: contact, since: afterTheWindow,
            shieldedSpendState: { asked.append($0.address); return .pending })
        XCTAssertEqual(asked, ["reserved-contact-address"])
    }

    /// The SDK state of a withdrawal comes from its activity rows for the
    /// reserved address: Pending wins, then Confirmed, then Failed; no row,
    /// or only an Unknown one, is unrecorded.
    @MainActor
    func testShieldedWithdrawalStateComesFromTheAddressesActivityRows() throws {
        let walletId = Data(repeating: 0x41, count: 32)
        let script = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0x52), count: 20) + [0x88, 0xac])
        let otherScript = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0x53), count: 20) + [0x88, 0xac])
        let address = try XCTUnwrap(ScriptAddressCodec.address(forScript: script, network: .testnet))
        var nextId: UInt8 = 0
        func container(_ rows: [(status: Int, kind: Int, wallet: Data, counterparty: Data)]) throws -> ModelContainer {
            let config = ModelConfiguration(schema: DashModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: DashModelContainer.schema, configurations: [config])
            for row in rows {
                nextId += 1
                container.mainContext.insert(PersistentShieldedActivity(
                    walletId: row.wallet, accountIndex: 0, entryId: Data(repeating: nextId, count: 32),
                    kindTag: row.kind, direction: 1, status: row.status, amount: 1_000_000, fee: 1000, hasFee: true,
                    blockHeight: 0, hasBlockHeight: false, createdAtMs: 1_800_000_000_000,
                    identityId: Data(), counterparty: row.counterparty, memo: Data(), noteCmxs: Data(),
                    spentNullifiers: Data(repeating: nextId, count: 32)))
            }
            try container.mainContext.save()
            return container
        }
        func state(_ rows: [(status: Int, kind: Int, wallet: Data, counterparty: Data)],
                   address: String = address) throws -> DashPayWithdrawalStore.ShieldedSpendState {
            WalletSendService.shieldedWithdrawalState(
                to: address, walletId: walletId, network: .testnet, in: try container(rows))
        }
        let otherWallet = Data(repeating: 0x42, count: 32)
        XCTAssertEqual(try state([]), .unrecorded)
        XCTAssertEqual(try state([(3, 5, walletId, script)]), .unrecorded)
        XCTAssertEqual(try state([(1, 4, walletId, script), (1, 5, otherWallet, script), (2, 5, walletId, otherScript)]),
                       .unrecorded, "another kind, wallet or address")
        XCTAssertEqual(try state([(2, 5, walletId, script)]), .failed)
        XCTAssertEqual(try state([(2, 5, walletId, script), (1, 5, walletId, script)]), .confirmed)
        XCTAssertEqual(try state([(1, 5, walletId, script), (0, 5, walletId, script)]), .pending)
        XCTAssertEqual(try state([(0, 5, walletId, script)], address: ""), .unrecorded)
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
        XCTAssertEqual(try unpaidStreak, 1, "its outcome is unknown until the SDK answers")
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

    /// Only evidence that an address was paid ends the run: a withdrawal the
    /// SDK accepted and didn't fail, a Shielded one it confirmed, or a Core
    /// payment. An attempt whose outcome is unknown counts.
    func testOnlyEvidenceOfAPaymentEndsTheStreak() throws {
        func streak(_ state: DashPayWithdrawalStore.ShieldedSpendState = .pending) throws -> Int {
            try store.unpaidReservationStreak(scope: scope, contactIdentityId: contact, shieldedSpendState: { _ in state })
        }
        try store.update(try begin(source: .platform), status: .submitted)
        try store.update(try begin(), status: .unused)
        _ = try begin(source: .platform)
        try store.update(try begin(source: .shielded), status: .unconfirmed)
        try store.update(try begin(), status: .unused)
        XCTAssertEqual(try streak(), 4, "unknown outcomes count, Platform or Shielded")
        XCTAssertEqual(try streak(.confirmed), 1, "a confirmed Shielded withdrawal paid its address")

        try store.update(try begin(source: .shielded), status: .submitted)
        XCTAssertEqual(try streak(), 0)
        XCTAssertEqual(try streak(.failed), 5, "the SDK failed it after accepting it")

        try store.recordCorePayment(scope: scope, contactIdentityId: contact, amountDuffs: 10_000)
        XCTAssertEqual(try streak(.failed), 0)
        let core = try XCTUnwrap(try store.entries(scope: scope, contactIdentityId: contact).first { $0.status == .corePayment })
        XCTAssertFalse(core.mayHaveBeenSubmitted)
    }

    /// A Platform attempt interrupted before its withdrawal was dispatched
    /// still counts once its lock has expired: the address is used up.
    func testAnAgedInterruptedAttemptStillCountsAfterReopening() throws {
        try store.update(try begin(), status: .unused)
        _ = try begin(source: .platform, coreHeight: Self.recordedTip)
        try store.update(try begin(), status: .unused)
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertEqual(try reopened.lockState(
            scope: scope, contactIdentityId: contact, since: Date().addingTimeInterval(60), coreHeight: Self.agedTip,
            shieldedSpendState: { _ in .unrecorded }), .awaitingDecision)
        XCTAssertEqual(try reopened.unpaidReservationStreak(scope: scope, contactIdentityId: contact), 3)
    }

    // MARK: - What the contact's history shows

    func testHistoryShowsWhatTheSDKSettled() throws {
        let attempt = try begin(source: .shielded)
        try store.update(attempt, status: .unconfirmed)
        let unconfirmed = try XCTUnwrap(store.entries(scope: scope, contactIdentityId: contact).first)
        let unknown = String(localized: "Status unknown", comment: "DashPay payment history: outcome not confirmed")
        func shown(_ state: DashPayWithdrawalStore.ShieldedSpendState, _ entry: DashPayWithdrawalStore.Entry) -> [String?] {
            SwiftDashSDKContactsService.shownWithdrawals([entry], shieldedSpendState: { _ in state }).map(\.1)
        }
        XCTAssertEqual(shown(.pending, unconfirmed), [unknown])
        XCTAssertEqual(shown(.unrecorded, unconfirmed), [unknown])
        XCTAssertEqual(shown(.confirmed, unconfirmed), [nil])
        XCTAssertEqual(shown(.failed, unconfirmed), [], "a failed withdrawal sent nothing")

        var submitted = unconfirmed
        submitted.status = .submitted
        XCTAssertEqual(shown(.pending, submitted), [nil])
        var unused = unconfirmed
        unused.status = .unused
        XCTAssertEqual(shown(.confirmed, unused), [])
        var platform = try begin(source: .platform)
        platform.status = .unconfirmed
        XCTAssertEqual(shown(.failed, platform), [unknown], "the Shielded state says nothing about a Platform withdrawal")
    }

    // MARK: - Chains

    /// Named devnets share a network kind but never a journal; removing the
    /// wallet clears every chain's.
    func testNamedDevnetsKeepSeparateJournals() throws {
        let a = DashPayWithdrawalStore.Scope(networkRaw: 2, walletId: scope.walletId, ownerIdentityId: scope.ownerIdentityId,
                                             chain: "devnet-a_1")
        let b = DashPayWithdrawalStore.Scope(networkRaw: 2, walletId: scope.walletId, ownerIdentityId: scope.ownerIdentityId,
                                             chain: "devnet-b")
        _ = try begin(scope: a)
        XCTAssertTrue(try store.hasUnresolvedEntry(scope: a, contactIdentityId: contact, since: .distantPast))
        XCTAssertFalse(try store.hasUnresolvedEntry(scope: b, contactIdentityId: contact, since: .distantPast))
        XCTAssertTrue(try store.entries(scope: b, contactIdentityId: contact).isEmpty)
        _ = try begin(scope: b)
        XCTAssertEqual(try store.files(ofWallet: scope.walletId).count, 2)
        try store.clearForWallet(walletId: scope.walletId)
        XCTAssertTrue(try store.entries(scope: a, contactIdentityId: contact).isEmpty)
        XCTAssertTrue(try store.entries(scope: b, contactIdentityId: contact).isEmpty)
    }

    /// A record written before scopes named their chain reads as its kind's.
    func testAScopeWithoutAChainReadsAsItsNetworkKind() throws {
        let legacy = Data(#"{"networkRaw":1,"walletId":"AQ==","ownerIdentityId":"Ag=="}"#.utf8)
        let decoded = try JSONDecoder().decode(DashPayWithdrawalStore.Scope.self, from: legacy)
        XCTAssertEqual(decoded.chain, "testnet")
        XCTAssertEqual(decoded, DashPayWithdrawalStore.Scope(networkRaw: 1, walletId: Data([1]), ownerIdentityId: Data([2])))
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

    /// The cap names what it knows: no address can be reserved. Some of the
    /// attempts behind it may have paid, so it never says they were not sent.
    func testTheCapMessageDoesNotClaimAmbiguousPaymentsWereNotSent() throws {
        let recipient = ContactPaymentRecipient(
            identityId: contact, displayName: "contact", walletId: scope.walletId,
            ownerIdentityId: scope.ownerIdentityId, network: .testnet)
        for _ in 0..<3 {
            try store.update(try begin(), status: .unused)
        }
        _ = try begin(source: .platform)
        try store.update(try begin(source: .platform), status: .unconfirmed)
        let reopened = DashPayWithdrawalStore(directory: directory)
        XCTAssertThrowsError(try WalletSendService.rejectIfTooManyUnpaidReservations(recipient, store: reopened)) {
            let message = $0.localizedDescription
            XCTAssertTrue(message.contains("No more payment addresses can be reserved"), message)
            XCTAssertTrue(message.contains("received it before paying again"), message)
            XCTAssertFalse(message.contains("not sent"), message)
        }
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
            PlatformAddressSyncCoordinator.SendError.notSubmitted(CocoaError(.fileReadUnknown)),
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
    func testShieldedContactWithdrawalIsRefusedBeforeWalletResolutionOrReservation() async throws {
        let coordinator = ShieldedTransferCoordinator(contactWithdrawalStore: store)
        let recipient = ContactPaymentRecipient(
            identityId: contact, displayName: "Contact", walletId: scope.walletId,
            ownerIdentityId: scope.ownerIdentityId, network: .testnet)

        await coordinator.performWithdraw(amountCredits: 2_000_000_000, contactRecipient: recipient)

        guard case ShieldedTransferCoordinator.CoordinatorError.shieldedContactPaymentsUnavailable? = coordinator.lastFailure else {
            return XCTFail("A contact withdrawal must be refused before resolving the active wallet")
        }
        XCTAssertEqual(coordinator.phase, .failed(
            ShieldedTransferCoordinator.CoordinatorError.shieldedContactPaymentsUnavailable.localizedDescription))
        XCTAssertTrue(try store.entries(scope: scope, contactIdentityId: contact).isEmpty)
        XCTAssertFalse(coordinator.contactWithdrawalOutcomeUnknown)
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
        let outcomes = WalletSendService.shared.unknownContactPaymentOutcomes
        XCTAssertTrue(outcomes.contains(scope: scope, contactIdentityId: contact))
        let otherWallet = DashPayWithdrawalStore.Scope(
            networkRaw: scope.networkRaw, walletId: Data(repeating: 0xEE, count: 32),
            ownerIdentityId: scope.ownerIdentityId, chain: scope.chain)
        let otherDevnet = DashPayWithdrawalStore.Scope(
            networkRaw: scope.networkRaw, walletId: scope.walletId,
            ownerIdentityId: scope.ownerIdentityId, chain: "devnet-other")
        XCTAssertFalse(outcomes.contains(scope: otherWallet, contactIdentityId: contact))
        XCTAssertFalse(outcomes.contains(scope: otherDevnet, contactIdentityId: contact))
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

    /// A local read in front of the withdrawal SDK call that fails submitted
    /// nothing: the attempt is dropped as retryable, not left unknown. A
    /// `SendError` from there keeps its own case.
    @MainActor
    func testALocalReadFailingBeforeTheSDKCallIsNotASubmission() async throws {
        let readFailure = CocoaError(.fileReadUnknown)
        var thrown: Error?
        do {
            _ = try await PlatformAddressSyncCoordinator.beforeSubmission { () throws -> Int in throw readFailure }
        } catch {
            thrown = error
        }
        let error = try XCTUnwrap(thrown)
        guard case PlatformAddressSyncCoordinator.SendError.notSubmitted = error else {
            return XCTFail("expected notSubmitted, got \(error)")
        }
        XCTAssertEqual(error.localizedDescription, readFailure.localizedDescription)
        let (coordinator, attempt) = try coordinatorAndAttempt()
        XCTAssertFalse(coordinator.concludeUncertainContactWithdrawal(attempt, error: error))
        XCTAssertEqual(try store.entries(scope: scope, contactIdentityId: contact).map(\.status), [.unused])
        XCTAssertFalse(coordinator.contactWithdrawalOutcomeUnknown)

        do {
            _ = try await PlatformAddressSyncCoordinator.beforeSubmission { () throws -> Int in
                throw PlatformAddressSyncCoordinator.SendError.noFundedAddress
            }
            XCTFail("expected a throw")
        } catch PlatformAddressSyncCoordinator.SendError.noFundedAddress {
        } catch {
            XCTFail("expected noFundedAddress, got \(error)")
        }
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

    func testOnlyShieldedFundedDoesNotOfferShieldedContactPayments() {
        let result = plan([.shielded: 2_000_000])
        XCTAssertEqual(result.sources, [.core])
        XCTAssertEqual(result.initialSource, .core)
        XCTAssertFalse(result.offersChoice)
    }

    func testSeveralFundedBalancesOfferChoiceStartingWithTransparent() {
        let result = plan([.core: 1, .platform: 2_000_000, .shielded: 3_000_000])
        XCTAssertEqual(result.initialSource, .core)
        XCTAssertTrue(result.offersChoice)
        XCTAssertEqual(result.sources, [.core, .platform])
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

    /// An open amount step follows the journal: an attempt written while it
    /// is up locks it without the contact being chosen again.
    @MainActor
    func testAnOpenContactStepFollowsThePaymentLock() throws {
        let contact = ContactItem.fixture(idByte: 0x5c, relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let recipient = ContactPaymentRecipient(
            identityId: contact.contactIdentityId, displayName: "c",
            walletId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            ownerIdentityId: Data(repeating: 2, count: 32), network: .testnet)
        let viewModel = SendViewModel(contactLookup: { _ in contact })
        viewModel.setContactRecipient(contact, paymentRecipient: recipient)
        XCTAssertFalse(viewModel.contactSendOutcomeIsUnknown)
        let locked = expectation(description: "locked")
        let watch = viewModel.$contactSendOutcomeIsUnknown.filter { $0 }.first().sink { _ in locked.fulfill() }
        let entry = try DashPayWithdrawalStore.shared.begin(
            scope: .init(recipient), contactIdentityId: contact.contactIdentityId,
            address: "reserved-contact-address", amountDuffs: 10_000, source: .platform)
        defer { try? DashPayWithdrawalStore.shared.remove(entry) }
        wait(for: [locked], timeout: 5)
        watch.cancel()
    }

    /// A change no journal notification announces — a Shielded activity row
    /// the SDK's persister settles, or here a session outcome — reaches an
    /// open step on the next persister save, without choosing the contact
    /// again.
    func testAnOpenContactStepRereadsTheLockOnAPersisterSave() {
        let contact = ContactItem.fixture(idByte: 0x5d, relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let recipient = ContactPaymentRecipient(
            identityId: contact.contactIdentityId, displayName: "c",
            walletId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            ownerIdentityId: Data(repeating: 2, count: 32), network: .testnet)
        let viewModel = SendViewModel(contactLookup: { _ in contact })
        viewModel.setContactRecipient(contact, paymentRecipient: recipient)
        XCTAssertFalse(viewModel.contactSendOutcomeIsUnknown)
        let outcomes = WalletSendService.shared.unknownContactPaymentOutcomes
        outcomes.record(scope: .init(recipient), contactIdentityId: contact.contactIdentityId)
        defer { outcomes.removeAll(walletIds: [recipient.walletId]) }
        let locked = expectation(description: "locked")
        let watch = viewModel.$contactSendOutcomeIsUnknown.filter { $0 }.first().sink { _ in locked.fulfill() }
        NotificationCenter.default.post(name: .NSManagedObjectContextDidSave, object: nil)
        wait(for: [locked], timeout: 5)
        watch.cancel()
    }

    /// A removed wallet's session outcomes go with it; other wallets keep theirs.
    func testRemovingAWalletClearsOnlyItsSessionOutcomes() {
        let outcomes = UnknownContactPaymentOutcomes()
        let contact = Data(repeating: 7, count: 32)
        func scope(_ byte: UInt8) -> DashPayWithdrawalStore.Scope {
            .init(networkRaw: 1, walletId: Data(repeating: byte, count: 32), ownerIdentityId: Data(repeating: 2, count: 32))
        }
        outcomes.record(scope: scope(0xA1), contactIdentityId: contact)
        outcomes.record(scope: scope(0xB2), contactIdentityId: contact)
        outcomes.removeAll(walletIds: [scope(0xA1).walletId])
        XCTAssertFalse(outcomes.contains(scope: scope(0xA1), contactIdentityId: contact))
        XCTAssertTrue(outcomes.contains(scope: scope(0xB2), contactIdentityId: contact))
        outcomes.removeAll()
        XCTAssertFalse(outcomes.contains(scope: scope(0xB2), contactIdentityId: contact))
    }

    /// Two contacts with one display name differ on the confirmation by
    /// username, or by identity without one.
    func testTheConfirmationTellsContactsWithOneNameApart() {
        func recipient(_ byte: UInt8, username: String?) -> ContactPaymentRecipient {
            ContactPaymentRecipient(
                identityId: Data(repeating: byte, count: 32), displayName: "Alex",
                walletId: Data(repeating: 1, count: 32), ownerIdentityId: Data(repeating: 2, count: 32),
                network: .testnet, username: username)
        }
        XCTAssertEqual(recipient(1, username: "alex-1").distinguishingDetail, "alex-1")
        XCTAssertNil(recipient(1, username: "Alex").distinguishingDetail)
        XCTAssertEqual(recipient(0xab, username: nil).distinguishingDetail, "ID abababababab…")
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
        XCTAssertEqual(picker.validSources, [.core, .platform])
        picker.source = .shielded
        XCTAssertNil(picker.route)
        XCTAssertFalse(picker.canContinue)
    }

    /// The From step lists only the balances one contact payment can be
    /// paid from; a Platform balance whose largest address can't cover the
    /// fees and the floor is not offered.
    func testFromStepOffersOnlyBalancesThatCanPayTheContact() {
        let contact = ContactItem.fixture(relationship: .established, createdAt: Date(timeIntervalSince1970: 0))
        let payable: [ChainNetwork: UInt64] = [.core: 5_000, .platform: 0, .shielded: 2_000]
        let viewModel = SendViewModel(contactLookup: { _ in contact }, contactPayableDuffs: { payable[$0] ?? 0 })
        viewModel.setContactRecipient(contact, paymentRecipient: capturedRecipient(for: contact))
        XCTAssertEqual(viewModel.validSources, [.core])
        XCTAssertFalse(viewModel.contactOffersSourceChoice)
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

    /// Until a restored wallet's first sync has found its payments, the SDK
    /// could reserve an address already paid, so no contact payment starts.
    @MainActor
    func testContactPaymentWaitsForTheRestoredWalletsFirstSync() throws {
        try XCTSkipIf(SyncingActivityMonitor.shared.state == .syncDone)
        let options = DWGlobalOptions.sharedInstance()
        let saved = options.initialRestoreSyncGate
        defer { options.initialRestoreSyncGate = saved }
        options.initialRestoreSyncGate = .everyNetwork
        let recipient = ContactPaymentRecipient(
            identityId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), displayName: "c",
            walletId: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            ownerIdentityId: Data(repeating: 2, count: 32), network: .testnet)
        let service = WalletSendService.shared
        XCTAssertThrowsError(try service.beginContactPayment(recipient, validate: { _ in })) {
            XCTAssertEqual($0.localizedDescription, WalletSendService.contactPaymentRestoreSyncMessage)
        }
        XCTAssertFalse(service.contactPaymentClaims.isClaimed(contactIdentityId: recipient.identityId))
    }

    /// A contact that was removed, is no longer established, or whose payment
    /// channel broke is refused wherever the recipient is validated — before
    /// authorization, at reservation and before submission.
    @MainActor
    func testAContactThatCannotBePaidIsRefused() {
        let id = Data(repeating: 0xaa, count: 32)
        let at = Date(timeIntervalSince1970: 0)
        func reason(_ contact: ContactItem?) -> String? {
            WalletSendService.contactUnavailableMessage(for: id, lookup: { _ in contact })
        }
        XCTAssertEqual(reason(nil), SendViewModel.contactGoneMessage)
        XCTAssertEqual(reason(.fixture(relationship: .outgoing, createdAt: at)), SendViewModel.contactGoneMessage)
        XCTAssertEqual(
            reason(.fixture(relationship: .established, createdAt: at, paymentChannelBroken: true)),
            SendViewModel.contactPaymentsUnavailableMessage)
        XCTAssertNil(reason(.fixture(relationship: .established, createdAt: at)))
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
