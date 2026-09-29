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
        if invitation.rawLink == heldLink {
            await withCheckedContinuation { held = $0 }
        }
        return results[invitation.rawLink] ?? nil
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
    private var rearms = 0
    private var outcomes: [InvitationValidation] = []
    private var cancellables = Set<AnyCancellable>()

    private let walletA = InvitationScope(networkRawValue: 1, walletIdHex: "walletA")
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
            isActive: { _ in true },
            rearmIdentityRefresh: { [unowned self] in self.rearms += 1 },
            isWalletIneligible: { [unowned self] in self.isIneligible },
            validate: { await validator.validate($0) },
            isReadyToValidate: { true },
            isSynced: { true },
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
