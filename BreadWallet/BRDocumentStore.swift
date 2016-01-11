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
    
    func success(cb: AsyncCallback<T>) -> AsyncResult<T> {
        successCallbacks.append(cb)
        return self
    }
    
    func failure(cb: AsyncCallback<AsyncError>) -> AsyncResult<T> {
        failureCallbacks.append(cb)
        return self
    }
    
    func succeed(result: T) {
        guard !didCallback else {
            print("AsyncResult.succeed() error: callbacks already called. Result: \(result)")
            return
        }
        didCallback = true
        var prevResult = result
        for cb in successCallbacks {
            if let newResult = cb.fn(prevResult) {
                prevResult = newResult
            } else {
                break // returning nil terminates the callback chain
            }
        }
    }
    
    func error(code: Int, message: String) {
        guard !didCallback else {
            print("AsyncResult.error() error: callbacks already called. Error: \(code), \(message)")
            return
        }
        didCallback = true
        var prevResult = AsyncError(code: code, message: message)
        for cb in failureCallbacks {
            if let newResult = cb.fn(prevResult) {
                prevResult = newResult
            } else {
                break // returning nil terminates the callback chain
            }
        }
    }
}

public struct DatabaseInfo {
    
}

public struct RevisionInfo<T: Document> {
    
}

public protocol Document {
    
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
    func get<T>(id: String, options: [String: [String]]?) -> AsyncResult<T?>
    
    // put a document to the database
    func put<T: Document>(doc: T, options: [String: [String]]?) -> AsyncResult<Bool>
    
    // fetch all documents
    func allDocs<T: Document>(options: [String: [String]]?) -> AsyncResult<[T]>
    
    // update documents in bulk
    func bulkDocs<T: Document>(docs: [T], options: [String: [String]]?) -> AsyncResult<[Bool]>
    
    // compare document revisions
    func revsDiff<T: Document>(revs: [RevisionInfo<T>], options: [String: [String]]?) -> AsyncResult<[RevisionInfo<T>]>
    
    //func changes<T: Document>(options: [String: [String]]?) -> AsyncResult<
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
        return result
    }
    
    public func ensureFullCommit() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        return result
    }
    
    public func get<T>(id: String, options: [String : [String]]?) -> AsyncResult<T?> {
        let result = AsyncResult<T?>()
        return result
    }
    
    public func put<T : Document>(doc: T, options: [String : [String]]?) -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        return result
    }
    
    public func allDocs<T : Document>(options: [String : [String]]?) -> AsyncResult<[T]> {
        let result = AsyncResult<[T]>()
        return result
    }
    
    public func bulkDocs<T : Document>(docs: [T], options: [String : [String]]?) -> AsyncResult<[Bool]> {
        let result = AsyncResult<[Bool]>()
        return result
    }
    
    public func revsDiff<T : Document>(revs: [RevisionInfo<T>], options: [String : [String]]?) -> AsyncResult<[RevisionInfo<T>]> {
        let result = AsyncResult<[RevisionInfo<T>]>()
        return result
    }
}

