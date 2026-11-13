//
//  ShieldedRecoveryTapActionTests.swift
//  DashWalletTests
//
//  What "Finish now" on the shielded recovery sheet does in each coordinator
//  phase. Ticket 32167: after a failed attempt the coordinator stayed in
//  `.failed`, its single-flight gate only opens from `.idle`, and every later
//  tap was refused without a trace until the app was restarted.
//

import XCTest
@testable import dashpay

final class ShieldedRecoveryTapActionTests: XCTestCase {

    private typealias Phase = ShieldedTransferCoordinator.Phase

    func testIdleStartsAnAttempt() {
        XCTAssertEqual(ShieldedRecoveryViewModel.tapAction(for: .idle), .resume)
    }

    func testFailureResetsBeforeRetrying() {
        XCTAssertEqual(ShieldedRecoveryViewModel.tapAction(for: .failed("boom")), .resetAndResume)
    }

    func testRunningAttemptIsNeverDoubled() {
        let running: [Phase] = [.signing, .locking, .proving, .broadcasting]
        for phase in running {
            XCTAssertEqual(ShieldedRecoveryViewModel.tapAction(for: phase), .ignore, "\(phase)")
        }
    }

    func testFinishedVerdictsAreNotRetried() {
        XCTAssertEqual(ShieldedRecoveryViewModel.tapAction(for: .success), .ignore)
        // Re-submitting an unconfirmed broadcast risks a double spend.
        XCTAssertEqual(ShieldedRecoveryViewModel.tapAction(for: .submittedUnconfirmed), .ignore)
    }

    func testInFlightMatchesTheRunningPhases() {
        let all: [Phase] = [.idle, .signing, .locking, .proving, .broadcasting, .success, .submittedUnconfirmed, .failed("x")]
        let inFlight = all.filter(\.isInFlight)
        XCTAssertEqual(inFlight, [.signing, .locking, .proving, .broadcasting])
    }

    /// A Max drain can complete between opening the sheet from a pending row
    /// and tapping "Finish now". The preflight must read the SDK's
    /// DrainCompleted (6) as finished; a generic resume of that lock is
    /// rejected as already consumed and would show it as unconfirmed.
    func testPreflightTreatsACompletedDrainAsFinished() {
        XCTAssertEqual(AssetLockStatus(rawValue: 6), .drainCompleted)
        let finished = (0...6).filter { AssetLockStatus(rawValue: $0)?.isComplete == true }
        XCTAssertEqual(finished, [4, 6])
        XCTAssertEqual(TxDetailModel.lockStatusText(6), TxDetailModel.lockStatusText(4))
        XCTAssertFalse(TxDetailModel.statusAllowsRetry(6))
    }

    func testLongWaitStartsAfterTheCopysMinute() {
        XCTAssertEqual(ShieldedRecoveryViewModel.longProofWaitThreshold, .seconds(60))
    }
}
