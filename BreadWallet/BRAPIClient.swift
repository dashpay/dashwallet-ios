//
//  BRAPIClient.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 11/4/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import Foundation

extension String {
    func stringByAddingPercentEncodingForURLQueryValue() -> String? {
        let characterSet = NSMutableCharacterSet.alphanumericCharacterSet()
        characterSet.addCharactersInString("-._~")
        
        return stringByAddingPercentEncodingWithAllowedCharacters(characterSet)
    }
}

@objc class BRAPIClient: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {
    var session: NSURLSession!
    var queue: NSOperationQueue!
    var logEnabled = true
    var baseUrl = "https://api.breadwallet.com"
    
    override init() {
        super.init()
        queue = NSOperationQueue()
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        session = NSURLSession(configuration: config, delegate: self, delegateQueue: queue)
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
                let k = elem.0.stringByAddingPercentEncodingForURLQueryValue()
                let v = elem.1.stringByAddingPercentEncodingForURLQueryValue()
                return "\(k)=\(v)"
            }).joinWithSeparator("&"))
        } else {
            return joinPath(path)
        }
    }
    
    func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
        log("URLSession didBecomeInvalidWithError: \(error)")
    }
    
    func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        log("URLSession didReceiveChallenge \(challenge)")
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
