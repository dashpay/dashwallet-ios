//
//  BRAPIClient.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 11/4/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import Foundation

let BRAPIClientErrorDomain = "BRApiClientErrorDomain"

extension String {
    static var urlQuoteCharacterSet: NSCharacterSet {
        let cset = NSMutableCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        cset.removeCharactersInString("?=&")
        return cset
    }
    
    var urlEscapedString: String {
        return self.stringByAddingPercentEncodingWithAllowedCharacters(
            String.urlQuoteCharacterSet)!
    }
}

func getHeaderValue(k: String, d: Dictionary<NSObject, AnyObject>) -> String? {
    if let v = d[k] as? String { // short path: attempt to get the header directly
        return v
    }
    let lkKey = k.lowercaseString // long path: compare lowercase keys
    for (lk, lv) in d {
        if lk is String {
            let lks = lk as! String
            if lks == lkKey {
                if let lvs = lv as? String {
                    return lvs
                }
            }
        }
    }
    return nil
}

func getPublicKey() -> NSData? {
    let man = BRWalletManager.sharedInstance()
    return nil
}

func isBreadChallenge(r: NSHTTPURLResponse) -> Bool {
    if let challenge = getHeaderValue("www-authenticate", d: r.allHeaderFields) {
        if challenge.lowercaseString.hasPrefix("bread") {
            return true
        }
    }
    return false
}

@objc class BRAPIClient: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {
    var session: NSURLSession!
    var queue: NSOperationQueue!
    var logEnabled = true
    var proto = "http"
    var host = "localhost:8009"
    var baseUrl: String!
    
    // the singleton
    static let sharedClient = BRAPIClient()
    
    override init() {
        super.init()
        queue = NSOperationQueue()
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        session = NSURLSession(configuration: config, delegate: self, delegateQueue: queue)
        baseUrl = "\(proto)://\(host)"
    }
    
    func log(format: String, args: CVarArgType...) {
        if !logEnabled {
            return
        }
        let s = String(format: format, arguments: args)
        print("[BRAPIClient] \(s)")
    }
    
    // MARK: Networking functions
    
    // Constructs a full NSURL for a given path and url parameters
    func url(path: String, args: Dictionary<String, String>? =  nil) -> NSURL {
        func joinPath(k: String...) -> NSURL {
            return NSURL(string: ([baseUrl] + k).joinWithSeparator(""))!
        }
        
        if let args = args {
            return joinPath(path + "?" + args.map({ (elem) -> String in
                return "\(elem.0.urlEscapedString)=\(elem.1.urlEscapedString)"
            }).joinWithSeparator("&"))
        } else {
            return joinPath(path)
        }
    }
    
    func dataTaskWithRequest(
        request: NSURLRequest,
        handler: (NSData?, NSHTTPURLResponse?, NSError?) -> Void) -> NSURLSessionDataTask {
            return session.dataTaskWithRequest(request) { (data, resp, err) -> Void in
                if let httpResp = resp as? NSHTTPURLResponse {
                    if isBreadChallenge(httpResp) {
                        self.getToken({ (err) -> Void in
                            handler(data, httpResp, err)
                        })
                    } else {
                        handler(data, httpResp, err)
                    }
                }
            }
    }
    
    func getToken(handler: (NSError?) -> Void) -> Void {
        let req = NSMutableURLRequest(URL: url("/token"))
        req.HTTPMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let reqJson = [
            "pubKey": "",
            "deviceID": ""
        ]
        do {
            let dat = try NSJSONSerialization.dataWithJSONObject(reqJson, options: .PrettyPrinted)
            req.HTTPBody = dat
        } catch (let e) {
            log("JSON Serialization error \(e)")
        }
        let task = session.dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let httpResp = resp as? NSHTTPURLResponse {
                if httpResp.statusCode != 200 {
                    if let data = data {
                        if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                            self.log("Token error: \(s)")
                        }
                    }
                    return handler(NSError(
                        domain: BRAPIClientErrorDomain,
                        code: httpResp.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                            NSLocalizedString("Unable to retrieve API token", comment: "")]))
                }
            }
            if let data = data {
                do {
                    let json = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments)
                    self.log("POST /token: \(json)")
                } catch (let e) {
                    self.log("JSON Deserialization error \(e)")
                }
            }
            handler(err)
        }
        task.resume()
    }
    
    // MARK: URLSession Delegate
    
    func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
        log("URLSession didBecomeInvalidWithError: \(error)")
    }
    
    func URLSession(
        session: NSURLSession,
        task: NSURLSessionTask,
        didReceiveChallenge challenge: NSURLAuthenticationChallenge,
        completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
            log("URLSession task \(task) didReceivechallenge \(challenge.protectionSpace)")
            
    }
    
    func URLSession(
        session: NSURLSession,
        didReceiveChallenge challenge: NSURLAuthenticationChallenge,
        completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
            log("URLSession didReceiveChallenge \(challenge)")
            // handle HTTPS authentication
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if challenge.protectionSpace.host == host && challenge.protectionSpace.serverTrust != nil {
                    completionHandler(.UseCredential,
                        NSURLCredential(forTrust: challenge.protectionSpace.serverTrust!))
                } else {
                    completionHandler(.RejectProtectionSpace, nil)
                }
            }
    }
    
    // MARK: API Functions
    
    // Fetches the /v1/fee-per-kb endpoint
    func feePerKb(handler: (feePerKb: uint_fast64_t, error: String?) -> Void) {
        let req = NSURLRequest(URL: url("/v1/fee-per-kb"))
        let task = session.dataTaskWithRequest(req) { (data, response, err) -> Void in
            var feePerKb: uint_fast64_t = 0
            var errStr: String? = nil
            if err == nil {
                do {
                    let parsedObject: AnyObject? = try NSJSONSerialization.JSONObjectWithData(
                        data!, options: NSJSONReadingOptions.AllowFragments)
                    if let top = parsedObject as? NSDictionary {
                        if let n = top["fee_per_kb"] as? NSNumber {
                            feePerKb = n.unsignedLongLongValue
                        }
                    }
                } catch (let e) {
                    self.log("fee-per-kb: error parsing json \(e)")
                }
                if feePerKb == 0 {
                    errStr = "invalid json"
                }
            } else {
                self.log("fee-per-kb network error: \(err)")
                errStr = "bad network connection"
            }
            handler(feePerKb: feePerKb, error: errStr)
        }
        task.resume()
    }
    
    func me() {
        let req = NSURLRequest(URL: url("/me"))
        let task = dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let data = data {
                if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                    self.log("GET /me: \(s)")
                }
            }
        }
        task.resume()
    }
}
