import XCTest
#if canImport(dashpay)
@testable import dashpay
import SwiftUI
#else
@testable import UsernameRecoveryHarness
#endif

@MainActor
final class UsernameRegistrationRecoveryTests: XCTestCase {
    private enum Failure: Error { case cancelled, contextChanged, unavailable, insufficientCredits }

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
        XCTAssertEqual(events, ["auth", "context", "lookup", "context", "dpns", "context"])
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
}

#if canImport(dashpay)
extension UsernameRegistrationRecoveryTests {
    private func unnamedIdentitySnapshot() -> DWCurrentUserIdentityInfo.Snapshot {
        .init(balanceCredits: 9_639_634_780,
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
        snapshot.pendingContestedName = "dash786"
        XCTAssertFalse(snapshot.needsUsername)
    }

    func testProfileRendersRecoveryAfterSimulatedDPNSFailure() async throws {
        var snapshot = unnamedIdentitySnapshot()
        // IdentityCreate succeeded, DPNS failed: there is a funded identity,
        // no owned name and no external funding involved in showing recovery.
        XCTAssertTrue(snapshot.needsUsername)
        snapshot.isLoading = true
        let controller = UIHostingController(rootView: SDKIdentityProfileSheet(snapshotProvider: { snapshot }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 200_000_000)
        snapshot.isLoading = false
        try await Task.sleep(nanoseconds: 500_000_000)
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Funded identity after DPNS failure"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
