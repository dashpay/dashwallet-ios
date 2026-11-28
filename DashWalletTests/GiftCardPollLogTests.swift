//
//  GiftCardPollLogTests.swift
//  DashWalletTests
//

import XCTest
@testable import dashpay

/// The gift card poller writes provider answers to the exportable log; only app-owned labels and
/// error kinds may reach it.
final class GiftCardPollLogTests: XCTestCase {

    func testCTXKnownStatusesKeepTheirLabel() {
        for status in ["unpaid", "paid", "fulfilled", "rejected", "expired"] {
            XCTAssertEqual(GiftCardDetailsViewModel.loggableCTXStatus(status), status)
        }
        XCTAssertEqual(GiftCardDetailsViewModel.loggableCTXStatus("Expired"), "expired")
    }

    func testCTXUnknownStatusIsNotCopied() {
        XCTAssertEqual(GiftCardDetailsViewModel.loggableCTXStatus("on_hold"), "<unrecognized>")
        XCTAssertEqual(GiftCardDetailsViewModel.loggableCTXStatus("Card for jane@example.com"), "<unrecognized>")
        XCTAssertEqual(GiftCardDetailsViewModel.loggableCTXStatus(""), "<unrecognized>")
    }

    func testPiggyCardsKnownStatusesGetAppLabels() {
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("Payment pending"), "payment_pending")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("Paid"), "paid")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("Processing"), "processing")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("Complete"), "complete")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("completed"), "complete")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("Cancelled"), "cancelled")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("failed"), "failed")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("rejected"), "rejected")
    }

    func testPiggyCardsUnknownStatusIsNotCopied() {
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("refunded"), "<unrecognized>")
        XCTAssertEqual(GiftCardDetailsViewModel.loggablePiggyCardsStatus("Order 42 for Jane"), "<unrecognized>")
    }

    func testErrorLogsItsKindWithoutProviderText() {
        let providerText = "Order 42 belongs to jane@example.com"
        let custom = GiftCardDetailsViewModel.loggableError(DashSpendError.customError(providerText))
        XCTAssertEqual(custom, "DashSpendError.customError")

        let processing = GiftCardDetailsViewModel.loggableError(DashSpendError.paymentProcessingError(providerText))
        XCTAssertEqual(processing, "DashSpendError.paymentProcessingError")

        XCTAssertEqual(GiftCardDetailsViewModel.loggableError(DashSpendError.networkError), "DashSpendError.networkError")
        XCTAssertEqual(GiftCardDetailsViewModel.loggableError(URLError(.timedOut)), "NSURLErrorDomain -1001")
    }
}
