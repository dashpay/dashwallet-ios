//
//  Document.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright (c) 2016 breadwallet LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

enum DocumentLoadingError: ErrorType {
    case InvalidDocument
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
    var _deleted: Bool { get set }
}

public class DefaultDocument: Document {
    public var _id: String = ""
    public var _rev: String = ""
    public var _deleted: Bool = false
    public var _revisions: [RevisionDiff] = [RevisionDiff]()
    public var _doc: [String: AnyObject] = [String: AnyObject]()
    public var isMany: Bool = false
    public var manyCount: Int = -1
    private var _manyDocs: NSArray!
    
    public required init(json: AnyObject?) throws {
        if let json = json {
            if let doc = json as? NSDictionary {
                if let __id = doc["_id"] as? String {
                    _id = __id
                }
                if let __rev = doc["_rev"] as? String {
                    _rev = __rev
                }
                if let __revisions = doc["_revisions"] as? [String: [String: [String]]] {
                    for (id, r) in __revisions {
                        _revisions.append(RevisionDiff(
                            id: id, misssing: r["missing"] ?? [], possibleAncestors: r["possible_ancestors"] ?? []))
                    }
                    
                }
                _doc = doc as! [String: AnyObject]
                self.load(doc)
            } else if let docs = json as? NSArray {
                isMany = true
                let col = NSMutableArray(capacity: docs.count)
                for doc in docs {
                    var addDoc: NSDictionary? = nil
                    if let doc = doc as? NSDictionary {
                        if let docOk = doc["ok"] as? NSDictionary {
                            addDoc = docOk
                        } else {
                            addDoc = doc
                        }
                    }
                    if let addDoc = addDoc {
                        col.addObject(try self.dynamicType.init(json: addDoc))
                    }
                }
                manyCount = col.count
                _manyDocs = col
            } else {
                throw DocumentLoadingError.InvalidDocument
            }
        }
    }
    
    public func objectAtIndex(index: Int) -> AnyObject? {
        if isMany && index < _manyDocs.count {
            return _manyDocs.objectAtIndex(index)
        }
        return nil
    }
    
    public func dump() throws -> NSData {
        return try NSJSONSerialization.dataWithJSONObject(dict() as NSDictionary, options: [])
    }
    
    public func dict() -> [String : AnyObject] {
        var d = [String: AnyObject]()
        if _id != "" {
            d["_id"] = _id
        }
        if _rev != "" {
            d["_rev"] = _rev
        }
        return self.dump(d)
    }
    
    public func load(json: NSDictionary) {
        // override this in descendant structs
    }
    
    public func dump(json: [String: AnyObject]) -> [String: AnyObject] {
        var d = _doc
        for (k, v) in json { d[k] = v }
        if d["_revisions"] != nil {
            d.removeValueForKey("_revisions")
        }
        return d
    }
}

public struct RevisionDiff {
    let id: String
    let misssing: [String]
    let possibleAncestors: [String]
}
