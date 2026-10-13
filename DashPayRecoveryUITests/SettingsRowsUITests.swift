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
