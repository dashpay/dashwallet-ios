//
//  BRAPIProxy.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation

// Add this middleware to a BRHTTPServer to expose a proxy to the breadwallet HTTP api
// It has all the capabilities of the real API but with the ability to authenticate 
// requests using the users private keys stored on device.
//
// Clients should set the "X-Should-Verify" to enable response verification and can set
// "X-Should-Authenticate" to sign requests with the users private authentication key
@objc public class BRAPIProxy: NSObject, BRHTTPMiddleware {
    var mountPoint: String
    var apiInstance: BRAPIClient
    var shouldVerifyHeader: String = "x-should-verify"
    var shouldAuthHeader: String = "x-should-authenticate"
    
    var bannedSendHeaders: [String] {
        return [
            shouldVerifyHeader,
            shouldAuthHeader,
            "connection",
            "authorization"
        ]
    }
    
    var bannedReceiveHeaders: [String] = ["content-length", "connection"]
    
    init(mountAt: String, client: BRAPIClient) {
        mountPoint = mountAt
        if mountPoint.hasSuffix("/") {
            mountPoint = mountPoint.substringToIndex(mountPoint.endIndex.advancedBy(-1))
        }
        apiInstance = client
        super.init()
    }
    
    public func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        if request.path.hasPrefix(mountPoint) {
            var path = request.path.substringFromIndex(request.path.startIndex.advancedBy(mountPoint.characters.count))
            if request.queryString.utf8.count > 0 {
                path += "?\(request.queryString)"
            }
            let nsReq = NSMutableURLRequest(URL: apiInstance.url(path))
            nsReq.HTTPMethod = request.method
            // copy body
            if request.hasBody {
                nsReq.HTTPBody = request.body()
            }
            // copy headers
            for (hdrName, hdrs) in request.headers {
                if bannedSendHeaders.contains(hdrName) { continue }
                for hdr in hdrs {
                    nsReq.setValue(hdr, forHTTPHeaderField: hdrName)
                }
            }
            
            var verify = false, auth = false
            if let verifyHeader = request.headers[shouldVerifyHeader] where verifyHeader.count > 0 {
                if verifyHeader[0].lowercaseString == "yes" {
                    verify = true
                }
            }
            if let authHeader = request.headers[shouldAuthHeader] where authHeader.count > 0 {
                if authHeader[0].lowercaseString == "yes" {
                    auth = true
                }
            }
            apiInstance.dataTaskWithRequest(nsReq, authenticated: auth, verify: verify, retryCount: 0, handler:
                { (nsData, nsHttpResponse, nsError) -> Void in
                    if let httpResp = nsHttpResponse {
                        var hdrs = [String: [String]]()
                        for (k, v) in httpResp.allHeaderFields {
                            if self.bannedReceiveHeaders.contains((k as! String).lowercaseString) { continue }
                            hdrs[k as! String] = [v as! String]
                        }
                        var body: [UInt8]? = nil
                        if let bod = nsData {
                            let b = UnsafeBufferPointer<UInt8>(start: UnsafePointer(bod.bytes), count: bod.length)
                            body = Array(b)
                        }
                        let resp = BRHTTPResponse(
                            request: request, statusCode: httpResp.statusCode,
                            statusReason: NSHTTPURLResponse.localizedStringForStatusCode(httpResp.statusCode),
                            headers: hdrs, body: body)
                        return next(BRHTTPMiddlewareResponse(request: request, response: resp))
                    } else {
                        print("[BRAPIProxy] error getting response from backend: \(nsError)")
                        return next(BRHTTPMiddlewareResponse(request: request, response: nil))
                    }
            }).resume()
        } else {
            return next(BRHTTPMiddlewareResponse(request: request, response: nil))
        }
    }
}
