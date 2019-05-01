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
        if (_SNAPSHOT) {
            let app = XCUIApplication()
            snapshot("1")
            
//            app.children(matching: .window).element(boundBy: 0).tap()
//            snapshot("3")
//
//            app.pageIndicators.element(boundBy: 0).tap()
//            snapshot("2")
//
//            app.navigationBars.buttons["burger"].tap()
//            snapshot("4")
        }
    }

}
