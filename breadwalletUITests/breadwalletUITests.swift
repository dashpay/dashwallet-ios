//
//  breadwalletUISnapshot.swift
//
//  Created by James MacWhyte on 12/9/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import XCTest

class breadwalletUISnapshot: XCTestCase {
    
    override func setUp() {
        super.setUp()
        
        continueAfterFailure = false
        
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testTakeScreenshots() {
        
        let app = XCUIApplication()
        snapshot("1")
        
        app.childrenMatchingType(.Window).elementBoundByIndex(0).tap()
        snapshot("3")
        
        app.pageIndicators.elementBoundByIndex(0).tap()
        snapshot("2")
        
        app.navigationBars.buttons["burger"].tap()
        snapshot("4")
        
    }
    
}
