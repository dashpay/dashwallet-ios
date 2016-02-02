//
//  Document.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

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
