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

/// Where the send outcome goes after Confirm (AC-19, SCR-09, SCR-10, ADR-0040): `sent` to the existing success
/// view of the route, `inFlight` to a Toast without Retry, `notSent` to Send failed with Retry back to Send.
/// The router is the real one; only the outcome and the request are values.
final class SendOutcomeRouterTests: XCTestCase {
    private let router = SendOutcomeRouter()

    private let allReasons: [NotSentReason] = [
        .offline, .rejected, .earlierPaymentPending, .signingKeyUnavailable, .belowMinimum, .failed
    ]

    // `SendRoute` is not `CaseIterable`; the list is explicit so a new route is a conscious test change.
    private let allRoutes: [SendRoute] = [
        .coreToCore, .coreToShielded, .coreToPlatform, .coreToIdentity,
        .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity,
        .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity,
        .identityToCore, .identityToPlatform, .identityToIdentity
    ]

    // MARK: - Fixtures

    private func request(_ route: SendRoute = .coreToCore, amount: UInt64 = 150_000_000,
                         isMax: Bool = false) -> SendAmountRequest {
        SendAmountRequest(
            route: route,
            destination: Destination(type: .coreAddress, text: "XdestinationAddress", amountDuffs: 5),
            amount: amount,
            isMax: isMax)
    }

    private func failed(_ reason: NotSentReason, _ request: SendAmountRequest) -> SendFailedContent? {
        guard case .sendFailed(let content) = router.destination(for: .notSent(reason), request: request) else {
            XCTFail("expected .sendFailed for \(reason)")
            return nil
        }
        return content
    }

    // MARK: - sent

    func testSentFromCoreShowsTheTransactionSuccessScreen() {
        for route in allRoutes where route.source == .core {
            XCTAssertEqual(router.destination(for: .sent, request: request(route)), .success(.transactionDetails),
                           "\(route)")
        }
    }

    /// Shielded, Platform and Identity sends have no Core transaction to show: the sheet closes on a Sent Toast.
    func testSentFromEveryOtherSourceShowsTheSentToast() {
        for route in allRoutes where route.source != .core {
            XCTAssertEqual(router.destination(for: .sent, request: request(route)), .success(.toast(message: "Sent")),
                           "\(route)")
        }
    }

    /// Retry lives only on Send failed (ADR-0040).
    private func offersRetry(_ destination: SendOutcomeDestination) -> Bool {
        if case .sendFailed = destination { return true }
        return false
    }

    func testSentNeverOffersRetry() {
        XCTAssertFalse(offersRetry(router.destination(for: .sent, request: request())))
    }

    // MARK: - inFlight

    func testInFlightClosesTheSheetWithTheSendInProgressToast() {
        XCTAssertEqual(
            router.destination(for: .inFlight, request: request()),
            .infoToast(title: "Send in progress",
                       message: "It will finish on its own. You don't need to send it again."))
    }

    func testInFlightNeverOffersRetryOnAnyRoute() {
        for route in allRoutes {
            let destination = router.destination(for: .inFlight, request: request(route))
            XCTAssertFalse(offersRetry(destination), "\(route)")
            if case .sendFailed = destination { XCTFail("inFlight must never be a failure: \(route)") }
        }
    }

    // MARK: - The Toast text

    func testTheToastShowsTheTitleBeforeTheMessage() {
        XCTAssertEqual(
            ExternalSendHostController.toastText(
                title: "Send in progress", message: "It will finish on its own. You don't need to send it again."),
            "Send in progress. It will finish on its own. You don't need to send it again.")
        XCTAssertEqual(ExternalSendHostController.toastText(title: "Done!", message: "All set."), "Done! All set.")
        XCTAssertEqual(ExternalSendHostController.toastText(title: "", message: "All set."), "All set.")
    }

    // MARK: - notSent

    func testNotSentShowsSendFailedWithTheReasonsMessage() {
        for reason in allReasons {
            let content = failed(reason, request())
            XCTAssertEqual(content?.title, "Send failed", "\(reason)")
            XCTAssertEqual(content?.reason, reason.localizedMessage, "\(reason)")
        }
    }

    func testNotSentBelowMinimumShowsItsOwnMessage() {
        XCTAssertEqual(failed(.belowMinimum, request())?.reason,
                       "The amount is below the minimum for this payment. Your funds were not sent.")
    }

    func testNotSentOffersRetry() {
        for reason in allReasons {
            XCTAssertTrue(offersRetry(router.destination(for: .notSent(reason), request: request())), "\(reason)")
        }
    }

    func testNotSentNamesTheSourceTheMoneyIsStillIn() {
        let expected: [(SendRoute, String)] = [
            (.coreToShielded, "Core"), (.shieldedToCore, "Shielded"),
            (.platformToIdentity, "Platform"), (.identityToCore, "Identity")
        ]
        for (route, source) in expected {
            XCTAssertEqual(failed(.failed, request(route))?.info,
                           "Nothing was sent. Your money is still in your \(source) balance.", "\(route)")
        }
    }
}
