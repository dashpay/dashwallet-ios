//
//  BRHTTPServer.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


enum BRHTTPServerError: ErrorType {
    case SocketCreationFailed
    case SocketBindFailed
    case SocketListenFailed
    case SocketRecvFailed
    case SocketWriteFailed
    case InvalidHttpRequest
    case InvalidRangeHeader
}

@objc public protocol BRHTTPMiddleware {
    func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void)
}

@objc public class BRHTTPMiddlewareResponse: NSObject {
    var request: BRHTTPRequest
    var response: BRHTTPResponse?
    
    init(request: BRHTTPRequest, response: BRHTTPResponse?) {
        self.request = request
        self.response = response
    }
}

@objc public class BRHTTPServer: NSObject {
    var fd: Int32 = -1
    var clients: Set<Int32> = []
    var middleware: [BRHTTPMiddleware] = [BRHTTPMiddleware]()
    var isStarted: Bool { return fd != -1 }
    var port: in_port_t = 0
    
    var _Q: dispatch_queue_t? = nil
    var Q: dispatch_queue_t {
        if _Q == nil {
            _Q = dispatch_queue_create("br_http_server", DISPATCH_QUEUE_CONCURRENT)
        }
        return _Q!
    }
    
    func prependMiddleware(middleware mw: BRHTTPMiddleware) {
        middleware.insert(mw, atIndex: 0)
    }
    
    func appendMiddleware(middle mw: BRHTTPMiddleware) {
        middleware.append(mw)
    }
    
    func resetMiddleware() {
        middleware.removeAll()
    }
    
    func start() throws {
        for _ in 0 ..< 100 {
            // get a random port
            let port = in_port_t(arc4random() % (49152 - 1024) + 1024)
            do {
                try start(port)
                self.port = port
                return
            } catch {
                continue
            }
        }
        throw BRHTTPServerError.SocketBindFailed
    }
    
    func start(port: in_port_t, maxPendingConnections: Int32 = SOMAXCONN) throws {
        stop()
        
        let sfd = socket(AF_INET, SOCK_STREAM, 0)
        if sfd == -1 {
            throw BRHTTPServerError.SocketCreationFailed
        }
        var v: Int32 = 1
        if setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &v, socklen_t(sizeof(Int32))) == -1 {
            Darwin.shutdown(sfd, SHUT_RDWR)
            close(sfd)
            throw BRHTTPServerError.SocketCreationFailed
        }
        v = 1
        setsockopt(sfd, SOL_SOCKET, SO_NOSIGPIPE, &v, socklen_t(sizeof(Int32)))
        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(sizeof(sockaddr_in))
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Int(OSHostByteOrder()) == OSLittleEndian ? _OSSwapInt16(port) : port
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0 ,0)
        
        var bind_addr = sockaddr()
        memcpy(&bind_addr, &addr, Int(sizeof(sockaddr_in)))
        
        if bind(sfd, &bind_addr, socklen_t(sizeof(sockaddr_in))) == -1 {
            perror("bind error");
            Darwin.shutdown(sfd, SHUT_RDWR)
            close(sfd)
            throw BRHTTPServerError.SocketBindFailed
        }
        
        if listen(sfd, maxPendingConnections) == -1 {
            perror("listen error");
            Darwin.shutdown(sfd, SHUT_RDWR)
            close(sfd)
            throw BRHTTPServerError.SocketListenFailed
        }
        
        fd = sfd
        acceptClients()
        print("[BRHTTPServer] Serving on \(port)")
    }
    
    func stop() {
        Darwin.shutdown(fd, SHUT_RDWR)
        close(fd)
        fd = -1
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        for cli_fd in self.clients {
            Darwin.shutdown(cli_fd, SHUT_RDWR)
        }
        self.clients.removeAll(keepCapacity: true)
        print("[BRHTTPServer] no longer serving")
    }
    
    func addClient(cli_fd: Int32) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        clients.insert(cli_fd)
    }
    
    func rmClient(cli_fd: Int32) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        clients.remove(cli_fd)
    }
    
    private func acceptClients() {
        dispatch_async(Q) { () -> Void in
            while true {
                var addr = sockaddr(sa_len: 0, sa_family: 0, sa_data: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                var len: socklen_t = 0
                let cli_fd = accept(self.fd, &addr, &len)
                if cli_fd == -1 {
                    break
                }
                var v: Int32 = 1
                setsockopt(cli_fd, SOL_SOCKET, SO_NOSIGPIPE, &v, socklen_t(sizeof(Int32)))
                self.addClient(cli_fd)
                // print("startup: \(cli_fd)")
                dispatch_async(self.Q) { () -> Void in
                    while let req = try? BRHTTPRequestImpl(readFromFd: cli_fd, queue: self.Q) {
                        self.dispatch(middleware: self.middleware, req: req) { resp in
                            Darwin.shutdown(cli_fd, SHUT_RDWR)
                            // print("shutdown: \(cli_fd)")
                            close(cli_fd)
                            self.rmClient(cli_fd)
                        }
                        if !req.isKeepAlive { break }
                    }
                }
            }
            self.stop()
        }
    }
    
    private func dispatch(middleware mw: [BRHTTPMiddleware], req: BRHTTPRequest, finish: (BRHTTPResponse) -> Void) {
        var newMw = mw
        if let curMw = newMw.popLast() {
            curMw.handle(req, next: { (mwResp) -> Void in
                // print("[BRHTTPServer] trying \(req.path) \(curMw)")
                if let httpResp = mwResp.response {
                    httpResp.done {
                        do {
                            try httpResp.send()
                            self.logline(req, response: httpResp)
                        } catch let e {
                            print("[BRHTTPServer] error sending response. request: \(req) error: \(e)")
                        }
                        finish(httpResp)
                    }
                } else {
                    self.dispatch(middleware: newMw, req: mwResp.request, finish: finish)
                }
            })
        } else {
            let resp = BRHTTPResponse(
                request: req, statusCode: 404, statusReason: "Not Found", headers: nil, body: nil)
            logline(req, response: resp)
            _ = try? resp.send()
            finish(resp)
        }
    }
    
    private func logline(request: BRHTTPRequest, response: BRHTTPResponse) {
        let ms = Double(round((request.start.timeIntervalSinceNow * -1000.0)*1000)/1000)
        let b = response.body?.count ?? 0
        let c = response.statusCode ?? -1
        let s = response.statusReason ?? "Unknown"
        print("[BRHTTPServer] \(request.method) \(request.path) -> \(c) \(s) \(b)b in \(ms)ms")
    }
}

@objc public protocol BRHTTPRequest {
    var fd: Int32 { get }
    var queue: dispatch_queue_t { get }
    var method: String { get }
    var path: String { get }
    var queryString: String { get }
    var query: [String: [String]] { get }
    var headers: [String: [String]] { get }
    var isKeepAlive: Bool { get }
    func body() -> NSData?
    var hasBody: Bool { get }
    var contentType: String { get }
    var contentLength: Int { get }
    var start: NSDate { get }
    optional func json() -> AnyObject?
}

@objc public class BRHTTPRequestImpl: NSObject, BRHTTPRequest {
    public var fd: Int32
    public var queue: dispatch_queue_t
    public var method = "GET"
    public var path = "/"
    public var queryString = ""
    public var query = [String: [String]]()
    public var headers = [String: [String]]()
    public var start = NSDate()
    
    public var isKeepAlive: Bool {
        return (headers["connection"] != nil
            && headers["connection"]?.count > 0
            && headers["connection"]![0] == "keep-alive")
    }
    
    static let rangeRe = try! NSRegularExpression(pattern: "bytes=(\\d*)-(\\d*)", options: .CaseInsensitive)
    
    public required init(fromRequest r: BRHTTPRequest) {
        fd = r.fd
        queue = r.queue
        method = r.method
        path = r.path
        queryString = r.queryString
        query = r.query
        headers = r.headers
        if let ri = r as? BRHTTPRequestImpl {
            _bodyRead = ri._bodyRead
            _body = ri._body
        }
    }
    
    public required init(readFromFd: Int32, queue: dispatch_queue_t) throws {
        fd = readFromFd
        self.queue = queue
        super.init()
        let status = try readLine()
        let statusParts = status.componentsSeparatedByString(" ")
        if statusParts.count < 3 {
            throw BRHTTPServerError.InvalidHttpRequest
        }
        method = statusParts[0]
        path = statusParts[1]
        // parse query string
        if path.rangeOfString("?") != nil {
            let parts = path.componentsSeparatedByString("?")
            path = parts[0]
            queryString = parts[1..<parts.count].joinWithSeparator("?")
            let pairs = queryString.componentsSeparatedByString("&")
            for pair in pairs {
                let pairSides = pair.componentsSeparatedByString("=")
                if pairSides.count == 2 {
                    if query[pairSides[0]] != nil {
                        query[pairSides[0]]?.append(pairSides[1])
                    } else {
                        query[pairSides[0]] = [pairSides[1]]
                    }
                }
            }
        }
        // parse headers
        while true {
            let hdr = try readLine()
            if hdr.isEmpty { break }
            let hdrParts = hdr.componentsSeparatedByString(":")
            if hdrParts.count >= 2 {
                let name = hdrParts[0].lowercaseString
                let hdrVal = hdrParts[1..<hdrParts.count].joinWithSeparator(":").stringByTrimmingCharactersInSet(
                    NSCharacterSet.whitespaceCharacterSet())
                if headers[name] != nil {
                    headers[name]?.append(hdrVal)
                } else {
                    headers[name] = [hdrVal]
                }
            }
        }
    }
    
    func readLine() throws -> String {
        var chars: String = ""
        var n = 0
        repeat {
            n = self.read()
            if (n > 13 /* CR */) { chars.append(Character(UnicodeScalar(n))) }
        } while n > 0 && n != 10 /* NL */
        if n == -1 {
            throw BRHTTPServerError.SocketRecvFailed
        }
        return chars
    }
    
    func read() -> Int {
        var buf = [UInt8](count: 1, repeatedValue: 0)
        let n = recv(fd, &buf, 1, 0)
        if n <= 0 {
            return n
        }
        return Int(buf[0])
    }
    
    public var hasBody: Bool {
        return method == "POST" || method == "PATCH" || method == "PUT"
    }
    
    public var contentLength: Int {
        if let hdrs = headers["content-length"] where hasBody && hdrs.count > 0 {
            if let i = Int(hdrs[0]) {
                return i
            }
        }
        return 0
    }
    
    public var contentType: String {
        if let hdrs = headers["content-type"] where hdrs.count > 0 { return hdrs[0] }
        return "application/octet-stream"
    }
    
    private var _body: [UInt8]?
    private var _bodyRead: Bool = false
    
    public func body() -> NSData? {
        if _bodyRead && _body != nil {
            return NSData(bytesNoCopy: UnsafeMutablePointer(_body!), length: contentLength, freeWhenDone: false)
        }
        if _bodyRead {
            return nil
        }
        var buf = [UInt8](count: contentLength, repeatedValue: 0)
        let n = recv(fd, &buf, contentLength, 0)
        if n <= 0 {
            _bodyRead = true
            return nil
        }
        _body = buf
        return NSData(bytesNoCopy: UnsafeMutablePointer(_body!), length: contentLength, freeWhenDone: false)
    }
    
    public func json() -> AnyObject? {
        if let b = body() {
            return try? NSJSONSerialization.JSONObjectWithData(b, options: [])
        }
        return nil
    }
    
    func rangeHeader() throws -> (Int, Int)? {
        if headers["range"] == nil {
            return nil
        }
        guard let rngHeader = headers["range"]?[0],
            match = BRHTTPRequestImpl.rangeRe.matchesInString(rngHeader, options: .Anchored, range:
                NSRange(location: 0, length: rngHeader.characters.count)).first
            where match.numberOfRanges == 3 else {
                throw BRHTTPServerError.InvalidRangeHeader
        }
        let startStr = (rngHeader as NSString).substringWithRange(match.rangeAtIndex(1))
        let endStr = (rngHeader as NSString).substringWithRange(match.rangeAtIndex(2))
        guard let start = Int(startStr), end = Int(endStr) else {
            throw BRHTTPServerError.InvalidRangeHeader
        }
        return (start, end)
    }
}

@objc public class BRHTTPResponse: NSObject {
    var request: BRHTTPRequest
    var statusCode: Int?
    var statusReason: String?
    var headers: [String: [String]]?
    var body: [UInt8]?
    
    var async = false
    var onDone: (() -> Void)?
    var isDone = false
    var isKilled = false
    
    static var reasonMap: [Int: String] = [
        100: "Continue",
        101: "Switching Protocols",
        200: "OK",
        201: "Created",
        202: "Accepted",
        203: "Non-Authoritative Information",
        204: "No Content",
        205: "Reset Content",
        206: "Partial Content",
        300: "Multiple Choices",
        301: "Moved Permanently",
        302: "Found",
        303: "See Other",
        304: "Not Modified",
        305: "Use Proxy",
        306: "", // unused in spec
        307: "Temporary Redirect",
        400: "Bad Request",
        401: "Unauthorized",
        402: "Payment Required",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        406: "Not Acceptable",
        407: "Proxy Authentication Required",
        408: "Request Timeout",
        409: "Conflict",
        410: "Gone",
        411: "Length Required",
        412: "Precondition Failed",
        413: "Request Entity Too Large",
        414: "Request-URI Too Long",
        415: "Unsupported Media Type",
        416: "Request Range Not Satisfiable",
        417: "Expectation Failed",
        500: "Internal Server Error",
        501: "Not Implemented",
        502: "Bad Gateway",
        503: "Service Unavailable",
        504: "Gateway Timeout",
        505: "HTTP Version Not Supported"
    ]
    
    init(request: BRHTTPRequest, statusCode: Int?, statusReason: String?, headers: [String: [String]]?, body: [UInt8]?) {
        self.request = request
        self.statusCode = statusCode
        self.statusReason = statusReason
        self.headers = headers
        self.body = body
        self.isDone = true
        super.init()
    }
    
    init(async request: BRHTTPRequest) {
        self.request = request
        self.async = true
    }
    
    convenience init(request: BRHTTPRequest, code: Int) {
        self.init(
            request: request, statusCode: code, statusReason: BRHTTPResponse.reasonMap[code], headers: nil, body: nil)
    }
    
    convenience init(request: BRHTTPRequest, code: Int, json j: AnyObject) throws {
        let jsonData = try NSJSONSerialization.dataWithJSONObject(j, options: [])
        let bodyBuffer = UnsafeBufferPointer<UInt8>(start: UnsafePointer(jsonData.bytes), count: jsonData.length)
        self.init(
            request: request, statusCode: code, statusReason: BRHTTPResponse.reasonMap[code],
            headers: ["Content-Type": ["application/json"]], body: Array(bodyBuffer))
    }
    
    func send() throws {
        if isKilled {
            return // do nothing... the connection should just be closed
        }
        let status = statusCode ?? 200
        let reason = statusReason ?? "OK"
        try writeUTF8("HTTP/1.1 \(status) \(reason)\r\n")
        
        let length = body?.count ?? 0
        try writeUTF8("Content-Length: \(length)\r\n")
        if request.isKeepAlive {
            try writeUTF8("Connection: keep-alive\r\n")
        }
        let hdrs = headers ?? [String: [String]]()
        for (n, v) in hdrs {
            for yv in v {
                try writeUTF8("\(n): \(yv)\r\n")
            }
        }
        
        try writeUTF8("\r\n")
        
        if let b = body {
            try writeUInt8(b)
        }
    }
    
    func writeUTF8(s: String) throws {
        try writeUInt8([UInt8](s.utf8))
    }
    
    func writeUInt8(data: [UInt8]) throws {
        try data.withUnsafeBufferPointer { pointer in
            var sent = 0
            while sent < data.count {
                let s = write(request.fd, pointer.baseAddress + sent, Int(data.count - sent))
                if s <= 0 {
                    throw BRHTTPServerError.SocketWriteFailed
                }
                sent += s
            }
        }
    }
    
    func provide(status: Int, json: AnyObject) {
        objc_sync_enter(self)
        if isDone {
            print("ERROR: can not call provide() on async HTTP response more than once!")
            return
        }
        isDone = true
        objc_sync_exit(self)
        do {
            let jsonData = try NSJSONSerialization.dataWithJSONObject(json, options: [])
            let bodyBuffer = UnsafeBufferPointer<UInt8>(start: UnsafePointer(jsonData.bytes), count: jsonData.length)
            statusCode = status
            statusReason = BRHTTPResponse.reasonMap[status]
            headers = ["Content-Type": ["application/json"]]
            body = Array(bodyBuffer)
        } catch let e {
            print("Async http response provider threw exception \(e)")
            statusCode = 500
            statusReason = BRHTTPResponse.reasonMap[500]
        }
        objc_sync_enter(self)
        isDone = true
        if self.onDone != nil {
            self.onDone!()
        }
        objc_sync_exit(self)
    }
    
    func kill() {
        objc_sync_enter(self)
        if isDone {
            print("ERROR: can not call kill() on async HTTP response more than once!")
            return
        }
        isDone = true
        isKilled = true
        if self.onDone != nil {
            self.onDone!()
        }
        objc_sync_exit(self)
    }
    
    func done(onDone: () -> Void) {
        objc_sync_enter(self)
        self.onDone = onDone
        if self.isDone {
            self.onDone!()
        }
        objc_sync_exit(self)
    }
}
