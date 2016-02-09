//
//  BRHTTPRouter.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


public typealias BRHTTPRouteMatch = [String: [String]]

public typealias BRHTTPRoute = (request: BRHTTPRequest, match: BRHTTPRouteMatch) throws -> BRHTTPResponse

@objc public protocol BRHTTPRouterPlugin {
    func hook(router: BRHTTPRouter)
}

@objc public class BRHTTPRoutePair: NSObject {
    public var method: String = "GET"
    public var path: String = "/"
    public var regex: NSRegularExpression!
    var captureGroups: [Int: String]!
    
    override public var hashValue: Int {
        return method.hashValue ^ path.hashValue
    }
    
    init(method m: String, path p: String) {
        method = m.uppercaseString
        path = p
        super.init()
        parse()
    }
    
    private func parse() {
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        if path.hasSuffix("/") {
            path = path.substringToIndex(path.endIndex.advancedBy(-1))
        }
        let parts = path.componentsSeparatedByString("/")
        captureGroups = [Int: String]()
        var reParts = [String]()
        var i = 0
        for part in parts {
            if part.hasPrefix("(") && part.hasSuffix(")") {
                let wcRange = Range(start: part.endIndex.advancedBy(-2), end: part.endIndex.advancedBy(-1))
                if part.substringWithRange(wcRange) == "*" { // a wild card capture (part*)
                    captureGroups[i] = part.substringWithRange(
                        Range(start: part.startIndex.advancedBy(1), end: part.endIndex.advancedBy((-2))))
                    reParts.append("(.*)")
                } else {
                    captureGroups[i] = part.substringWithRange(
                        Range(start: part.startIndex.advancedBy(1), end: part.endIndex.advancedBy(-1)))
                    reParts.append("([^/]+)") // a capture (part)
                }
                i++
            } else {
                reParts.append(part) // a non-captured component
            }
        }
        
        let re = "^" + reParts.joinWithSeparator("/") + "$"
        //print("\n\nroute: \n\n method: \(method)\n path: \(path)\n regex: \(re)\n captures: \(captureGroups)\n\n")
        regex = try! NSRegularExpression(pattern: re, options: [])
    }
    
    public func match(request: BRHTTPRequest) -> BRHTTPRouteMatch? {
        if request.method.uppercaseString != method {
            return nil
        }
        var p = request.path as NSString // strip trailing slash
        if p.hasSuffix("/") { p = request.path.substringToIndex(request.path.endIndex.advancedBy(-1)) }
        if let m = regex.firstMatchInString(request.path, options: [], range: NSMakeRange(0, p.length))
            where m.numberOfRanges - 1 == captureGroups.count {
                var match = BRHTTPRouteMatch()
                for i in 1..<m.numberOfRanges {
                    let key = captureGroups[i-1]!
                    let captured = p.substringWithRange(m.rangeAtIndex(i))
                    if match[key] == nil {
                        match[key] = [captured]
                    } else {
                        match[key]?.append(captured)
                    }
                    //print("capture range: '\(key)' = '\(captured)'\n\n")
                }
                return match
        }
        return nil
    }
}

@objc public class BRHTTPRouter: NSObject, BRHTTPMiddleware {
    var routes = [(BRHTTPRoutePair, BRHTTPRoute)]()
    var plugins = [BRHTTPRouterPlugin]()
    
    public func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        var response: BRHTTPResponse? = nil
        
        for (routePair, route) in routes {
            if let match = routePair.match(request) {
                do {
                    response = try route(request: request, match: match)
                } catch let e {
                    print("[BRHTTPRouter] route \(routePair.method) \(routePair.path) threw an exception \(e)")
                    response = BRHTTPResponse(request: request, code: 500)
                }
                break
            }
        }
        
        return next(BRHTTPMiddlewareResponse(request: request, response: response))
    }
    
    public func get(pattern: String, route: BRHTTPRoute) {
        routes.append((BRHTTPRoutePair(method: "GET", path: pattern), route))
    }
    
    public func post(pattern: String, route: BRHTTPRoute) {
        routes.append((BRHTTPRoutePair(method: "POST", path: pattern), route))
    }
    
    public func put(pattern: String, route: BRHTTPRoute) {
        routes.append((BRHTTPRoutePair(method: "PUT", path: pattern), route))
    }
    
    public func patch(pattern: String, route: BRHTTPRoute) {
        routes.append((BRHTTPRoutePair(method: "PATCH", path: pattern), route))
    }
    
    public func delete(pattern: String, route: BRHTTPRoute) {
        routes.append((BRHTTPRoutePair(method: "DELETE", path: pattern), route))
    }
    
    public func any(pattern: String, route: BRHTTPRoute) {
        for m in ["GET", "POST", "PUT", "PATCH", "DELETE"] {
            routes.append((BRHTTPRoutePair(method: m, path: pattern), route))
        }
    }
    
    public func plugin(plugin: BRHTTPRouterPlugin) {
        plugin.hook(self)
        plugins.append(plugin)
    }
}
