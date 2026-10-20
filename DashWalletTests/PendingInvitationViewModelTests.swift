//
//  PendingInvitationViewModelTests.swift
//  DashWalletTests
//
//  The Home card's view model decides when a stored invitation is checked,
//  when a verdict removes it, and when the user sees that verdict. The
//  network check is replaced by a scripted one; the store runs on fake
//  Keychain storage.
//

import Combine
import SwiftDashSDK
import XCTest
@testable import dashpay

/// A scripted network check: answers from `results` per link, and can hold
/// one link's answer until the test releases it.
@MainActor
private final class ScriptedValidator {
    var results: [String: InvitationValidation?] = [:]
    private(set) var calls: [String] = []
    var heldLink: String?
    private var held: CheckedContinuation<Void, Never>?

    func validate(_ invitation: PendingInvitation) async -> InvitationValidation? {
        calls.append(invitation.rawLink)
        // The answer is the one scripted when the check started.
        let result = results[invitation.rawLink] ?? nil
        if invitation.rawLink == heldLink {
            await withCheckedContinuation { held = $0 }
        }
        return result
    }

    var isHolding: Bool { held != nil }

    func release() {
        heldLink = nil
        held?.resume()
        held = nil
    }
}

@MainActor
final class PendingInvitationViewModelTests: XCTestCase {

    private var storage: FakeSecretStorage!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: PendingInvitationStore!
    private var validator: ScriptedValidator!
    private var isIneligible = false
    private var isRegistering = false
    private var registrationActivity = PassthroughSubject<Bool, Never>()
    /// nil: every scope counts as active.
    private var activeScope: InvitationScope?
    private var rearms = 0
    private var outcomes: [InvitationValidation] = []
    private var cancellables = Set<AnyCancellable>()

    private let walletA = InvitationScope(networkRawValue: 1, walletIdHex: "walletA")
    private let walletB = InvitationScope(networkRawValue: 1, walletIdHex: "walletB")
    private let linkA = "dashpay://invite?du=alice&assetlocktx=\(String(repeating: "ab", count: 32))&pk=A&islock=null"
    private let linkB = "dashpay://invite?du=bob&assetlocktx=\(String(repeating: "cd", count: 32))&pk=B&islock=null"
    private let inviter = InvitationInviter(username: "alice", displayName: nil, avatarURL: nil)

    override func setUp() {
        super.setUp()
        storage = FakeSecretStorage()
        suiteName = "PendingInvitationViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        let scope = walletA
        store = PendingInvitationStore(
            storage: storage,
            defaults: defaults,
            currentScope: { scope },
            hasRegisteredUsername: { false },
            isActiveAndBound: { _ in true })
        validator = ScriptedValidator()
        isIneligible = false
        isRegistering = false
        activeScope = nil
        rearms = 0
        outcomes = []
    }

    override func tearDown() {
        cancellables.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeViewModel() -> PendingInvitationViewModel {
        let validator = validator!
        let viewModel = PendingInvitationViewModel(
            store: store,
            isActive: { [unowned self] scope in self.activeScope.map { $0 == scope } ?? true },
            rearmIdentityRefresh: { [unowned self] in self.rearms += 1 },
            isWalletIneligible: { [unowned self] in self.isIneligible },
            validate: { await validator.validate($0) },
            isReadyToValidate: { true },
            isSynced: { true },
            isRegistrationInFlight: { [unowned self] in self.isRegistering },
            registrationActivity: registrationActivity.eraseToAnyPublisher(),
            observesSyncMonitor: false,
            notReadyRetryDelay: 1_000_000)
        viewModel.definitiveOutcomes
            .sink { [unowned self] in self.outcomes.append($0) }
            .store(in: &cancellables)
        return viewModel
    }

    private var valid: InvitationValidation {
        .valid(tier: .nonContested, amountDuffs: 3_000_000, inviter: inviter)
    }

    /// Lets the view model's tasks run until `condition` holds.
    private func settle(until condition: @escaping @MainActor () -> Bool,
                        file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("condition not reached", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    // MARK: - Finished registration

    /// The registration finished but the copy could not be removed: the card
    /// goes and is not checked (the new username would read as "already has
    /// one"), on this reload and the next.
    func testNoCardOrCheckWhileAFinishedRegistrationsRemovalIsOwed() async throws {
        XCTAssertEqual(store.receive(linkA), .stored)
        validator.results[linkA] = .alreadyHasIdentity
        validator.heldLink = linkA
        let viewModel = makeViewModel()
        await settle(until: { self.validator.isHolding })
        let invitation = try XCTUnwrap(store.pending)
        let account = PendingInvitationStore.keychainPrefix + walletA.storageKey
        storage.undeletable = [account]
        XCTAssertFalse(store.retireFinished(invitation))
        validator.release()
        XCTAssertNil(viewModel.invitation, "the card goes with the finished registration")

        store.reload()
        XCTAssertNil(store.pending, "a reload does not bring it back")
        XCTAssertNil(viewModel.invitation, "so the card has nothing to check")
        XCTAssertEqual(validator.calls, [linkA], "only the check from before the registration ran")
        XCTAssertTrue(outcomes.isEmpty, "no 'already has one' dialog after a finished registration")
    }

    // MARK: - Verdicts

    func testDefinitiveVerdictRemovesTheCopyAndIsDeliveredOnce() async {
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)

        await settle { !self.outcomes.isEmpty }
        XCTAssertEqual(outcomes, [.alreadyClaimed(inviter: inviter)])
        XCTAssertNil(store.pending)
        XCTAssertTrue(storage.items.isEmpty, "a spent voucher leaves the Keychain")
        XCTAssertEqual(viewModel.undeliveredOutcome, .alreadyClaimed(inviter: inviter))

        viewModel.validateIfPossible()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(outcomes.count, 1, "nothing is left to check, so nothing is emitted again")
        XCTAssertEqual(validator.calls, [linkA])
    }

    /// A's verdict waits for a visible Home; invitation B then arrives in the
    /// same wallet. A's dialog must not be offered while B is the card.
    func testWaitingVerdictIsDroppedWhenAnotherInvitationReplacesIt() async {
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        validator.results[linkB] = .undetermined
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { !self.outcomes.isEmpty }
        XCTAssertEqual(viewModel.undeliveredOutcome, .alreadyClaimed(inviter: inviter))

        XCTAssertEqual(store.receive(linkB), .stored)
        XCTAssertEqual(viewModel.invitation?.rawLink, linkB)
        XCTAssertNil(viewModel.undeliveredOutcome, "A's dialog is not shown over B's card")
        await settle { self.validator.calls.contains(self.linkB) }
        await settle { viewModel.cardState == .undetermined }
    }

    /// A leftover copy of the same voucher coming back (a failed clean-up,
    /// or the link opened again) keeps the verdict waiting for it.
    func testTheSameVoucherComingBackKeepsItsWaitingVerdict() async {
        validator.results[linkA] = .alreadyRequestedUsername
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { self.outcomes.count == 1 }
        validator.results[linkA] = .undetermined

        XCTAssertEqual(store.receive(linkA), .stored)
        XCTAssertEqual(viewModel.undeliveredOutcome, .alreadyRequestedUsername)
    }

    func testTransientVerdictKeepsTheInvitation() async {
        validator.results[linkA] = .undetermined
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)

        await settle { viewModel.cardState == .undetermined }
        XCTAssertEqual(store.pending?.rawLink, linkA)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testACheckFinishingForAReplacedInvitationIsDiscarded() async {
        validator.heldLink = linkA
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        validator.results[linkB] = valid
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { self.validator.isHolding }

        // Hidden while its check runs, and another link takes its place.
        viewModel.hide()
        XCTAssertEqual(store.receive(linkB), .stored)
        validator.release()

        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }
        XCTAssertEqual(validator.calls, [linkA, linkB], "the replacement gets its own check")
        XCTAssertTrue(outcomes.isEmpty, "the hidden invitation's verdict is not shown")
        XCTAssertEqual(store.pending?.rawLink, linkB)
    }

    // MARK: - Wallet not ready

    func testThreeNotReadyResultsOfferRetry() async {
        validator.results[linkA] = .some(nil)
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)

        await settle { viewModel.cardState == .undetermined }
        XCTAssertEqual(validator.calls.count, InvitationNotReadyPolicy.attemptsBeforeRetry)
        XCTAssertEqual(rearms, InvitationNotReadyPolicy.attemptsBeforeRetry)
    }

    func testFailedNameReadNotificationsDoNotRestartChecks() async {
        validator.results[linkA] = .some(nil)
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { viewModel.cardState == .undetermined }
        let checks = validator.calls.count

        // Each re-armed name read that fails posts this notification.
        for _ in 0..<5 {
            NotificationCenter.default.post(name: .DWDashPayRegistrationStatusUpdated, object: nil)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(validator.calls.count, checks, "the retry budget is not bypassed")
        XCTAssertEqual(viewModel.cardState, .undetermined)
    }

    // MARK: - Create

    func testCreateInsideTheCacheWindowRechecksAnIneligibleWallet() async {
        validator.results[linkA] = valid
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }
        XCTAssertEqual(validator.calls.count, 1)

        // A username was registered elsewhere since the cached verdict.
        isIneligible = true
        validator.results[linkA] = .alreadyHasIdentity
        var proceeded = false
        viewModel.create { _, _ in proceeded = true }

        await settle { !self.outcomes.isEmpty }
        XCTAssertEqual(validator.calls.count, 2, "the cached valid verdict is not trusted")
        XCTAssertFalse(proceeded)
        XCTAssertEqual(outcomes, [.alreadyHasIdentity])
    }

    func testCreateInsideTheCacheWindowUsesTheCachedVerdict() async {
        validator.results[linkA] = valid
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }

        var tier: InvitationTier?
        viewModel.create { _, proceededTier in tier = proceededTier }
        XCTAssertEqual(tier, .nonContested)
        XCTAssertEqual(validator.calls.count, 1)
    }

    // MARK: - Scope of a waiting verdict

    func testVerdictForOneWalletIsNotShownOrUsedUpInAnother() async {
        validator.results[linkA] = .alreadyRequestedUsername
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { viewModel.undeliveredOutcome != nil }

        // Home was off screen; the user switches to another wallet.
        activeScope = walletB
        XCTAssertNil(viewModel.undeliveredOutcome, "wallet B's Home has nothing to show")
        viewModel.acknowledgeOutcome(.alreadyRequestedUsername)

        activeScope = walletA
        XCTAssertEqual(viewModel.undeliveredOutcome, .alreadyRequestedUsername, "wallet A still gets its verdict")
        viewModel.acknowledgeOutcome(.alreadyRequestedUsername)
        XCTAssertNil(viewModel.undeliveredOutcome)
    }

    func testWaitingVerdictIsOfferedAgainOnReturnToItsWallet() async {
        validator.results[linkA] = .alreadyRequestedUsername
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { self.outcomes.count == 1 }

        activeScope = walletB
        NotificationCenter.default.post(
            name: SwiftDashSDKWalletState.activeWalletDidChangeNotification, object: nil)
        XCTAssertEqual(outcomes.count, 1, "nothing is offered to wallet B")

        activeScope = walletA
        NotificationCenter.default.post(
            name: SwiftDashSDKWalletState.activeWalletDidChangeNotification, object: nil)
        XCTAssertEqual(outcomes, [.alreadyRequestedUsername, .alreadyRequestedUsername])
        XCTAssertEqual(viewModel.undeliveredOutcome, .alreadyRequestedUsername)
    }

    // MARK: - A registration in flight

    func testNoCheckRunsWhileARegistrationIsInFlight() async {
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        isRegistering = true
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)

        NotificationCenter.default.post(name: .DWDashPayRegistrationStatusUpdated, object: nil)
        viewModel.validateIfPossible()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(validator.calls.isEmpty, "our own claim must not read as someone else's")
        XCTAssertNotNil(store.pending)

        isRegistering = false
        NotificationCenter.default.post(name: .DWDashPayRegistrationStatusUpdated, object: nil)
        await settle { !self.outcomes.isEmpty }
        XCTAssertEqual(validator.calls, [linkA])
    }

    func testSkippedCheckRunsWhenTheRegistrationEndsWithoutAStatusChange() async {
        validator.results[linkA] = valid
        isRegistering = true
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(validator.calls.isEmpty)

        // A cancelled PIN: the attempt ends and nothing else is posted.
        isRegistering = false
        registrationActivity.send(false)
        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }
        XCTAssertEqual(validator.calls, [linkA])
    }

    func testVerdictFromACheckOverlappingARegistrationIsDiscarded() async {
        validator.heldLink = linkA
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { self.validator.isHolding }

        // The user submits the form while the check is still on the network;
        // the query then sees the voucher spent by that claim.
        isRegistering = true
        registrationActivity.send(true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        validator.release()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNotNil(store.pending, "our own claim must not remove the invitation")
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertNil(viewModel.undeliveredOutcome)

        // The attempt failed without spending it: a fresh check decides.
        validator.results[linkA] = valid
        isRegistering = false
        registrationActivity.send(false)
        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }
        XCTAssertEqual(validator.calls, [linkA, linkA])
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testVerdictIsDiscardedWhenTheRegistrationEndedBeforeTheCheckDid() async {
        validator.heldLink = linkA
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { self.validator.isHolding }

        registrationActivity.send(true)
        registrationActivity.send(false)
        try? await Task.sleep(nanoseconds: 20_000_000)
        validator.results[linkA] = valid
        validator.release()

        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }
        XCTAssertEqual(validator.calls, [linkA, linkA], "the overlapped answer is replaced by a fresh one")
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertNotNil(store.pending)
    }

    func testVerdictIsDiscardedWhileTheStartOfARegistrationIsNotYetReported() async {
        validator.heldLink = linkA
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { self.validator.isHolding }

        // The attempt is running, but its phase change has not arrived yet.
        isRegistering = true
        validator.results[linkA] = valid
        validator.release()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNotNil(store.pending)
        XCTAssertTrue(outcomes.isEmpty)

        isRegistering = false
        registrationActivity.send(false)
        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }
        XCTAssertEqual(validator.calls, [linkA, linkA])
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testCachedVerdictIsCheckedAgainWhenARegistrationEnds() async {
        validator.results[linkA] = valid
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { viewModel.cardState == .valid(tier: .nonContested, amountDuffs: 3_000_000) }

        registrationActivity.send(true)
        registrationActivity.send(false)
        await settle { self.validator.calls.count == 2 }
    }

    // MARK: - Wipe

    func testWipeDropsAnUndeliveredVerdict() async {
        validator.results[linkA] = .alreadyClaimed(inviter: inviter)
        let viewModel = makeViewModel()
        XCTAssertEqual(store.receive(linkA), .stored)
        await settle { viewModel.undeliveredOutcome != nil }

        XCTAssertTrue(store.eraseForWipe())
        XCTAssertNil(viewModel.undeliveredOutcome, "the old wallet's verdict is not shown after a wipe")
        store.resumeReceipt()
    }
}
