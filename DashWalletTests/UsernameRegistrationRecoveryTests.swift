import XCTest
@testable import dashpay
import SwiftDashSDK
import SwiftUI
import SwiftDashSDK

@MainActor
final class UsernameRegistrationRecoveryTests: XCTestCase {
    private enum Failure: Error { case cancelled, contextChanged, unavailable, insufficientCredits }

    func testUncertainTopUpRetainsFundingStageInsteadOfDPNSSubmission() {
        typealias Coordinator = DWIdentityRegistrationCoordinator
        let errors: [Error] = [
            SDKError.stateTransitionResultUnconfirmed("unknown"),
            PlatformWalletError.transactionBroadcastUnconfirmed("unknown"),
            PlatformWalletError.shieldedSpendUnconfirmed("unknown"),
        ]
        for error in errors {
            let failure = Coordinator.identityTopUpFailure(error)
            XCTAssertTrue(failure.isIdentityTopUp,
                          "Funding did not reach DPNS; its provisional bookmark must be withdrawn")
            guard case .identityTopUp(let underlying) = failure,
                  case Coordinator.CoordinatorError.platformWriteUnconfirmed = underlying else {
                return XCTFail("The funding-stage wrapper must retain the unconfirmed warning")
            }
            XCTAssertTrue(failure.localizedDescription.contains("could not be confirmed"))
        }
    }

    func testUnconfirmedPurchaseKeepsFormBlockedAfterItsWarning() async {
        typealias Error = DWIdentityRegistrationCoordinator.CoordinatorError
        let model = CreateUsernameViewModel.makeForPreview()
        let outcome = model.purchaseFailureOutcome(Error.purchase(Error.platformWriteUnconfirmed))
        guard case .submittedUnconfirmed = outcome else { return XCTFail("Expected purchase warning") }
        XCTAssertTrue(model.purchaseSubmissionUnconfirmed)
        XCTAssertFalse(model.canPurchaseListedNameDirectly)
        // A second action stays unknown even without a sale price; it must not reach funding.
        let retry = await model.purchaseListedUsername(name: "alpha")
        guard case .submittedUnconfirmed = retry else { return XCTFail("Purchase was reopened") }
    }

    func testDefinitePurchaseFailureDoesNotLockTheForm() {
        let model = CreateUsernameViewModel.makeForPreview()
        let outcome = model.purchaseFailureOutcome(Failure.insufficientCredits)
        guard case .failure = outcome else { return XCTFail("Expected a definite failure") }
        XCTAssertFalse(model.purchaseSubmissionUnconfirmed)
    }

    func testDefiniteTopUpFailureKeepsItsOriginalCause() {
        let failure = DWIdentityRegistrationCoordinator.identityTopUpFailure(Failure.insufficientCredits)
        guard case .identityTopUp(let underlying) = failure,
              case Failure.insufficientCredits = underlying else {
            return XCTFail("A definite refusal must not become an unconfirmed submission")
        }
    }

    func testNameReadinessRequiresSuccessfulReadAndExplicitRetryAfterFailure() throws {
        let readiness = IdentityNameReadiness()
        let scope = UsernameRegistrationDraftStore.Scope(network: "testnet", walletId: Data([1]), identityId: Data([2]))
        let other = UsernameRegistrationDraftStore.Scope(network: "mainnet", walletId: Data([1]), identityId: Data([2]))
        let first = try XCTUnwrap(readiness.begin(scope))
        XCTAssertNil(readiness.begin(scope), "Polling must not duplicate the in-flight read")
        readiness.finish(scope, generation: first, succeeded: false)
        XCTAssertFalse(readiness.isLoaded(scope))
        XCTAssertNil(readiness.begin(scope), "Failed reads wait for user retry")
        readiness.retry()
        let second = try XCTUnwrap(readiness.begin(scope))
        readiness.finish(scope, generation: second, succeeded: true)
        XCTAssertTrue(readiness.isLoaded(scope))
        XCTAssertFalse(readiness.isLoaded(other))
        readiness.retry(scope)
        let background = try XCTUnwrap(readiness.begin(scope, refresh: true))
        XCTAssertTrue(readiness.isLoaded(scope), "Background refresh preserves known absence")
        readiness.finish(scope, generation: background, succeeded: false)
        XCTAssertTrue(readiness.isLoaded(scope))
    }

    func testRetryReplacesStuckReadAndIgnoresItsLateCompletion() throws {
        let readiness = IdentityNameReadiness()
        let scope = UsernameRegistrationDraftStore.Scope(network: "testnet", walletId: Data([1]), identityId: Data([2]))
        let stuck = try XCTUnwrap(readiness.begin(scope))
        readiness.retry()
        let replacement = try XCTUnwrap(readiness.begin(scope))
        readiness.finish(scope, generation: stuck, succeeded: true)
        XCTAssertFalse(readiness.isLoaded(scope), "An obsolete success must not establish absence")
        readiness.finish(scope, generation: replacement, succeeded: true)
        readiness.finish(scope, generation: stuck, succeeded: false)
        XCTAssertTrue(readiness.isLoaded(scope), "An obsolete failure must not undo the replacement")
    }

    func testDraftSurvivesStoreRecreationAndIsScopedToNetworkWalletAndIdentity() throws {
        let suite = "dpns-recovery-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = UsernameRegistrationDraftStore.Scope(network: "mainnet", walletId: Data([1]), identityId: Data([2]))
        let draft = UsernameRegistrationDraftStore.Draft(username: "dash786", temporaryUsername: "dash786-temp")
        try UsernameRegistrationDraftStore(defaults: defaults).save(draft, for: scope)
        let restored = UsernameRegistrationDraftStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.draft(for: scope), draft)
        for other in [
            UsernameRegistrationDraftStore.Scope(network: "testnet", walletId: Data([1]), identityId: Data([2])),
            .init(network: "mainnet", walletId: Data([3]), identityId: Data([2])),
            .init(network: "mainnet", walletId: Data([1]), identityId: Data([4]))
        ] {
            XCTAssertNil(restored.draft(for: other))
        }
        restored.clear(for: scope)
        XCTAssertNil(restored.draft(for: scope))
    }

    func testRecoverySeparatesUnfinishedPaymentFromExistingIdentity() {
        XCTAssertFalse(UsernameRegistrationRecovery.none.isPending)
        XCTAssertNil(UsernameRegistrationRecovery.pendingCoreAssetLock.identityId)
        let recovery = UsernameRegistrationRecovery.identityNeedsUsername(Data([2]))
        XCTAssertTrue(recovery.isPending)
        XCTAssertEqual(recovery.identityId, Data([2]))
    }

    func testExistingIdentityNeverCallsIdentityCreationOrFunding() async throws {
        let identityId = Data(repeating: 1, count: 32)
        var fundingOrCreateCalls = 0
        var dpnsCalls = 0
        // The report's 0.09639635 DASH identity balance is sufficient even
        // when no Core, Platform-address or shielded funds remain.
        var identityCredits: UInt64 = 9_639_634_780
        let result = try await UsernameRegistrationRecoveryFlow.route(
            identityId: identityId,
            resume: { id in
                XCTAssertEqual(id, identityId)
                _ = try await UsernameRegistrationRecoveryFlow.run(
                    authorize: {}, validateContext: {}, lookup: { .available },
                    register: { dpnsCalls += 1; identityCredits -= 1_000 })
                return id
            },
            create: { fundingOrCreateCalls += 1; XCTFail("Must not create or fund an identity"); return Data() })
        XCTAssertEqual(result, identityId)
        XCTAssertEqual(fundingOrCreateCalls, 0)
        XCTAssertEqual(dpnsCalls, 1)
        XCTAssertEqual(identityCredits, 9_639_633_780)
    }

    func testResumeFailureCannotFallThroughToIdentityCreation() async {
        do {
            _ = try await UsernameRegistrationRecoveryFlow.route(
                identityId: Data([1]), resume: { _ in throw Failure.insufficientCredits },
                create: { XCTFail("Failed DPNS must never fall back to funding"); return Data() })
            XCTFail("Expected DPNS error")
        } catch Failure.insufficientCredits {} catch { XCTFail("Unexpected \(error)") }
    }

    func testAvailableNameAuthorizesChecksContextThenSubmitsOnce() async throws {
        var events: [String] = []
        let result = try await UsernameRegistrationRecoveryFlow.run(
            authorize: { events.append("auth") },
            validateContext: { events.append("context") },
            lookup: { events.append("lookup"); return .available },
            register: { events.append("dpns") })
        XCTAssertEqual(result, .available)
        XCTAssertEqual(events, ["auth", "context", "lookup", "context", "dpns"])
    }

    func testContextSwitchDuringSuccessfulBroadcastDoesNotReportFailure() async throws {
        var current = true
        var broadcasts = 0
        let result = try await UsernameRegistrationRecoveryFlow.run(
            authorize: {},
            validateContext: { if !current { throw Failure.contextChanged } },
            lookup: { .available },
            register: { broadcasts += 1; current = false })
        XCTAssertEqual(result, .available)
        XCTAssertEqual(broadcasts, 1)
    }

    func testOwnedAndVotingNamesReconcileWithoutBroadcasting() async throws {
        for state in [UsernameRegistrationRecoveryFlow.NameState.owned, .voting] {
            let result = try await UsernameRegistrationRecoveryFlow.run(
                authorize: {}, validateContext: {}, lookup: { state },
                register: { XCTFail("Already submitted names must not spend credits again") })
            XCTAssertEqual(result, state)
        }
    }

    func testAuthenticationCancellationNeverQueriesOrBroadcasts() async {
        do {
            _ = try await UsernameRegistrationRecoveryFlow.run(
                authorize: { throw Failure.cancelled }, validateContext: {},
                lookup: { XCTFail("Cancelled authentication"); return .available },
                register: { XCTFail("Cancelled authentication") })
            XCTFail("Expected cancellation")
        } catch Failure.cancelled {} catch { XCTFail("Unexpected \(error)") }
    }

    func testWalletOrNetworkSwitchAfterAuthenticationOrLookupPreventsBroadcast() async {
        for failAtCheck in [1, 2] {
            var checks = 0
            do {
                _ = try await UsernameRegistrationRecoveryFlow.run(
                    authorize: {},
                    validateContext: {
                        checks += 1
                        if checks == failAtCheck { throw Failure.contextChanged }
                    },
                    lookup: { .available }, register: { XCTFail("Stale context") })
                XCTFail("Expected context change")
            } catch Failure.contextChanged {} catch { XCTFail("Unexpected \(error)") }
        }
    }

    func testFailedOrUnavailableLookupNeverImpliesAvailability() async {
        for error in [Failure.unavailable, .contextChanged] {
            do {
                _ = try await UsernameRegistrationRecoveryFlow.run(
                    authorize: {}, validateContext: {}, lookup: { throw error },
                    register: { XCTFail("A failed read must not spend credits") })
                XCTFail("Expected lookup error")
            } catch { }
        }
    }

    func testCompletedPurchaseDefersReconciliationAfterContextSwitch() {
        var reconciliations = 0
        XCTAssertFalse(UsernamePurchaseCompletion.reconcileIfCurrent(
            isCurrent: { false }, reconcile: { reconciliations += 1 }))
        XCTAssertEqual(reconciliations, 0)
        XCTAssertTrue(UsernamePurchaseCompletion.reconcileIfCurrent(
            isCurrent: { true }, reconcile: { reconciliations += 1 }))
        XCTAssertEqual(reconciliations, 1)
    }

    func testInsufficientCreditsReturnsErrorWithoutAutomaticRetryOrFunding() async {
        var broadcasts = 0
        do {
            _ = try await UsernameRegistrationRecoveryFlow.run(
                authorize: {}, validateContext: {}, lookup: { .available },
                register: { broadcasts += 1; throw Failure.insufficientCredits })
            XCTFail("Expected insufficient credits")
        } catch Failure.insufficientCredits {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertEqual(broadcasts, 1)
    }

    /// Wallet deletion drops that wallet's drafts under every network scope —
    /// a devnet scope name may itself contain dots — and no other wallet's.
    func testClearingAWalletsDraftsLeavesOtherWalletsAlone() throws {
        let suite = "UsernameRegistrationDraftCleanup"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UsernameRegistrationDraftStore(defaults: defaults)
        let draft = UsernameRegistrationDraftStore.Draft(username: "alice", temporaryUsername: nil)
        let removed = Data([0xaa, 0x11]), kept = Data([0xbb, 0x22])
        let removedScopes = ["testnet", "devnet-a.b"].map {
            UsernameRegistrationDraftStore.Scope(network: $0, walletId: removed, identityId: Data([1]))
        }
        // The removed wallet's id as another wallet's identity id is not a match.
        let keptScope = UsernameRegistrationDraftStore.Scope(network: "testnet", walletId: kept, identityId: removed)
        try (removedScopes + [keptScope]).forEach { try store.save(draft, for: $0) }

        store.clearAll(walletIdHex: "aa11")

        XCTAssertTrue(removedScopes.allSatisfy { store.draft(for: $0) == nil })
        XCTAssertEqual(store.draft(for: keptScope), draft)
    }
}

extension UsernameRegistrationRecoveryTests {
    private func unnamedIdentitySnapshot() -> DWCurrentUserIdentityInfo.Snapshot {
        .init(namesAreLoaded: true, balanceCredits: 9_639_634_780,
              identityId: Data(repeating: 1, count: 32), identityIdHex: String(repeating: "01", count: 32),
              username: nil, usernames: [], displayName: nil, avatarURL: nil, publicMessage: nil)
    }

    func testRestoredCompanionDraftSurvivesOpeningConfirmation() {
        let field = TemporaryUsernameFieldModel(acceptsOwnedName: true)
        field.restoreDraft("my-custom-777", for: "alpha")
        field.seedSuggestion(from: "alpha")
        XCTAssertEqual(field.trimmedText, "my-custom-777")
        field.seedSuggestion(from: "beta")
        XCTAssertEqual(field.trimmedText, "beta2")
    }

    func testLoadingIdentityDoesNotOfferRegistrationAndLoadedIdentityDoes() {
        var snapshot = unnamedIdentitySnapshot()
        snapshot.isLoading = true
        XCTAssertFalse(snapshot.needsUsername)
        snapshot.isLoading = false
        XCTAssertTrue(snapshot.needsUsername)
        XCTAssertEqual(snapshot.registrationRecovery, .identityNeedsUsername(snapshot.identityId!))
        snapshot.pendingContestedName = "dash786"
        XCTAssertFalse(snapshot.needsUsername)
    }

    func testUnloadedNamesDoNotImplyUnnamedIdentity() {
        var snapshot = unnamedIdentitySnapshot()
        snapshot.namesAreLoaded = false
        XCTAssertFalse(snapshot.needsUsername)
        XCTAssertEqual(snapshot.registrationRecovery, .none)
        snapshot.namesAreLoaded = true
        XCTAssertTrue(snapshot.needsUsername)
    }

    func testUnknownBalanceIsNotKnownZero() {
        XCTAssertNil(DWCurrentUserIdentityInfo.cachedBalanceCredits(0))
        XCTAssertNil(DWCurrentUserIdentityInfo.cachedBalanceCredits(nil))
        XCTAssertEqual(DWCurrentUserIdentityInfo.cachedBalanceCredits(42), 42)
        var snapshot = unnamedIdentitySnapshot()
        snapshot.balanceCredits = nil
        XCTAssertFalse(snapshot.hasKnownZeroBalance)
        snapshot.balanceCredits = 0
        XCTAssertTrue(snapshot.hasKnownZeroBalance)
        snapshot.balanceCredits = 9_639_634_780
        XCTAssertFalse(snapshot.hasKnownZeroBalance)
    }

    /// A recovered paid lock funds the identity and nothing more: when the
    /// name asked for costs more than the lock left, the run stops before any
    /// funding call; a lock that covers the name completes without one; and
    /// the retry — no longer a recovery — honours the amount it confirmed.
    func testRecoveredLockNeverAuthorizesANewTopUp() {
        typealias Coordinator = DWIdentityRegistrationCoordinator
        let confirmed: UInt64 = 25_000_000
        let plainLockCredits: UInt64 = 2_800_000_000

        // A 0.03 lock recovered, then a contested name: short, and not authorized.
        let contestedNeed = Coordinator.identityTopUpDuffs(
            requiredCredits: Coordinator.requiredRegistrationCredits(
                isContested: true, nameCount: 1,
                contestFundCredits: ContestedUsernameFee.Amounts.legacy.fundCredits),
            heldCredits: plainLockCredits)
        XCTAssertGreaterThan(contestedNeed, 0)
        let recovered = Coordinator.topUpAuthorization(confirmedDuffs: confirmed, recoveredPaidLock: true)
        XCTAssertNil(recovered)
        XCTAssertEqual(Coordinator.topUpDecision(neededDuffs: contestedNeed, authorizedDuffs: recovered), .notConfirmed)

        // The same lock for the plain name it was paid for: nothing to top up.
        let plainNeed = Coordinator.identityTopUpDuffs(
            requiredCredits: Coordinator.requiredRegistrationCredits(
                isContested: false, nameCount: 1,
                contestFundCredits: ContestedUsernameFee.Amounts.legacy.fundCredits),
            heldCredits: plainLockCredits)
        XCTAssertEqual(plainNeed, 0)
        XCTAssertEqual(Coordinator.topUpDecision(neededDuffs: plainNeed, authorizedDuffs: recovered), .notNeeded)

        // The retry, with the shortfall confirmed: within the ceiling it runs,
        // above it it stops, and an unconfirmed (0) amount authorizes nothing.
        let retry = Coordinator.topUpAuthorization(confirmedDuffs: confirmed, recoveredPaidLock: false)
        XCTAssertEqual(retry, confirmed)
        XCTAssertEqual(Coordinator.topUpDecision(neededDuffs: contestedNeed, authorizedDuffs: retry), .proceed)
        XCTAssertEqual(
            Coordinator.topUpDecision(neededDuffs: confirmed + 1, authorizedDuffs: retry),
            .exceedsConfirmed(confirmedDuffs: confirmed))
        XCTAssertEqual(Coordinator.topUpDecision(neededDuffs: contestedNeed, authorizedDuffs: 0), .notConfirmed)
    }

    /// A resolved contest retires the handoff record of that request and no
    /// other: left behind after a restart, a matching record made the row say
    /// "interrupted" for a request whose outcome was already known.
    func testResolvedContestRetiresOnlyItsOwnHandoffRecord() {
        let prefs = UsernamePrefs.shared
        let saved = prefs.inFlightRegistrationUsername
        defer { prefs.inFlightRegistrationUsername = saved }

        // Confirmed bookmark resolved, handoff marker for the same name unconsumed.
        prefs.inFlightRegistrationUsername = "Alice"
        prefs.retireInFlightRegistration(matching: "alice.dash")
        XCTAssertNil(prefs.inFlightRegistrationUsername)

        // Another request is in flight when the contest resolves.
        prefs.inFlightRegistrationUsername = "bob"
        prefs.retireInFlightRegistration(matching: "alice")
        XCTAssertEqual(prefs.inFlightRegistrationUsername, "bob")
    }

    /// Removing a wallet drops its registration reports on every network and
    /// leaves another wallet's alone; the full wipe drops them all. A wallet
    /// id is derived from the phrase, so a survivor would be read back by the
    /// same wallet re-imported.
    func testWalletDeletionClearsOnlyThatWalletsRegistrationRecords() throws {
        let suite = "UsernameRegistrationRecordCleanup"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let bases = UsernamePrefs.registrationRecordKeys
        XCTAssertEqual(bases.count, 7)
        let removed = Data([0xaa, 0x11]), kept = Data([0xbb, 0x22])
        func keys(_ wallet: Data) -> [String] {
            WalletEnvironment.NetworkKind.allCases.flatMap { network in
                bases.map {
                    JoinDashPayDismissalScope.scopedKey(
                        $0, networkRawValue: network.rawValue, walletIdHex: wallet.hexEncodedString())
                }
            }
        }
        (keys(removed) + keys(kept)).forEach { defaults.set("x", forKey: $0) }
        let drafts = UsernameRegistrationDraftStore(defaults: defaults)
        let draft = UsernameRegistrationDraftStore.Draft(username: "alice", temporaryUsername: nil)
        func scope(_ wallet: Data) -> UsernameRegistrationDraftStore.Scope {
            .init(network: "testnet", walletId: wallet, identityId: Data([1]))
        }
        try drafts.save(draft, for: scope(removed))
        try drafts.save(draft, for: scope(kept))
        // Not a registration report: neither cleanup touches it.
        let dismissal = JoinDashPayDismissalScope.storageKey(networkRawValue: 1, walletIdHex: removed.hexEncodedString())
        defaults.set(true, forKey: dismissal)

        UsernamePrefs.clearRegistrationRecords(walletIdHex: removed.hexEncodedString(), defaults: defaults)
        XCTAssertTrue(keys(removed).allSatisfy { defaults.object(forKey: $0) == nil })
        XCTAssertNil(drafts.draft(for: scope(removed)))
        XCTAssertTrue(keys(kept).allSatisfy { defaults.object(forKey: $0) != nil })
        XCTAssertEqual(drafts.draft(for: scope(kept)), draft)

        UsernamePrefs.clearAllRegistrationRecords(defaults: defaults)
        XCTAssertTrue(keys(kept).allSatisfy { defaults.object(forKey: $0) == nil })
        XCTAssertNil(drafts.draft(for: scope(kept)))
        XCTAssertNotNil(defaults.object(forKey: dismissal))
    }

    func testConfirmedNameDoesNotOfferRegistrationRecovery() {
        let snapshot = DWCurrentUserIdentityInfo.Snapshot(
            balanceCredits: 0, identityId: Data([1]), identityIdHex: "01",
            username: "confirmed-name", usernames: ["confirmed-name"],
            displayName: nil, avatarURL: nil, publicMessage: nil)
        XCTAssertFalse(snapshot.needsUsername)
        XCTAssertEqual(snapshot.registrationRecovery, .none)
    }

    // MARK: - Type-20 create failure classifier

    // The node's verdict text of an in-block rejection. Since platform v5.1-dev
    // it proves nothing on its own: a free rejection (anchor, nullifier, pool,
    // identity exists) reads the same as the paid key-state one.
    private var chargedText: String {
        "shielded identity-create-from-pool failed: Shielded broadcast failed: "
            + "state transition broadcast error: Identity public key with id 0 is already registered"
    }

    /// What the SDK throws once its proven reads show the inputs spent and no identity.
    private var chargedError: PlatformWalletError { .shieldedIdentityCreateInputsConsumed(chargedText) }

    func testProvenSpentInputsWithoutIdentityIsCharged() {
        XCTAssertEqual(ShieldedCreateFailureKind.classify(chargedError), .charged)
    }

    func testVerdictTextAloneIsNotCharged() {
        // A free in-block rejection carries the same text: no record, no "money came back".
        XCTAssertEqual(
            ShieldedCreateFailureKind.classify(PlatformWalletError.shieldedBroadcastFailed(chargedText)),
            .notClassified)
        for text in ["anchor not found", "nullifier already spent", "identity already exists"] {
            XCTAssertEqual(ShieldedCreateFailureKind.classify(PlatformWalletError.shieldedBroadcastFailed(
                "shielded identity-create-from-pool failed: Shielded broadcast failed: "
                    + "state transition broadcast error: " + text)), .notClassified, text)
        }
    }

    func testUnconfirmedSubmissionIsUnknownOutcome() {
        // A submission whose result is unknown is never "did not go through".
        for error: Error in [
            SDKError.stateTransitionResultUnconfirmed("unknown"),
            PlatformWalletError.transactionBroadcastUnconfirmed("unknown"),
            PlatformWalletError.shieldedSpendUnconfirmed("unknown"),
        ] {
            XCTAssertEqual(ShieldedCreateFailureKind.classify(error), .unknownOutcome, "\(error)")
            XCTAssertNil(DWIdentityRegistrationCoordinator.shieldedCreateFailure(error), "\(error)")
        }
    }

    func testCheckTxRejectionIsNotClassified() {
        // Same Swift case, built from `Error::Protocol` before any block: nothing was spent.
        let error = PlatformWalletError.shieldedBroadcastFailed(
            "shielded identity-create-from-pool failed: Shielded broadcast failed: "
                + "Protocol error: consensus error: Identity public key with id 0 is already registered")
        XCTAssertEqual(ShieldedCreateFailureKind.classify(error), .notClassified)
    }

    func testUnconfirmedCreateIsUnknownOutcomeNeverCharged() {
        let error = DWIdentityRegistrationCoordinator.CoordinatorError.shieldedCreateUnconfirmed
        XCTAssertEqual(ShieldedCreateFailureKind.classify(error), .unknownOutcome)
        XCTAssertEqual(
            ShieldedCreateFailureKind.classify(PlatformWalletError.shieldedBroadcastUnconfirmed(chargedText)),
            .unknownOutcome)
    }

    func testOtherErrorsAreNotClassified() {
        XCTAssertEqual(ShieldedCreateFailureKind.classify(PlatformWalletError.walletOperation(chargedText)),
                       .notClassified, "Only the proven charged case can be charged")
        XCTAssertEqual(ShieldedCreateFailureKind.classify(Failure.unavailable), .notClassified)
    }

    // MARK: - Charged failure record store

    private func chargedFailureDefaults() throws -> (UserDefaults, String) {
        let suite = "ShieldedChargedFailureStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (defaults, suite)
    }

    private func chargedFailureRecord(
        _ username: String = "alice", contested: Bool = false
    ) -> ShieldedChargedFailureStore.Record {
        .init(username: username, isContested: contested,
              exitDenominationDuffs: contested ? 25_000_000 : 3_000_000,
              fallbackAddress: Data([0, 1, 2]), snapshotCredits: 5_000, returnedDuffs: nil)
    }

    func testChargedFailureRecordSurvivesStoreRecreationAndIsScopedToNetworkAndWallet() throws {
        let (defaults, suite) = try chargedFailureDefaults()
        let record = chargedFailureRecord()
        ShieldedChargedFailureStore(defaults: defaults).save(record, networkRawValue: 1, walletIdHex: "aa11")

        let restored = ShieldedChargedFailureStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.record(networkRawValue: 1, walletIdHex: "aa11"), record)
        XCTAssertNil(restored.record(networkRawValue: 0, walletIdHex: "aa11"), "Other network (AC-07)")
        XCTAssertNil(restored.record(networkRawValue: 1, walletIdHex: "bb22"), "Other wallet (AC-07)")
        XCTAssertNotNil(defaults.data(forKey: JoinDashPayDismissalScope.scopedKey(
            "shieldedChargedFailureRecord", networkRawValue: 1, walletIdHex: "aa11")))

        restored.clear(networkRawValue: 1, walletIdHex: "aa11")
        XCTAssertNil(restored.record(networkRawValue: 1, walletIdHex: "aa11"))
        restored.clear(networkRawValue: 1, walletIdHex: "aa11")
    }

    func testChargedFailureStoreIgnoresTheUnboundScopeAndUndecodableValues() throws {
        let (defaults, _) = try chargedFailureDefaults()
        let store = ShieldedChargedFailureStore(defaults: defaults)
        for wallet in [nil, ""] as [String?] {
            store.save(chargedFailureRecord(), networkRawValue: 1, walletIdHex: wallet)
            XCTAssertNil(store.record(networkRawValue: 1, walletIdHex: wallet))
        }
        let base = ShieldedChargedFailureStore.baseKey
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix(base) })

        defaults.set(Data("not json".utf8), forKey: JoinDashPayDismissalScope.scopedKey(
            "shieldedChargedFailureRecord", networkRawValue: 1, walletIdHex: "aa11"))
        XCTAssertNil(store.record(networkRawValue: 1, walletIdHex: "aa11"))
    }

    func testSecondChargedFailureReplacesTheRecordAndReturnedAmountIsWriteOnce() throws {
        let (defaults, _) = try chargedFailureDefaults()
        let store = ShieldedChargedFailureStore(defaults: defaults)
        store.fixReturnedAmount(2_900_000, networkRawValue: 1, walletIdHex: "aa11")
        XCTAssertNil(store.record(networkRawValue: 1, walletIdHex: "aa11"), "No record: nothing to fix")

        store.save(chargedFailureRecord(), networkRawValue: 1, walletIdHex: "aa11")
        store.fixReturnedAmount(2_900_000, networkRawValue: 1, walletIdHex: "aa11")
        store.fixReturnedAmount(1_000, networkRawValue: 1, walletIdHex: "aa11")
        XCTAssertEqual(store.record(networkRawValue: 1, walletIdHex: "aa11")?.returnedDuffs, 2_900_000,
                       "The first returned amount wins (AC-04)")

        let second = chargedFailureRecord("bob", contested: true)
        store.save(second, networkRawValue: 1, walletIdHex: "aa11")
        XCTAssertEqual(store.record(networkRawValue: 1, walletIdHex: "aa11"), second,
                       "A second failure replaces the first, never sums")
        XCTAssertNil(store.record(networkRawValue: 1, walletIdHex: "aa11")?.returnedDuffs)
    }

    func testWalletDeletionAndFullWipeRemoveTheChargedFailureRecord() throws {
        let (defaults, _) = try chargedFailureDefaults()
        let store = ShieldedChargedFailureStore(defaults: defaults)
        for network in WalletEnvironment.NetworkKind.allCases {
            store.save(chargedFailureRecord(), networkRawValue: network.rawValue, walletIdHex: "aa11")
            store.save(chargedFailureRecord(), networkRawValue: network.rawValue, walletIdHex: "bb22")
        }
        UsernamePrefs.clearRegistrationRecords(walletIdHex: "aa11", defaults: defaults)
        for network in WalletEnvironment.NetworkKind.allCases {
            XCTAssertNil(store.record(networkRawValue: network.rawValue, walletIdHex: "aa11"))
            XCTAssertNotNil(store.record(networkRawValue: network.rawValue, walletIdHex: "bb22"))
        }
        UsernamePrefs.clearAllRegistrationRecords(defaults: defaults)
        for network in WalletEnvironment.NetworkKind.allCases {
            XCTAssertNil(store.record(networkRawValue: network.rawValue, walletIdHex: "bb22"))
        }
    }

    // MARK: - Charged failure explanation texts

    private func dash(_ duffs: UInt64) -> String { duffs.dashAmount.formattedDashAmountWithoutCurrencySymbol }

    private func assertNoForbiddenWording(_ texts: [String], file: StaticString = #filePath, line: UInt = #line) {
        for text in texts {
            XCTAssertFalse(text.lowercased().contains("contest fee"), "No 'contest fee' wording: \(text)",
                           file: file, line: line)
            XCTAssertFalse(text.contains("Error"), "No technical error text: \(text)", file: file, line: line)
            XCTAssertFalse(text.contains("FFI"), "No technical error text: \(text)", file: file, line: line)
        }
    }

    func testChargedFailurePlainTextIsTheShortFirstBlock() {
        XCTAssertEqual(ShieldedChargedFailureExplanation.plain, "The registration did not go through.")
    }

    func testChargedFailureExplanationWhileReturnedAmountIsUnknownIsChecking() {
        let text = ShieldedChargedFailureExplanation.text(returnedDuffs: nil, amountToAddDuffs: nil)
        XCTAssertEqual(text.block1, ShieldedChargedFailureExplanation.plain)
        XCTAssertEqual(text.block2, "Checking where the money went\u{2026}")
        let block2 = text.block2 ?? ""
        XCTAssertFalse(block2.contains("Dash"), "No figures yet (AC-01)")
        XCTAssertFalse(block2.lowercased().contains("try again"), "No advice yet (AC-01)")
        assertNoForbiddenWording([text.block1, block2])
    }

    func testChargedFailureExplanationWithAmountToAddNamesBothFiguresInOrder() throws {
        let text = ShieldedChargedFailureExplanation.text(returnedDuffs: 2_900_000, amountToAddDuffs: 100_000)
        XCTAssertEqual(text.block1, ShieldedChargedFailureExplanation.plain)
        let block2 = try XCTUnwrap(text.block2)
        XCTAssertEqual(block2, "\(dash(2_900_000)) Dash came back to your Platform balance. "
            + "Add \(dash(100_000)) Dash there to try again.")
        assertNoForbiddenWording([text.block1, block2])
    }

    func testChargedFailureExplanationWithNothingToAddSaysRegisterNow() throws {
        let text = ShieldedChargedFailureExplanation.text(returnedDuffs: 2_900_000, amountToAddDuffs: 0)
        XCTAssertEqual(text.block1, ShieldedChargedFailureExplanation.plain)
        let block2 = try XCTUnwrap(text.block2)
        XCTAssertEqual(block2, "\(dash(2_900_000)) Dash came back to your Platform balance "
            + "\u{2014} enough to register this username from it now.")
        XCTAssertFalse(block2.contains("Add "), "Nothing to add (AC-02)")
        assertNoForbiddenWording([text.block1, block2])
    }

    func testChargedFailureExplanationForContestedFiguresUsesTheSameShapeWithItsOwnFigures() throws {
        let text = ShieldedChargedFailureExplanation.text(returnedDuffs: 24_900_000, amountToAddDuffs: 100_000)
        let block2 = try XCTUnwrap(text.block2)
        XCTAssertEqual(block2, "\(dash(24_900_000)) Dash came back to your Platform balance. "
            + "Add \(dash(100_000)) Dash there to try again.")
        assertNoForbiddenWording([text.block1, block2])
    }

    /// A returned amount once stated stays stated (AC-04); while the amount to add is unknown it gets no
    /// advice, and it never reads as still checking.
    func testChargedFailureExplanationWithUnknownAmountToAddStatesReturnedAmountWithoutAdvice() throws {
        let text = ShieldedChargedFailureExplanation.text(returnedDuffs: 2_900_000, amountToAddDuffs: nil)
        XCTAssertEqual(text.block1, ShieldedChargedFailureExplanation.plain)
        let block2 = try XCTUnwrap(text.block2)
        XCTAssertEqual(block2, "\(dash(2_900_000)) Dash came back to your Platform balance.")
        assertNoForbiddenWording([text.block1, block2])
    }

    // MARK: - Charged failure coordinator seams

    private typealias Coordinator = DWIdentityRegistrationCoordinator
    private var rawSdkText: String {
        "state transition broadcast error: Identity public key with id 0 is already registered"
    }

    func testChargedRecordBuilderForStandardNameConvertsCreditsToDuffs() {
        let record = ShieldedChargedFailureStore.Record.charged(
            username: "alice", isContested: false, denominationCredits: 3_000_000_000,
            fallbackAddress: Data([0, 1, 2]), snapshotCredits: 7_000)
        let expected = ShieldedChargedFailureStore.Record(
            username: "alice", isContested: false, exitDenominationDuffs: 3_000_000,
            fallbackAddress: Data([0, 1, 2]), snapshotCredits: 7_000, returnedDuffs: nil)
        XCTAssertEqual(record, expected)
    }

    func testChargedRecordBuilderForContestedNameUsesTheContestedDenomination() {
        let record = ShieldedChargedFailureStore.Record.charged(
            username: "bob", isContested: true, denominationCredits: 25_000_000_000,
            fallbackAddress: Data([0, 9]), snapshotCredits: 0)
        XCTAssertEqual(record.exitDenominationDuffs, 25_000_000)
        XCTAssertTrue(record.isContested)
        XCTAssertEqual(record.snapshotCredits, 0)
        XCTAssertNil(record.returnedDuffs, "Returned amount is unknown when the record is written")
    }

    // MARK: - Charged failure record lifecycle (AC-04)

    private var recordNetwork: Int { 1 }
    private var recordWalletHex: String { "01" }

    private func makeFailureStore() throws -> ShieldedChargedFailureStore {
        let suite = "ShieldedChargedFailureLifecycle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ShieldedChargedFailureStore(defaults: defaults)
    }

    private func saveChargedRecord(_ store: ShieldedChargedFailureStore, walletIdHex: String) {
        store.save(
            .charged(username: "alice", isContested: false, denominationCredits: 3_000_000_000,
                     fallbackAddress: Data([0, 1]), snapshotCredits: 0),
            networkRawValue: recordNetwork, walletIdHex: walletIdHex)
    }

    @MainActor
    private func makeCoordinator(_ store: ShieldedChargedFailureStore) -> DWIdentityRegistrationCoordinator {
        let network = recordNetwork
        let walletHex = recordWalletHex
        return DWIdentityRegistrationCoordinator(collaborators: .init(
            contestedNames: NoOpContestedNames(), draftStore: NoOpDraftStore(), isActiveContext: { _, _ in true },
            shieldedFailureStore: store, activeFailureRecordScope: { (network, walletHex) }))
    }

    /// The next registration in this wallet starting is enough, whatever it later fails on.
    @MainActor
    func testStartingACreateRegistrationClearsTheChargedFailureRecord() async throws {
        let store = try makeFailureStore()
        saveChargedRecord(store, walletIdHex: recordWalletHex)
        let coordinator = makeCoordinator(store)
        do {
            // A companion beside a non-contested name is refused before anything else runs.
            try await coordinator.startCreateUsername("alice123", fundingSource: .core, temporaryUsername: "bob")
            XCTFail("Expected the companion pairing to be refused")
        } catch {}
        XCTAssertNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
    }

    @MainActor
    func testStartingAPurchaseClearsTheChargedFailureRecord() async throws {
        try XCTSkipIf(SwiftDashSDKHost.shared.wallet != nil, "A loaded wallet would let the purchase go on")
        let store = try makeFailureStore()
        saveChargedRecord(store, walletIdHex: recordWalletHex)
        let coordinator = makeCoordinator(store)
        do {
            try await coordinator.startPurchaseUsername(name: "alice", priceCredits: 1)
            XCTFail("Expected the purchase to stop without a wallet")
        } catch {}
        XCTAssertNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
    }

    @MainActor
    func testResumingARegistrationClearsTheChargedFailureRecord() async throws {
        try XCTSkipIf(SwiftDashSDKHost.shared.wallet != nil, "A loaded wallet would let the registration go on")
        let store = try makeFailureStore()
        saveChargedRecord(store, walletIdHex: recordWalletHex)
        let coordinator = makeCoordinator(store)
        do {
            try await coordinator.resumeUsernameRegistration(identityId: Data([7]), username: "alice")
            XCTFail("Expected the registration to stop without a wallet")
        } catch {}
        XCTAssertNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
    }

    @MainActor
    func testACompletedNameRegistrationClearsTheRegisteringWalletsRecordOnly() async throws {
        let store = try makeFailureStore()
        saveChargedRecord(store, walletIdHex: recordWalletHex)
        saveChargedRecord(store, walletIdHex: "02")
        let coordinator = makeCoordinator(store)
        let identityId = Data([2])
        let walletId = Data([1])
        _ = coordinator.completeNameRegistration(
            identityId: identityId, username: "alice", nameState: .owned,
            draftScope: .init(network: "testnet", walletId: walletId, identityId: identityId),
            walletId: walletId, network: .testnet, newController: DWIdentityRegistrationController()
        ) {}
        XCTAssertNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
        XCTAssertNotNil(store.record(networkRawValue: recordNetwork, walletIdHex: "02"), "Another wallet keeps its own")
    }

    /// A network switch during the attempt must not file the record under the network now active.
    @MainActor
    func testAChargedFailureIsSavedUnderTheRegisteringNetworkOnly() throws {
        let store = try makeFailureStore()
        let coordinator = makeCoordinator(store)
        let record = ShieldedChargedFailureStore.Record.charged(
            username: "alice", isContested: false, denominationCredits: 3_000_000_000,
            fallbackAddress: Data([0, 1]), snapshotCredits: 7_000)
        let mainnet = WalletEnvironment.NetworkKind.mainnet.rawValue
        XCTAssertNotEqual(mainnet, recordNetwork, "The active scope must be another network")

        let thrown = coordinator.shieldedCreateFailureError(
            chargedError, chargedRecord: record,
            walletId: Data([1]), network: .mainnet)

        guard case .shieldedRegistrationCharged? = thrown as? Coordinator.CoordinatorError else {
            return XCTFail("Expected shieldedRegistrationCharged, got \(thrown)")
        }
        XCTAssertEqual(store.record(networkRawValue: mainnet, walletIdHex: recordWalletHex), record)
        XCTAssertNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
    }

    @MainActor
    func testAnUnclassifiedFailureSavesNoRecord() throws {
        let store = try makeFailureStore()
        let coordinator = makeCoordinator(store)
        let record = ShieldedChargedFailureStore.Record.charged(
            username: "alice", isContested: false, denominationCredits: 3_000_000_000,
            fallbackAddress: Data([0, 1]), snapshotCredits: 0)

        let thrown = coordinator.shieldedCreateFailureError(
            PlatformWalletError.shieldedBroadcastFailed("CheckTx rejected"), chargedRecord: record,
            walletId: Data([1]), network: .testnet)

        guard case .shieldedRegistrationNotClassified? = thrown as? Coordinator.CoordinatorError else {
            return XCTFail("Expected shieldedRegistrationNotClassified, got \(thrown)")
        }
        XCTAssertNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
    }

    @MainActor
    func testACompletedNameRegistrationClearsTheRegisteringNetworksRecordOnly() throws {
        let store = try makeFailureStore()
        let mainnet = WalletEnvironment.NetworkKind.mainnet.rawValue
        let record = ShieldedChargedFailureStore.Record.charged(
            username: "alice", isContested: false, denominationCredits: 3_000_000_000,
            fallbackAddress: Data([0, 1]), snapshotCredits: 0)
        store.save(record, networkRawValue: mainnet, walletIdHex: recordWalletHex)
        saveChargedRecord(store, walletIdHex: recordWalletHex)
        let coordinator = makeCoordinator(store)
        let identityId = Data([2])
        let walletId = Data([1])
        _ = coordinator.completeNameRegistration(
            identityId: identityId, username: "alice", nameState: .owned,
            draftScope: .init(network: "mainnet", walletId: walletId, identityId: identityId),
            walletId: walletId, network: .mainnet, newController: DWIdentityRegistrationController()
        ) {}
        XCTAssertNil(store.record(networkRawValue: mainnet, walletIdHex: recordWalletHex))
        XCTAssertNotNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex),
                        "The active network's record is another failure's")
    }

    func testChargedVerdictMapsToChargedCaseWithPlainTextAndNoRawSdkText() throws {
        let error = chargedError
        let mapped = try XCTUnwrap(Coordinator.shieldedCreateFailure(error))
        guard case .shieldedRegistrationCharged = mapped else {
            return XCTFail("Expected shieldedRegistrationCharged, got \(mapped)")
        }
        XCTAssertEqual(mapped.localizedDescription, ShieldedChargedFailureExplanation.plain)
        XCTAssertFalse(mapped.localizedDescription.contains(rawSdkText))
    }

    func testNotClassifiedFailureMapsToNotClassifiedCaseWithPlainTextAndNoRawSdkText() throws {
        let error = PlatformWalletError.shieldedBroadcastFailed(
            "shielded identity-create-from-pool failed: Shielded broadcast failed: Protocol error: " + rawSdkText)
        let mapped = try XCTUnwrap(Coordinator.shieldedCreateFailure(error))
        guard case .shieldedRegistrationNotClassified = mapped else {
            return XCTFail("Expected shieldedRegistrationNotClassified, got \(mapped)")
        }
        XCTAssertEqual(mapped.localizedDescription, ShieldedChargedFailureExplanation.plain)
        XCTAssertFalse(mapped.localizedDescription.contains(rawSdkText))
    }

    func testUnknownOutcomeIsNotRemappedSoTheExistingStillConfirmingPathStays() {
        // nil = the caller keeps the existing `.shieldedCreateUnconfirmed` handling (AC-03).
        XCTAssertNil(Coordinator.shieldedCreateFailure(Coordinator.CoordinatorError.shieldedCreateUnconfirmed))
    }

    // MARK: - Name-step failure wording

    private typealias Wording = UsernameRegistrationFailureWording

    /// Real consensus texts, platform 1721ca7a8b (rs-dpp errors/consensus/state/document), placeholders filled in.
    private var nameTakenDuplicateRaw: String {
        "Document 4vJ7xQe2 has duplicate unique properties "
        + "[\"normalizedLabel\", \"normalizedParentDomainName\"] with other documents"
    }
    private var nameTakenPresentRaw: String {
        "Document 4vJ7xQe2 is already present"
    }
    private var contestClosedRaw: String {
        "Document Contest for vote_poll ContestedDocumentResourceVotePoll { } "
        + "is not joinable NotStarted, it started 1700000000000 and it is now 1701000000000, "
        + "and you can only join for 1209600000"
    }
    private var contestFullRaw: String {
        "The vote poll ContestedDocumentResourceVotePoll { } already has 3 contenders, "
        + "the most a contest accepts"
    }
    private var alreadyRequestedRaw: String {
        "An Identity with the id 9fKq1Zr is already a contestant for the vote_poll "
        + "ContestedDocumentResourceVotePoll { }"
    }
    private var deviceClockRaw: String {
        "Document 4vJ7xQe2 $createdAt timestamp 1700000000000 are out of block time window "
        + "from 1700000100000 and 1700000200000"
    }

    private func assertWording(_ raw: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        for shielded in [false, true] {
            let text = Wording.message(forRaw: "Platform error: " + raw, username: "alice", paidFromShielded: shielded)
            XCTAssertEqual(text, expected, "paidFromShielded=\(shielded)", file: file, line: line)
        }
    }

    func testNameTakenDuplicateUniquePropertiesWording() {
        assertWording(nameTakenDuplicateRaw,
                      "\u{201C}alice\u{201D} was just taken. Please choose a different username.")
    }

    func testNameTakenAlreadyPresentWording() {
        assertWording(nameTakenPresentRaw,
                      "\u{201C}alice\u{201D} was just taken. Please choose a different username.")
    }

    func testContestClosedWording() {
        assertWording(contestClosedRaw,
                      "Requests for \u{201C}alice\u{201D} are closed \u{2014} its vote has started. "
                          + "Please choose a different username.")
    }

    func testContestFullWording() {
        assertWording(contestFullRaw,
                      "\u{201C}alice\u{201D} already has the most requests a vote accepts. "
                          + "Please choose a different username.")
    }

    func testAlreadyRequestedWording() {
        assertWording(alreadyRequestedRaw, "You have already requested \u{201C}alice\u{201D}.")
    }

    func testDeviceClockWording() {
        assertWording(deviceClockRaw, "Check the date and time on your device, then try again.")
    }

    func testUnknownCauseShieldedPaidGetsPlainTextWithoutRawText() {
        let raw = "Something unforeseen: ContestedDocumentResourceVotePoll { index_name: \"parentNameAndLabel\" }"
        let text = Wording.message(forRaw: raw, username: "alice", paidFromShielded: true)
        XCTAssertEqual(text, ShieldedChargedFailureExplanation.plain)
        XCTAssertFalse(text.contains(raw))
        XCTAssertFalse(text.contains("ContestedDocumentResourceVotePoll"))
    }

    func testUnknownCauseOtherSourceKeepsRawTextUnchanged() {
        let raw = "Something unforeseen: ContestedDocumentResourceVotePoll { }"
        XCTAssertEqual(Wording.message(forRaw: raw, username: "alice"), raw)
        XCTAssertEqual(Wording.message(forRaw: raw, username: "alice", paidFromShielded: false), raw)
    }

    func testLockedTextUnchangedWhenPaidFromShielded() {
        let raw = "vote_poll_status: Locked"
        XCTAssertEqual(Wording.message(forRaw: raw, username: "alice", paidFromShielded: true),
                       Wording.message(forRaw: raw, username: "alice"))
        XCTAssertTrue(Wording.message(forRaw: raw, username: "alice", paidFromShielded: true)
            .contains("was locked by a masternode vote"))
    }

    func testInsufficientCreditsTextUnchangedWhenPaidFromShielded() {
        let raw = "Insufficient identity balance: required 100, available 1"
        let text = Wording.message(forRaw: raw, username: "alice", paidFromShielded: true)
        XCTAssertEqual(text, Wording.message(forRaw: raw, username: "alice"))
        XCTAssertTrue(text.hasPrefix("Not enough identity credits"))
    }

    func testTwoCausesInOneRawTextFirstInTableOrderWins() {
        let raw = deviceClockRaw + "; " + nameTakenPresentRaw
        XCTAssertEqual(Wording.message(forRaw: raw, username: "alice", paidFromShielded: true),
                       "\u{201C}alice\u{201D} was just taken. Please choose a different username.")
    }

    // MARK: - Typed coordinator errors vs raw platform text (the row and the form)

    private typealias CoordinatorError = DWIdentityRegistrationCoordinator.CoordinatorError

    /// The coordinator's own texts survive a Shielded attempt: the unknown outcome keeps its
    /// "still confirming" text (AC-03) and a refusal before anything was sent keeps its reason.
    func testTypedCoordinatorErrorKeepsItsOwnTextWhenPaidFromShielded() throws {
        let typed: [CoordinatorError] = [
            .shieldedCreateUnconfirmed, .noShieldedFallbackAddress, .shieldedPoolTooSmall(currentNotes: 3),
            .insufficientShieldedBalance(requiredCredits: 3_000_000_000, availableCredits: 1_000),
            .alreadyInFlight, .authFailed, .noWallet,
        ]
        for error in typed {
            let own = try XCTUnwrap(error.errorDescription)
            XCTAssertEqual(Wording.message(for: error, username: "alice", paidFromShielded: true), own, "\(error)")
            XCTAssertEqual(Wording.message(for: error as NSError, username: "alice", paidFromShielded: true), own,
                           "bridged \(error)")
        }
    }

    /// Texts the app writes itself are not raw platform text, also inside a name-step wrapper.
    func testAppWrittenTextsKeepTheirWordsWhenPaidFromShielded() throws {
        XCTAssertEqual(CoordinatorError.usernameAvailabilityUnknown.errorDescription,
                       "Could not check username availability. Please try again.")
        XCTAssertEqual(CoordinatorError.contestFundUnavailable.errorDescription,
                       "Network error. Please check your connection and try again.")
        let appWritten: [CoordinatorError] = [
            .dpnsRegistration(CoordinatorError.usernameAvailabilityUnknown), .contestFundUnavailable,
        ]
        for error in appWritten {
            XCTAssertEqual(Wording.message(for: error, username: "alice", paidFromShielded: true),
                           try XCTUnwrap(error.errorDescription), "\(error)")
        }
    }

    func testAnUnresolvableContestFundBecomesItsOwnCoordinatorError() {
        let mapped = DWIdentityRegistrationCoordinator.contestFundFailure(
            ContestedUsernameFee.UnresolvedProtocolVersion())
        guard case .contestFundUnavailable? = mapped as? CoordinatorError else {
            return XCTFail("Expected contestFundUnavailable, got \(mapped)")
        }
        let other = NSError(domain: "Test", code: 3)
        XCTAssertIdentical(DWIdentityRegistrationCoordinator.contestFundFailure(other) as NSError, other,
                           "Any other fund error is passed on as it is")
    }

    func testRawPlatformTextReadsPlainWhenPaidFromShielded() {
        let raw = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something unforeseen { }"])
        let plain = ShieldedChargedFailureExplanation.plain
        XCTAssertEqual(Wording.message(for: raw, username: "alice", paidFromShielded: true), plain)
        XCTAssertEqual(Wording.message(for: CoordinatorError.identityRegistration(raw), username: "alice",
                                       paidFromShielded: true), plain)
        XCTAssertEqual(Wording.message(for: CoordinatorError.dpnsRegistration(raw), username: "alice",
                                       paidFromShielded: true), plain)
        // These describe themselves with the wrapped error's raw text too.
        for wrapper in [CoordinatorError.keyDerivation(raw), .identityTopUp(raw), .availabilityCheck(raw)] {
            XCTAssertEqual(Wording.message(for: wrapper, username: "alice", paidFromShielded: true), plain,
                           "\(wrapper)")
        }
        XCTAssertEqual(Wording.message(for: raw, username: "alice", paidFromShielded: false),
                       "Something unforeseen { }")
    }
}

@MainActor
private final class NoOpContestedNames: ContestedNamePendingClearing {
    func clearPending(label: String, for network: Network, walletId: Data?) {}
}

private struct NoOpDraftStore: UsernameRegistrationDraftClearing {
    func clear(for scope: UsernameRegistrationDraftStore.Scope) {}
}

// MARK: - DashPay row with a charged failure record (AC-04)

extension UsernameRegistrationRecoveryTests {
    private var explanation: String {
        "The registration did not go through.\n0.029 Dash came back to your Platform balance."
    }

    func testARecordTurnsAnInterruptedRowIntoTheExplainedFailure() {
        let shown = JoinDashPayViewModel.rowFailure(state: .interrupted, failureReason: nil, explanation: explanation)
        XCTAssertEqual(shown.state, .creationFailed, "Not \"Registration was interrupted\" after a relaunch")
        XCTAssertEqual(shown.failureExplanation, explanation)
        XCTAssertNil(shown.failureReason)
    }

    func testARecordReplacesTheBridgesFailureText() {
        let shown = JoinDashPayViewModel.rowFailure(
            state: .creationFailed, failureReason: "The registration did not go through.", explanation: explanation)
        XCTAssertEqual(shown.state, .creationFailed)
        XCTAssertEqual(shown.failureExplanation, explanation)
        XCTAssertNil(shown.failureReason)
    }

    func testARecordLeavesOtherStatesAlone() {
        for state in [JoinDashPayState.creating, .registered, .voting] {
            let shown = JoinDashPayViewModel.rowFailure(state: state, failureReason: nil, explanation: explanation)
            XCTAssertEqual(shown.state, state)
            XCTAssertNil(shown.failureExplanation, "\(state)")
        }
    }

    func testWithoutARecordTheReportIsUnchanged() {
        let interrupted = JoinDashPayViewModel.rowFailure(state: .interrupted, failureReason: nil, explanation: nil)
        XCTAssertEqual(interrupted.state, .interrupted)
        let failed = JoinDashPayViewModel.rowFailure(state: .creationFailed, failureReason: "raw", explanation: nil)
        XCTAssertEqual(failed.state, .creationFailed)
        XCTAssertEqual(failed.failureReason, "raw")
        XCTAssertNil(failed.failureExplanation)
    }

    func testRecordBackedRowShowsTheExplanationAloneAndNoX() {
        let copy = JoinDashPayCopy(
            state: .creationFailed, username: "alice123", shieldedSnapshot: nil,
            registrationStep: .registrationUsername, failureReason: "raw", failureExplanation: explanation)
        XCTAssertEqual(copy.subtitle, explanation, "No step line, no bridge text")
        XCTAssertTrue(copy.isRecordBackedFailure, "The row hides its X while the record explains the failure")
    }

    func testWithoutAReportTheRecordAloneIsTheExplainedFailure() {
        let shown = JoinDashPayViewModel.recordRow(recordUsername: "alice", explanation: explanation)
        XCTAssertEqual(shown?.row.state, .creationFailed)
        XCTAssertEqual(shown?.row.failureExplanation, explanation)
        XCTAssertNil(shown?.row.failureReason)
        XCTAssertEqual(shown?.username, "alice")
        XCTAssertNil(JoinDashPayViewModel.recordRow(recordUsername: nil, explanation: nil))
    }

    /// The row was closed while the registration ran, which drops the handoff marker; the charged
    /// failure that follows is still reported from its record, and again after a relaunch.
    @MainActor
    func testClosingTheRunningRowThenAChargedFailureStillShowsTheRecordAfterRelaunch() throws {
        let prefs = UsernamePrefs.shared
        let saved = prefs.inFlightRegistrationUsername
        defer { prefs.inFlightRegistrationUsername = saved }
        prefs.inFlightRegistrationUsername = "alice"
        JoinDashPayViewModel(previewState: .creating, username: "alice").markAsDismissed()
        XCTAssertNil(prefs.inFlightRegistrationUsername)

        let store = try makeFailureStore()
        saveChargedRecord(store, walletIdHex: "aa")
        func relaunchedRow() -> (row: JoinDashPayViewModel.RowFailure, username: String)? {
            let model = ShieldedChargedFailureExplanationModel(
                store: store, networkRawValue: recordNetwork, walletIdHex: "aa",
                candidates: { nil }, nextReceive: { nil }, fundingDuffs: { _ in 0 })
            model.refresh()
            return JoinDashPayViewModel.recordRow(recordUsername: model.username, explanation: model.text?.block1)
        }
        for shown in [relaunchedRow(), relaunchedRow()] {
            XCTAssertEqual(shown?.row.state, .creationFailed)
            XCTAssertEqual(shown?.username, "alice")
            XCTAssertEqual(
                shown?.row.failureExplanation,
                ShieldedChargedFailureExplanation.text(returnedDuffs: nil, amountToAddDuffs: nil).block1)
        }
    }

    func testFailedRowWithoutARecordKeepsTodaysText() {
        let copy = JoinDashPayCopy(
            state: .creationFailed, username: "alice123", shieldedSnapshot: nil,
            registrationStep: .registrationUsername, failureReason: "raw")
        XCTAssertTrue(copy.subtitle.hasSuffix("\nraw"), copy.subtitle)
        XCTAssertNotEqual(copy.subtitle, explanation)
        XCTAssertFalse(copy.isRecordBackedFailure)
    }
}

// MARK: - A create left unconfirmed, proven charged later

extension UsernameRegistrationRecoveryTests {
    private var unresolvedIdentityId: Data { Data(repeating: 9, count: 32) }

    /// The create call's outcome reads were unavailable: the attempt is kept for the SDK to
    /// settle, under the registering network, with no charged record and no explanation yet.
    @MainActor
    func testAnUnconfirmedCreateKeepsItsAttemptUnderTheRegisteringNetworkWithoutARecord() throws {
        let store = try makeFailureStore()
        let coordinator = makeCoordinator(store)
        let record = chargedFailureRecord()
        let mainnet = WalletEnvironment.NetworkKind.mainnet.rawValue

        let thrown = coordinator.shieldedCreateFailureError(
            ShieldedIdentityCreateUnconfirmedError(identityId: unresolvedIdentityId, message: "wait timed out"),
            chargedRecord: record, walletId: Data([1]), network: .mainnet)

        guard case .shieldedCreateUnconfirmed? = thrown as? Coordinator.CoordinatorError else {
            return XCTFail("Expected shieldedCreateUnconfirmed, got \(thrown)")
        }
        XCTAssertEqual(
            store.unresolvedAttempt(networkRawValue: mainnet, walletIdHex: recordWalletHex),
            .init(identityId: unresolvedIdentityId, record: record))
        XCTAssertNil(store.unresolvedAttempt(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
        XCTAssertNil(store.record(networkRawValue: mainnet, walletIdHex: recordWalletHex), "Amount-free until proven")
    }

    func testAnUnresolvedAttemptBecomesItsChargedRecordOnlyOnceItsInputsAreProvenConsumed() throws {
        let store = try makeFailureStore()
        let attempt = ShieldedChargedFailureStore.UnresolvedAttempt(
            identityId: unresolvedIdentityId, record: chargedFailureRecord())
        store.saveUnresolved(attempt, networkRawValue: recordNetwork, walletIdHex: recordWalletHex)

        XCTAssertFalse(store.reconcileUnresolved(
            networkRawValue: recordNetwork, walletIdHex: recordWalletHex, inputsConsumed: { _ in false }))
        XCTAssertEqual(store.unresolvedAttempt(networkRawValue: recordNetwork, walletIdHex: recordWalletHex), attempt)
        XCTAssertNil(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))

        var asked: [Data] = []
        XCTAssertTrue(store.reconcileUnresolved(
            networkRawValue: recordNetwork, walletIdHex: recordWalletHex,
            inputsConsumed: { asked.append($0); return true }))
        XCTAssertEqual(asked, [unresolvedIdentityId], "Asked about the attempt's own create")
        XCTAssertEqual(store.record(networkRawValue: recordNetwork, walletIdHex: recordWalletHex), attempt.record)
        XCTAssertNil(store.unresolvedAttempt(networkRawValue: recordNetwork, walletIdHex: recordWalletHex))
    }

    func testStartingAgainAndWipingDropTheUnresolvedAttempt() throws {
        let (defaults, _) = try chargedFailureDefaults()
        let store = ShieldedChargedFailureStore(defaults: defaults)
        let attempt = ShieldedChargedFailureStore.UnresolvedAttempt(
            identityId: unresolvedIdentityId, record: chargedFailureRecord())
        store.saveUnresolved(attempt, networkRawValue: 1, walletIdHex: "aa11")
        store.clear(networkRawValue: 1, walletIdHex: "aa11")
        XCTAssertNil(store.unresolvedAttempt(networkRawValue: 1, walletIdHex: "aa11"))

        for network in WalletEnvironment.NetworkKind.allCases {
            store.saveUnresolved(attempt, networkRawValue: network.rawValue, walletIdHex: "aa11")
        }
        UsernamePrefs.clearRegistrationRecords(walletIdHex: "aa11", defaults: defaults)
        for network in WalletEnvironment.NetworkKind.allCases {
            XCTAssertNil(store.unresolvedAttempt(networkRawValue: network.rawValue, walletIdHex: "aa11"))
        }
    }

    /// The create's outcome reads were unavailable, so the row reported the attempt
    /// unconfirmed; a later sync proves its inputs consumed. The explanation reads that proof,
    /// after a relaunch too, and the row then explains the charged failure instead.
    @MainActor
    func testAFailureProvenDuringALaterSyncIsExplainedAfterRelaunch() throws {
        let store = try makeFailureStore()
        let coordinator = makeCoordinator(store)
        _ = coordinator.shieldedCreateFailureError(
            ShieldedIdentityCreateUnconfirmedError(identityId: unresolvedIdentityId, message: "wait timed out"),
            chargedRecord: chargedFailureRecord(), walletId: Data([1]), network: .testnet)
        let network = WalletEnvironment.NetworkKind.testnet.rawValue
        var proven = false
        func relaunchedModel() -> ShieldedChargedFailureExplanationModel {
            let model = ShieldedChargedFailureExplanationModel(
                store: store, networkRawValue: network, walletIdHex: recordWalletHex,
                candidates: { nil }, nextReceive: { nil }, fundingDuffs: { _ in 0 },
                inputsConsumed: { [unresolvedIdentityId] in proven && $0 == unresolvedIdentityId })
            model.refresh()
            return model
        }

        let before = relaunchedModel()
        XCTAssertTrue(before.hasUnresolvedAttempt)
        XCTAssertFalse(before.hasRecord)
        XCTAssertNil(before.text, "Unresolved: no charged explanation")
        XCTAssertEqual(
            JoinDashPayViewModel.rowFailure(state: .interrupted, failureReason: nil, explanation: nil).state,
            .interrupted)

        proven = true
        for model in [relaunchedModel(), relaunchedModel()] {
            XCTAssertFalse(model.hasUnresolvedAttempt)
            XCTAssertTrue(model.hasRecord)
            XCTAssertEqual(model.username, "alice")
            let text = try XCTUnwrap(model.text)
            XCTAssertEqual(text.block2, "Checking where the money went\u{2026}")
            let shown = JoinDashPayViewModel.rowFailure(
                state: .interrupted, failureReason: nil, explanation: text.block1 + "\n" + (text.block2 ?? ""))
            XCTAssertEqual(shown.state, .creationFailed)
            XCTAssertNotNil(shown.failureExplanation)
        }
    }

    func testOnlyTheInputsConsumedStatusIsAProvenChargedFailure() {
        XCTAssertEqual(ShieldedActivityItem.Status.inputsConsumed.rawValue, 4, "The SDK's InputsConsumed status")
        XCTAssertEqual(ShieldedActivityItem.Status.failed.rawValue, 2)
    }
}
