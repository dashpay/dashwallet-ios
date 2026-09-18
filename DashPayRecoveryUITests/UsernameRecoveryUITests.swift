import XCTest

final class UsernameRecoveryUITests: XCTestCase {
    func testFundedUnnamedIdentityOffersRecoveryAfterLoading() {
        let app = XCUIApplication()
        app.launchEnvironment["DPNS_RECOVERY_UI_TEST"] = "1"
        app.launch()
        let loading = app.descendants(matching: .any)["identityProfileLoading"].firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 5))
        let recovery = app.buttons["finishUsernameRegistration"]
        XCTAssertFalse(recovery.exists)
        app.buttons["loadIdentityFixture"].tap()
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        XCTAssertTrue(recovery.isHittable, "Recovery must be visible and actionable after identity hydration")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Funded unnamed identity offers DPNS recovery"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }
    func testLoadingTimeoutOffersActionableRetry() {
        let app = XCUIApplication()
        app.launchEnvironment["DPNS_RECOVERY_UI_TEST"] = "1"
        app.launch()
        let retry = app.buttons["Retry loading identity"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.buttons["finishUsernameRegistration"].exists)
        retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["identityProfileLoading"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["loadIdentityFixture"].tap()
        XCTAssertTrue(app.buttons["finishUsernameRegistration"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testContextChangeRestartsTimedOutLoading() {
        let app = XCUIApplication()
        app.launchEnvironment["DPNS_RECOVERY_UI_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Retry loading identity"].waitForExistence(timeout: 10))
        app.buttons["switchIdentityFixture"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["identityProfileLoading"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Retry loading identity"].exists)
        app.buttons["loadIdentityFixture"].tap()
        XCTAssertTrue(app.buttons["finishUsernameRegistration"].waitForExistence(timeout: 5))
        app.terminate()
    }

}
