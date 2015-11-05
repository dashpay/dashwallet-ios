//
//  BRAPIClient.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 11/4/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import Foundation

extension String {
    static var urlQuoteCharacterSet: NSCharacterSet {
        let cset = NSMutableCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        cset.removeCharactersInString("?=&")
        return cset
    }
    
    func urlEscapedString() -> String {
        return self.stringByAddingPercentEncodingWithAllowedCharacters(
            String.urlQuoteCharacterSet)!
    }
}

@objc class BRAPIClient: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {
    var session: NSURLSession!
    var queue: NSOperationQueue!
    var logEnabled = true
    var host = "api.breadwallet.com"
    var baseUrl: String!
    
    // the singleton
    static let sharedClient = BRAPIClient()
    
    override init() {
        super.init()
        queue = NSOperationQueue()
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        session = NSURLSession(configuration: config, delegate: self, delegateQueue: queue)
        baseUrl = "https://\(host)"
    }
    
    func log(format: String, args: CVarArgType...) {
        if !logEnabled {
            return
        }
        let s = String(format: format, arguments: args)
        print("[BRAPIClient] \(s)")
    }
    
    // Constructs a full NSURL for a given path and url parameters
    func url(path: String, args: Dictionary<String, String>? =  nil) -> NSURL {
        func joinPath(k: String...) -> NSURL {
            return NSURL(string: ([baseUrl] + k).joinWithSeparator(""))!
        }
        
        if let args = args {
            return joinPath(path + "?" + args.map({ (elem) -> String in
                return "\(elem.0.urlEscapedString())=\(elem.1.urlEscapedString())"
            }).joinWithSeparator("&"))
        } else {
            return joinPath(path)
        }
    }
    
    func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
        log("URLSession didBecomeInvalidWithError: \(error)")
    }
    
    func URLSession(
        session: NSURLSession,
        didReceiveChallenge challenge: NSURLAuthenticationChallenge,
        completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
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
        let task = session.dataTaskWithRequest(req, completionHandler: { (data, resp, err) -> Void in
            let ds = String(data: data!, encoding: NSUTF8StringEncoding)
            self.log("GET /me: \(ds)")
        })
        task.resume()
    }
}
