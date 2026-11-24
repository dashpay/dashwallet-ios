import XCTest
@testable import IdentityTopUpHarness

@MainActor final class IdentityTopUpCompatibilityTests: XCTestCase {
    let host = SwiftDashSDKHost.shared

    override func setUp() async throws {
        host.wallet = ManagedPlatformWallet()
        host.manager = NativeManager()
        SwiftDashSDKTransactionSender.coins = nil
    }

    func topUp() async throws -> UInt64 {
        try await IdentityCreditsTopUp().fromShielded(
            identityId: Data([2]), amountDuffs: 100,
            wallet: host.wallet!, modelContainer: ModelContainer())
    }

    func testAmbiguousSecondLegRetainsUnknownOutcome() async {
        let unknowns: [Error] = [
            SDKError.stateTransitionResultUnconfirmed("result unavailable"),
            PlatformWalletError.transactionBroadcastUnconfirmed("may be sent"),
            PlatformWalletError.shieldedSpendUnconfirmed("may be spent"),
        ]
        for unknown in unknowns {
            host.wallet = ManagedPlatformWallet()
            host.manager = NativeManager()
            host.wallet!.failure = unknown
            do {
                _ = try await topUp()
                XCTFail("Expected unknown broadcast outcome")
            } catch SDKError.stateTransitionResultUnconfirmed, PlatformWalletError.transactionBroadcastUnconfirmed,
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

    func testSettledFirstLegCannotUnshieldAgainAfterWarningDismissal() async {
        host.wallet!.failure = PlatformWalletError.walletOperation("rejected")
        let model = IdentityTopUpViewModel()
        let result = await model.topUp(identityId: Data([2]), amountDuffs: 100, source: .shielded)
        XCTAssertNil(result)
        XCTAssertTrue(model.movedToPlatform)
        XCTAssertFalse(model.submittedUnconfirmed)
        model.errorMessage = nil // Dismiss the warning, then try the same action.
        XCTAssertFalse(model.canTopUp(from: .shielded))
        XCTAssertTrue(model.canTopUp(from: .platform))
        let retry = await model.topUp(identityId: Data([2]), amountDuffs: 100, source: .shielded)
        XCTAssertNil(retry)
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
        } catch IdentityTopUpViewModel.TopUpError.secondLegCancelled {
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

    func testCancelledSecondLegBlocksFreshTopUpPresentation() async {
        host.wallet!.failure = CancellationError()
        let model = IdentityTopUpViewModel()
        let result = await model.topUp(identityId: Data([2]), amountDuffs: 100, source: .shielded)
        XCTAssertNil(result)
        XCTAssertTrue(model.submittedUnconfirmed)
        XCTAssertFalse(model.isProcessing)
        XCTAssertTrue(model.errorMessage?.contains("may have been submitted") == true)
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
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

    func testTransparentInputLimitPreservesConsolidationPresentation() async {
        SwiftDashSDKTransactionSender.coins = (0..<101).map { _ in
            .init(isFinal: true, valueDuffs: 10_000, isCombinable: true)
        }
        let model = IdentityTopUpViewModel()
        let result = await model.topUp(identityId: Data([2]), amountDuffs: 990_000, source: .transparent)
        XCTAssertNil(result)
        XCTAssertNotNil(model.inputLimitCheck)
        XCTAssertFalse(model.submittedUnconfirmed)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(host.wallet!.topUpCalls, 0)
    }

    func testInputLimitPolicyDoesNotReclassifyUnknownSubmission() async {
        let check = AssetLockInputLimit.Check(amountDuffs: 100, inputBudget: 100)
        do {
            let _: UInt64 = try await AssetLockInputLimit.mappingRefusal(check) {
                throw PlatformWalletError.transactionBroadcastUnconfirmed("unknown")
            }
            XCTFail("Expected unknown submission")
        } catch PlatformWalletError.transactionBroadcastUnconfirmed {
        } catch {
            XCTFail("Unknown submission reclassified: \(error)")
        }
    }

    func testRunnerDoesNotCarryUnknownOutcomeIntoNextAuthorizedRequest() async {
        let runner = InternalTransferRunner()
        let request = InternalTransferRequest(amountDuffsUnsigned: 100)
        let firstWallet = host.wallet!
        firstWallet.failure = PlatformWalletError.transactionBroadcastUnconfirmed("unknown")
        await runner.runTopUp(.init(identityId: Data([2]), source: .shielded), request)
        XCTAssertEqual(runner.phase, .submittedUnconfirmed)
        XCTAssertEqual(firstWallet.topUpCalls, 1)
        // A new reviewed request can target another identity/runtime.
        host.wallet = ManagedPlatformWallet()
        await runner.runTopUp(.init(identityId: Data([3]), source: .shielded), request)
        XCTAssertEqual(runner.phase, .success)
        XCTAssertEqual(runner.notice, .succeeded)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
        XCTAssertEqual(host.manager!.unshieldCalls, 2)
    }

    func testRunnerDoesNotCarryMovedFundsIntoNextAuthorizedRequest() async {
        let runner = InternalTransferRunner()
        let request = InternalTransferRequest(amountDuffsUnsigned: 100)
        let transfer = IdentityTopUpTransfer(identityId: Data([2]), source: .shielded)
        host.wallet!.failure = PlatformWalletError.walletOperation("refused")
        await runner.runTopUp(transfer, request)
        guard case .failed = runner.phase else { return XCTFail("Expected second-leg refusal") }
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        host.wallet!.failure = nil
        await runner.runTopUp(transfer, request)
        XCTAssertEqual(runner.phase, .success)
        XCTAssertEqual(runner.notice, .succeeded)
        XCTAssertEqual(host.manager!.unshieldCalls, 2)
        XCTAssertEqual(host.wallet!.topUpCalls, 2)
    }

    func testSuccessfulTopUpCompletesBothLegs() async throws {
        let balance = try await topUp()
        XCTAssertEqual(balance, 97)
        XCTAssertEqual(host.manager!.unshieldCalls, 1)
        XCTAssertEqual(host.wallet!.topUpCalls, 1)
    }
}
