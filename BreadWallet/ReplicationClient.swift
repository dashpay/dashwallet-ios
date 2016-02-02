//
//  ReplicationClient.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


// A replication client is responsible for talking to a database (remote or local regardless) which can replicate
// its state to another database following the same protocol.
public protocol ReplicationClient {
    // the id of the database
    var id: String { get }
    
    // checks for database existence
    func exists() -> AsyncResult<Bool>
    
    // creates the database
    func create() -> AsyncResult<Bool>
    
    // retrieves info about the database
    func info() -> AsyncResult<DatabaseInfo>
    
    //
    func ensureFullCommit() -> AsyncResult<Bool>
    
    // retrieve a document from the database
    func get<T: Document>(id: String, options: [String: [String]]?, returning: T.Type) -> AsyncResult<T?>
    
    // put a document to the database
    func put<T: Document>(doc: T, options: [String: [String]]?, returning: T.Type) -> AsyncResult<T>
    
    // fetch all documents
    func allDocs<T: Document>(options: [String: [String]]?) -> AsyncResult<[T]>
    
    // update documents in bulk
    func bulkDocs<T: Document>(docs: [T], options: [String: AnyObject]?) -> AsyncResult<[Bool]>
    
    // compare document revisions
    func revsDiff(revs: [String: [String]], options: [String: [String]]?) -> AsyncResult<[RevisionDiff]>
    
    // fetch changes feed from the database
    func changes(options: [String: [String]]?) -> AsyncResult<Changes>
}

public struct DatabaseInfo: DocumentLoading {
    let dbName: String
    let docCount: Int
    let diskSize: Int
    let dataSize: Int
    let docDelCount: Int
    let purgeSeq: Int
    let updateSeq: Int
    let compactRunning: Bool
    let committedUpdateSeq: Int
    
    public init(json: AnyObject?) throws {
        let doc = json as! NSDictionary
        dbName = doc["db_name"] as! String
        docCount = (doc["doc_count"] as! NSNumber).integerValue
        diskSize = (doc["disk_size"] as! NSNumber).integerValue
        dataSize = (doc["data_size"] as! NSNumber).integerValue
        docDelCount = (doc["doc_del_count"] as! NSNumber).integerValue
        purgeSeq = (doc["purge_seq"] as! NSNumber).integerValue
        updateSeq = (doc["update_seq"] as! NSNumber).integerValue
        compactRunning = (doc["compact_running"] as! NSNumber).boolValue
        committedUpdateSeq = (doc["committed_update_seq"] as! NSNumber).integerValue
    }
    
    public func dump() throws -> NSData {
        return try NSJSONSerialization.dataWithJSONObject(dict() as NSDictionary, options: [])
    }
    
    public func dict() -> [String : AnyObject] {
        var d = [String: AnyObject]()
        d["db_name"] = dbName
        d["doc_count"] = NSNumber(integer: docCount)
        d["disk_size"] = NSNumber(integer: diskSize)
        d["data_size"] = NSNumber(integer: dataSize)
        d["doc_del_count"] = NSNumber(integer: docDelCount)
        d["purge_seq"] = NSNumber(integer: purgeSeq)
        d["update_seq"] = NSNumber(integer: updateSeq)
        d["compact_running"] = NSNumber(bool: compactRunning)
        d["committed_update_seq"] = NSNumber(integer: committedUpdateSeq)
        return d
    }
}

public struct DesignDocument: Document {
    public var _id: String
    public var _deleted = false
    public var _rev: String
    public var _revisions: [RevisionDiff] = [RevisionDiff]()
    
    // these fields are incomplete - they only implement what is currently needed internally
    let language: String? // "javascript" - usually
    let filters: [String: String]? // {"filter_name": "js_function"}
    
    public init(json: AnyObject?) throws {
        let doc = json as! NSDictionary
        _id = doc["_id"] as! String
        _rev = doc["_rev"] as! String
        language = doc["language"] as? String
        filters = doc["filters"] as? [String: String]
    }
    
    public func dict() -> [String : AnyObject] {
        var d = [String: AnyObject]()
        d["_id"] = _id
        d["_rev"] = _rev
        d["language"] = language
        d["filters"] = filters
        return d
    }
    
    public func dump() throws -> NSData {
        return try NSJSONSerialization.dataWithJSONObject(dict() as NSDictionary, options: [])
    }
}

public struct Change: DocumentLoading {
    let changes: [[String: String]]
    let id: String
    var deleted: Bool? = nil
    let seq: Int
    
    public init(json: AnyObject?) throws {
        let doc = json as! NSDictionary
        changes = doc["changes"] as! [[String: String]]
        id = doc["id"] as! String
        if let deld = doc["deleted"] as? Bool {
            deleted = deld
        }
        seq = (doc["seq"] as! NSNumber).integerValue
    }
    
    public func dict() -> [String : AnyObject] {
        return [String: AnyObject]()
    }
    
    public func dump() throws -> NSData {
        return NSData() // this is a fetch-only document
    }
}

public struct Changes: DocumentLoading {
    let lastSeq: Int
    let results: [Change]
    
    public init(json: AnyObject?) throws {
        let doc = json as! NSDictionary
        lastSeq = (doc["last_seq"] as! NSNumber).integerValue
        results = (doc["results"] as! [NSDictionary]).map({ (resD) -> Change in
            return try! Change(json: resD)
        })
    }
    
    public func dict() -> [String : AnyObject] {
        return [String: AnyObject]()
    }
    
    public func dump() throws -> NSData {
        return NSData() // this is a fetch-only document
    }
}