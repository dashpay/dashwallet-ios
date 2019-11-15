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

        // Set time in status bar to 9:41, full battery, wifi and carrier
        if _SNAPSHOT {
            SDStatusBarManager.sharedInstance()?.enableOverrides()
        }

        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
    }

    func testTakeScreenshots() {
        if _SNAPSHOT {
            let app = XCUIApplication()

            // Send screen
            //
            snapshot("1")

            // Receive screen
            //
            app.pageIndicators.element(boundBy: 0).tap()
            snapshot("2")

            // Request amount screen
            //
            app.buttons["share_button"].tap()
            sleep(1)
            app.sheets.buttons.element(boundBy: 1).tap()
            sleep(2)
            app.staticTexts["3"].tap()
            app.staticTexts["amount_button_separator"].tap()
            app.staticTexts["1"].tap()
            app.staticTexts["4"].tap()
            snapshot("3")

            // Transactions screen
            //
            // press cancel button
            app.navigationBars["DWAmountView"].children(matching: .button).element(boundBy: 0).tap()
            // press menu button
            app.navigationBars["DWRootView"].children(matching: .button).element(boundBy: 0).tap()
            snapshot("4")

            // About
            //
            app.tables.cells.element(boundBy: 5).tap()
            app.tables.cells.element(boundBy: 0).tap()
            snapshot("5")
        }
    }
}
