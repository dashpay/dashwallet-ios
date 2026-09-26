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

import XCTest

#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
#error("Unknown test host module")
#endif

/// `DeepLinkQueue` is the single holder of pending deep links and the single
/// rule for handing them over: in arrival order, one at a time, only when
/// the app can act on them, and bounded.
final class DeepLinkQueueTests: XCTestCase {
    private let invitation = DeepLink(url: URL(string: "dashpay://invite?du=x&pk=y")!, isInvitation: true, isUnsupported: false)
    private let secondInvitation = DeepLink(url: URL(string: "dashpay://invite?du=z&pk=w")!, isInvitation: true, isUnsupported: false)
    private let scan = DeepLink(url: URL(string: "dashwallet://scanqr")!, isInvitation: false, isUnsupported: false)
    private let payment = DeepLink(url: URL(string: "dash:XpESxaUmonkq8RaLLp46Brx2K39ggQe226?amount=0.01")!, isInvitation: false, isUnsupported: false)

    private func ready(_ queue: DeepLinkQueue, invitationsReady: Bool = true) -> DeepLink? {
        queue.takeNext(walletPresented: true, attached: true, unlocked: true, launchHoldPending: false, invitationsReady: invitationsReady)
    }

    private func url(_ n: Int, unsupported: Bool = false) -> DeepLink {
        DeepLink(url: URL(string: "dash:Xaddress\(n)?amount=\(n)")!, isInvitation: false, isUnsupported: unsupported)
    }

    func testLinksAreHandedOverInArrivalOrderAndKeptWhole() {
        let queue = DeepLinkQueue()
        queue.enqueue(invitation)
        queue.enqueue(scan)
        queue.enqueue(payment)
        XCTAssertEqual(queue.pending.count, 3, "every link is kept, not one per kind")

        XCTAssertTrue(ready(queue) === invitation)
        queue.dispatchDidFinish()
        XCTAssertTrue(ready(queue) === scan)
        queue.dispatchDidFinish()
        XCTAssertTrue(ready(queue) === payment)
        queue.dispatchDidFinish()
        XCTAssertNil(ready(queue))
        XCTAssertTrue(queue.isEmpty)
    }

    func testOnlyOneLinkIsInFlightUntilItsHandlerReportsBack() {
        let queue = DeepLinkQueue()
        queue.enqueue(invitation)
        queue.enqueue(scan)

        XCTAssertTrue(ready(queue) === invitation)
        XCTAssertTrue(queue.isDispatching)
        XCTAssertNil(ready(queue), "the scanner waits for the invitation's screen")
        XCTAssertNil(ready(queue))
        queue.dispatchDidFinish()
        XCTAssertFalse(queue.isDispatching)
        XCTAssertTrue(ready(queue) === scan)
    }

    /// A payment link's handler prepares the send asynchronously and
    /// presents its confirmation later; until it reports, nothing else is
    /// handed over — however often the owner asks.
    func testADelayedPaymentPreparationKeepsTheQueueBusy() {
        let queue = DeepLinkQueue()
        queue.enqueue(payment)
        queue.enqueue(scan)

        XCTAssertTrue(ready(queue) === payment)
        for _ in 0..<5 {
            XCTAssertNil(ready(queue), "still preparing")
        }
        XCTAssertEqual(queue.pending.count, 1)
        queue.dispatchDidFinish()
        XCTAssertTrue(ready(queue) === scan)
    }

    /// Two invitations before sync is done: both wait in the queue, in
    /// order, without holding up a URL behind them; once the home screen
    /// can take invitations they are handed over one after the other —
    /// neither overwrites the other.
    func testInvitationsWaitForSyncInOrderWithoutBlockingURLs() {
        let queue = DeepLinkQueue()
        queue.enqueue(invitation)
        queue.enqueue(secondInvitation)
        queue.enqueue(scan)

        XCTAssertTrue(ready(queue, invitationsReady: false) === scan, "a URL is not gated on sync")
        queue.dispatchDidFinish()
        XCTAssertNil(ready(queue, invitationsReady: false), "the invitations wait")
        XCTAssertEqual(queue.pending.count, 2, "both are kept")

        XCTAssertTrue(ready(queue, invitationsReady: true) === invitation)
        XCTAssertNil(ready(queue, invitationsReady: true), "one at a time")
        queue.dispatchDidFinish()
        XCTAssertTrue(ready(queue, invitationsReady: true) === secondInvitation)
        queue.dispatchDidFinish()
        XCTAssertTrue(queue.isEmpty)
    }

    func testNothingIsHandedOverWhileTheAppCannotActOnLinks() {
        let queue = DeepLinkQueue()
        queue.enqueue(payment)

        XCTAssertNil(queue.takeNext(walletPresented: false, attached: true, unlocked: true, launchHoldPending: false, invitationsReady: true), "no wallet on screen: setup, or the hold's card")
        XCTAssertNil(queue.takeNext(walletPresented: true, attached: false, unlocked: true, launchHoldPending: false, invitationsReady: true), "the hierarchy is not in a window yet (a root created during onboarding)")
        XCTAssertNil(queue.takeNext(walletPresented: true, attached: true, unlocked: false, launchHoldPending: false, invitationsReady: true), "locked")
        XCTAssertNil(queue.takeNext(walletPresented: true, attached: true, unlocked: true, launchHoldPending: true, invitationsReady: true), "the launch hold has not reported")
        XCTAssertNil(queue.takeNext(walletPresented: false, attached: false, unlocked: false, launchHoldPending: true, invitationsReady: false))
        XCTAssertEqual(queue.pending.count, 1, "refusing keeps the link")
        XCTAssertFalse(queue.isDispatching)

        XCTAssertTrue(ready(queue) === payment)
    }

    /// A walletless install: the invitation that opened the app (and any
    /// URL after it) waits in the queue through setup — no separate store —
    /// and is handed over, in order, once setup has presented the wallet.
    func testWalletlessInvitationWaitsForSetupAndIsHandedOverFirst() {
        let queue = DeepLinkQueue()
        queue.enqueue(invitation)
        XCTAssertNil(queue.takeNext(walletPresented: false, attached: true, unlocked: true, launchHoldPending: false, invitationsReady: true))
        queue.enqueue(payment)
        XCTAssertNil(queue.takeNext(walletPresented: false, attached: true, unlocked: true, launchHoldPending: false, invitationsReady: true))
        XCTAssertEqual(queue.pending.count, 2)

        // Setup completed and presented the wallet.
        XCTAssertTrue(ready(queue) === invitation)
        queue.dispatchDidFinish()
        XCTAssertTrue(ready(queue) === payment)
    }

    /// A burst is bounded: the newest `capacity` links are kept, a link
    /// identical to the one queued just before it is dropped, and
    /// unsupported URLs collapse into one pending alert.
    func testABurstIsBoundedDeduplicatedAndCoalesced() {
        let queue = DeepLinkQueue()
        XCTAssertEqual(DeepLinkQueue.capacity, 10)

        var evictions = 0
        for n in 1...25 {
            if queue.enqueue(url(n)) == .queuedEvictingOldest { evictions += 1 }
        }
        XCTAssertEqual(queue.pending.count, 10)
        XCTAssertEqual(evictions, 15)
        XCTAssertEqual(queue.pending.map(\.url.absoluteString).first, url(16).url.absoluteString, "the oldest went, the newest stayed")
        XCTAssertEqual(queue.pending.map(\.url.absoluteString).last, url(25).url.absoluteString)

        let fresh = DeepLinkQueue()
        XCTAssertEqual(fresh.enqueue(scan), .queued)
        XCTAssertEqual(fresh.enqueue(scan), .droppedDuplicate, "the same link twice in a row is one link")
        XCTAssertEqual(fresh.enqueue(payment), .queued)
        XCTAssertEqual(fresh.enqueue(scan), .queued, "not consecutive: kept")
        XCTAssertEqual(fresh.pending.count, 3)

        let alerts = DeepLinkQueue()
        XCTAssertEqual(alerts.enqueue(url(1, unsupported: true)), .queued)
        XCTAssertEqual(alerts.enqueue(url(2, unsupported: true)), .droppedUnsupportedCoalesced, "one alert per burst")
        XCTAssertEqual(alerts.enqueue(payment), .queued)
        XCTAssertEqual(alerts.pending.count, 2)
        XCTAssertTrue(ready(alerts)?.isUnsupported == true)
        alerts.dispatchDidFinish()
        XCTAssertEqual(alerts.enqueue(url(3, unsupported: true)), .queued, "the alert was shown; a new burst gets its own")
    }

    /// A handler's report belongs to one hand-over. After the owner's
    /// watchdog ended a dispatch whose screen never came, a late report
    /// from that handler must not end the next link's dispatch.
    func testALateReportCannotFinishALaterDispatch() {
        let queue = DeepLinkQueue()
        queue.enqueue(scan)
        queue.enqueue(payment)

        XCTAssertTrue(ready(queue) === scan)
        let first = queue.dispatchToken
        XCTAssertTrue(queue.dispatchDidFinish(token: first), "the watchdog ends the dispatch")
        XCTAssertFalse(queue.dispatchDidFinish(token: first), "already over")

        XCTAssertTrue(ready(queue) === payment)
        let second = queue.dispatchToken
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(queue.dispatchDidFinish(token: first), "the scanner's late report is ignored")
        XCTAssertTrue(queue.isDispatching, "the payment is still in flight")
        XCTAssertTrue(queue.dispatchDidFinish(token: second))
        XCTAssertFalse(queue.isDispatching)
    }

    func testAnEmptyQueueHandsOverNothingAndStaysIdle() {
        let queue = DeepLinkQueue()
        XCTAssertNil(ready(queue))
        XCTAssertFalse(queue.isDispatching)
        queue.dispatchDidFinish()
        XCTAssertFalse(queue.isDispatching)
    }

    func testAnInvitationIsRecognizedByItsLink() {
        #if DASHPAY
        let invite = DeepLink(url: URL(string: "dashpay://invite?du=x&pk=y")!, isUnsupported: true)
        XCTAssertTrue(invite.isInvitation)
        XCTAssertFalse(invite.isUnsupported, "an invitation is never an unsupported URL")
        #endif
        XCTAssertFalse(DeepLink(url: URL(string: "dashwallet://scanqr")!).isInvitation)
        XCTAssertFalse(DeepLink(url: URL(string: "dash:XpESxaUmonkq8RaLLp46Brx2K39ggQe226")!).isInvitation)
        XCTAssertTrue(DeepLink(url: URL(string: "dashwallet://nothing")!, isUnsupported: true).isUnsupported)
    }
}
