//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

@testable import dashpay
import XCTest

/// The lock-held sheet's Finish: it resumes the held lock through the resume seam (in the app,
/// `AssetLockRecoveryService.retry`, the Rebroadcast resume) and reports what the resume established. The seam is a
/// fake; the ViewModel is the real one.
@MainActor
final class SendLockHeldViewModelTests: XCTestCase {
    private struct ResumeFailure: Error {}

    private final class FakeResumer: HeldAssetLockResuming {
        var result: Result<AssetLockRecoveryService.Outcome, Error> = .success(.completed)
        private(set) var resumed: [HeldAssetLock] = []
        /// Runs inside `resume`, before it answers.
        var onResume: (() async -> Void)?

        func resume(_ lock: HeldAssetLock) async throws -> AssetLockRecoveryService.Outcome {
            resumed.append(lock)
            await onResume?()
            return try result.get()
        }
    }

    private let lock = HeldAssetLock(fundingTypeRaw: 4, txidWire: Data(repeating: 0x2A, count: 32), vout: 1)
    private let resumer = FakeResumer()
    private var results: [SendLockHeldViewModel.Result] = []

    private func makeViewModel() -> SendLockHeldViewModel {
        let viewModel = SendLockHeldViewModel(lock: lock, resumer: resumer)
        viewModel.onFinished = { [unowned self] in results.append($0) }
        return viewModel
    }

    func testFinishResumesTheHeldLockAndReportsCompleted() async {
        let viewModel = makeViewModel()

        await viewModel.finish()

        XCTAssertEqual(resumer.resumed, [lock])
        XCTAssertEqual(results, [.completed])
        XCTAssertEqual(viewModel.state, .ready)
    }

    func testAnUnconfirmedResumeReportsWhatTheResumeEstablished() async {
        let cases: [(AssetLockRecoveryService.Outcome, String)] = [
            (.completionUnconfirmed, "Already spent — nothing to transfer"),
            (.submittedAwaitingSync, "Submitted — waiting for the network to confirm"),
        ]
        for (outcome, text) in cases {
            results = []
            resumer.result = .success(outcome)
            await makeViewModel().finish()
            XCTAssertEqual(results, [.info(text)], "\(outcome)")
        }
    }

    /// Backing out of the PIN prompt is not a failure: the sheet stays as it was and Finish can be tapped again.
    func testACancelledPromptLeavesTheSheetReady() async {
        resumer.result = .failure(DWIdentityAuthorizer.AuthError.cancelled)
        let viewModel = makeViewModel()

        await viewModel.finish()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertNil(viewModel.failureMessage)
        XCTAssertTrue(results.isEmpty)
    }

    func testAFailedResumeKeepsTheSheetWithItsFailureAndFinishAgainResumesTheSameLock() async {
        resumer.result = .failure(ResumeFailure())
        let viewModel = makeViewModel()

        await viewModel.finish()

        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertNotNil(viewModel.failureMessage)
        XCTAssertTrue(results.isEmpty)

        resumer.result = .success(.completed)
        await viewModel.finish()

        XCTAssertEqual(resumer.resumed, [lock, lock])
        XCTAssertEqual(results, [.completed])
    }

    /// Another attempt is already consuming the lock: nothing failed, the flow closes on the coordinator's text.
    func testAResumeRefusedAsInProgressReportsItsText() async {
        resumer.result = .failure(AssetLockRecoveryService.RecoveryError.inProgress("busy"))

        await makeViewModel().finish()

        XCTAssertEqual(results, [.info("busy")])
    }

    func testASecondFinishWhileTheFirstRunsStartsNothing() async {
        let viewModel = makeViewModel()
        resumer.onResume = { [unowned self] in
            XCTAssertTrue(viewModel.isFinishing)
            resumer.onResume = nil
            await viewModel.finish()
        }

        await viewModel.finish()

        XCTAssertEqual(resumer.resumed, [lock])
        XCTAssertEqual(results, [.completed])
    }
}
