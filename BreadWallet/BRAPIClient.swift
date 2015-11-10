//
//  BRAPIClient.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 11/4/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
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

let BRAPIClientErrorDomain = "BRApiClientErrorDomain"

public typealias URLSessionTaskHandler = (NSData?, NSHTTPURLResponse?, NSError?) -> Void
public typealias URLSessionChallengeHandler = (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void

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
            if lks.lowercaseString == lkKey {
                if let lvs = lv as? String {
                    return lvs
                }
            }
        }
    }
    return nil
}

func getAuthKey() -> BRKey? {
    if let manager = BRWalletManager.sharedInstance(), authKey = manager.authPrivateKey {
        return BRKey(privateKey: authKey)
    }
    return nil
}

func getDeviceId() -> String {
    let ud = NSUserDefaults.standardUserDefaults()
    if let s = ud.stringForKey("BR_DEVICE_ID") {
        return s
    }
    let s = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String
    ud.setValue(s, forKey: "BR_DEVICE_ID")
    print("new device id \(s)")
    return s
}

func isBreadChallenge(r: NSHTTPURLResponse) -> Bool {
    if let challenge = getHeaderValue("www-authenticate", d: r.allHeaderFields) {
        if challenge.lowercaseString.hasPrefix("bread") {
            return true
        }
    }
    return false
}

func buildURLResourceString(url: NSURL?) -> String {
    var urlStr = ""
    if let url = url, path = url.path {
        urlStr = "\(path)"
        if let query = url.query {
            if query.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
                urlStr = "\(url)?\(query)"
            }
        }
    }
    return urlStr
}

func buildRequestSigningString(r: NSMutableURLRequest) -> String {
    let headers = r.allHTTPHeaderFields ?? Dictionary<String, String>()
    var parts = [
        r.HTTPMethod,
        "",
        getHeaderValue("content-type", d: headers) ?? "",
        getHeaderValue("date", d: headers) ?? "",
        buildURLResourceString(r.URL)
    ]
    switch r.HTTPMethod {
    case "POST", "PUT", "PATCH":
        if let d = r.HTTPBody {
            let sha = d.SHA256()
            parts[1] = NSData(UInt256: sha).base58String()
        }
    default: break
    }
    return parts.joinWithSeparator("\n")
}

func buildResponseSigningString(req: NSMutableURLRequest, res: NSHTTPURLResponse, data: NSData? = nil) -> String {
    let parts: [String] = [
        req.HTTPMethod,
        "\(res.statusCode)",
        data != nil ? NSData(UInt256: data!.SHA256()).base58String() : "",
        getHeaderValue("content-type", d: res.allHeaderFields) ?? "",
        getHeaderValue("date", d: res.allHeaderFields) ?? "",
        buildURLResourceString(res.URL)
    ]
    
    return parts.joinWithSeparator("\n")
}

var rfc1123DateFormatter: NSDateFormatter {
    let fmt = NSDateFormatter()
    fmt.timeZone = NSTimeZone(abbreviation: "GMT")
    fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    fmt.locale = NSLocale(localeIdentifier: "en_US")
    return fmt
}

func httpDateNow() -> String {
    return rfc1123DateFormatter.stringFromDate(NSDate())
}

@objc public class BRAPIClient: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {
    var session: NSURLSession!
    var queue: NSOperationQueue!
    var logEnabled = true
    var proto = "http"
    var host = "localhost:8009"
    
    var baseUrl: String!
    
    var userAccountKey: String {
        return "\(proto)://\(host)"
    }
    
    var serverPubKey: BRKey {
        let encoded = "24jsCR3itNGbbmYbZnG6jW8gjguhqybCXsoUAgfqdjprz"
        return BRKey(publicKey: NSData(base58String: encoded))!
    }
    
    // the singleton
    static let sharedClient = BRAPIClient()
    
    override init() {
        super.init()
        queue = NSOperationQueue()
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        session = NSURLSession(configuration: config, delegate: self, delegateQueue: queue)
        baseUrl = "\(proto)://\(host)"
    }
    
    func log(format: String, args: CVarArgType...) -> Int? {
        if !logEnabled {
            return 1
        }
        let s = String(format: format, arguments: args)
        print("[BRAPIClient] \(s)")
        return 2
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
    
    func signRequest(request: NSURLRequest) -> NSURLRequest {
        let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
        let dateHeader = getHeaderValue("date", d: mutableRequest.allHTTPHeaderFields ?? Dictionary<String, String>())
        if dateHeader == nil {
            // add Date header if necessary
            mutableRequest.setValue(httpDateNow(), forHTTPHeaderField: "Date")
        }
        do {
            if let tokenData = try BRKeychain.loadDataForUserAccount(userAccountKey), token = tokenData["token"], authKey = getAuthKey() {
                let sha = buildRequestSigningString(mutableRequest).dataUsingEncoding(NSUTF8StringEncoding)!.SHA256_2()
                let sig = authKey.compactSign(sha)!.base58String()
                mutableRequest.setValue("bread \(token):\(sig)", forHTTPHeaderField: "Authorization")
            }
        } catch let e as BRKeychainError {
            log("keychain error fetching tokoen \(e)")
        } catch let e {
            log("unexpected error fetching keychain data \(e)")
        }
        return mutableRequest.copy() as! NSURLRequest
    }
    
    func verifyResponse(request: NSMutableURLRequest, response: NSHTTPURLResponse, data: NSData?) -> Bool {
        // ensure the signature header is present and in the correct format
        guard let sigHeader = getHeaderValue("signature", d: response.allHeaderFields),
            sigRange = sigHeader.rangeOfString("bread ")
            where sigHeader.startIndex.distanceTo(sigRange.startIndex) == 0 else { return false }
        
        // extract signing signature bytes and signing string
        let sigStr = sigHeader[sigRange.endIndex..<sigHeader.endIndex],
            sig = NSData(base58String: sigStr),
            signingString = buildResponseSigningString(request, res: response, data: data)
        
        // extract the public key and ensure it equals the one we have configured
        if let sha = signingString.dataUsingEncoding(NSUTF8StringEncoding)?.SHA256_2(),
            pk = BRKey(recoveredFromCompactSig: sig, andMessageDigest: sha),
            pkDatA = pk.publicKey, pkDatB = serverPubKey.publicKey
            where pkDatA.isEqualToData(pkDatB) {

            return true
        }
        return false
    }
    
    func dataTaskWithRequest(request: NSURLRequest, authenticated: Bool = false, verify: Bool = true, retryCount: Int = 0, handler: URLSessionTaskHandler) -> NSURLSessionDataTask {
        let start = NSDate()
        var logLine = ""
        if let meth = request.HTTPMethod, u = request.URL {
            logLine = "\(meth) \(u) auth=\(authenticated) retry=\(retryCount)"
        }
        let origRequest = request.mutableCopy() as! NSURLRequest
        var actualRequest = request
        if authenticated && getAuthKey() != nil {
            actualRequest = signRequest(request)
        }
        return session.dataTaskWithRequest(actualRequest) { (data, resp, err) -> Void in
            let end = NSDate()
            let dur = Int(end.timeIntervalSinceDate(start) * 1000)
            if let httpResp = resp as? NSHTTPURLResponse {
                var errStr = ""
                if httpResp.statusCode >= 400 {
                    if let data = data, s = NSString(data: data, encoding: NSUTF8StringEncoding) {
                        errStr = s as String
                    }
                }
                let verified = verify ? self.verifyResponse(actualRequest.mutableCopy() as! NSMutableURLRequest, response: httpResp, data: data) : true
                
                self.log("\(logLine) -> status=\(httpResp.statusCode) duration=\(dur)ms verified=\(verified) errStr=\(errStr)")
                
                if !verified {
                    return handler(nil, nil, NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("Unable to verify server identity", comment: "")]))
                }
                if authenticated && isBreadChallenge(httpResp) {
                    self.log("got authentication challenge from API - will attempt to get token")
                    self.getToken({ (err) -> Void in
                        if err != nil && retryCount < 1 { // retry once
                            self.log("error retrieving token: \(err) - will retry")
                            dispatch_after(1, dispatch_get_main_queue(), { () -> Void in
                                self.dataTaskWithRequest(origRequest, authenticated: authenticated, retryCount: retryCount + 1, handler: handler).resume()
                            })
                        } else if err != nil && retryCount > 0 { // fail if we already retried
                            self.log("error retrieving token: \(err) - will no longer retry")
                            handler(nil, nil, err)
                        } else if retryCount < 1 { // no error, so attempt the request again
                            self.log("retrieved token, so retrying the original request")
                            self.dataTaskWithRequest(origRequest, authenticated: authenticated, retryCount: retryCount + 1, handler: handler).resume()
                        } else {
                            self.log("retried token multiple times, will not retry again")
                            handler(data, httpResp, err)
                        }
                    })
                } else {
                    handler(data, httpResp, err)
                }
            } else {
                self.log("\(logLine) encountered connection error \(err)")
                handler(data, nil, err)
            }
        }
    }
    
    // retrieve a token and save it in the keychain data for this account
    func getToken(handler: (NSError?) -> Void) -> Void {
        if getAuthKey() == nil {
            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Wallet not ready", comment: "")]))
        }
        let req = NSMutableURLRequest(URL: url("/token"))
        req.HTTPMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let reqJson = [
            "pubKey": getAuthKey()!.publicKey!.base58String(),
            "deviceID": getDeviceId()
        ]
        do {
            let dat = try NSJSONSerialization.dataWithJSONObject(reqJson, options: .PrettyPrinted)
            req.HTTPBody = dat
        } catch (let e) {
            log("JSON Serialization error \(e)")
            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("JSON Serialization Error", comment: "")]))
        }
        let task = session.dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let httpResp = resp as? NSHTTPURLResponse {
                // unsuccessful response from the server
                if httpResp.statusCode != 200 {
                    if let data = data {
                        if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                            self.log("Token error: \(s)")
                        }
                    }
                    return handler(NSError(domain: BRAPIClientErrorDomain, code: httpResp.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("Unable to retrieve API token", comment: "")]))
                }
            }
            if let data = data {
                do {
                    let json = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments)
                    self.log("POST /token: \(json)")
                    if let topObj = json as? NSDictionary, tok = topObj["token"] as? NSString, uid = topObj["userID"] as? NSString {
                        // success! store it in the keychain
                        let kcData = ["token": tok, "userID": uid]
                        do {
                            try BRKeychain.saveData(kcData, forUserAccount: self.userAccountKey)
                        } catch let e {
                            self.log("Error saving token in keychain \(e)")
                            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                                NSLocalizedDescriptionKey: NSLocalizedString("Unable to save API token", comment: "")]))
                        }
                    }
                } catch let e {
                    self.log("JSON Deserialization error \(e)")
                }
            }
            handler(err)
        }
        task.resume()
    }
    
    // MARK: URLSession Delegate
    
    public func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
        log("URLSession didBecomeInvalidWithError: \(error)")
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge: NSURLAuthenticationChallenge, completionHandler: URLSessionChallengeHandler) {
            log("URLSession task \(task) didReceivechallenge \(didReceiveChallenge.protectionSpace)")
            
    }
    
    public func URLSession(session: NSURLSession, didReceiveChallenge: NSURLAuthenticationChallenge, completionHandler: URLSessionChallengeHandler) {
        log("URLSession didReceiveChallenge \(didReceiveChallenge)")
        // handle HTTPS authentication
        if didReceiveChallenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if didReceiveChallenge.protectionSpace.host == host && didReceiveChallenge.protectionSpace.serverTrust != nil {
                completionHandler(.UseCredential,
                    NSURLCredential(forTrust: didReceiveChallenge.protectionSpace.serverTrust!))
            } else {
                completionHandler(.RejectProtectionSpace, nil)
            }
        }
    }
    
    // MARK: API Functions
    
    // Fetches the /v1/fee-per-kb endpoint
    public func feePerKb(handler: (feePerKb: uint_fast64_t, error: String?) -> Void) {
        let req = NSURLRequest(URL: url("/v1/fee-per-kb"))
        let task = self.dataTaskWithRequest(req) { (data, response, err) -> Void in
            var feePerKb: uint_fast64_t = 0
            var errStr: String? = nil
            if err == nil {
                do {
                    let parsedObject: AnyObject? = try NSJSONSerialization.JSONObjectWithData(
                        data!, options: NSJSONReadingOptions.AllowFragments)
                    if let top = parsedObject as? NSDictionary, n = top["fee_per_kb"] as? NSNumber {
                        feePerKb = n.unsignedLongLongValue
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
    
    public func me() {
        let req = NSURLRequest(URL: url("/me"))
        let task = dataTaskWithRequest(req, authenticated: true) { (data, resp, err) -> Void in
            if let data = data {
                if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                    self.log("GET /me: \(s)")
                }
            }
        }
        task.resume()
    }
}

let BreadDefaultService = "org.voisine.breadwallet"

enum BRKeychainError: String, ErrorType {
    // this is borrowed from the "Locksmith" library: https://github.com/matthewpalmer/Locksmith
    case Allocate = "Failed to allocate memory."
    case AuthFailed = "Authorization/Authentication failed."
    case Decode = "Unable to decode the provided data."
    case Duplicate = "The item already exists."
    case InteractionNotAllowed = "Interaction with the Security Server is not allowed."
    case NoError = "No error."
    case NotAvailable = "No trust results are available."
    case NotFound = "The item cannot be found."
    case Param = "One or more parameters passed to the function were not valid."
    case RequestNotSet = "The request was not set"
    case TypeNotFound = "The type was not found"
    case UnableToClear = "Unable to clear the keychain"
    case Undefined = "An undefined error occurred"
    case Unimplemented = "Function or operation not implemented."
    
    init?(fromStatusCode code: Int) {
        switch code {
        case Int(errSecAllocate):
            self = Allocate
        case Int(errSecAuthFailed):
            self = AuthFailed
        case Int(errSecDecode):
            self = Decode
        case Int(errSecDuplicateItem):
            self = Duplicate
        case Int(errSecInteractionNotAllowed):
            self = InteractionNotAllowed
        case Int(errSecItemNotFound):
            self = NotFound
        case Int(errSecNotAvailable):
            self = NotAvailable
        case Int(errSecParam):
            self = Param
        case Int(errSecUnimplemented):
            self = Unimplemented
        default:
            return nil
        }
    }
}

class BRKeychain {
    // this API is inspired by the aforementioned Locksmith library
    static func loadDataForUserAccount(account: String, inService service: String = BreadDefaultService) throws -> [String: AnyObject]? {
        var q = getBaseQuery(account, service: service)
        q[String(kSecReturnData)] = kCFBooleanTrue
        q[String(kSecMatchLimit)] = kSecMatchLimitOne
        var res: AnyObject?
        let status: OSStatus = withUnsafeMutablePointer(&res) {
            SecItemCopyMatching(q, UnsafeMutablePointer($0))
        }
        if let err = BRKeychainError(fromStatusCode: Int(status)) {
            switch err {
            case .NotFound, .NotAvailable:
                return nil
            default:
                throw err
            }
        }
        if let res = res as? NSData {
            return NSKeyedUnarchiver.unarchiveObjectWithData(res) as? [String: AnyObject]
        }
        print("Unable to unarchive keychain data... deleting data")
        do {
            try deleteDataForUserAccount(account, inService: service)
        } catch let e as BRKeychainError {
            print("Unable to delete from keychain: \(e)")
        }
        return nil
    }
    
    static func saveData(data: [String: AnyObject], forUserAccount account: String, inService service: String = BreadDefaultService) throws {
        do {
            try deleteDataForUserAccount(account, inService: service)
        } catch let e as BRKeychainError {
            print("Unable to delete from keychain: \(e)")
        }
        var q = getBaseQuery(account, service: service)
        q[String(kSecValueData)] = NSKeyedArchiver.archivedDataWithRootObject(data)
        let status: OSStatus = SecItemAdd(q, nil)
        if let err = BRKeychainError(fromStatusCode: Int(status)) {
            throw err
        }
    }
    
    static func deleteDataForUserAccount(account: String, inService service: String = BreadDefaultService) throws {
        let q = getBaseQuery(account, service: service)
        let status: OSStatus = SecItemDelete(q)
        if let err = BRKeychainError(fromStatusCode: Int(status)) {
            throw err
        }
    }
    
    private static func getBaseQuery(account: String, service: String) -> [String: AnyObject] {
        let query = [
            String(kSecClass): String(kSecClassGenericPassword),
            String(kSecAttrAccount): account,
            String(kSecAttrService): service,
            String(kSecAttrAccessible): String(kSecAttrAccessibleAlwaysThisDeviceOnly)
        ]
        return query
    }
}
