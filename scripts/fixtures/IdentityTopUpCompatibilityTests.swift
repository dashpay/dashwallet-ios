import XCTest
@testable import IdentityTopUpHarness

@MainActor final class IdentityTopUpCompatibilityTests: XCTestCase {
    let host = SwiftDashSDKHost.shared

    override func setUp() async throws {
        host.wallet = ManagedPlatformWallet()
        host.manager = NativeManager()
        host.operationVersion = 0
        host.scopeCalls = 0
        host.rejectScopeCall = nil
    }

    func topUp() async throws -> UInt64 {
        try await IdentityTopUpViewModel().topUpFromShielded(
            identityId: Data([2]), amountDuffs: 100,
            wallet: host.wallet!, modelContainer: ModelContainer(),
            preparation: .init(operationVersion: 0))
    }

    func testChangedOperationVersionDoesNotAttemptSecondLeg() async {
        host.manager!.afterUnshield = { self.host.operationVersion += 1 }
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
        ]
        for unknown in unknowns {
            host.wallet = ManagedPlatformWallet()
            host.manager = NativeManager()
            host.wallet!.failure = unknown
            do {
                _ = try await topUp()
                XCTFail("Expected unknown broadcast outcome")
            } catch PlatformWalletError.transactionBroadcastUnconfirmed {
            } catch {
                XCTFail("Unknown outcome mislabeled as safe top-up from Platform: \(error)")
            }
            XCTAssertEqual(host.manager!.unshieldCalls, 1)
            XCTAssertEqual(host.wallet!.topUpCalls, 1)
        }
    }

    func testAmbiguousUnshieldDoesNotStartIdentityTopUp() async {
        host.manager!.failure = PlatformWalletError.shieldedSpendUnconfirmed("may be sent")
        do {
            _ = try await topUp()
            XCTFail("Expected unknown unshield outcome")
        } catch PlatformWalletError.shieldedSpendUnconfirmed {
        } catch {
            XCTFail("Unshield outcome was misclassified: \(error)")
        }
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 0)
    }

    func testFirstLegFailureNeverClaimsFundsLanded() async {
        host.manager!.failure = PlatformWalletError.walletOperation("rejected")
        do {
            _ = try await topUp()
            XCTFail("Expected first-leg refusal")
        } catch PlatformWalletError.walletOperation {
        } catch {
            XCTFail("First-leg failure was misclassified: \(error)")
        }
        XCTAssertEqual(host.wallet!.topUpCalls, 0)
    }

    func testSuccessfulSecondLegRemainsSuccessAfterOperationVersionChanges() async throws {
        host.wallet!.afterTopUp = { self.host.operationVersion += 1 }
        let balance = try await topUp()
        XCTAssertEqual(balance, 97)
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
    }

    func testInformationalRefreshBetweenLegsDoesNotStopTransfer() async throws {
        host.manager!.afterUnshield = { self.host.checkGeneration += 1 }
        let result = try await topUp()
        XCTAssertEqual(result, 97)
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
    }

    func testSecondScopeAdmissionRefusalKeepsSettledFirstLeg() async {
        host.rejectScopeCall = 2
        do {
            _ = try await topUp()
            XCTFail("Expected refusal entering the second operation's scope")
        } catch IdentityTopUpViewModel.TopUpError.movedToPlatform(let cause) {
            XCTAssertTrue(cause is WalletOperationPreparationError)
        } catch {
            XCTFail("Lost the settled first leg at scope admission: \(error)")
        }
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 0)
    }
}
