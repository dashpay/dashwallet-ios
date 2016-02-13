//
//  BRWebSocketPlugin.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/13/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


// this just plugs into a Router and registers an asynchronous GET request for the given endpoint
@objc public class BRWebSocketPlugin: NSObject, BRHTTPRouterPlugin {
    var endpoint: String
    
    public init(endpoint: String) {
        self.endpoint = endpoint
        super.init()
    }
    
    public func hook(router: BRHTTPRouter) {
        router.get(self.endpoint) { (request, match) -> BRHTTPResponse in
            // initiate handshake
            let resp = BRHTTPResponse(async: request)
            let ws = BRWebSocket(request: request, response: resp)
            if !ws.handshake() {
                resp.provide(400, json: ["error": "invalid handshake"])
            } else {
                
            }
            return resp
        }
    }
}

let GID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
let (STREAM, TEXT, BINARY, CLOSE, PING, PONG) = (0x0, 0x1, 0x2, 0x8, 0x9, 0xA)
let (HEADERB1, HEADERB2, LENGTHSHORT, LENGTHLONG, MASK, PAYLOAD) = (1, 2, 4, 5, 6, 7)
let (MAXHEADER, MAXPAYLOAD) = (65536, 33554432)

class BRWebSocket {
    var request: BRHTTPRequest
    var response: BRHTTPResponse
    var fd: Int32
    var key: String!
    var version: String!
    
    init(request: BRHTTPRequest, response: BRHTTPResponse) {
        self.request = request
        self.fd = request.fd
        self.response = response
    }
    
    func handshake() -> Bool {
        if let upgrades = request.headers["upgrade"] where upgrades.count > 0 {
            let upgrade = upgrades[0]
            if upgrade.lowercaseString == "websocket" {
                if let ks = request.headers["sec-websocket-key"], vs = request.headers["sec-websocket-version"]
                where ks.count > 0 && vs.count > 0 {
                    key = ks[0]
                    version = vs[0]
                    do {
                        let acceptStr = "\(key)\(GID)" as NSString;
                        let acceptData = NSData(bytes: acceptStr.UTF8String,
                            length: acceptStr.lengthOfBytesUsingEncoding(NSUTF8StringEncoding));
                        let acceptEncodedStr = NSData(UInt160: acceptData.SHA1()).base64EncodedStringWithOptions([])
                        
                        try response.writeUTF8("HTTP/1.1 101 Switching Protocols\r\n")
                        try response.writeUTF8("Upgrade: WebSocket\r\n")
                        try response.writeUTF8("Connection: Upgrade\r\n")
                        try response.writeUTF8("Sec-WebSocket-Accept: \(acceptEncodedStr)\r\n\r\n")
                    } catch let e {
                        print("[BRWebSocket] error writing handshake: \(e)")
                        return false
                    }
                    return true
                }
            }
        }
        return false
    }
    
    func serviceClient() {
        
    }
}