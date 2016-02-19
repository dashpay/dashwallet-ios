//
//  BRWebSocket.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/18/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


@objc public protocol BRWebSocket {
    var id: String { get }
    var request: BRHTTPRequest { get }
    var match: BRHTTPRouteMatch { get }
    func send(text: String)
}

@objc public protocol BRWebSocketClient {
    optional func socketDidConnect(socket: BRWebSocket)
    optional func socket(socket: BRWebSocket, didReceiveData data: NSData)
    optional func socket(socket: BRWebSocket, didReceiveText text: String)
    optional func socketDidDisconnect(socket: BRWebSocket)
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

enum SocketOpcode: UInt8, CustomStringConvertible {
    case STREAM = 0x0
    case TEXT = 0x1
    case BINARY = 0x2
    case CLOSE = 0x8
    case PING = 0x9
    case PONG = 0xA
    
    var description: String {
        switch (self) {
        case .STREAM: return "STREAM"
        case .TEXT: return "TEXT"
        case .BINARY: return "BINARY"
        case .CLOSE: return "CLOSE"
        case .PING: return "PING"
        case .PONG: return "PONG"
        }
    }
}

let (MAXHEADER, MAXPAYLOAD) = (65536, 33554432)

enum SocketCloseEventCode: UInt16 {
    case CLOSE_NORMAL = 1000
    case CLOSE_GOING_AWAY = 1001
    case CLOSE_PROTOCOL_ERROR = 1002
    case CLOSE_UNSUPPORTED = 1003
    case CLOSE_NO_STATUS = 1005
    case CLOSE_ABNORMAL = 1004
    case UnsupportedData = 1006
    case PolicyViolation = 1007
    case CLOSE_TOO_LARGE = 1008
    case MissingExtension = 1009
    case InternalError = 1010
    case ServiceRestart = 1011
    case TryAgainLater = 1012
    case TLSHandshake = 1015
}

class BRWebSocketServer {
    var sockets = [Int32: BRWebSocketImpl]()
    var thread: pthread_t = nil
    var waiter: UnsafeMutablePointer<pthread_cond_t>
    var mutex: UnsafeMutablePointer<pthread_mutex_t>
    
    init() {
        mutex = UnsafeMutablePointer.alloc(sizeof(pthread_mutex_t))
        waiter = UnsafeMutablePointer.alloc(sizeof(pthread_cond_t))
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(waiter, nil)
    }
    
    func add(socket: BRWebSocketImpl) {
        log("adding socket \(socket.fd)")
        pthread_mutex_lock(mutex)
        sockets[socket.fd] = socket
        socket.client.socketDidConnect?(socket)
        pthread_cond_signal(waiter)
        pthread_mutex_unlock(mutex)
    }
    
    func serveForever() {
        objc_sync_enter(self)
        if thread == nil {
            objc_sync_exit(self)
            return
        }
        let selfPointer = UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque())
        pthread_create(&thread, nil, { (sillySelf: UnsafeMutablePointer<Void>) in
            let localSelf = Unmanaged<BRWebSocketServer>.fromOpaque(COpaquePointer(sillySelf)).takeUnretainedValue()
            localSelf.log("in server thread")
            localSelf._serveForever()
            return nil
        }, selfPointer)
        objc_sync_exit(self)
    }
    
    func _serveForever() {
        log("starting websocket poller")
        while true {
            while sockets.count < 1 {
                log("awaiting clients")
                pthread_cond_wait(waiter, mutex)
            }
            log("awaiting select")
            
            // all fds should be available for a read
            let readFds = sockets.map({ (ws) -> Int32 in return ws.0 });
            
            // only fds which have items in the send queue are available for a write
            let writeFds = sockets.map({
                (ws) -> Int32 in return ws.1.sendq.count > 0 ? ws.0 : -1
            }).filter({ i in return i != -1 })
            
            // build the select request and execute it, checking the result for an error
            let req = bw_select_request(
                write_fd_len: Int32(writeFds.count),
                read_fd_len: Int32(readFds.count),
                write_fds: UnsafeMutablePointer(writeFds),
                read_fds: UnsafeMutablePointer(readFds));
            
            let resp = bw_select(req)
            
            if resp.error > 0 {
                let errstr = strerror(resp.error)
                log("error doing a select \(errstr) - removing all clients")
                sockets.removeAll()
                continue
            }
            
            // read for all readers that have data waiting
            for i in 0..<resp.read_fd_len {
                if let readSock = sockets[resp.read_fds[Int(i)]] {
                    readSock.handleRead()
                }
            }
            
            // write for all writers
            for i in 0..<resp.write_fd_len {
                log("handle write fd=\(sockets[resp.write_fds[Int(i)]]!.fd)")
                if let writeSock = sockets[resp.write_fds[Int(i)]] {
                    let (opcode, payload) = writeSock.sendq.removeFirst()
                    do {
                        let sentBytes = try sendBuffer(writeSock.fd, buffer: payload)
                        if sentBytes != payload.count {
                            let remaining = Array(payload.suffixFrom(sentBytes - 1))
                            writeSock.sendq.insert((opcode, remaining), atIndex: 0)
                            break // terminate sends and continue sending on the next select
                        } else {
                            if opcode == .CLOSE {
                                log("KILLING fd=\(writeSock.fd)")
                                writeSock.response.kill()
                                writeSock.client.socketDidDisconnect?(writeSock)
                                sockets.removeValueForKey(writeSock.fd)
                                continue // go to the next select client
                            }
                        }
                    } catch {
                        // close...
                        writeSock.response.kill()
                        writeSock.client.socketDidDisconnect?(writeSock)
                        sockets.removeValueForKey(writeSock.fd)
                    }
                }
            }
            
            // kill sockets that wrote out of bound data
            for i in 0..<resp.error_fd_len {
                if let errSock = sockets[resp.error_fds[Int(i)]] {
                    errSock.response.kill()
                    errSock.client.socketDidDisconnect?(errSock)
                    sockets.removeValueForKey(errSock.fd)
                }
            }
        }
    }
    
    // attempt to send a buffer, returning the number of sent bytes
    func sendBuffer(fd: Int32, buffer: [UInt8]) throws -> Int {
        log("send buffer fd=\(fd) buffer=\(buffer)")
        var sent = 0
        try buffer.withUnsafeBufferPointer { pointer in
            while sent < buffer.count {
                let s = send(fd, pointer.baseAddress + sent, Int(buffer.count - sent), 0)
                log("write result \(s)")
                if s <= 0 {
                    let serr = Int32(s)
                    // full buffer, should try again next iteration
                    if Int32(serr) == EWOULDBLOCK || Int32(serr) == EAGAIN {
                        return
                    } else {
                        self.log("socket write failed fd=\(fd) err=\(strerror(serr))")
                        throw BRHTTPServerError.SocketWriteFailed
                    }
                }
                sent += s
            }
        }
        return sent
    }
    
    func log(s: String) {
        print("[BRWebSocketHost] \(s)")
    }
}

class BRWebSocketImpl: BRWebSocket {
    @objc var request: BRHTTPRequest
    var response: BRHTTPResponse
    @objc var match: BRHTTPRouteMatch
    var client: BRWebSocketClient
    var fd: Int32
    var key: String!
    var version: String!
    @objc var id: String = NSUUID().UUIDString
    
    var state = SocketState.HEADERB1
    var fin: UInt8 = 0
    var hasMask = false
    var opcode = SocketOpcode.STREAM
    var closed = false
    var index = 0
    var length = 0
    var lengtharray = [UInt8]()
    var lengtharrayWritten = 0
    var data = [UInt8]()
    var dataWritten = 0
    var maskarray = [UInt8]()
    var maskarrayWritten = 0
    
    var fragStart = false
    var fragType = SocketOpcode.BINARY
    var fragBuffer = [UInt8]()
    
    var sendq = [(SocketOpcode, [UInt8])]()
    
    init(request: BRHTTPRequest, response: BRHTTPResponse, match: BRHTTPRouteMatch, client: BRWebSocketClient) {
        self.request = request
        self.match = match
        self.fd = request.fd
        self.response = response
        self.client = client
    }
    
    // MARK: - public interface impl
    
    @objc func send(text: String) {
        sendMessage(false, opcode: .TEXT, data: [UInt8](text.utf8))
    }
    
    // MARK: - private interface
    
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
            log("parse HEADERB1 fin=\(fin) opcode=\(opcode)")
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
                        data = [UInt8]()
                        dataWritten = 0
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
            log("parse HEADERB2 hasMask=\(hasMask) opcode=\(opcode)")
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
                        data = [UInt8]()
                        dataWritten = 0
                        state = .HEADERB1
                    } else {
                        data = [UInt8](count: length, repeatedValue: 0)
                        dataWritten = 0
                        state = .PAYLOAD
                    }
                }
            }
            log("parse LENGTHSHORT lengtharrayWritten=\(lengtharrayWritten) length=\(length) state=\(state) opcode=\(opcode)")
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
                        data = [UInt8]()
                        dataWritten = 0
                        state = .HEADERB1
                    } else {
                        data = [UInt8](count: length, repeatedValue: 0)
                        dataWritten = 0
                        state = .PAYLOAD
                    }
                }
            }
            log("parse LENGTHLONG lengtharrayWritten=\(lengtharrayWritten) length=\(length) state=\(state) opcode=\(opcode)")
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
                    data = [UInt8]()
                    dataWritten = 0
                    state = .HEADERB1
                } else {
                    data = [UInt8](count: length, repeatedValue: 0)
                    dataWritten = 0
                    state = .PAYLOAD
                }
            }
            log("parse MASK maskarrayWritten=\(maskarrayWritten) state=\(state)")
        } else if state == .PAYLOAD {
            dataWritten += 1
            if dataWritten >= MAXPAYLOAD {
                log("payload exceed allowable size! wat!")
                return
            }
            if hasMask {
                log("payload byte length=\(length) mask=\(maskarray[index%4]) byte=\(byte)")
                data[dataWritten - 1] = byte ^ maskarray[index % 4]
            } else {
                log("payload byte length=\(length) \(byte)")
                data[dataWritten - 1] = byte
            }
            if index + 1 == length {
                log("payload done")
                handlePacket()
                data = [UInt8]()
                dataWritten = 0
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
            // valid
        } else if opcode == .PONG || opcode == .PING {
            if dataWritten >  125 {
                log("control frame length can not be > 125")
                return
            }
        } else {
            log("unknown opcode")
            return
        }
        
        if opcode == .CLOSE {
            log("CLOSE")
            var status = SocketCloseEventCode.CLOSE_NORMAL
            var reason = ""
            if dataWritten >= 2 {
                let lt = Array(data.prefix(2))
                let ll = CFSwapInt16BigToHost(UnsafePointer<UInt16>(lt).memory)
                if let ss = SocketCloseEventCode(rawValue: ll) {
                    status = ss
                } else {
                    status = .CLOSE_PROTOCOL_ERROR
                }
                let lr = Array(data.suffixFrom(2))
                if lr.count > 0 {
                    if let rr = String(bytes: lr, encoding: NSUTF8StringEncoding) {
                        reason = rr
                    } else {
                        log("bad utf8 data in close reason string...")
                        status = .CLOSE_PROTOCOL_ERROR
                        reason = "bad UTF8 data"
                    }
                }
            } else {
                status = .CLOSE_PROTOCOL_ERROR
            }
            close(status, reason: reason)
        } else if fin == 0 {
            log("getting fragment \(fin)")
            if opcode != .STREAM {
                if opcode == .PING || opcode == .PONG {
                    log("error: control messages can not be fragmented")
                    return
                }
                // start of fragments
                fragType = opcode
                fragStart = true
                fragBuffer = fragBuffer + data
            } else {
                if !fragStart {
                    log("error: fragmentation protocol error y")
                    return
                }
                fragBuffer = fragBuffer + data
            }
        } else {
            if opcode == .STREAM {
                if !fragStart {
                    log("error: fragmentation protocol error x")
                    return
                }
                if self.fragType == .TEXT {
                    if let str = String(bytes: data, encoding: NSUTF8StringEncoding) {
                        self.client.socket?(self, didReceiveText: str)
                    } else {
                        log("error decoding utf8 data")
                    }
                } else {
                    let bin = NSData(bytes: UnsafePointer(data), length: data.count)
                    self.client.socket?(self, didReceiveData: bin)
                }
                fragType = .BINARY
                fragStart = false
                fragBuffer = [UInt8]()
            } else if opcode == .PING {
                sendMessage(false, opcode: .PONG, data: data)
            } else if opcode == .PONG {
                // nothing to do
            } else {
                if fragStart {
                    log("error: fragment protocol error z")
                    return
                }
                if opcode == .TEXT {
                    if let str = String(bytes: data, encoding: NSUTF8StringEncoding) {
                        self.client.socket?(self, didReceiveText: str)
                    } else {
                        log("error decoding uft8 data")
                    }
                }
            }
        }
    }
    
    func close(status: SocketCloseEventCode = .CLOSE_NORMAL, reason: String = "") {
        if !closed {
            log("sending close")
            sendMessage(false, opcode: .CLOSE, data: status.rawValue.toNetwork() + [UInt8](reason.utf8))
        } else {
            log("socket is already closed")
        }
        closed = true
    }
    
    func sendMessage(fin: Bool, opcode: SocketOpcode, data: [UInt8]) {
        log("send message opcode=\(opcode)")
        var b1: UInt8 = 0
        var b2: UInt8 = 0
        if !fin { b1 |= 0x80 }
        var payload = [UInt8]() // todo: pick the right size for this
        b1 |= opcode.rawValue
        payload.append(b1)
        if data.count <= 125 {
            b2 |= UInt8(data.count)
            payload.append(b2)
        } else if data.count >= 126 && data.count <= 65535 {
            b2 |= 126
            payload.append(b2)
            payload.appendContentsOf(UInt16(data.count).toNetwork())
        } else {
            b2 |= 127
            payload.append(b2)
            payload.appendContentsOf(UInt64(data.count).toNetwork())
        }
        payload.appendContentsOf(data)
        sendq.append((opcode, payload))
    }
    
    func log(s: String) {
        print("[BRWebSocket \(fd)] \(s)")
    }
}

extension UInt16 {
    func toNetwork() -> [UInt8] {
        var selfBig = CFSwapInt16HostToBig(self)
        let size = sizeof(UInt16)
        let dat = UnsafePointer<UInt8>(NSData(bytes: &selfBig, length: size).bytes)
        let buf = UnsafeBufferPointer(start: dat, count: size)
        return Array(buf)
    }
}

extension UInt64 {
    func toNetwork() -> [UInt8] {
        var selfBig = CFSwapInt64HostToBig(self)
        let size = sizeof(UInt64)
        let dat = UnsafePointer<UInt8>(NSData(bytes: &selfBig, length: size).bytes)
        let buf = UnsafeBufferPointer(start: dat, count: size)
        return Array(buf)
    }
}
