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
