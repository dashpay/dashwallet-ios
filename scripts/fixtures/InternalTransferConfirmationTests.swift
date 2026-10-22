import XCTest
@testable import ConfirmationHarness

@MainActor final class ConfirmationTests: XCTestCase {
    func testRejectedConfirmationRemainsDistinctFromSubmissionAndCancelledAuthorization() async {
        let model = ConfirmationModel()
        for outcome in [InternalTransferRunner.StartOutcome.rejected, .notAuthorized, .started, .busy] {
            model.runner.startOutcome = outcome
            let result = await model.confirm()
            XCTAssertEqual(result, outcome)
        }
    }

    func testRecoveryRebindsPreparationAfterRuntimeChangesDuringAuthorization() async {
        let runner = InternalTransferRunner()
        SwiftDashSDKHost.shared.runtime = 1
        CoreShieldedDrainService.context = .init(wallet: 1)
        runner.authorizer.onAuthorize = { SwiftDashSDKHost.shared.runtime = 2 }
        _ = await runner.resumeCoreDrain(context: .init(wallet: 1), operation: nil)
        XCTAssertEqual(runner.coordinator.acceptedResumes, 1)
        XCTAssertEqual(try runner.coordinator.preparation.get().runtime, 2)
        XCTAssertFalse(runner.isAwaitingAuthorization)
    }

    func testRecoveryDoesNotRebindAcrossWalletChangeDuringAuthorization() async {
        let runner = InternalTransferRunner()
        CoreShieldedDrainService.context = .init(wallet: 1)
        runner.authorizer.onAuthorize = { CoreShieldedDrainService.context = .init(wallet: 2) }
        _ = await runner.resumeCoreDrain(context: .init(wallet: 1), operation: nil)
        XCTAssertEqual(runner.coordinator.acceptedResumes, 0)
        XCTAssertFalse(runner.isAwaitingAuthorization)
    }
}
