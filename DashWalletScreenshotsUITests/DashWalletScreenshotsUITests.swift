//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

class DashWalletScreenshotsUITests: XCTestCase {
    override func setUp() {
        super.setUp()

        continueAfterFailure = false

        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
    }

    func testTakeScreenshots() {
        if _SNAPSHOT {
            let app = XCUIApplication()

            // Home screen
            snapshot("1")

            waitAndTap(app.cells["shortcut_secure_wallet"])
            waitAndTap(app.buttons["show_recovery_button"])
            waitAndTap(app.otherElements["seedphrase_checkbox"])
            waitAndTap(app.buttons["seedphrase_continue_button"])
            sleep(1)
            // Seed Phrase Backup
            snapshot("5")

            waitAndTap(app.navigationBars.buttons.element(boundBy: 0))
            waitAndTap(app.navigationBars.buttons.element(boundBy: 0))
            waitAndTap(app.navigationBars.buttons.element(boundBy: 0))

            waitAndTap(app.buttons["tabbar_payments_button"])
            waitAndTap(app.buttons["send_pasteboard_button"])
            waitAndTap(app.staticTexts["1"])
            waitAndTap(app.buttons["amount_send_button"])
            sleep(1)
            // Sending confirmation
            snapshot("2")

            waitAndTap(app.otherElements["modal_dimming_view"])
            waitAndTap(app.navigationBars.buttons.element(boundBy: 0))
            waitAndTap(app.otherElements["payments_receive_segment"])
            sleep(1)
            // Receive screen
            snapshot("3")

            waitAndTap(app.buttons["tabbar_payments_button"])
            waitAndTap(app.otherElements["tabbar_menu_button"])
            waitAndTap(app.cells["menu_security_item"])
            waitAndTap(app.cells["menu_security_advanced_item"])
            sleep(1)
            // Advanced Security
            snapshot("4")
        }
    }

    private func waitAndTap(_ element: XCUIElement) {
        let exists = element.waitForExistence(timeout: 3)
        XCTAssert(exists, "\(element)")
        element.tap()
    }
}
