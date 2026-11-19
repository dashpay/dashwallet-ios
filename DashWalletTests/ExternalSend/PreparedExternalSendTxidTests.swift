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

/// The Core to Core txid the success screen opens after the broadcast, kept on the prepared send.
@MainActor
final class PreparedExternalSendTxidTests: XCTestCase {
    private let destination = Destination(type: .coreAddress, text: "XdestinationAddress")

    func testStandardSendExposesItsWireOrderTxid() {
        let display = Data((0..<32).map { UInt8($0) })
        let standard = PreparedStandardSend(
            txData: Data([0x01]), txHash: display, fee: 226, address: "XdestinationAddress", amount: 100_000,
            ensureOnlineAction: {}, broadcastAction: { .accepted(txid: "") })
        let prepared = PreparedExternalSend(
            route: .coreToCore, amount: 100_000, fee: 226, isMax: false, plan: .standard(standard))

        XCTAssertEqual(prepared.txidWire, Data(display.reversed()))
    }

    func testRoutedSendHasNoTxid() {
        let prepared = PreparedExternalSend(
            route: .coreToShielded, amount: 100_000, fee: 226, isMax: false, plan: .routed(destination: destination))

        XCTAssertNil(prepared.txidWire)
    }
}
