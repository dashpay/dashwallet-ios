//
//  BRDocumentStore.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/10/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation

public struct AsyncError {
    var code: Int
    var message: String
}

public struct AsyncCallback<T> {
    let fn: (T) -> T?
}

public class AsyncResult<T> {
    private var successCallbacks: [AsyncCallback<T>] = [AsyncCallback<T>]()
    private var failureCallbacks: [AsyncCallback<AsyncError>] = [AsyncCallback<AsyncError>]()
    private var didCallback: Bool = false
    
    private var successResult: T!
    private var errorResult: AsyncError!
    
    func success(cb: AsyncCallback<T>) -> AsyncResult<T> {
        objc_sync_enter(self)
        successCallbacks.append(cb)
        if didCallback { // immediately call the callback if a result was already produced
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                objc_sync_enter(self)
                self.successResult = cb.fn(self.successResult)
                objc_sync_exit(self)
            })
        }
        objc_sync_exit(self)
        return self
    }
    
    func failure(cb: AsyncCallback<AsyncError>) -> AsyncResult<T> {
        objc_sync_enter(self)
        failureCallbacks.append(cb)
        if didCallback {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                objc_sync_enter(self)
                self.errorResult = cb.fn(self.errorResult)
                objc_sync_exit(self)
            })
        }
        objc_sync_exit(self)
        return self
    }
    
    func succeed(result: T) {
        objc_sync_enter(self)
        guard !didCallback else {
            print("AsyncResult.succeed() error: callbacks already called. Result: \(result)")
            objc_sync_exit(self)
            return
        }
        didCallback = true
        objc_sync_exit(self)
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            objc_sync_enter(self)
            self.successResult = result
            for cb in self.successCallbacks {
                if let newResult = cb.fn(self.successResult) {
                    self.successResult = newResult
                } else {
                    break // returning nil terminates the callback chain
                }
            }
            objc_sync_exit(self)
        }
    }
    
    func error(code: Int, message: String) {
        objc_sync_enter(self)
        guard !didCallback else {
            print("AsyncResult.error() error: callbacks already called. Error: \(code), \(message)")
            objc_sync_exit(self)
            return
        }
        didCallback = true
        objc_sync_exit(self)
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            objc_sync_enter(self)
            self.errorResult = AsyncError(code: code, message: message)
            for cb in self.failureCallbacks {
                if let newResult = cb.fn(self.errorResult) {
                    self.errorResult = newResult
                } else {
                    break // returning nil terminates the callback chain
                }
            }
            objc_sync_exit(self)
        }
    }
}

public protocol DocumentLoading {
    init(json: AnyObject?) throws
    func dump() throws -> NSData
    func dict() -> [String: AnyObject]
}

public protocol Document: DocumentLoading {
    var _id: String { get set }
    var _rev: String { get set }
    var _revisions: [RevisionDiff] { get set }
}

public class DefaultDocument: Document {
    public var _id: String = ""
    public var _rev: String = ""
    public var _revisions: [RevisionDiff]
    public var _doc: [String: AnyObject]
    
    public required init(json: AnyObject?) throws {
        if let json = json {
            let doc = json as! NSDictionary
            if let __id = doc["_id"] as? String {
                _id = __id
            } else {
                _id = ""
            }
            if let __rev = doc["_rev"] as? String {
                _rev = __rev
            } else {
                _rev = ""
            }
            var __revs = [RevisionDiff]()
            if let __revisions = doc["_revisions"] as? [String: [String: [String]]] {
                for (id, r) in __revisions {
                    __revs.append(RevisionDiff(
                        id: id, misssing: r["missing"] ?? [], possibleAncestors: r["possible_ancestors"] ?? []))
                }
                
            }
            _doc = doc as! [String: AnyObject]
            _revisions = __revs
            self.load(doc)
        }
    }
    
    public func dump() throws -> NSData {
        return try NSJSONSerialization.dataWithJSONObject(dict() as NSDictionary, options: [])
    }
    
    public func dict() -> [String : AnyObject] {
        var d = [String: AnyObject]()
        if _id != "" {
            d["_id"] = _id
        }
        return self.dump(d)
    }
    
    public func load(json: NSDictionary) {
        // override this in descendant structs
    }
    
    public func dump(json: [String: AnyObject]) -> [String: AnyObject] {
        // override this in descendant structs
        return json
    }
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
        compactRunning = (doc["update_seq"] as! NSNumber).boolValue
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

public struct RevisionDiff {
    let id: String
    let misssing: [String]
    let possibleAncestors: [String]
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
    func bulkDocs<T: Document>(docs: [T], options: [String: [String]]?) -> AsyncResult<[Bool]>
    
    // compare document revisions
    func revsDiff(revs: [String: [String]], options: [String: [String]]?) -> AsyncResult<[RevisionDiff]>
    
    // fetch changes feed from the database
    func changes(options: [String: [String]]?) -> AsyncResult<Changes>
}

public class RemoteCouchDB: ReplicationClient {
    var url: String
    public var id: String {
        return url
    }
    
    init(url u: String) {
        url = u
    }
    
    public func exists() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        
        let req = NSMutableURLRequest(URL: NSURL(string: url)!)
        req.HTTPMethod = "HEAD"
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let resp = resp as? NSHTTPURLResponse {
                if resp.statusCode == 200 {
                    result.succeed(true)
                } else if resp.statusCode == 404 {
                    result.succeed(false)
                } else {
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                result.error(-1001, message: "\(err?.debugDescription)")
            }
        }.resume()
        
        return result
    }
    
    public func create() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        
        let req = NSMutableURLRequest(URL: NSURL(string: url)!)
        req.HTTPMethod = "PUT"
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let resp = resp as? NSHTTPURLResponse {
                if resp.statusCode == 201 {
                    result.succeed(true)
                } else {
                    let dat = NSString(data: data!, encoding: NSUTF8StringEncoding)
                    print("[RemoteCouchDB] create failure: \(resp) \(dat)")
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                result.error(-1001, message: "\(err?.debugDescription)")
            }
        }.resume()
        
        return result
    }
    
    public func info() -> AsyncResult<DatabaseInfo> {
        let result = AsyncResult<DatabaseInfo>()
        
        let req = NSURLRequest(URL: NSURL(string: url)!)
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let resp = resp as? NSHTTPURLResponse {
                if let data = data where resp.statusCode == 200 {
                    do {
                        let j = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        let i = try DatabaseInfo(json: j)
                        result.succeed(i)
                    } catch let e {
                        print("[RemoteCouchDB] error loading object: \(e)")
                        result.error(-1001, message: "Error loading remote response: \(e)")
                    }
                } else {
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                print("[RemoteCouchDB] error getting database info \(err?.debugDescription)")
                result.error(-1001, message: "Error loading database info")
            }
        }.resume()
        
        return result
    }
    
    public func ensureFullCommit() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        let req = NSMutableURLRequest(URL: NSURL(string: url + "/_ensure_full_commit")!)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.HTTPMethod = "POST"
        req.HTTPBody = NSData()
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, urlResp, urlErr) -> Void in
            if let resp = urlResp as? NSHTTPURLResponse {
                if let data = data where resp.statusCode == 201 {
                    do {
                        let j = (try NSJSONSerialization.JSONObjectWithData(data, options: [])) as! NSDictionary
                        let ok = j["ok"] as! Bool
                        result.succeed(ok)
                    } catch let e {
                        print("[RemoteCouchDB] error loading _ensure_full_commit response \(e)")
                        result.error(-1001, message: "Error loading _ensure_full_commit response \(e)")
                    }
                } else {
                    print("[RemoteCouchDB] _ensure_full_commit error \(resp)")
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                print("[RemoteCouchDB] error sending ensure full commit \(urlErr?.debugDescription)")
                result.error(-1001, message: "error sending full commit \(urlErr?.debugDescription)")
            }
        }.resume()
        return result
    }
    
    public func get<T: Document>(id: String, options: [String : [String]]?, returning: T.Type) -> AsyncResult<T?> {
        let result = AsyncResult<T?>()
        
        let req = NSMutableURLRequest(URL: NSURL(string: url + "/" + id + String.buildQueryString(options, includeQ: true))!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let resp = resp as? NSHTTPURLResponse {
                if let data = data where resp.statusCode == 200 {
                    do {
                        let j = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        let doc = try T(json: j)
                        result.succeed(doc)
                    } catch let e {
                        print("[RemoteCouchDB] error loading get json \(e)")
                        result.error(-1001, message: "Error loading document json: \(e)")
                    }
                } else if resp.statusCode == 404 {
                    result.succeed(nil)
                } else {
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                result.error(-1001, message: "Error running get request \(err?.debugDescription)")
            }
        }.resume()
        
        return result
    }
    
    public func put<T : Document>(doc: T, options: [String : [String]]?, returning: T.Type) -> AsyncResult<T> {
        let result = AsyncResult<T>()
        var docJson: NSData? = nil
        do {
            docJson = try doc.dump()
        } catch let e {
            print("[RemoteCouchDB] error dumping json")
            result.error(-1001, message: "JSON Dumping Error: \(e)")
            return result
        }
        
        let req = NSMutableURLRequest(URL: NSURL(string: url + "/" + doc._id + String.buildQueryString(options, includeQ: true))!)
        req.HTTPMethod = "PUT"
        req.HTTPBody = docJson
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let resp = resp as? NSHTTPURLResponse {
                if let data = data where resp.statusCode == 201 {
                    do {
                        let j = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        let rev = j["rev"] as! NSString
                        var d = doc
                        d._rev = rev as String
                        result.succeed(d)
                    } catch let e {
                        print("[RemoteCouchDB] error loading put response \(e)")
                        result.error(-1001, message: "Error loading put response \(e)")
                    }
                } else {
                    print("[RemoteCouchDB] put error resp: \(resp)")
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                result.error(-1001, message: "Error sending put \(err?.debugDescription)")
            }
        }.resume()
        
        return result
    }
    
    public func allDocs<T : Document>(options: [String : [String]]?) -> AsyncResult<[T]> {
        let result = AsyncResult<[T]>()
        return result
    }
    
    public func bulkDocs<T : Document>(docs: [T], options: [String : [String]]?) -> AsyncResult<[Bool]> {
        let result = AsyncResult<[Bool]>()
        var mopts = options
        let docsJson = docs.map() { (doc) -> [String: AnyObject] in return doc.dict() }
        let req = NSMutableURLRequest(URL: NSURL(string: url + "/_bulk_docs")!)
        req.HTTPMethod = "POST"
        req.HTTPBody = try? NSJSONSerialization.dataWithJSONObject(docsJson, options: [])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let o = options, oac = o["full_commit"] where oac.count > 0 {
            req.setValue(oac[0], forKey: "X-Couch-Full-Commit")
            mopts?.removeValueForKey("full_commit")
        }

        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, urlResp, urlErr) -> Void in
            if let resp = urlResp as? NSHTTPURLResponse {
                if let data = data where resp.statusCode == 201 {
                    do {
                        let j = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        let doc = j as! [[String: AnyObject]]
                        let br = doc.map({ (d) -> Bool in
                            if let ok = d["ok"] as? Bool {
                                return ok
                            }
                            return false
                        })
                        result.succeed(br)
                    } catch let e {
                        print("[RemoteCouchDB] error loading bulk json \(e)", e)
                        result.error(-1001, message: "error loading _bulk_json \(e)")
                    }
                } else {
                    print("[RemoteCouchDB] bulk json response error \(resp)")
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                print("[RemoteCouchDB] error sending bulk json \(urlErr?.debugDescription)")
                result.error(-1001, message: "error sending bulk json \(urlErr?.debugDescription)")
            }
        }.resume()
        return result
    }
    
    public func revsDiff(revs: [String: [String]], options: [String : [String]]?) -> AsyncResult<[RevisionDiff]> {
        let result = AsyncResult<[RevisionDiff]>()
        
        let req = NSMutableURLRequest(
            URL: NSURL(string: url + "/_revs_diff" + String.buildQueryString(options, includeQ: true))!)
        req.HTTPMethod = "POST"
        req.HTTPBody = try? NSJSONSerialization.dataWithJSONObject(revs, options: []) ?? NSData()
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let resp = resp as? NSHTTPURLResponse {
                if let data = data where resp.statusCode == 201 {
                    do {
                        let j = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        let doc = j as! [String: [String: [String]]]
                        var revs = [RevisionDiff]()
                        for (id, r) in doc {
                            revs.append(RevisionDiff(
                                id: id, misssing: r["missing"] ?? [], possibleAncestors: r["possible_ancestors"] ?? []))
                        }
                        result.succeed(revs)
                    } catch let e {
                        print("[RemoteCouchDB] error loading revs diff response \(e)")
                        result.error(-1001, message: "error loading _revs_diff response \(e)")
                    }
                } else {
                    print("[RemoteCouchDB] revs diff response error: \(resp)")
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                print("[RemoteCouchDB] error sending revs diff: \(err?.debugDescription)")
                result.error(-1001, message: "error sending revs diff")
            }
        }.resume()
        return result
    }
    
    public func changes(options: [String : [String]]?) -> AsyncResult<Changes> {
        let result = AsyncResult<Changes>()
        var req: NSURLRequest!
        
        // requesting changes for specific doc ids looks different (it's a POST with a specific "filter" value)
        if let options = options,
            docIds = options["doc_ids"],
            docIdJson = try? NSJSONSerialization.dataWithJSONObject(docIds, options: []) {
            var mutOpts = options
            mutOpts["filter"] = ["_doc_ids"]
            mutOpts.removeValueForKey("doc_ids")
            let mreq = NSMutableURLRequest(
                URL: NSURL(string: url + "/_changes" + String.buildQueryString(mutOpts, includeQ: true))!)
            mreq.HTTPMethod = "POST"
            mreq.HTTPBody = docIdJson
            mreq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            mreq.setValue("application/json", forKey: "Accept")
            req = mreq
        } else {
            req = NSURLRequest(
                URL: NSURL(string: url + "/_changes" + String.buildQueryString(options, includeQ: true))!)
        }
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let resp = resp as? NSHTTPURLResponse {
                if let data = data where resp.statusCode == 200 {
                    do {
                        let j = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        let doc = try Changes(json: j)
                        result.succeed(doc)
                    } catch let e {
                        print("[RemoteCouchDB] error loading _changes response: \(e)")
                        result.error(-1001, message: "error loading _changes response: \(e)")
                    }
                } else {
                    print("[RemoteCouchDB] _changes response error: \(resp)")
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                result.error(-1001, message: "Error sending _changes request: \(err?.debugDescription)")
            }
        }.resume()
        
        return result
    }
}

public struct ReplicationStep<T> {
    let fn: (T) -> AsyncResult<T>
}

public class Replicator {
    let source: ReplicationClient
    let destination: ReplicationClient
    public var running: Bool = false
    
    public struct ReplicationConfig {
        let id: String = NSUUID().UUIDString
        let batchSize: Int = 100
        let maxRequests: Int = 4
        let heartbeat: Int = 10 // sec
        let docIds: [String] = [String]()
        let queryParams: [String: [String]] = [String: [String]]()
        let filter: String? = nil
        let continuous: Bool = false
    }
    
    public struct ReplicationState {
        let config: ReplicationConfig = ReplicationConfig()
        
        var id: String = ""
        var idVersion: Int = 3
        
        let sessionId: String = NSUUID().UUIDString
        let startTime: NSDate = NSDate()
        var missingChecked: Int = 0
        var missingFound: Int = 0
        var docsRead: Int = 0
        var docsWritten: Int = 0
        var docsWriteFailures: Int = 0
        var startLastSeq: Int = -1 // -1 == no previous start
        var endLastSeq: Int = -1
        var recordedSeq: Int = -1
        
        var sourceInfo: DatabaseInfo? = nil
        var destinationInfo: DatabaseInfo? = nil
        
        var sourceReplicationLog: ReplicationLog? = nil
        var destinationReplicationLog: ReplicationLog? = nil
        
        var docs: [DefaultDocument] = [DefaultDocument]()
        var uploadedDocs: [DefaultDocument] = [DefaultDocument]()
        var changedDocs: [RevisionDiff] = [RevisionDiff]()
        
        func changedDoc(id: String) -> RevisionDiff? {
            for rd in changedDocs {
                if rd.id == id {
                    return rd
                }
            }
            return nil
        }
    }
    
    public class ReplicationItem: DefaultDocument {
        var sessionId: String!
        var startTime: String! // iso-8601 date
        var endTime: String! // iso-8601 date
        var missingChecked: Int!
        var missingFound: Int!
        var docsRead: Int!
        var docsWritten: Int!
        var docWriteFailures: Int!
        var startLastSeq: Int!
        var recordedSeq: Int!
        var endLastSeq: Int!
        
        public override func load(json: NSDictionary) {
            sessionId = json["session_id"] as! String
            startTime = json["start_time"] as! String
            endTime = json["end_time"] as! String
            missingChecked = (json["missing_checked"] as! NSNumber).integerValue
            missingFound = (json["missing_found"] as! NSNumber).integerValue
            docsRead = (json["docs_read"] as! NSNumber).integerValue
            docsWritten = (json["docs_written"] as! NSNumber).integerValue
            docWriteFailures = (json["doc_write_failures"] as! NSNumber).integerValue
            startLastSeq = (json["start_last_seq"] as! NSNumber).integerValue
            recordedSeq = (json["recorded_seq"] as! NSNumber).integerValue
            endLastSeq = (json["end_last_seq"] as! NSNumber).integerValue
        }
        
        public override func dict() -> [String: AnyObject] {
            var d = [String: AnyObject]()
            d["_id"] = _id
            d["_rev"] = _rev
            d["session_id"] = sessionId
            d["start_time"] = startTime
            d["end_time"] = endTime
            d["missing_checked"] = NSNumber(integer: missingChecked)
            d["missing_found"] = NSNumber(integer: missingFound)
            d["docs_read"] = NSNumber(integer: docsRead)
            d["docs_written"] = NSNumber(integer: docsWritten)
            d["doc_write_failures"] = NSNumber(integer: docWriteFailures)
            d["start_last_seq"] = NSNumber(integer: startLastSeq)
            d["recorded_seq"] = NSNumber(integer: recordedSeq)
            d["end_last_seq"] = NSNumber(integer: endLastSeq)
            return d
        }
        
        public override func dump(json: [String : AnyObject]) -> [String : AnyObject] {
            return dict()
        }
    }
    
    public class ReplicationLog: DefaultDocument {
        var sessionId: String!
        var replicationIdVersion: Int!
        var sourceLastSeq: Int!
        var history: [ReplicationItem]!
        
        public override func load(json: NSDictionary) {
            sessionId = json["session_id"] as! String
            replicationIdVersion = (json["replication_id_version"] as! NSNumber).integerValue
            sourceLastSeq = (json["source_last_seq"] as! NSNumber).integerValue
            history = (json["history"] as! [AnyObject]).map({ (historyJson) -> ReplicationItem in
                return try! ReplicationItem(json: historyJson)
            })
        }
        
        public override func dump(json: [String : AnyObject]) -> [String : AnyObject] {
            var d = json
            d["history"] = history.map({ (historyItem) -> NSDictionary in return historyItem.dict() })
            d["session_id"] = sessionId
            d["replication_id_version"] = replicationIdVersion
            d["source_last_seq"] = NSNumber(integer: sourceLastSeq)
            return d
        }
    }
    
    // Ensure that both source and destination databases exist via parallel .exists() requests
    public var verifyPeers: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                let dgroup = dispatch_group_create()
                var exists = ["source": false, "destination": false]
                
                dispatch_group_enter(dgroup); dispatch_group_enter(dgroup)
                
                dispatch_apply(2, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { (i) -> Void in
                    let c = i == 0 ? self.source : self.destination
                    let n = (i == 0 ? "source" : "destination")
                    c.exists().success(AsyncCallback<Bool> { doesExist in
                        if doesExist {
                            exists[n] = true
                        }
                        dispatch_group_leave(dgroup)
                        return doesExist
                    }).failure(AsyncCallback<AsyncError> { existsError in
                        dispatch_group_leave(dgroup)
                        return existsError
                    })
                })
                
                dispatch_group_notify(dgroup, dispatch_get_main_queue(), { () -> Void in
                    if exists["source"]! && exists["destination"]! {
                        result.succeed(replState)
                    } else {
                        result.error(404, message: "both source and destination must exist")
                    }
                })
            })

            return result
        }
    }
    
    // Loads the .info() results (DatabaseInfo object) into the ReplicationState for source and destination
    public var getPeersInformation: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                let dgroup = dispatch_group_create()
                dispatch_group_enter(dgroup); dispatch_group_enter(dgroup)
                dispatch_apply(2, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { (i) -> Void in
                    let c = i == 0 ? self.source : self.destination
                    c.info().success(AsyncCallback<DatabaseInfo> { dbInfo in
                        if i == 0 {
                            retReplState.sourceInfo = dbInfo
                        } else {
                            retReplState.destinationInfo = dbInfo
                        }
                        dispatch_group_leave(dgroup)
                        return dbInfo
                    }).failure(AsyncCallback<AsyncError> { infoFailure in
                        dispatch_group_leave(dgroup)
                        return infoFailure
                    })
                })
                dispatch_group_notify(dgroup, dispatch_get_main_queue(), { () -> Void in
                    if retReplState.sourceInfo == nil || retReplState.destinationInfo == nil {
                        result.error(-1001, message: "could not retrieve both source and destination info()")
                    } else {
                        result.succeed(retReplState)
                    }
                })
            })
            
            return result
        }
    }
    
    // Generate a unique identifier for this replication session
    public var generateReplicationId: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            var idParts = [replState.config.id, self.source.id, self.destination.id]
            
            // retrieves the javascript function body for a given filter name
            let getFilter = ReplicationStep<String?>(fn: { (filterSpec) -> AsyncResult<String?> in
                let result = AsyncResult<String?>()
                if let filterSpec = filterSpec {
                    let designDocNameParts = filterSpec.componentsSeparatedByString("/")
                    if designDocNameParts.count < 2 { // invalid filter spec
                        result.succeed(nil)
                        return result
                    }
                    let designDocName = designDocNameParts[0]
                    let filterName = designDocNameParts[1]
                    self.source.get("_design/" + designDocName, options: nil, returning: DesignDocument.self)
                        .success(AsyncCallback<DesignDocument?> { designDoc in
                            if let designDoc = designDoc, filters = designDoc.filters, filter = filters[filterName] {
                                result.succeed(filter)
                            } else {
                                result.succeed(nil)
                            }
                            
                            return designDoc
                        })
                        .failure(AsyncCallback<AsyncError> { designDocError in
                            // dont care about an error here
                            result.succeed(nil)
                            return designDocError
                        })
                } else {
                    result.succeed(nil)
                }
                
                return result
            })
            
            getFilter.fn(replState.config.filter).success(AsyncCallback<String?> { filterValue in
                if let filterValue = filterValue {
                    idParts.append(filterValue)
                }
                if replState.config.queryParams.count > 0 {
                    idParts.append(replState.config.queryParams.description)
                }
                if replState.config.docIds.count > 0 {
                    idParts.append(replState.config.docIds.description)
                }
                retReplState.id = idParts.joinWithSeparator("").MD5()
                result.succeed(retReplState)
                return filterValue
            })
            
            return result
        }
    }
    
    // Determines the startup checkpoint if the replication state is being reused
    public var findCommonAncestry: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
                let dgroup = dispatch_group_create()
                var docs: [String: ReplicationLog?] = ["source": nil, "destination": nil]
                dispatch_group_enter(dgroup); dispatch_group_enter(dgroup)
                
                // fetch replication logs
                dispatch_apply(2, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { i in
                    let c = i == 0 ? self.source : self.destination
                    let n = i == 0 ? "source" : "destination"
                    c.get("_local/" + replState.id, options: nil, returning: ReplicationLog.self)
                        .success(AsyncCallback<ReplicationLog?> { log in
                            docs[n] = log // it's ok for this to be nil
                            dispatch_group_leave(dgroup)
                            return log
                        })
                        .failure(AsyncCallback<AsyncError> { logErr in
                            dispatch_group_leave(dgroup)
                            return logErr
                        })
                }
                
                dispatch_group_notify(dgroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
                    retReplState.destinationReplicationLog = docs["destination"]!
                    retReplState.sourceReplicationLog = docs["source"]!
                    guard let destLog = retReplState.destinationReplicationLog,
                        sourceLog = retReplState.sourceReplicationLog else {
                        // there is no common history - force full replication
                        result.succeed(retReplState)
                        return
                    }
                    // we are already at the most recent seq
                    if destLog.sessionId == sourceLog.sessionId {
                        retReplState.startLastSeq = sourceLog.sourceLastSeq
                        result.succeed(retReplState)
                        return
                    }
                    // find the most recent common seq
                    let histories = sourceLog.history.filter({ (histItem) -> Bool in
                        let destHistories = destLog.history.filter({ (destHistItem) -> Bool in
                            return destHistItem.sessionId == histItem.sessionId
                        })
                        return destHistories.count > 0
                    })
                    guard histories.count > 0 else { // there is no common history - force full replication
                        result.succeed(retReplState)
                        return
                    }
                    retReplState.startLastSeq = histories[0].recordedSeq
                    result.succeed(retReplState)
                }
            }
            
            return result
        }
    }
    
    public var locateChangedDocs: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            // get the options object together
            var changeOptions: [String: [String]] = [
                "style": ["all_docs"],
                "limit": [String(replState.config.batchSize)]
            ]
            if replState.startLastSeq != -1 { changeOptions["since"] = [String(replState.startLastSeq)] }
            if replState.endLastSeq != -1 { changeOptions["since"] = [String(replState.endLastSeq)] }
            if replState.config.continuous {
                changeOptions["feed"] = ["continuous"]
                changeOptions["heartbeat"] = [String(replState.config.heartbeat)]
            }
            if let f = replState.config.filter { changeOptions["filter"] = [f] }
            if replState.config.queryParams.count > 0 {
                changeOptions["query_params"] = [String(replState.config.queryParams)]
            }
            if replState.config.docIds.count > 0 {
                changeOptions["doc_ids"] = replState.config.docIds
            }
            
            // fetch changes from source database
            self.source.changes(changeOptions).success(AsyncCallback<Changes> { changes in
                retReplState.endLastSeq = changes.lastSeq
                
                guard changes.results.count > 0 else {
                    result.succeed(retReplState)
                    return changes
                }
                // amount of checked revisions on source
                retReplState.missingChecked = changes.results.reduce(0, combine: { (i, chng) -> Int in
                    return i + chng.changes.count
                })
                
                var revs = [String: [String]]()
                for chng in changes.results {
                    revs[chng.id] = chng.changes.map({ (changeBit) -> String in
                        return changeBit["rev"]!
                    })
                }
                // find revisions the source is missing
                self.destination.revsDiff(revs, options: nil).success(AsyncCallback<[RevisionDiff]> { diffs in
                    retReplState.changedDocs = diffs
                    // amount of missing revisions on source
                    retReplState.missingFound = diffs.reduce(0, combine: { (i, d) -> Int in
                        return i + d.misssing.count
                    })
                    result.succeed(retReplState)
                    return diffs
                }).failure(AsyncCallback<AsyncError> { revsError in
                    result.error(revsError.code, message: revsError.message)
                    return revsError
                })
                
                return changes
            }).failure(AsyncCallback<AsyncError> { changeError in
                result.error(changeError.code, message: changeError.message)
                return changeError
            })
            
            return result
        }
    }
    
    public var fetchChangedDocs: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            retReplState.docs = [DefaultDocument]()
            guard retReplState.changedDocs.count < 1 else {
                result.succeed(retReplState) // nothing to do if there are no changed docs
                return result
            }
            let missingIds = retReplState.changedDocs.map({ (rev) -> String in
                return rev.id
            })
            guard missingIds.count < 1 else {
                result.succeed(retReplState) // nothing to do if there are no missing ids
                return result
            }
            
            func fetch(id: String) -> AsyncResult<DefaultDocument?> {
                let omissing = replState.changedDoc(id)?.misssing ?? []
                let orevsj = try! NSJSONSerialization.dataWithJSONObject(omissing, options: [])
                let orevs = NSString(data: orevsj, encoding: NSUTF8StringEncoding) as! String
                let opts = ["revs": ["true"], "attachments": ["true"], "latest": ["true"], "open_revs": [orevs]]
                return self.source.get(id, options: opts, returning: DefaultDocument.self)
            }
            
            func fetchSingleDocuments(ids: [String]) -> AsyncResult<[DefaultDocument]> {
                let docsResult = AsyncResult<[DefaultDocument]>()
                var docs = [DefaultDocument]()
                
                let fetchOpQ = NSOperationQueue()
                fetchOpQ.maxConcurrentOperationCount = retReplState.config.maxRequests
                let grp = dispatch_group_create()
                
                for did in ids {
                    dispatch_group_enter(grp)
                    fetchOpQ.addOperationWithBlock() {
                        fetch(did).success(AsyncCallback<DefaultDocument?> { doc in
                            if let doc = doc {
                                objc_sync_enter(docs)
                                docs.append(doc)
                                objc_sync_exit(docs)
                            }
                            dispatch_group_leave(grp)
                            return doc
                        }).failure(AsyncCallback<AsyncError> { docErr in
                            // uhhh... try to figure out what to do here
                            print("[Replicator] fetchChangedDocs - individual doc fetch error \(docErr)")
                            dispatch_group_leave(grp)
                            return docErr
                        })
                    }
                }
                
                dispatch_group_notify(grp, dispatch_get_main_queue()) {
                    docsResult.succeed(docs)
                }
                
                return docsResult
            }
            
            // TODO: optimization for first generation documents - fetch from bulkDocs
            
            fetchSingleDocuments(missingIds).success(AsyncCallback<[DefaultDocument]> { docs in
                retReplState.docs = docs
                retReplState.docsRead += docs.count
                result.succeed(retReplState)
                return docs
            }).failure(AsyncCallback<AsyncError> { docsErr in
                result.error(docsErr.code, message: docsErr.message)
                return docsErr
            })
            
            return result
        }
    }
    
    public var uploadDocuments: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            guard replState.docs.count > 0 else {
                result.succeed(replState)
                return result
            }
            
            self.destination.bulkDocs(replState.docs, options: ["new_edits": ["true"]])
                .success(AsyncCallback<[Bool]> { bulkResults in
                    var retReplState = replState
                    // TODO: update doc write failures
                    retReplState.docsWritten += bulkResults.count
                    retReplState.uploadedDocs = retReplState.docs
                    result.succeed(retReplState)
                    return bulkResults
                }).failure(AsyncCallback<AsyncError> { bulkErr in
                    result.error(bulkErr.code, message: bulkErr.message)
                    return bulkErr
                })
            
            return result
        }
    }
    
    public var ensureFullCommit: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            self.destination.ensureFullCommit().success(AsyncCallback<Bool> { ok in
                if ok {
                    result.succeed(replState)
                } else {
                    result.error(-1001, message: "database did not report an ok result for full commit")
                }
            }).failure(AsyncCallback<AsyncError> { okErr in
                result.error(okErr.code, message: okErr.message)
                return okErr
            })
            return result
        }
    }
    
    public var recordReplicationCheckpoint: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            let newReplItem = try! ReplicationItem(json: nil)
            newReplItem.sessionId = replState.sessionId
            newReplItem.startTime = replState.startTime.description
            newReplItem.endTime = NSDate().description
            newReplItem.missingChecked = replState.missingChecked
            newReplItem.missingFound = replState.missingFound
            newReplItem.docsRead = replState.docsRead
            newReplItem.docsWritten = replState.docsWritten
            newReplItem.docWriteFailures = replState.docsWriteFailures
            newReplItem.startLastSeq = replState.startLastSeq
            newReplItem.recordedSeq = replState.endLastSeq
            newReplItem.endLastSeq = replState.endLastSeq
            
            if retReplState.sourceReplicationLog == nil {
                retReplState.sourceReplicationLog = try! ReplicationLog(json: nil)
            }
            if retReplState.destinationReplicationLog == nil {
                retReplState.destinationReplicationLog = try! ReplicationLog(json: nil)
            }
            
            func saveReplDoc(db: ReplicationClient, d: ReplicationLog) -> AsyncResult<ReplicationLog> {
                d._id = "_local/" + replState.id
                d.replicationIdVersion = replState.idVersion
                d.sessionId = newReplItem.sessionId
                d.sourceLastSeq = newReplItem.recordedSeq
                d.history.insert(newReplItem, atIndex: 0)
                return db.put(d, options: nil, returning: ReplicationLog.self)
            }
            
            let dgrp = dispatch_group_create()
            let saves = [
                (self.source, retReplState.sourceReplicationLog!, "source"),
                (self.destination, retReplState.destinationReplicationLog!, "dest")
            ]
            
            for (db, d, loc) in saves {
                dispatch_group_enter(dgrp)
                saveReplDoc(db, d: d)
                    .success(AsyncCallback<ReplicationLog> { replLog in
                        dispatch_group_leave(dgrp)
                        if loc == "source" {
                            retReplState.sourceReplicationLog!._rev = replLog._rev
                        } else {
                            retReplState.destinationReplicationLog!._rev = replLog._rev
                        }
                        return replLog
                    })
                    .failure(AsyncCallback<AsyncError> { replErr in
                        dispatch_group_leave(dgrp)
                        return replErr
                    })
            }
            
            dispatch_group_notify(dgrp, dispatch_get_main_queue()) {
                retReplState.recordedSeq = retReplState.endLastSeq
                result.succeed(retReplState)
            }
            
            return result
        }
    }
    
    
    public init(source s: ReplicationClient, destination d: ReplicationClient) {
        source = s
        destination = d
    }
    
    public func performSteps<T>(arg: T, steps: [ReplicationStep<T>]) -> AsyncResult<T> {
        let result = AsyncResult<T>()
        
        var steps = Array(steps.reverse())
        var prevResult: T = arg
        func doStep() {
            if let step = steps.popLast() {
                step.fn(prevResult).success(AsyncCallback<T> { newResult in
                    prevResult = newResult
                    dispatch_async(dispatch_get_main_queue()) {
                        doStep()
                    }
                    return newResult
                }).failure(AsyncCallback<AsyncError> { newError in
                    // send error directly without calling doStep() again
                    result.error(newError.code, message: newError.message)
                    return newError
                })
            } else {
                result.succeed(prevResult)
            }
        }
        doStep()
        
        return result
    }
    
    public func prepare() -> AsyncResult<ReplicationState> {
        let replState = ReplicationState()
        let steps = [
            verifyPeers,
            getPeersInformation,
            generateReplicationId,
            findCommonAncestry
        ]
        return performSteps(replState, steps: steps)
    }
    
    public func replicate(state: ReplicationState) -> AsyncResult<ReplicationState> {
        let steps = [
            locateChangedDocs,
            fetchChangedDocs,
            uploadDocuments,
            ensureFullCommit,
            recordReplicationCheckpoint
        ]
        var replicatedOnce = false
        var lastMissingChecked = state.missingChecked
        let ret = performSteps(state, steps: steps).success(AsyncCallback<ReplicationState> { replState in
            if replicatedOnce && replState.missingChecked < 1 {
                // no changes
                return replState
            }
            if replicatedOnce && lastMissingChecked == replState.missingChecked {
                // something else happend... but whaat?
                return replState
            }
            replicatedOnce = true
            lastMissingChecked = replState.missingChecked
            self.replicate(state)
            return replState
        })
        return ret
    }
    
    public func start() {
        
    }
}

extension String {
    func MD5() -> String {
        let data = (self as NSString).dataUsingEncoding(NSUTF8StringEncoding)!
        let result = NSMutableData(length: Int(CC_MD5_DIGEST_LENGTH))!
        let resultBytes = UnsafeMutablePointer<CUnsignedChar>(result.mutableBytes)
        CC_MD5(data.bytes, CC_LONG(data.length), resultBytes)
        
        let a = UnsafeBufferPointer<CUnsignedChar>(start: resultBytes, count: result.length)
        let hash = NSMutableString()
        
        for i in a {
            hash.appendFormat("%02x", i)
        }
        
        return hash as String
    }
    
    static func buildQueryString(options: [String: [String]]?, includeQ: Bool = false) -> String {
        var s = ""
        if let options = options where options.count > 0 {
            s = includeQ ? "?" : ""
            var i = 0
            for (k, vals) in options {
                for v in vals {
                    if i != 0 {
                        s += "&"
                    }
                    i++
                    s += "\(k.urlEscapedString)=\(v.urlEscapedString)"
                }
            }
        }
        return s
    }
}
