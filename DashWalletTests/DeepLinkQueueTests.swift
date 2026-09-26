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
/// rule for handing them over: in arrival order, one at a time, and only when
/// the app can act on them.
final class DeepLinkQueueTests: XCTestCase {
    private let invitation = DeepLink(url: URL(string: "dashpay://invite?du=x&pk=y")!, isInvitation: true)
    private let scan = DeepLink(url: URL(string: "dashwallet://scanqr")!, isInvitation: false)
    private let payment = DeepLink(url: URL(string: "dash:XpESxaUmonkq8RaLLp46Brx2K39ggQe226?amount=0.01")!, isInvitation: false)

    private func ready(_ queue: DeepLinkQueue) -> DeepLink? {
        queue.takeNext(walletPresented: true, unlocked: true, launchHoldPending: false)
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

    func testOnlyOneLinkIsInFlightUntilItsScreenReportsBack() {
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

    func testNothingIsHandedOverWhileTheAppCannotActOnLinks() {
        let queue = DeepLinkQueue()
        queue.enqueue(payment)

        XCTAssertNil(queue.takeNext(walletPresented: false, unlocked: true, launchHoldPending: false), "no wallet on screen: setup, or the hold's card")
        XCTAssertNil(queue.takeNext(walletPresented: true, unlocked: false, launchHoldPending: false), "locked")
        XCTAssertNil(queue.takeNext(walletPresented: true, unlocked: true, launchHoldPending: true), "the launch hold has not reported")
        XCTAssertNil(queue.takeNext(walletPresented: false, unlocked: false, launchHoldPending: true))
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
        XCTAssertNil(queue.takeNext(walletPresented: false, unlocked: true, launchHoldPending: false))
        queue.enqueue(payment)
        XCTAssertNil(queue.takeNext(walletPresented: false, unlocked: true, launchHoldPending: false))
        XCTAssertEqual(queue.pending.count, 2)

        // Setup completed and presented the wallet.
        XCTAssertTrue(ready(queue) === invitation)
        queue.dispatchDidFinish()
        XCTAssertTrue(ready(queue) === payment)
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
        XCTAssertTrue(DeepLink(url: URL(string: "dashpay://invite?du=x&pk=y")!).isInvitation)
        #endif
        XCTAssertFalse(DeepLink(url: URL(string: "dashwallet://scanqr")!).isInvitation)
        XCTAssertFalse(DeepLink(url: URL(string: "dash:XpESxaUmonkq8RaLLp46Brx2K39ggQe226")!).isInvitation)
    }
}
