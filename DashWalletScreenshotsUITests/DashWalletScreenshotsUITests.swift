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
/// To accessibility the row is the switch itself: one `.switch` element that
/// carries the row's identifier and the setting's value, with the explainer
/// as a named action. A plain tap on that element lands on the row's centre,
/// which is the body that opens the explainer, so the taps go to the switch's
/// place at the row's trailing end, as a finger would.
class AdvancedModeRowUITests: XCTestCase {

    /// The switch's centre, from the row's trailing edge: `MenuItem` pads the
    /// row by 10 pt and the switch is 64 pt wide.
    private static let switchCenterFromTrailingEdge: CGFloat = 42

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testTappingTheSwitchDoesNotOpenTheExplainer() throws {
        app.launch()

        let row = app.switches["settings_row_advanced_mode"]
        XCTAssert(row.waitForExistence(timeout: 15),
                  "Advanced mode row not found as a switch — the Settings screen is not on display, or VoiceOver reads it as something else")
        XCTAssertFalse(row.label.isEmpty, "The Advanced mode switch has no label")
        // One element: without the row's own representation the button still
        // reads as a switch, with an unlabelled switch nested inside it.
        XCTAssertEqual(row.descendants(matching: .switch).count, 0,
                       "The Advanced mode row exposes a nested switch")

        let before = try XCTUnwrap(row.value as? String, "The Advanced mode switch has no value")
        let flipped = before == "1" ? "0" : "1"

        // The switch writes through to UserDefaults, which this target does not
        // reset between runs — put it back, even after a failure, so the next
        // test does not start in whichever mode this one left behind. Only the
        // mode comes back: a flip by hand also records Advanced mode as the
        // user's own choice, so it no longer turns on by itself afterwards.
        let sheet = app.descendants(matching: .any)["advanced_mode_info_sheet"]
        addTeardownBlock { [self] in
            // The row sits behind the explainer when it is open, so close it first.
            if sheet.exists {
                let close = app.buttons["Close"].firstMatch
                XCTAssert(close.waitForExistence(timeout: 3), "The explainer has no Close button")
                close.tap()
                XCTAssert(sheet.waitForNonExistence(timeout: 3), "The explainer did not close")
            }
            guard row.waitForExistence(timeout: 3) else {
                XCTFail("The Advanced mode row is gone, so its original state could not be restored")
                return
            }
            guard (row.value as? String) != before else { return }
            tapSwitch(in: row)
            XCTAssertTrue(waitForValue(of: row, toBe: before),
                          "Could not restore the Advanced mode switch to its original state")
        }

        tapSwitch(in: row)

        XCTAssertFalse(sheet.waitForExistence(timeout: 2),
                       "Tapping the switch opened the explainer — the row's button swallowed it")

        XCTAssertTrue(waitForValue(of: row, toBe: flipped),
                      "The switch did not change state, so the tap never reached it")
    }

    /// A coordinate tap lands wherever the point is, so the row must be on
    /// screen and uncovered first.
    private func tapSwitch(in row: XCUIElement) {
        XCTAssert(row.isHittable, "The Advanced mode row is off screen or covered")
        row.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -Self.switchCenterFromTrailingEdge, dy: 0))
            .tap()
    }

    /// Waits for the row to re-render after a tap, until its value is `value`.
    private func waitForValue(of row: XCUIElement, toBe value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: row)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }
}
