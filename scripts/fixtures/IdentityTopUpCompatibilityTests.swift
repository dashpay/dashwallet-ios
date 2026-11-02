import XCTest
@testable import IdentityTopUpHarness

@MainActor final class IdentityTopUpCompatibilityTests: XCTestCase {
    let host = SwiftDashSDKHost.shared

    override func setUp() async throws {
        host.wallet = ManagedPlatformWallet()
        host.manager = NativeManager()
    }

    func topUp() async throws -> UInt64 {
        try await IdentityTopUpViewModel().topUpFromShielded(
            identityId: Data([2]), amountDuffs: 100,
            wallet: host.wallet!, modelContainer: ModelContainer())
    }

    func testAmbiguousSecondLegRetainsUnknownOutcome() async {
        let unknowns: [PlatformWalletError] = [
            .transactionBroadcastUnconfirmed("may be sent"),
            .shieldedSpendUnconfirmed("may be spent"),
        ]
        for unknown in unknowns {
            host.wallet = ManagedPlatformWallet()
            host.manager = NativeManager()
            host.wallet!.failure = unknown
            do {
                _ = try await topUp()
                XCTFail("Expected unknown broadcast outcome")
            } catch PlatformWalletError.transactionBroadcastUnconfirmed,
                    PlatformWalletError.shieldedSpendUnconfirmed {
            } catch {
                XCTFail("Unknown outcome mislabeled as safe top-up from Platform: \(error)")
            }
            XCTAssertEqual(host.manager!.unshieldCalls, 1)
            XCTAssertEqual(host.wallet!.topUpCalls, 1)
        }
    }

    func testAmbiguousSecondLegSetsNonRetryablePresentationState() async {
        host.wallet!.failure = PlatformWalletError.transactionBroadcastUnconfirmed("proof unavailable after dispatch")
        let model = IdentityTopUpViewModel()
        let result = await model.topUp(identityId: Data([2]), amountDuffs: 100, source: .shielded)
        XCTAssertNil(result)
        XCTAssertTrue(model.submittedUnconfirmed)
        XCTAssertFalse(model.isProcessing)
        XCTAssertTrue(model.errorMessage?.contains("may have been submitted") == true)
        XCTAssertFalse(model.errorMessage?.contains("Finish the top-up from Platform") == true)
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
    }

    func testSecondLegRefusalKeepsSettledFirstLeg() async {
        host.wallet!.failure = PlatformWalletError.walletOperation("rejected")
        do {
            _ = try await topUp()
            XCTFail("Expected second-leg refusal")
        } catch IdentityTopUpViewModel.TopUpError.movedToPlatform(let cause) {
            guard case PlatformWalletError.walletOperation = cause else {
                return XCTFail("Lost original refusal: \(cause)")
            }
        } catch {
            XCTFail("Lost settled first leg: \(error)")
        }
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
    }

    func testCancelledSecondLegRetainsUnknownOutcome() async {
        host.wallet!.failure = CancellationError()
        do {
            _ = try await topUp()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Cancellation was misclassified: \(error)")
        }
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
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

    func testSuccessfulTopUpCompletesBothLegs() async throws {
        let balance = try await topUp()
        XCTAssertEqual(balance, 97)
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
    }
}
