import XCTest
@testable import IdentityTopUpHarness

@MainActor final class IdentityTopUpCompatibilityTests: XCTestCase {
    let host = SwiftDashSDKHost.shared

    override func setUp() async throws {
        host.wallet = ManagedPlatformWallet()
        host.manager = NativeManager()
        host.generation = 0
        host.scopeCalls = 0
        host.rejectScopeCall = nil
    }

    func topUp() async throws -> UInt64 {
        try await IdentityTopUpViewModel().topUpFromShielded(
            identityId: Data([2]), amountDuffs: 100,
            wallet: host.wallet!, modelContainer: ModelContainer(),
            preparation: .init(generation: 0))
    }

    func testNativeRefusalAfterLocalGuardPreservesLandedFirstLeg() async {
        let refusals: [PlatformWalletError] = [
            .protocolCompatibilityUnavailable("offline"),
            .protocolCompatibilityChecking("checking"),
            .unsupportedProtocolVersion("future"),
            .platformPreparationExpired("stale"),
        ]
        for refusal in refusals {
            host.wallet = ManagedPlatformWallet()
            host.manager = NativeManager()
            // The local guard succeeds. Refusal arrives from the actual second
            // operation, simulating a Rust check after crossing the FFI boundary.
            host.wallet!.failure = refusal
            do {
                _ = try await topUp()
                XCTFail("Expected refusal")
            } catch IdentityTopUpViewModel.TopUpError.movedToPlatform(let cause) {
                XCTAssertTrue(cause is PlatformWalletError)
            } catch {
                XCTFail("Lost the already-landed first leg: \(error)")
            }
            XCTAssertEqual(host.manager!.unshieldCalls, 1)
            XCTAssertEqual(host.wallet!.topUpCalls, 1)
        }
    }

    func testLocalStalePermitDoesNotAttemptSecondLeg() async {
        host.manager!.afterUnshield = { self.host.generation += 1 }
        do {
            _ = try await topUp()
            XCTFail("Expected stale preparation")
        } catch IdentityTopUpViewModel.TopUpError.movedToPlatform {
        } catch {
            XCTFail("Expected settled-first-leg diagnostic: \(error)")
        }
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 0)
    }

    func testAmbiguousSecondLegRetainsUnknownOutcome() async {
        let unknowns: [PlatformWalletError] = [
            .transactionBroadcastUnconfirmed("may be sent"),
            .platformWriteUnconfirmed("compatibility changed after dispatch"),
        ]
        for unknown in unknowns {
            host.wallet = ManagedPlatformWallet()
            host.manager = NativeManager()
            host.wallet!.failure = unknown
            do {
                _ = try await topUp()
                XCTFail("Expected unknown broadcast outcome")
            } catch PlatformWalletError.transactionBroadcastUnconfirmed,
                    PlatformWalletError.platformWriteUnconfirmed {
            } catch {
                XCTFail("Unknown outcome mislabeled as safe top-up from Platform: \(error)")
            }
            XCTAssertEqual(host.manager!.unshieldCalls, 1)
            XCTAssertEqual(host.wallet!.topUpCalls, 1)
        }
    }

    func testFirstLegFailureNeverClaimsFundsLanded() async {
        host.manager!.failure = PlatformWalletError.protocolCompatibilityChecking("checking")
        do {
            _ = try await topUp()
            XCTFail("Expected first-leg refusal")
        } catch PlatformWalletError.protocolCompatibilityChecking {
        } catch {
            XCTFail("First-leg failure was misclassified: \(error)")
        }
        XCTAssertEqual(host.wallet!.topUpCalls, 0)
    }

    func testSuccessfulSecondLegRemainsSuccessAfterGenerationChanges() async throws {
        host.wallet!.afterTopUp = { self.host.generation += 1 }
        let balance = try await topUp()
        XCTAssertEqual(balance, 97)
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
    }

    func testBothLegsCarryOriginalPreparationWithoutLeakingScope() async throws {
        let balance = try await topUp()
        XCTAssertEqual(balance, 97)
        XCTAssertEqual(host.manager!.receivedPreparations, [0])
        XCTAssertEqual(host.wallet!.receivedPreparations, [0])
        XCTAssertEqual(host.scopeCalls, 2)
        XCTAssertNil(SwiftDashSDKHost.scopedPreparation)
    }

    func testSecondScopeAdmissionRefusalKeepsSettledFirstLeg() async {
        host.rejectScopeCall = 2
        do {
            _ = try await topUp()
            XCTFail("Expected refusal entering the second operation's scope")
        } catch IdentityTopUpViewModel.TopUpError.movedToPlatform(let cause) {
            XCTAssertTrue(cause is SDKError)
        } catch {
            XCTFail("Lost the settled first leg at scope admission: \(error)")
        }
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 0)
        XCTAssertNil(SwiftDashSDKHost.scopedPreparation)
    }
}
