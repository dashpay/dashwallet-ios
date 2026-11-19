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

/// The Advanced mode row hands its explainer to `MenuItem` as the row action:
/// the icon and text are one button that opens the explainer, and the switch
/// is its own element beside it, named after the row. Neither sits inside the
/// other, so a tap on the switch must flip the setting and leave the sheet
/// shut, and a tap on the body must open the sheet and leave the setting.
extension SettingsRowsUITests {

    func testAdvancedModeSwitchDoesNotOpenTheExplainer() throws {
        let row = advancedModeRow()
        let toggle = row.children(matching: .switch).firstMatch
        let before = try XCTUnwrap(toggle.value as? String, "The Advanced mode switch has no value")
        let flipped = before == "1" ? "0" : "1"
        let sheet = app.descendants(matching: .any)["advanced_mode_info_sheet"]
        restoreAdvancedMode(to: before, toggle: toggle, sheet: sheet)

        toggle.tap()

        XCTAssertFalse(sheet.waitForExistence(timeout: 2), "Tapping the switch opened the explainer")
        XCTAssertTrue(waitForValue(of: toggle, toBe: flipped), "The switch did not change state")
    }

    func testAdvancedModeBodyOpensTheExplainerWithoutFlipping() throws {
        let row = advancedModeRow()
        let toggle = row.children(matching: .switch).firstMatch
        let before = try XCTUnwrap(toggle.value as? String, "The Advanced mode switch has no value")
        let sheet = app.descendants(matching: .any)["advanced_mode_info_sheet"]
        restoreAdvancedMode(to: before, toggle: toggle, sheet: sheet)

        row.children(matching: .button).firstMatch.tap()

        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "Tapping the row body did not open the explainer")
        XCTAssertEqual(toggle.value as? String, before, "Tapping the row body flipped the switch")
    }

    /// The row's group, after checking it holds exactly one button and one
    /// switch, both named after the row. Only direct children count:
    /// `SwitchView` keeps a zero-size switch inside its own element, which
    /// VoiceOver does not enter.
    private func advancedModeRow(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = app.descendants(matching: .any)["settings_row_advanced_mode"]
        XCTAssert(row.waitForExistence(timeout: 15),
                  "Advanced mode row not found — the Settings screen is not on display", file: file, line: line)
        let switches = row.children(matching: .switch)
        let buttons = row.children(matching: .button)
        XCTAssertEqual(switches.count, 1, "The Advanced mode row should expose one switch", file: file, line: line)
        XCTAssertEqual(buttons.count, 1, "The Advanced mode row should expose one button", file: file, line: line)
        XCTAssertEqual(switches.firstMatch.label, "Advanced mode", "The switch is not named after the row",
                       file: file, line: line)
        XCTAssertEqual(buttons.firstMatch.label, "Advanced mode", "The row body is not named after the row",
                       file: file, line: line)
        return row
    }

    /// The switch writes through to UserDefaults, which this target does not
    /// reset between runs — put it back, even after a failure, so the next
    /// test does not start in whichever mode this one left behind. Only the
    /// mode comes back: a flip by hand also records Advanced mode as the
    /// user's own choice, so it no longer turns on by itself afterwards.
    private func restoreAdvancedMode(to value: String, toggle: XCUIElement, sheet: XCUIElement) {
        addTeardownBlock { [self] in
            // A failed check here must not stop the block before the restore.
            continueAfterFailure = true
            // The row sits behind the explainer when it is open, so close it first.
            if sheet.exists {
                // By label: the sheet's own identifier covers its children's,
                // the close button's `navigationbar-close` included.
                let close = app.buttons["Close"].firstMatch
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
            guard toggle.waitForExistence(timeout: 3) else {
                XCTFail("The Advanced mode switch is gone, so its original state could not be restored")
                return
            }
            guard (toggle.value as? String) != value else { return }
            toggle.tap()
            XCTAssertTrue(waitForValue(of: toggle, toBe: value),
                          "Could not restore the Advanced mode switch to its original state")
        }
    }

    /// Waits for the switch to re-render after a tap, until its value is `value`.
    private func waitForValue(of toggle: XCUIElement, toBe value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }
}
