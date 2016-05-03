//
//  CouchDB.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation

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
        
        let req = NSMutableURLRequest(
            URL: NSURL(string: url + "/" + id + String.buildQueryString(options, includeQ: true))!)
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
        let req = NSMutableURLRequest(
            URL: NSURL(string: url + "/" + doc._id + String.buildQueryString(options, includeQ: true))!)
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
                    let errStr = NSString(data: data!, encoding: NSUTF8StringEncoding)
                    print("[RemoteCouchDB] put error resp: \(resp) msg=\(errStr)")
                    result.error(
                        resp.statusCode, message: NSHTTPURLResponse.localizedStringForStatusCode(resp.statusCode))
                }
            } else {
                result.error(-1001, message: "Error sending put \(err?.debugDescription)")
            }
        }.resume()
        
        return result
    }
    
    public func allDocs<T : Document>(options: [String: [String]]?) -> AsyncResult<[T]> {
        let result = AsyncResult<[T]>()
        return result
    }
    
    public func bulkDocs<T : Document>(docs: [T], options: [String: AnyObject]?) -> AsyncResult<[Bool]> {
        var docs = docs;
        let result = AsyncResult<[Bool]>()
        var mopts = options
        var docsJson: [String: AnyObject] = ["docs": docs.map() { (doc) -> [String: AnyObject] in return doc.dict() }]
        if let options = options {
            for (k, v) in options {
                docsJson[k] = v
            }
        }
        print("bulk docs json: " + (NSString(data: try! NSJSONSerialization.dataWithJSONObject(docsJson, options: []), encoding: NSUTF8StringEncoding)! as String))
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
                    print("hello " + (NSString(data: data, encoding: NSUTF8StringEncoding)! as String))
                    do {
                        let j = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        let doc = j as! [[String: AnyObject]]
                        var ret = [Bool]()
                        for (i, d) in doc.enumerate() {
                            if let ok = d["ok"] as? Bool {
                                ret.append(ok)
                            } else {
                                ret.append(false)
                            }
                            if let newRev = d["rev"] as? String {
                                docs[i]._rev = newRev
                            }
                        }
                        result.succeed(ret)
                    } catch let e {
                        print("[RemoteCouchDB] error loading bulk json \(e)", e)
                        result.error(-1001, message: "error loading _bulk_json \(e)")
                    }
                } else {
                    let errStr = NSString(data: data!, encoding: NSUTF8StringEncoding)
                    print("[RemoteCouchDB] bulk json response error \(resp) err: \(errStr)")
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
                if let data = data where resp.statusCode == 200 {
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
