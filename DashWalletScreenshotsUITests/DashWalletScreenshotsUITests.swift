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

            waitAndTap(app.buttons["tabbar_menu_button"])
            waitAndTap(app.cells["menu_security_item"])
            waitAndTap(app.cells["menu_security_advanced_item"])
            sleep(1)
            // Advanced Security
            snapshot("4")

            waitAndTap(app.navigationBars.buttons.element(boundBy: 0))
            waitAndTap(app.navigationBars.buttons.element(boundBy: 0))

            waitAndTap(app.buttons["tabbar_home_button"])
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
            waitAndTap(app.buttons["action_button"])
            sleep(1)
            // Sending confirmation
            snapshot("2")

            waitAndTap(app.otherElements["modal_dimming_view"])
            waitAndTap(app.navigationBars.buttons.element(boundBy: 0))
            waitAndTap(app.otherElements["payments_receive_segment"])
            sleep(1)
            // Receive screen
            snapshot("3")
        }
    }

    private func waitAndTap(_ element: XCUIElement) {
        let exists = element.waitForExistence(timeout: 3)
        XCTAssert(exists, "\(element)")
        element.tap()
    }
}

// MARK: - Advanced mode row

/// The Advanced mode row is a `Button` that opens the explainer, wrapped around
/// a `MenuItem` whose accessory is an interactive switch. Nesting a control
/// inside a button is where a tap can end up answered twice, so this pins the
/// split: the switch flips the setting and the sheet stays shut.
///
/// `SwitchView` is not a `Toggle` — it is a custom view carrying `.isButton`
/// and an On/Off accessibility value — which is why the switch is found as a
/// button descendant of the row rather than through `app.switches`.
class AdvancedModeRowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testTappingTheSwitchDoesNotOpenTheExplainer() {
        app.launch()

        let row = app.descendants(matching: .any)["settings_row_advanced_mode"]
        XCTAssert(row.waitForExistence(timeout: 15),
                  "Advanced mode row not found — the Settings screen is not on display")

        let toggle = row.buttons.firstMatch
        XCTAssert(toggle.waitForExistence(timeout: 3),
                  "No switch inside the Advanced mode row")

        let before = toggle.value as? String
        toggle.tap()

        let sheet = app.descendants(matching: .any)["advanced_mode_info_sheet"]
        XCTAssertFalse(sheet.waitForExistence(timeout: 2),
                       "Tapping the switch opened the explainer — the row's button swallowed it")

        XCTAssertNotEqual(toggle.value as? String, before,
                          "The switch did not change state, so the tap never reached it")

        // The switch writes through to UserDefaults, which this target does not
        // reset between runs — put it back so the next test does not start in
        // whichever mode this one left behind.
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, before,
                       "Could not restore the Advanced mode switch to its original state")
    }
}
