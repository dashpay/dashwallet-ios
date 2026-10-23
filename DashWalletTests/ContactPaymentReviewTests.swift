//
//  ContactPaymentReviewTests.swift
//  DashWalletTests
//
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

import XCTest
@testable import dashpay

/// Which duffs a contact payment spends, and how often. A fiat entry used to
/// be converted again at the Send tap, so the payment differed from the
/// review; the review now fixes the amount, and these pin that it is spent as
/// reviewed, once, and never after a cancel.
final class ContactPaymentReviewTests: XCTestCase {
    private typealias Review = SendViewModel.ContactPaymentReview

    func testTheSpendGetsTheReviewedDuffs() {
        var review = Review()
        XCTAssertTrue(review.begin(duffs: 2_275_171))
        review.confirm()

        XCTAssertTrue(review.isSending)
        XCTAssertEqual(review.take(), 2_275_171)
    }

    func testAReviewCannotBeSpentTwice() {
        var review = Review()
        _ = review.begin(duffs: 1_000)
        review.confirm()

        XCTAssertEqual(review.take(), 1_000)
        XCTAssertNil(review.take())
    }

    func testACancelledReviewSpendsNothing() {
        var review = Review()
        _ = review.begin(duffs: 1_000)
        review.cancel()
        review.confirm()

        XCTAssertFalse(review.isSending)
        XCTAssertNil(review.duffs)
        XCTAssertNil(review.take())
    }

    func testNothingIsSpentBeforeTheReviewsSend() {
        var review = Review()
        _ = review.begin(duffs: 1_000)

        XCTAssertNil(review.take())
        XCTAssertEqual(review.duffs, 1_000, "a refused take leaves the review open")
    }

    func testSendWithoutAnOpenReviewDoesNotStartSending() {
        var review = Review()
        review.confirm()

        XCTAssertFalse(review.isSending)
    }

    /// An edited entry reviewed again must pay the new figure.
    func testReviewingAgainBeforeSendReplacesTheAmount() {
        var review = Review()
        _ = review.begin(duffs: 1_000)
        XCTAssertTrue(review.begin(duffs: 2_000))
        review.confirm()

        XCTAssertEqual(review.take(), 2_000)
    }

    func testAReopenedReviewCannotReplaceTheCommittedAmount() {
        var review = Review()
        _ = review.begin(duffs: 1_000)
        review.confirm()
        XCTAssertFalse(review.begin(duffs: 9_999))
        review.cancel()

        XCTAssertEqual(review.take(), 1_000)
    }

    func testAFinishedSendLeavesNothingToSpend() {
        var review = Review()
        _ = review.begin(duffs: 1_000)
        review.confirm()
        _ = review.take()
        review.finish()

        XCTAssertFalse(review.isSending)
        XCTAssertNil(review.take())
    }
}
