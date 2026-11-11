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

/// The Send tab menu model (SCR-01, AC-20): three rows, in this order, each with the
/// action it triggers today.
final class SendMenuTests: XCTestCase {
    func testMenuListsThreeRowsInOrder() {
        XCTAssertEqual(SendMenuRow.allRows.map(\.title),
                       ["Send to username", "Send to Dash address", "Scan Dash QR"])
    }

    func testRowsCarryTheirActions() {
        XCTAssertEqual(SendMenuRow.allRows.map(\.action),
                       [.openContactFlow, .openAddressScreen, .openQRScanner])
    }

    func testUsernameRowOpensExistingContactFlow() {
        XCTAssertEqual(SendMenuRow.sendToUsername.action, .openContactFlow)
    }

    // MARK: - The card's wiring: each row the card shows calls its own callback

    private final class Spy {
        var calls: [String] = []
    }

    private func card(showsUsername: Bool, spy: Spy) -> PaymentsSendCard {
        PaymentsSendCard(
            showsSendToUsername: showsUsername,
            onSendToUsername: { spy.calls.append("username") },
            onSendToAddress: { spy.calls.append("address") },
            onScanQR: { spy.calls.append("scan") })
    }

    func testEachRowOfTheCardCallsItsOwnCallback() {
        let spy = Spy()
        let card = card(showsUsername: true, spy: spy)
        XCTAssertEqual(card.visibleRows, [.sendToUsername, .sendToAddress, .scanQR])
        for row in card.visibleRows {
            card.handler(for: row.action)()
        }
        XCTAssertEqual(spy.calls, ["username", "address", "scan"])
    }

    func testWithoutAUsernameTheCardHasNoUsernameRowAndNeverOpensTheContactFlow() {
        let spy = Spy()
        let card = card(showsUsername: false, spy: spy)
        XCTAssertEqual(card.visibleRows, [.sendToAddress, .scanQR])
        for row in card.visibleRows {
            card.handler(for: row.action)()
        }
        XCTAssertEqual(spy.calls, ["address", "scan"])
    }
}
