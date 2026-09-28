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

/// `PaymentOperationGate` decides which payment's callbacks a controller
/// admits: only the current one's. Payment A's preparation (a BIP70 fetch,
/// a BIP73 hop) can outlive payment B's start; A's callbacks then arrive
/// obsolete and must neither act nor end B.
final class PaymentOperationGateTests: XCTestCase {
    func testOnlyTheCurrentOperationIsAdmitted() {
        var gate = PaymentOperationGate()
        XCTAssertFalse(gate.admits(0), "nothing runs yet")

        let a = gate.begin()
        XCTAssertTrue(gate.admits(a))
        let b = gate.begin()
        XCTAssertFalse(gate.admits(a), "A is obsolete once B started")
        XCTAssertTrue(gate.admits(b))
        XCTAssertNotEqual(a, b)
    }

    /// A abandoned by the link queue, B started, then A's late callback:
    /// before B settled it must not act, and it must not end B; after B
    /// settled it must not act either — an ended operation stays ended.
    func testAnObsoleteOperationsLateCallbackNeitherActsNorEndsTheNext() {
        var gate = PaymentOperationGate()
        let a = gate.begin()
        let b = gate.begin() // B started while A was still preparing

        // A returns before B settled.
        XCTAssertFalse(gate.admits(a), "A's confirmation is refused")
        XCTAssertFalse(gate.end(a), "A cannot end B's operation")
        XCTAssertTrue(gate.admits(b), "B is still current")

        // B settles.
        XCTAssertTrue(gate.end(b))
        XCTAssertFalse(gate.admits(b))

        // A returns after B settled.
        XCTAssertFalse(gate.admits(a))
        XCTAssertFalse(gate.end(a))
        XCTAssertNil(gate.current)
    }

    func testEndingIsOnce() {
        var gate = PaymentOperationGate()
        let a = gate.begin()
        XCTAssertTrue(gate.end(a))
        XCTAssertFalse(gate.end(a), "already ended")
        XCTAssertFalse(gate.admits(a))
        let c = gate.begin()
        XCTAssertTrue(gate.admits(c), "a new operation after an ended one")
    }

    /// Payment A pushed its amount step, payment B started and pushed its
    /// own: an amount from A's step (reached by Back, or left on the stack)
    /// is refused even though B's processor is current; B's own step is
    /// admitted; a step never bound to any operation is refused.
    func testOnlyTheCurrentOperationsOwnScreenFeedsIt() {
        final class Screen {}
        let stepA = Screen(), stepB = Screen(), stranger = Screen()
        var gate = PaymentOperationGate()

        let a = gate.begin()
        gate.bind(ObjectIdentifier(stepA), to: a)
        XCTAssertTrue(gate.admits(screen: ObjectIdentifier(stepA)))

        let b = gate.begin()
        XCTAssertFalse(gate.admits(screen: ObjectIdentifier(stepA)), "A's step is not B's")
        gate.bind(ObjectIdentifier(stepB), to: b)
        XCTAssertTrue(gate.admits(screen: ObjectIdentifier(stepB)))
        XCTAssertFalse(gate.admits(screen: ObjectIdentifier(stepA)), "still refused after B bound its own")
        XCTAssertFalse(gate.admits(screen: ObjectIdentifier(stranger)), "never bound")

        gate.bind(ObjectIdentifier(stepA), to: a)
        XCTAssertFalse(gate.admits(screen: ObjectIdentifier(stepA)), "binding to an obsolete operation is refused")

        XCTAssertTrue(gate.end(b))
        XCTAssertFalse(gate.admits(screen: ObjectIdentifier(stepB)), "an ended operation's step is refused")
    }
}

/// `PaymentOperationSequence` is what `PaymentController.performPayment`
/// runs every replacement through: the new operation becomes current, then
/// the replaced one's link completion is delivered. These tests drive it
/// with the real `DeepLinkQueue` and a copy of the root controller's
/// completion (`dispatchDidFinish(token:)`, then the next hand-over, which
/// — with nothing presented — starts the next payment synchronously), so
/// the ordering the controller relies on is checked without UIKit or a
/// payment processor.
final class PaymentOperationSequenceTests: XCTestCase {
    /// The root controller's side: the queue, one completion per hand-over
    /// that ends that hand-over and asks for the next one, and the payment
    /// each hand-over starts on the same controller.
    private final class LinkRoot {
        let queue = DeepLinkQueue()
        let sequence: PaymentOperationSequence
        private(set) var completions: [String: Int] = [:]
        private(set) var tokens: [String: PaymentOperationSequence.Token] = [:]
        /// A payment that found its token replaced before it could install
        /// its operation: it must stop there.
        private(set) var stopped: [String] = []

        init(deliver: @escaping (@escaping () -> Void) -> Void) {
            sequence = PaymentOperationSequence(deliver: deliver)
        }

        func enqueue(_ name: String) {
            queue.enqueue(DeepLink(url: URL(string: "dash:\(name)")!, isInvitation: false, isUnsupported: false))
        }

        /// `dispatchNextLinkIfReady` with everything ready and nothing
        /// presented: the payment starts inside this call.
        func dispatchNext() {
            guard let link = queue.takeNext(walletPresented: true, attached: true, unlocked: true, launchHoldPending: false, invitationsReady: true) else { return }
            let name = String(link.url.absoluteString.dropFirst("dash:".count))
            let token = queue.dispatchToken
            let done = { [unowned self] in
                self.completions[name, default: 0] += 1
                guard self.queue.dispatchDidFinish(token: token) else { return }
                self.dispatchNext()
            }
            perform(name, settled: done, isAbandoned: { [unowned self] in !self.queue.isDispatching || self.queue.dispatchToken != token })
        }

        /// `performPayment`'s ordering: begin (current first, predecessor
        /// notified after), then stop if the token was replaced meanwhile.
        func perform(_ name: String, settled: (() -> Void)?, isAbandoned: (() -> Bool)?) {
            let token = sequence.begin(settled: settled, isAbandoned: isAbandoned)
            guard sequence.admits(token) else {
                stopped.append(name)
                return
            }
            tokens[name] = token
        }

        func current() -> String? {
            tokens.first { sequence.current == $0.value }?.key
        }
    }

    /// Settlements delivered on a later turn, drained by hand.
    private final class Turns {
        var pending: [() -> Void] = []
        func deliver(_ work: @escaping () -> Void) { pending.append(work) }
        func drain() {
            while !pending.isEmpty {
                pending.removeFirst()()
            }
        }
    }

    /// The reported scenario: link A is preparing (its BIP70 fetch has not
    /// returned), link C is queued behind it, and the user scans payment B
    /// by hand. Starting B must not start C inside B's own start; B is
    /// current when B's start returns; A's completion then runs once, the
    /// queue hands C over, and C — not B — owns the controller, with C's
    /// hand-over still in flight until C settles, exactly once.
    func testManualPaymentOverAPreparingLinkDoesNotReenterOrOverwriteTheQueuedOne() {
        let turns = Turns()
        let root = LinkRoot(deliver: turns.deliver)
        root.enqueue("A")
        root.enqueue("C")
        root.dispatchNext()
        XCTAssertEqual(root.current(), "A")
        XCTAssertTrue(root.sequence.awaitsSettlement(root.tokens["A"]!))

        root.perform("B", settled: nil, isAbandoned: nil) // the scanner's payment

        XCTAssertEqual(root.current(), "B", "B is current when its start returns")
        XCTAssertNil(root.tokens["C"], "C did not start inside B's start")
        XCTAssertEqual(root.completions["A"] ?? 0, 0, "A's completion is delivered later, not inside B's start")
        XCTAssertFalse(root.sequence.awaitsSettlement(root.tokens["A"]!), "A is detached at once")
        XCTAssertTrue(root.queue.isDispatching, "A's hand-over is still in flight until the delivery")

        turns.drain()

        XCTAssertEqual(root.completions["A"], 1)
        XCTAssertEqual(root.current(), "C", "the queued link owns the controller")
        XCTAssertFalse(root.sequence.admits(root.tokens["B"]!), "B's late callbacks are refused")
        XCTAssertTrue(root.queue.isDispatching, "C's hand-over waits for C's screen")
        XCTAssertTrue(root.sequence.awaitsSettlement(root.tokens["C"]!))
        XCTAssertTrue(root.stopped.isEmpty)

        // C's amount step finishes presenting.
        root.sequence.settle(root.tokens["C"]!)
        root.sequence.settle(root.tokens["C"]!) // a second report is a no-op
        turns.drain()

        XCTAssertEqual(root.completions, ["A": 1, "C": 1], "each link settled exactly once")
        XCTAssertFalse(root.queue.isDispatching)
        XCTAssertTrue(root.queue.isEmpty)
    }

    /// The same scenario with the predecessor notified synchronously (the
    /// ordering before the fix): C starts inside B's start. B's start must
    /// then find its token replaced and stop instead of overwriting C, and
    /// every link still settles exactly once.
    func testAReentrantStartStopsTheOuterOneInsteadOfOverwritingTheInner() {
        let root = LinkRoot(deliver: { $0() })
        root.enqueue("A")
        root.enqueue("C")
        root.dispatchNext()

        root.perform("B", settled: nil, isAbandoned: nil)

        XCTAssertEqual(root.stopped, ["B"], "B's start stops once C has replaced it")
        XCTAssertEqual(root.current(), "C", "C's operation is not overwritten")
        XCTAssertEqual(root.completions["A"], 1)
        XCTAssertTrue(root.sequence.awaitsSettlement(root.tokens["C"]!), "C's link is still C's to settle")

        root.sequence.settle(root.tokens["C"]!)
        XCTAssertEqual(root.completions, ["A": 1, "C": 1])
        XCTAssertFalse(root.queue.isDispatching)
    }

    /// Whoever replaces an operation settles it: a link payment replaced by
    /// another link payment is settled by the replacement, once, and its
    /// own late settlement afterwards changes nothing.
    func testAReplacedLinkIsSettledOnceByItsReplacement() {
        let turns = Turns()
        let sequence = PaymentOperationSequence(deliver: turns.deliver)
        var settled: [String: Int] = [:]
        let a = sequence.begin(settled: { settled["A", default: 0] += 1 }, isAbandoned: nil)
        let b = sequence.begin(settled: { settled["B", default: 0] += 1 }, isAbandoned: nil)
        XCTAssertTrue(settled.isEmpty, "nothing runs inside begin")
        turns.drain()
        XCTAssertEqual(settled, ["A": 1])

        sequence.settle(a) // A's own late presentation completion
        sequence.settle(b)
        sequence.settle(b)
        turns.drain()
        XCTAssertEqual(settled, ["A": 1, "B": 1])
    }

    /// A settled payment is no longer the queue's: its later screens (the
    /// confirmation after its amount step) are not dropped because the
    /// queue has since moved on.
    func testASettledPaymentIsNotAbandoned() {
        let turns = Turns()
        let sequence = PaymentOperationSequence(deliver: turns.deliver)
        var queueMovedOn = false
        let a = sequence.begin(settled: {}, isAbandoned: { queueMovedOn })
        queueMovedOn = true
        XCTAssertTrue(sequence.isAbandoned(a), "the queue gave A up before A showed anything")

        sequence.settle(a)
        XCTAssertFalse(sequence.isAbandoned(a), "after A settled, the queue's state is not A's")

        let manual = sequence.begin(settled: nil, isAbandoned: nil)
        XCTAssertFalse(sequence.isAbandoned(manual))
        XCTAssertFalse(sequence.awaitsSettlement(manual))
    }
}
