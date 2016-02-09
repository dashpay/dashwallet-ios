//
//  BRHTTPFileMiddleware.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


@objc public class BRHTTPFileMiddleware: NSObject, BRHTTPMiddleware {
    var baseURL: NSURL!
    var debugURL: NSURL?
    
    init(baseURL: NSURL, debugURL: NSURL? = nil) {
        super.init()
        self.baseURL = baseURL
        self.debugURL = debugURL
    }
    
    public func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        var fileURL: NSURL!
        if debugURL == nil {
            let reqPath = request.path.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "/"))
            fileURL = baseURL.URLByAppendingPathComponent(reqPath)
        } else {
            var reqPath = request.path
            if (debugURL!.path!.hasSuffix("/")) {
                reqPath = reqPath.substringFromIndex(reqPath.startIndex.advancedBy(1))
            }
            fileURL = debugURL!.URLByAppendingPathComponent(reqPath)
        }
        
        guard let body = NSData(contentsOfURL: fileURL) else {
            return next(BRHTTPMiddlewareResponse(request: request, response: nil))
        }
        NSLog("GET \(fileURL)")
        NSLog("Detected content type: \(detectContentType(URL: fileURL))")
        
        do {
            let privReq = request as! BRHTTPRequestImpl
            let rangeHeader = try privReq.rangeHeader()
            if rangeHeader != nil {
                let (end, start) = rangeHeader!
                let length = end - start
                let range = NSRange(location: start, length: length + 1)
                guard range.location + range.length <= body.length else {
                    let r =  BRHTTPResponse(
                        request: request, statusCode: 418, statusReason: "Request Range Not Satisfiable",
                        headers: nil, body: nil)
                    return next(BRHTTPMiddlewareResponse(request: request, response: r))
                }
                let subDat = body.subdataWithRange(range)
                let headers = [
                    "Content-Range": ["bytes \(start)-\(end)/\(body.length)"],
                    "Content-Type": [detectContentType(URL: fileURL)]
                ]
                var ary = [UInt8](count: subDat.length, repeatedValue: 0)
                subDat.getBytes(&ary, length: subDat.length)
                let r =  BRHTTPResponse(
                    request: request, statusCode: 200, statusReason: "OK", headers: headers, body: ary)
                return next(BRHTTPMiddlewareResponse(request: request, response: r))
            }
        } catch {
            let r = BRHTTPResponse(
                request: request, statusCode: 400, statusReason: "Bad Request", headers: nil,
                body: [UInt8]("Invalid Range Header".utf8))
            return next(BRHTTPMiddlewareResponse(request: request, response: r))
        }
        
        var ary = [UInt8](count: body.length, repeatedValue: 0)
        body.getBytes(&ary, length: body.length)
        let r = BRHTTPResponse(request: request, statusCode: 200, statusReason: "OK",
            headers: ["Content-Type": [detectContentType(URL: fileURL)]], body: ary)
        return next(BRHTTPMiddlewareResponse(request: request, response: r))
    }
    
    private func detectContentType(URL url: NSURL) -> String {
        if let ext = url.pathExtension {
            switch ext {
            case "ttf":
                return "application/font-truetype"
            case "woff":
                return "application/font-woff"
            case "otf":
                return "application/font-opentype"
            case "svg":
                return "image/svg+xml"
            case "html":
                return "text/html"
            case "png":
                return "image/png"
            case "jpeg", "jpg":
                return "image/jpeg"
            case "css":
                return "text/css"
            case "js":
                return "application/javascript"
            case "json":
                return "application/json"
            default: break
            }
        }
        return "application/octet-stream"
    }
}
