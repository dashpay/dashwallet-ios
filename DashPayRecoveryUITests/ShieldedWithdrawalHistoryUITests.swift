import XCTest

/// End-to-end UI/persistence regression, with outcomes injected at the SDK
/// persistence boundary. No network submission or Rust verification is simulated.
final class ShieldedWithdrawalHistoryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SHIELDED_HISTORY_UI_TEST"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["recordPending"].waitForExistence(timeout: 15))
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    private func row(_ byte: UInt8) -> XCUIElement {
        let key = String(repeating: String(format: "%02x", byte), count: 32)
        return app.descendants(matching: .any)["shielded-\(key)-0"].firstMatch
    }

    /// Waits for the production row to expose its projected status to accessibility.
    private func assertStatus(_ value: String, id: UInt8 = 1, file: StaticString = #filePath, line: UInt = #line) {
        let element = row(id)
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        // SwiftUI may expose the button's children separately or combine them
        // into its label; both are the real production row's accessibility text.
        let status = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.label.contains(value) || element.staticTexts[value].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [status], timeout: 5), .completed,
                       "Expected \(value) in \(element.debugDescription)", file: file, line: line)
        XCTAssertFalse(app.staticTexts["fixtureError"].exists, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInjectedRejectionRemainsFailedAfterRelaunchAndLaterSmallerPayout() {
        app.buttons["recordPending"].tap()
        assertStatus("Pending")
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: yes")
        app.buttons["injectFailure"].tap()
        assertStatus("Failed")
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: no")
        // SwiftUI localizes numeric interpolation (including grouping separators).
        XCTAssertEqual(app.staticTexts["fixtureBalance"].label.filter(\.isNumber), "10000000000")
        XCTAssertEqual(app.staticTexts["fixtureReceipts"].label, "Core receipts: 0")
        capture("Rejected withdrawal retains Shielded balance")
        row(1).tap()
        XCTAssertTrue(app.staticTexts["Failed"].waitForExistence(timeout: 5))
        capture("Failed withdrawal details")
        app.buttons["closeDetails"].tap()
        app.terminate()
        app.launch()
        assertStatus("Failed")
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: no")
        app.buttons["recordSmaller"].tap()
        assertStatus("Pending", id: 2)
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: yes")
        app.buttons["recordReceipt"].tap()
        assertStatus("Failed")
        XCTAssertFalse(row(2).exists)
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: yes")
        XCTAssertEqual(app.staticTexts["fixtureReceipts"].label, "Core receipts: 1")
        capture("Earlier failure survives later receipt to same address")
    }

    func testRestoredFailureCannotBecomePendingOrDisappearAfterReceipt() {
        app.buttons["recordRestoredFailure"].tap()
        assertStatus("Failed", id: 3)
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: no")
        app.buttons["recordReceipt"].tap()
        app.buttons["reloadHistory"].tap()
        assertStatus("Failed", id: 3)
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: no")
        capture("Restored failure preserved")
    }

    func testConfirmedWithdrawalWaitsUntilCoreReceiptArrives() {
        app.buttons["recordPending"].tap()
        app.buttons["confirmWithdrawal"].tap()
        assertStatus("Pending")
        capture("Confirmed withdrawal awaiting Core receipt")
        app.buttons["recordReceipt"].tap()
        XCTAssertFalse(row(1).exists)
        XCTAssertEqual(app.staticTexts["fixtureDestinationTagged"].label, "Destination tagged: yes")
        XCTAssertEqual(app.staticTexts["fixtureReceipts"].label, "Core receipts: 1")
    }
}
