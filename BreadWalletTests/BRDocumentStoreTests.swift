//
//  BRDocumentStoreTests.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/10/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import XCTest
@testable import breadwallet

class BRDocumentStoreTests: XCTestCase {
    var cli: ReplicationClient!
    
    override func setUp() {
        let uuid = "yyz" + NSUUID().UUIDString.lowercaseString
        cli = RemoteCouchDB(url: "http://localhost:5984/" + uuid)
        super.setUp()
    }
    
    override func tearDown() {
        cli = nil
        super.tearDown()
    }
    
    func testExistFailure() {
        let exp = expectationWithDescription("existence failure")

        cli.exists().success(AsyncCallback<Bool> { didSucceed in
            XCTAssert(didSucceed == false)
            exp.fulfill()
            return didSucceed
        }).failure(AsyncCallback<AsyncError> { existsFailure in
            XCTFail()
            exp.fulfill()
            return existsFailure
        })
        
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testCreateSuccess() {
        let exp = expectationWithDescription("create success")
        cli.create().success(AsyncCallback<Bool> { didSucceed in
            XCTAssert(didSucceed)
            exp.fulfill()
            return didSucceed
        }).failure(AsyncCallback<AsyncError> { existsFailure in
            XCTFail()
            exp.fulfill()
            return existsFailure
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testCreateThenExists() {
        let exp = expectationWithDescription("create then exists")
        cli.create().success(AsyncCallback<Bool> { didSucceed in
            XCTAssert(didSucceed)
            self.cli.exists().success(AsyncCallback<Bool> { doesExist in
                XCTAssert(doesExist)
                exp.fulfill()
                return doesExist
            })
            return didSucceed
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    
}
