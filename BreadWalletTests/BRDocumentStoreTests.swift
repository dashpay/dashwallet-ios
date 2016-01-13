//
//  BRDocumentStoreTests.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/10/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import XCTest
@testable import breadwallet

class BRDocumentStoreStartTests: XCTestCase {
    var cli: ReplicationClient!
    var dbName: String!
    
    override func setUp() {
        dbName = "yyz" + NSUUID().UUIDString.lowercaseString
        cli = RemoteCouchDB(url: "http://localhost:5984/" + dbName)
        super.setUp()
    }
    
    override func tearDown() {
        cli = nil
        dbName = nil
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
    
    func testCreateThenInfo() {
        let exp = expectationWithDescription("create then info")
        cli.create().success(AsyncCallback<Bool> { didSucceed in
            XCTAssert(didSucceed)
            self.cli.info().success(AsyncCallback<DatabaseInfo> { dbInfo in
                XCTAssert(dbInfo.dbName == self.dbName)
                exp.fulfill()
                return dbInfo
            })
            return didSucceed
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}

class TestDocument: Document {
    var _id: String
    var _rev: String
    var aString: String
    
    required init(json: AnyObject?) throws {
        let d = json as! NSDictionary
        _id = d["_id"] as! String
        _rev = d["_rev"] as! String
        aString = d["a_string"] as! String
    }
    
    init(name: String, value: String) {
        _id = name
        aString = value
        _rev = ""
    }
    
    func dump() throws -> NSData {
        var d = [String: AnyObject]()
        d["_id"] = _id
        if _rev != "" {
            d["_rev"] = _rev
        }
        d["a_string"] = aString
        return try NSJSONSerialization.dataWithJSONObject(d as NSDictionary, options: [])
    }
}

class BRDocumentStoreTests: XCTestCase {
    var cli: ReplicationClient!
    var dbName: String!
    
    override func setUp() {
        dbName = "yyz" + NSUUID().UUIDString.lowercaseString
        cli = RemoteCouchDB(url: "http://localhost:5984/" + dbName)
        let exp = expectationWithDescription("db setup")
        cli.create().success(AsyncCallback<Bool> { didSucceed in
            XCTAssert(didSucceed)
            exp.fulfill()
            return didSucceed
        })
        waitForExpectationsWithTimeout(5, handler: nil)
        super.setUp()
    }
    
    override func tearDown() {
        cli = nil
        dbName = nil
        super.tearDown()
    }
    
    func testGet404() {
        let exp = expectationWithDescription("get 404")
        cli.get("hello404", options: nil, returning: TestDocument.self).success(AsyncCallback<TestDocument?> { d in
            XCTAssert(d == nil)
            exp.fulfill()
            return d
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testPutSuccess() {
        let exp = expectationWithDescription("put success")
        let doc = TestDocument(name: "helloPut", value: "a value")
        cli.put(doc, options: nil, returning: TestDocument.self).success(AsyncCallback<TestDocument> { d in
            XCTAssert(d._rev != "")
            exp.fulfill()
            return d
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testPutThenGet() {
        let exp = expectationWithDescription("put then get")
        let doc = TestDocument(name: "helloPut", value: "a value")
        cli.put(doc, options: nil, returning: TestDocument.self).success(AsyncCallback<TestDocument> { d in
            XCTAssert(d._rev != "")
            let rev = d._rev
            self.cli.get("helloPut", options: nil, returning: TestDocument.self).success(AsyncCallback<TestDocument?> { d in
                XCTAssert(d!._rev == rev)
                XCTAssert(d!.aString == "a value")
                exp.fulfill()
                return d
            })
            return d
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}

class BRDocumentStoreReplicationTests: XCTestCase {
    var cliA: ReplicationClient!
    var cliB: ReplicationClient!
    
    override func setUp() {
        cliA = RemoteCouchDB(url: "http://localhost:5984/" + "yyz" + NSUUID().UUIDString.lowercaseString)
        cliB = RemoteCouchDB(url: "http://localhost:5984/" + "aab" + NSUUID().UUIDString.lowercaseString)
        let expA = expectationWithDescription("dba")
        let expB = expectationWithDescription("dbb")
        cliA.create().success(AsyncCallback<Bool>(fn: { (didSucceed) -> Bool? in
            XCTAssert(didSucceed)
            expA.fulfill()
            return didSucceed
        }))
        cliB.create().success(AsyncCallback<Bool>(fn: { (didSucceed) -> Bool? in
            XCTAssert(didSucceed)
            expB.fulfill()
            return didSucceed
        }))
        waitForExpectationsWithTimeout(5, handler: nil)
        super.setUp()
    }
    
    override func tearDown() {
        cliA = nil
        cliB = nil
        super.tearDown()
    }
    
    func testVerifyPeersSuccess() {
        let exp = expectationWithDescription("verify exists state")
        let repl = Replicator(source: cliA, destination: cliB)
        let state = Replicator.ReplicationState()
        repl.verifyPeers.fn(state).success(AsyncCallback<Replicator.ReplicationState> { state in
            exp.fulfill()
            return state
        }).failure(AsyncCallback<AsyncError> { error in
            XCTFail()
            exp.fulfill()
            return error
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testPeersInformationSuccess() {
        let exp = expectationWithDescription("peers info")
        let repl = Replicator(source: cliA, destination: cliB)
        let state = Replicator.ReplicationState()
        repl.getPeersInformation.fn(state).success(AsyncCallback<Replicator.ReplicationState> { state in
            if state.sourceInfo == nil || state.destinationInfo == nil {
                XCTFail()
            }
            exp.fulfill()
            return state
        }).failure(AsyncCallback<AsyncError> { err in
            XCTFail()
            exp.fulfill()
            return err
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testGenerateReplicationId() {
        let exp = expectationWithDescription("gen repl id")
        let repl = Replicator(source: cliA, destination: cliB)
        let state = Replicator.ReplicationState()
        repl.generateReplicationId.fn(state).success(AsyncCallback<Replicator.ReplicationState> { state in
            if state.id == "" {
                XCTFail()
            }
            exp.fulfill()
            return state
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testFindCommonAncestryWithNoPreviousAnscestor() {
        let exp = expectationWithDescription("common ancestor")
        let repl = Replicator(source: cliA, destination: cliB)
        let state = Replicator.ReplicationState()
        repl.findCommonAncestry.fn(state).success(AsyncCallback<Replicator.ReplicationState> { state in
            XCTAssert(state.startLastSeq == -1)
            exp.fulfill()
            return state
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}
