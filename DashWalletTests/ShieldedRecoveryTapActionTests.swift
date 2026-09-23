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

    func testLongWaitStartsAfterTheCopysMinute() {
        XCTAssertEqual(ShieldedRecoveryViewModel.longProofWaitThreshold, .seconds(60))
    }
}
