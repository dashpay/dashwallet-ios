import XCTest

/// A plain toggle row (Notifications, Enable Voting) is a button whose action
/// is the toggle, wrapped around a `MenuItem` that still draws its own switch.
/// This pins what that buys and what it must not cost: a tap anywhere on the
/// row — the gap between title and switch, the strip the 60 pt minimum height
/// adds, the switch itself — flips the setting exactly once, the switch moves
/// right away, and VoiceOver sees a single labeled switch.
///
/// The fixture hosts the real `SettingsScreen` with no wallet behind it.
/// A double-fired tap would leave the value where it started, so asserting
/// the flip after every tap is what "exactly once" checks.
final class SettingsRowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SETTINGS_ROWS_UI_TEST"] = "1"
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testEnableVotingRowFlipsFromAnywhereOnTheRow() {
        assertWholeRowFlips("settings_row_enable_voting", label: "Enable Voting")
    }

    func testNotificationsRowFlipsFromAnywhereOnTheRow() {
        assertWholeRowFlips("settings_row_notifications", label: "Notifications")
    }

    private func assertWholeRowFlips(_ identifier: String, label: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let row = app.switches[identifier]
        XCTAssert(row.waitForExistence(timeout: 10),
                  "\(label) is not a switch element — VoiceOver would read a stateless button",
                  file: file, line: line)
        XCTAssertEqual(row.label, label, file: file, line: line)
        // One element, not a button with a second switch inside it.
        XCTAssertEqual(row.descendants(matching: .switch).count, 0,
                       "\(label) exposes a nested switch next to the row", file: file, line: line)

        let original = value(of: row)
        let taps: [(String, CGVector)] = [
            ("the gap between title and switch", CGVector(dx: 0.6, dy: 0.5)),
            ("the minimum-height strip", CGVector(dx: 0.3, dy: 0.95)),
            ("the switch", CGVector(dx: 0.92, dy: 0.5)),
        ]
        var expected = original
        for (place, offset) in taps {
            row.coordinate(withNormalizedOffset: offset).tap()
            expected.toggle()
            XCTAssertEqual(value(of: row), expected,
                           "Tapping \(place) of \(label) did not flip it exactly once",
                           file: file, line: line)
        }

        // The setting persists in UserDefaults, which this target does not
        // reset between runs — put it back for the next run.
        if value(of: row) != original {
            row.tap()
            XCTAssertEqual(value(of: row), original,
                           "Could not restore \(label) to its original state", file: file, line: line)
        }
    }

    /// The switch's value, read once it has settled after a tap.
    private func value(of row: XCUIElement) -> Bool {
        _ = row.waitForExistence(timeout: 2)
        return (row.value as? String) == "1"
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
extension SettingsRowsUITests {

    /// The switch's centre, from the row's trailing edge: `MenuItem` pads the
    /// row by 10 pt and the switch is 64 pt wide.
    private static let switchCenterFromTrailingEdge: CGFloat = 42

    func testAdvancedModeSwitchDoesNotOpenTheExplainer() throws {
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
            // A failed check here must not stop the block before the restore.
            continueAfterFailure = true
            // The row sits behind the explainer when it is open, so close it first.
            if sheet.exists {
                let close = app.buttons["navigationbar-close"].firstMatch
                guard close.waitForExistence(timeout: 3) else {
                    XCTFail("The explainer has no Close button, so the mode could not be restored")
                    return
                }
                close.tap()
                guard sheet.waitForNonExistence(timeout: 3) else {
                    XCTFail("The explainer did not close, so the mode could not be restored")
                    return
                }
            }
            guard row.waitForExistence(timeout: 3) else {
                XCTFail("The Advanced mode row is gone, so its original state could not be restored")
                return
            }
            guard (row.value as? String) != before else { return }
            guard row.isHittable else {
                XCTFail("The Advanced mode row is covered, so its original state could not be restored")
                return
            }
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
