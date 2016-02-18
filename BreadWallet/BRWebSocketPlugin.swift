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
let (STREAM, TEXT, BINARY, CLOSE, PING, PONG) = (UInt8(0x0), UInt8(0x1), UInt8(0x2), UInt8(0x8), UInt8(0x9), UInt8(0xA))
let (HEADERB1, HEADERB2, LENGTHSHORT, LENGTHLONG, MASK, PAYLOAD) = (1, 2, 4, 5, 6, 7)
let (MAXHEADER, MAXPAYLOAD) = (65536, 33554432)

class BRWebSocketHost {
    var sockets = [Int32: BRWebSocket]()
    
    func add(socket: BRWebSocket) {
        sockets[socket.fd] = socket
    }
    
    func serveForever() {
        while true {
            let req = bw_select_request(
                write_fd_len: 0,
                read_fd_len: Int32(sockets.count),
                write_fds: nil,
                read_fds: UnsafeMutablePointer(sockets.map({ (ws) -> Int32 in
                    return ws.0;
                })));
            let resp = bw_select(req)
            if resp.error > 0 {
                // uhh do something i guess
                print("[BRWebSocketHost] error doing a select");
                break
            }
            for i in 0..<resp.read_fd_len {
                if let readSock = sockets[resp.read_fds[Int(i)]] {
                    readSock.handleRead()
                }
            }
        }
    }
}

class BRWebSocket {
    var request: BRHTTPRequest
    var response: BRHTTPResponse
    var fd: Int32
    var key: String!
    var version: String!
    
    
    var state = HEADERB1
    var fin: UInt8 = 0
    var hasMask: Bool = false
    var opcode: UInt8 = 0
    var index: Int = 0
    var length: Int = 0
    var lengtharray: [UInt8]!
    var lengtharrayWritten: Int = 0
    var data: [UInt8]!
    var dataWritten: Int = 0
    var maskarray: [UInt8]!
    var maskarrayWritten: Int = 0
    
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
                    // enter non-blocking mode
                    if !setNonBlocking() {
                        return false
                    }
                    return true
                }
            }
        }
        return false
    }
    
    func setNonBlocking() -> Bool {
        let nbResult = bw_nbioify(request.fd)
        if nbResult < 0 {
            print("[BRWebSocket] unable to set socket to non blocking \(nbResult)")
            return false
        }
        return true
    }
    
    func handleRead() {
        var buf = [UInt8](count: 1, repeatedValue: 0)
        let n = recv(fd, &buf, 1, 0)
        if n <= 0 {
            return // failed read - figure out what to do here i guess
        }
        parseMessage(buf[0])
    }
    
    func parseMessage(byte: UInt8) {
        if state == HEADERB1 {
            fin = byte & UInt8(0x80)
            opcode = byte & UInt8(0x0F)
            state = HEADERB2
            index = 0
            length = 0
            let rsv = byte & 0x70
            if rsv != 0 {
                // fail out here probably
                print("[BRWebSocket] rsv bit is not zero! wat!")
                return
            }
        } else if state == HEADERB2 {
            let mask = byte & 0x80
            let length = byte & 0x7F
            if opcode == PING {
                print("[BRWebSocket] ping packet is too large! wat!")
                return
            }
            hasMask = mask == 128
            if length <= 125 {
                self.length = Int(length)
                if hasMask {
                    maskarray = [UInt8](count: 4, repeatedValue: 0)
                    maskarrayWritten = 0
                    state = MASK
                } else {
                    // there is no mask and no payload then we're done
                    if length <= 0 {
                        handlePacket()
                        data = nil
                        state = HEADERB1
                    } else {
                        // there is no mask and some payload
                        data = [UInt8](count: self.length, repeatedValue: 0)
                        dataWritten = 0
                        state = PAYLOAD
                    }
                }
            } else if length == 126 {
                lengtharray = [UInt8](count: 2, repeatedValue: 0)
                lengtharrayWritten = 0
                state = LENGTHSHORT
            } else if length == 127 {
                lengtharray = [UInt8](count: 8, repeatedValue: 0)
                lengtharrayWritten = 0
                state = LENGTHLONG
            }
        } else if state == LENGTHSHORT {
            lengtharrayWritten += 1
            if lengtharrayWritten > 2 {
                print("[BRWebSocket] short length exceeded allowable size! wat!")
                return
            }
            lengtharray[lengtharrayWritten - 1] = byte
            if lengtharrayWritten == 2 {
                var ll = UnsafePointer<UInt16>(lengtharray).memory
                if Int(OSHostByteOrder()) != OSBigEndian {
                    ll = CFSwapInt16BigToHost(ll)
                }
                length = Int(ll)
                if hasMask {
                    maskarray = [UInt8](count: 4, repeatedValue: 0)
                    maskarrayWritten = 0
                    state = MASK
                } else {
                    if length <= 0 {
                        handlePacket()
                        data = nil
                        state = HEADERB1
                    } else {
                        data = [UInt8](count: length, repeatedValue: 0)
                        dataWritten = 0
                        state = PAYLOAD
                    }
                }
            }
        } else if state == LENGTHLONG {
            lengtharrayWritten += 1
            if lengtharrayWritten > 8 {
                print("[BRWebSocket] long length exceeded allowable size! wat!")
                return
            }
            lengtharray[lengtharrayWritten - 1] = byte
            if lengtharrayWritten == 8 {
                var ll = UnsafePointer<UInt64>(lengtharray).memory
                if Int(OSHostByteOrder()) != OSBigEndian {
                    ll = CFSwapInt64BigToHost(ll)
                }
                length = Int(ll)
                if hasMask {
                    maskarray = [UInt8](count: 4, repeatedValue: 0)
                    maskarrayWritten = 0
                    state = MASK
                } else {
                    if length <= 0 {
                        handlePacket()
                        data = nil
                        state = HEADERB1
                    } else {
                        data = [UInt8](count: length, repeatedValue: 0)
                        dataWritten = 0
                        state = PAYLOAD
                    }
                }
            }
        } else if state == MASK {
            maskarrayWritten += 1
            if lengtharrayWritten > 4 {
                print("[BRWebSocket] mask exceeded allowable size! wat!")
                return
            }
            maskarray[maskarrayWritten - 1] = byte
            if maskarrayWritten == 4 {
                if length <= 0 {
                    handlePacket()
                    data = nil
                    state = HEADERB1
                } else {
                    data = [UInt8](count: length, repeatedValue: 0)
                    dataWritten = 0
                    state = PAYLOAD
                }
            }
        } else if state == PAYLOAD {
            dataWritten += 1
            if dataWritten >= MAXPAYLOAD {
                print("[BRWebSocket] payload exceed allowable size! wat!")
                return
            }
            if hasMask {
                data[dataWritten - 1] = byte ^ maskarray[index % 4]
            } else {
                data[dataWritten - 1] = byte
            }
            if index + 1 == length {
                handlePacket()
                data = nil
                state = HEADERB1
            } else {
                index += 1
            }
        }
    }
    
    func handlePacket() {
        // validate opcode
        if opcode == CLOSE || opcode == STREAM || opcode == TEXT || opcode == BINARY {
            // er
        } else if opcode == PONG || opcode == PING {
            if dataWritten >  125 {
                print("[BRWebSocket] control frame length can not be > 125")
                return
            }
        } else {
            print("[BRWebSocket] unknown opcode")
            return
        }
        
        
    }
}
