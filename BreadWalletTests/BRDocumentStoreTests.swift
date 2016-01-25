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

class TestDocument: DefaultDocument {
    var aString: String = ""
    
    override func load(json: NSDictionary) {
        aString = (json["a_string"] as? String) ?? ""
    }
    
    override func dump(json: [String : AnyObject]) -> [String : AnyObject] {
        var d = json
        d["a_string"] = aString
        return d
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
    
    func getDoc() -> TestDocument {
        let doc = try! TestDocument(json: nil)
        doc._id = NSUUID().UUIDString
        doc.aString = "hello omg"
        return doc
    }
    
    func testPutSuccess() {
        let exp = expectationWithDescription("put success")
        cli.put(getDoc(), options: nil, returning: TestDocument.self).success(AsyncCallback<TestDocument> { d in
            XCTAssert(d._rev != "")
            exp.fulfill()
            return d
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testPutThenGet() {
        let exp = expectationWithDescription("put then get")
        let doc = getDoc()
        cli.put(doc, options: nil, returning: TestDocument.self).success(AsyncCallback<TestDocument> { d in
            XCTAssert(d._rev != "")
            let rev = d._rev
            self.cli.get(doc._id, options: nil, returning: TestDocument.self).success(AsyncCallback<TestDocument?> { d in
                XCTAssert(d!._rev == rev)
                XCTAssert(d!.aString == doc.aString)
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
        let uid = NSUUID().UUIDString.lowercaseString
        cliA = RemoteCouchDB(url: "http://localhost:5984/" + "clia" + uid)
        cliB = RemoteCouchDB(url: "http://localhost:5984/" + "clib" + uid)
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
    
    func testPrepareWithTwoEmptyDatabases() {
        let exp = expectationWithDescription("prepare empty")
        let repl = Replicator(source: cliA, destination: cliB)
        repl.prepare().success(AsyncCallback<Replicator.ReplicationState> { state in
            XCTAssert(state.startLastSeq == -1)
            exp.fulfill()
            return state
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func createDocs(numA: Int, numB: Int) -> AsyncResult<([TestDocument], [TestDocument])> {
        let res = AsyncResult<([TestDocument], [TestDocument])>()
        var aDocs = [TestDocument]()
        if numA > 0 {
            for i in 1...numA {
                let d = try! TestDocument(json: nil)
                d._id = NSUUID().UUIDString
                print("test doc \(cliA.id)/\(d._id)")
                d.aString = "document a/\(i)"
                aDocs.append(d)
            }
        }
        var bDocs = [TestDocument]()
        if numB > 0 {
            for i in 1...numB {
                let d = try! TestDocument(json: nil)
                d._id = NSUUID().UUIDString
                print("test doc \(cliB.id)/\(d._id)")
                d.aString = "document b/\(i)"
                bDocs.append(d)
            }
        }
        cliA.bulkDocs(aDocs, options: nil).success(AsyncCallback<[Bool]> { ads in
            self.cliB.bulkDocs(bDocs, options: nil).success(AsyncCallback<[Bool]> { bds in
                res.succeed((aDocs, bDocs))
                return bds
            })
            return ads
        })
        return res
    }
    
    func testReplicationWithTwoEmptyDatabases() {
        let exp = expectationWithDescription("full replicate empty")
        let repl = Replicator(source: cliA, destination: cliB)
        repl.start().success(AsyncCallback<Replicator.ReplicationState> { state in
            XCTAssert(state.missingChecked == 0)
            XCTAssert(state.missingFound == 0)
            XCTAssert(state.recordedSeq == 0)
            exp.fulfill()
            return state
        }).failure(AsyncCallback<AsyncError> { err in
            XCTFail(err.message)
            exp.fulfill()
            return err
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testReplicationOfSingleDoc() {
        let exp = expectationWithDescription("single doc replication test")
        let repl = Replicator(source: cliA, destination: cliB)
        createDocs(1, numB: 0).success(AsyncCallback<([TestDocument], [TestDocument])> { docs in
            repl.start().success(AsyncCallback<Replicator.ReplicationState> { state in
                self.cliB.get(docs.0[0]._id, options: nil, returning: TestDocument.self)
                    .success(AsyncCallback<TestDocument?> { testDoc in
                        XCTAssertNotNil(testDoc)
                        XCTAssertEqual(docs.0[0].aString, testDoc!.aString)
                        exp.fulfill()
                        return testDoc
                    })
                
                return state
            })
            return docs
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testReplicationOfMultipleDocs() {
        let exp = expectationWithDescription("multiple doc replication")
        let repl = Replicator(source: cliA, destination: cliB)
        createDocs(20, numB: 0).success(AsyncCallback<([TestDocument], [TestDocument])> { docs in
            repl.start().success(AsyncCallback<Replicator.ReplicationState> { state in
                let g = dispatch_group_create()
                
                for i in 0...19 {
                    dispatch_group_enter(g)
                    self.cliB.get(docs.0[i]._id, options: nil, returning: TestDocument.self)
                        .success(AsyncCallback<TestDocument?> { testDoc in
                            XCTAssertNotNil(testDoc)
                            XCTAssertEqual(docs.0[i].aString, testDoc!.aString)
                            dispatch_group_leave(g)
                            return testDoc
                        })
                }
                dispatch_group_notify(g, dispatch_get_main_queue()) {
                    exp.fulfill()
                }
                return state
            })
            return docs
        })
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}
