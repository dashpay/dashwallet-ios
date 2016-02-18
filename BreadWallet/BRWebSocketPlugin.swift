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
    var host: BRWebSocketHost
    var thread: pthread_t
    
    public init(endpoint: String) {
        self.endpoint = endpoint
        host = BRWebSocketHost()
        thread = nil
        super.init()
    }
    
    public func hook(router: BRHTTPRouter) {
        // start the server
        log("hook")
        let selfPointer = UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque())
        pthread_create(&thread, nil, { (sillySelf: UnsafeMutablePointer<Void>) in
            let localSelf = Unmanaged<BRWebSocketPlugin>.fromOpaque(COpaquePointer(sillySelf)).takeUnretainedValue()
            localSelf.log("in server thread")
            localSelf.host.serveForever()
            return nil
        }, selfPointer)
        
        router.get(self.endpoint) { (request, match) -> BRHTTPResponse in
            // initiate handshake
            let resp = BRHTTPResponse(async: request)
            let ws = BRWebSocket(request: request, response: resp)
            if !ws.handshake() {
                self.log("invalid handshake")
                resp.provide(400, json: ["error": "invalid handshake"])
            } else {
                self.host.add(ws)
            }
            return resp
        }
    }
    
    func log(s: String) {
        print("[BRWebSocketPlugin] \(s)")
    }
}

let GID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

enum SocketState {
    case HEADERB1
    case HEADERB2
    case LENGTHSHORT
    case LENGTHLONG
    case MASK
    case PAYLOAD
}

enum SocketOpcode: UInt8 {
    case STREAM = 0x0
    case TEXT = 0x1
    case BINARY = 0x2
    case CLOSE = 0x8
    case PING = 0x9
    case PONG = 0xA
}

let (MAXHEADER, MAXPAYLOAD) = (65536, 33554432)

class BRWebSocketHost {
    var sockets = [Int32: BRWebSocket]()
    var waiter: UnsafeMutablePointer<pthread_cond_t>
    var mutex: UnsafeMutablePointer<pthread_mutex_t>
    
    init() {
        mutex = UnsafeMutablePointer.alloc(sizeof(pthread_mutex_t))
        waiter = UnsafeMutablePointer.alloc(sizeof(pthread_cond_t))
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(waiter, nil)
    }
    
    func add(socket: BRWebSocket) {
        log("adding socket \(socket.fd)")
        pthread_mutex_lock(mutex)
        sockets[socket.fd] = socket
        pthread_cond_signal(waiter)
        pthread_mutex_unlock(mutex)
    }
    
    func serveForever() {
        log("starting websocket poller")
        while true {
            log("awaiting clients")
            while sockets.count < 1 {
                pthread_cond_wait(waiter, mutex)
            }
            log("awaiting select")
            let readFds = sockets.map({ (ws) -> Int32 in
                return ws.0;
            });
            let req = bw_select_request(
                write_fd_len: 0,
                read_fd_len: Int32(sockets.count),
                write_fds: nil,
                read_fds: UnsafeMutablePointer(readFds));
            let resp = bw_select(req)
            if resp.error > 0 {
                let errstr = strerror(resp.error)
                log("error doing a select \(errstr) - removing all clients")
                sockets.removeAll()
                continue
            }
            
            for i in 0..<resp.read_fd_len {
                if let readSock = sockets[resp.read_fds[Int(i)]] {
                    readSock.handleRead()
                }
            }
        }
    }
    
    func log(s: String) {
        print("[BRWebSocketHost] \(s)")
    }
}

class BRWebSocket {
    var request: BRHTTPRequest
    var response: BRHTTPResponse
    var fd: Int32
    var key: String!
    var version: String!
    
    
    var state: SocketState = .HEADERB1
    var fin: UInt8 = 0
    var hasMask: Bool = false
    var opcode: SocketOpcode = .STREAM
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
        log("handshake initiated")
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
                        log("error writing handshake: \(e)")
                        return false
                    }
                    log("handshake written to socket")
                    // enter non-blocking mode
                    if !setNonBlocking() {
                        return false
                    }
                    
                    return true
                }
                log("invalid handshake - missing sec-websocket-key or sec-websocket-version")
            }
        }
        log("invalid handshake - missing or malformed \"upgrade\" header")
        return false
    }
    
    func setNonBlocking() -> Bool {
        log("setting socket to non blocking")
        let nbResult = bw_nbioify(request.fd)
        if nbResult < 0 {
            log("unable to set socket to non blocking \(nbResult)")
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
        if state == .HEADERB1 {
            fin = byte & UInt8(0x80)
            guard let opc = SocketOpcode(rawValue: byte & UInt8(0x0F)) else {
                log("invalid opcode")
                return
            }
            opcode = opc
            state = .HEADERB2
            index = 0
            length = 0
            let rsv = byte & 0x70
            if rsv != 0 {
                // fail out here probably
                log("rsv bit is not zero! wat!")
                return
            }
        } else if state == .HEADERB2 {
            let mask = byte & 0x80
            let length = byte & 0x7F
            if opcode == .PING {
                log("ping packet is too large! wat!")
                return
            }
            hasMask = mask == 128
            if length <= 125 {
                self.length = Int(length)
                if hasMask {
                    maskarray = [UInt8](count: 4, repeatedValue: 0)
                    maskarrayWritten = 0
                    state = .MASK
                } else {
                    // there is no mask and no payload then we're done
                    if length <= 0 {
                        handlePacket()
                        data = nil
                        state = .HEADERB1
                    } else {
                        // there is no mask and some payload
                        data = [UInt8](count: self.length, repeatedValue: 0)
                        dataWritten = 0
                        state = .PAYLOAD
                    }
                }
            } else if length == 126 {
                lengtharray = [UInt8](count: 2, repeatedValue: 0)
                lengtharrayWritten = 0
                state = .LENGTHSHORT
            } else if length == 127 {
                lengtharray = [UInt8](count: 8, repeatedValue: 0)
                lengtharrayWritten = 0
                state = .LENGTHLONG
            }
        } else if state == .LENGTHSHORT {
            lengtharrayWritten += 1
            if lengtharrayWritten > 2 {
                log("short length exceeded allowable size! wat!")
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
                    state = .MASK
                } else {
                    if length <= 0 {
                        handlePacket()
                        data = nil
                        state = .HEADERB1
                    } else {
                        data = [UInt8](count: length, repeatedValue: 0)
                        dataWritten = 0
                        state = .PAYLOAD
                    }
                }
            }
        } else if state == .LENGTHLONG {
            lengtharrayWritten += 1
            if lengtharrayWritten > 8 {
                log("long length exceeded allowable size! wat!")
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
                    state = .MASK
                } else {
                    if length <= 0 {
                        handlePacket()
                        data = nil
                        state = .HEADERB1
                    } else {
                        data = [UInt8](count: length, repeatedValue: 0)
                        dataWritten = 0
                        state = .PAYLOAD
                    }
                }
            }
        } else if state == .MASK {
            maskarrayWritten += 1
            if lengtharrayWritten > 4 {
                log("mask exceeded allowable size! wat!")
                return
            }
            maskarray[maskarrayWritten - 1] = byte
            if maskarrayWritten == 4 {
                if length <= 0 {
                    handlePacket()
                    data = nil
                    state = .HEADERB1
                } else {
                    data = [UInt8](count: length, repeatedValue: 0)
                    dataWritten = 0
                    state = .PAYLOAD
                }
            }
        } else if state == .PAYLOAD {
            dataWritten += 1
            if dataWritten >= MAXPAYLOAD {
                log("payload exceed allowable size! wat!")
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
                state = .HEADERB1
            } else {
                index += 1
            }
        }
    }
    
    func handlePacket() {
        log("handle packet state=\(state) opcode=\(opcode)")
        // validate opcode
        if opcode == .CLOSE || opcode == .STREAM || opcode == .TEXT || opcode == .BINARY {
            // er
        } else if opcode == .PONG || opcode == .PING {
            if dataWritten >  125 {
                log("control frame length can not be > 125")
                return
            }
        } else {
            log("unknown opcode")
            return
        }
        
        
    }
    
    func log(s: String) {
        print("[BRWebSocket \(fd)] \(s)")
    }
}
