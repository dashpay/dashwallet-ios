//
//  InternalTransferNoticeTests.swift
//  DashWalletTests
//
//  How long an internal transfer's toast stays up and which notice a close
//  clears. A failure has no timer — its reason is the one thing the history
//  will not show — and the close glyph must not sweep away a newer outcome.
//

import XCTest
@testable import dashpay

final class InternalTransferNoticeTests: XCTestCase {

    private typealias Notice = InternalTransferRunner.Notice

    private let duration: TimeInterval = 3
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private let timedNotices: [Notice] = [.started, .busy, .succeeded, .submitted]

    // MARK: - Display time

    func testFailureHasNoTimer() {
        XCTAssertNil(Notice.failed("boom").remainingDisplayTime(raisedAt: now, now: now, duration: duration))
    }

    func testFailureRaisedWhileAwayIsStillShown() {
        // Home reappears long after the failure: it is still there to read.
        let raisedAt = now.addingTimeInterval(-3600)
        XCTAssertNil(Notice.failed("boom").remainingDisplayTime(raisedAt: raisedAt, now: now, duration: duration))
    }

    func testFreshNoticeGetsTheWholeWindow() {
        for notice in timedNotices {
            XCTAssertEqual(notice.remainingDisplayTime(raisedAt: now, now: now, duration: duration), duration, "\(notice)")
        }
    }

    func testNoticeSeenLateGetsTheRestOfItsWindow() {
        let raisedAt = now.addingTimeInterval(-1)
        for notice in timedNotices {
            XCTAssertEqual(notice.remainingDisplayTime(raisedAt: raisedAt, now: now, duration: duration), 2, "\(notice)")
        }
    }

    func testNoticeWhoseWindowPassedUnseenExpiresAtOnce() {
        for age: TimeInterval in [3, 60] {
            let raisedAt = now.addingTimeInterval(-age)
            for notice in timedNotices {
                XCTAssertEqual(notice.remainingDisplayTime(raisedAt: raisedAt, now: now, duration: duration), 0, "\(notice), age \(age)")
            }
        }
    }

    func testFailureReplacingAStartedNoticeStopsTheCountdown() {
        // The toast's countdown is keyed by the notice; the failure that
        // replaces "Transfer started" mid-window must not inherit its timer.
        XCTAssertNotNil(Notice.started.remainingDisplayTime(raisedAt: now, now: now, duration: duration))
        XCTAssertNil(Notice.failed("boom").remainingDisplayTime(raisedAt: now, now: now, duration: duration))
    }

    // MARK: - Dismissal

    func testClosingTheShownFailureClearsIt() {
        XCTAssertTrue(InternalTransferRunner.dismissal(of: .failed("boom"), clears: .failed("boom")))
    }

    func testStaleCloseLeavesANewerNotice() {
        // The close callback was captured for the old failure; a new transfer
        // has replaced it since.
        let stale: Notice = .failed("first")
        XCTAssertFalse(InternalTransferRunner.dismissal(of: stale, clears: .started))
        XCTAssertFalse(InternalTransferRunner.dismissal(of: stale, clears: .failed("second")))
    }

    func testCloseAfterTheNoticeIsGoneDoesNothing() {
        XCTAssertFalse(InternalTransferRunner.dismissal(of: .failed("boom"), clears: nil))
    }
}
