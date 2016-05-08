//
//  SQLiteDB.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright (c) 2016 breadwallet LLC
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

class SQLite {
    var path: String
    var id: String {
        return path
    }
    var dbIsOpen = false
    
    // this holds the sqlite3* pointer
    private var _handle: COpaquePointer = nil
    
    // used to convert an sqlite result code into a useful error
    private enum Result: ErrorType, CustomStringConvertible {
        private static let successCodes: Set = [SQLITE_OK, SQLITE_ROW, SQLITE_DONE]
        
        case Error(message: String, code: Int32)
        
        init?(errorCode: Int32, connection: COpaquePointer) {
            guard !Result.successCodes.contains(errorCode) else { return nil }
            
            let message = String.fromCString(sqlite3_errmsg(connection))!
            self = Error(message: message, code: errorCode)
        }
        
        var description: String {
            switch self {
            case .Error(let msg, let c):
                return "SQLiteError(code=\(c) message=\(msg))"
            }
        }
    }
    
    // a queue is used to serialize all operations on the database
    private var _Q: dispatch_queue_t!
    private var _setQ: Bool = false
    private var Q: dispatch_queue_t {
        if !_setQ {
            _setQ = true
            _Q = dispatch_queue_create("localsqlitedb.\(id)", DISPATCH_QUEUE_SERIAL)
        }
        return _Q
    }
    
    init(path p: String) {
        path = p
    }
    
    private func open() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        if dbIsOpen {
            result.succeed(dbIsOpen)
        }
        dispatch_async(Q) {
            do {
                let flags = SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
                try self.check(sqlite3_open_v2(self.path, &self._handle, flags, nil))
                self.dbIsOpen = true
                result.succeed(self.dbIsOpen)
            } catch Result.Error(let e) {
                self.log("Error opening sqlite database \(e)")
                result.error(Int(e.code), message: e.message)
            } catch let e {
                self.log("Unknown error opening sqlite database \(e)")
                result.error(-1001, message: "\(e)")
            }
        }
        return result
    }
    
    deinit {
        sqlite3_close(_handle)
    }
    
    // check the result of an sqlite3 liberary call and throw if it is an error
    private func check(resultCode: Int32) throws -> Int32 {
        guard let error = Result(errorCode: resultCode, connection: _handle) else {
            return resultCode
        }
        throw error
    }
    
    private var _beginHandle: COpaquePointer = nil
    private var _commitHandle: COpaquePointer = nil
    private var _rollbackHandle: COpaquePointer = nil
    private var _txNesting: Int = 0
    
    // asynchronously executes a transaction on the database
    private func transaction(block: () throws -> Void) -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        open().success(AsyncCallback<Bool> { _ in
            dispatch_async(self.Q) {
                self._txNesting += 1
                defer {
                    self._txNesting -= 1
                }
                var didBegin = false
                do {
                    if self._beginHandle == nil {
                        try self.prepare("BEGIN DEFERRED TRANSACTION", handle: &self._beginHandle)
                        try self.prepare("COMMIT TRANSACTION", handle: &self._commitHandle)
                        try self.prepare("ROLLBACK TRANSACTION", handle: &self._rollbackHandle)
                    } else {
                        try self.reset(self._beginHandle)
                        try self.reset(self._commitHandle)
                        try self.reset(self._rollbackHandle)
                    }
                    // BEGIN
                    if self._txNesting == 1 {
                        self.log("transaction: BEGIN DEFERRED TRANSACTION")
                        try self.step(self._beginHandle)
                    }
                    didBegin = true
                    // EXECUTE
                    try block()
                } catch Result.Error(let txErr) {
                    if didBegin {
                        var didRollback = false
                        // ROLLBACK
                        do {
                            if self._txNesting == 1 {
                                self.log("transaction: ROLLBACK TRANSACTION")
                                try self.step(self._rollbackHandle)
                                self.log("transaction: rollback success")
                            }
                            didRollback = true
                        } catch Result.Error(let e) {
                            // send rollback error
                            self.log("transaction: rollback error \(e)")
                            result.error(Int(e.code), message: e.message)
                            return
                        } catch {
                            // this should never happen
                            self.log("transaction: unknown rollback error")
                            result.error(-1011, message: "unknown error occurred during rollback")
                            return
                        }
                        if didRollback {
                            // send original tx error
                            self.log("transaction: error \(txErr)")
                            result.error(Int(txErr.code), message: txErr.message)
                            return
                        }
                    }
                } catch {
                    self.log("transaction: unknown transaction error")
                    result.error(-1001, message: "unknown error occurred during transaction")
                    return
                }
                // COMMIT
                do {
                    if self._txNesting == 1 {
                        self.log("transaction: COMMIT TRANSACTION")
                        try self.step(self._commitHandle)
                        self.log("transaction: commit success")
                    }
                } catch Result.Error(let commitErr) {
                    self.log("transaction: commit error \(commitErr)")
                    result.error(Int(commitErr.code), message: commitErr.message)
                    return
                } catch {
                    self.log("transaction: unknown error during commit")
                    result.error(-1001, message: "unknown error during commit")
                    return
                }
                result.succeed(true)
            }
            return true
        }).failure(AsyncCallback<AsyncError> { e in
            result.error(e)
            return e
        })
        
        return result
    }
    
    private func prepare(query: String, inout handle: COpaquePointer) throws {
        log("prepare: \(query)")
        try check(sqlite3_prepare_v2(self._handle, query, -1, &handle, nil))
    }
    
    private func prepare(query: String) throws -> COpaquePointer {
        log("prepare: \(query)")
        var ret: COpaquePointer = nil
        try check(sqlite3_prepare_v2(self._handle, query, -1, &ret, nil))
        return ret
    }
    
    private func execute(query: String) throws {
        log("execute: \(query)")
        try check(sqlite3_exec(self._handle, query, nil, nil, nil))
    }
    
    private func reset(query: COpaquePointer) throws {
        log("reset: " + String.fromCString(sqlite3_sql(query))!)
        try check(sqlite3_reset(query))
    }
    
    private func step(query: COpaquePointer) throws -> Int32 {
        log("step: " + String.fromCString(sqlite3_sql(query))!)
        return try check(sqlite3_step(query))
    }
    
    private func finalize(query: COpaquePointer) throws {
        log("finalize: " + String.fromCString(sqlite3_sql(query))!)
        try check(sqlite3_finalize(query))
    }
    
    private func bind<T: StringLiteralConvertible>(string: T, query: COpaquePointer, index: Int) throws {
        let s = String(string)
        try check(sqlite3_bind_text(query, Int32(index), s, -1, nil))
    }
    
    private func column(query: COpaquePointer, index: Int) -> Int {
        return Int(sqlite3_column_int(query, Int32(index)))
    }
    
    private func column(query: COpaquePointer, index: Int) -> String {
        return String(sqlite3_column_text(query, Int32(index)))
    }
    
    typealias JSON = AnyObject
    
    private func column(query: COpaquePointer, index: Int) -> JSON {
        let t = String(sqlite3_column_text(query, Int32(index))) as NSString
        let d = NSData(bytes: t.UTF8String, length: t.length)
        do {
            let j = try NSJSONSerialization.JSONObjectWithData(d, options: [])
            return j
        } catch let e {
            log("error \(e) deserializing json value \(t)")
            return NSDictionary()
        }
    }
    
    private func log(s: String) {
        print("[Sqlite] \(s)")
    }
}

// Basically an implementation of CouchDB on top of SQLite. There are a lot of features missing.
// 
// TODO options: revs_limit
// TODO features:
//   - local docs
public class LocalSQLiteDB: ReplicationClient {
    private var db: SQLite
    public var id: String { return db.id }
    
    public init(path: String) {
        db = SQLite(path: path)
    }
    
    private var createDatabaseStatements: [String] = [
        "CREATE TABLE 'attach_store' (digest UNIQUE, escaped TINYINT(1), body BLOB)",
        "CREATE TABLE 'local_store' (id UNIQUE, rev, json)",
        "CREATE TABLE 'attach_seq_store' (digest, seq INTEGER)",
        "CREATE TABLE 'document_store' (id unique, json, winningseq, max_seq INTEGER UNIQUE)",
        "CREATE TABLE 'by_sequence' (seq INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, json, deleted TINYINT(1), doc_id, rev)",
        "CREATE TABLE 'metadata_store' (dbid, db_version INTEGER)",
        "DELETE FROM sqlite_sequence",
        "CREATE INDEX 'attach_seq_seq_idx' ON 'attach_seq_store' (seq)",
        "CREATE UNIQUE INDEX 'attach_seq_digest_idx' ON 'attach_seq_store' (digest, seq)",
        "CREATE INDEX 'doc_winningseq_idx' ON 'document_store' (winningseq)",
        "CREATE INDEX 'by_seq_deleted_idx' ON 'by_sequence' (seq, deleted)",
        "CREATE UNIQUE INDEX 'by_seq_doc_id_rev' ON 'by_sequence' (doc_id, rev)"
    ]
    
    private func log(s: String) {
        print("[SQLiteDB] \(s)")
    }
    
    // PRAGMA MARK - API helper functions
    
    private var _countHandle: COpaquePointer = nil // counts all documents in storage
    
    func countDocs() -> AsyncResult<Int> {
        let result = AsyncResult<Int>()
        db.transaction({
            if self._countHandle == nil {
                let sql =
                    "SELECT COUNT(document_store.id) AS num " +
                    "FROM document_store " +
                    "JOIN by_sequence " +
                    "ON by_sequence.seq = document_store.winningseq " +
                    "WHERE by_sequence.deleted = 0"
                try self.db.prepare(sql, handle: &self._countHandle)
            }
            defer {
                _ = try? self.db.finalize(self._countHandle)
            }
            try self.db.reset(self._countHandle)
            if try self.db.step(self._countHandle) == SQLITE_ROW {
                let res = sqlite3_column_int(self._countHandle, 0)
                result.succeed(Int(res))
            } else {
                self.log("countDocs: invalid result")
                result.error(-1001, message: "unknown count error occurred (result was not SQLITE_ROW)")
            }
        }).failure(AsyncCallback<AsyncError> { txErr in
            self.log("countDocs: tx error: \(txErr)")
            result.error(txErr)
            return txErr
        })
        return result
    }
    
    public func exists() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        return result
    }
    
    public func create() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        db.transaction({
            for stmt in self.createDatabaseStatements {
                try self.db.execute(stmt)
            }
        }).success(AsyncCallback<Bool> { res in
            result.succeed(res)
            return res
        }).failure(AsyncCallback<AsyncError> { txErr in
            result.error(txErr.code, message: txErr.message)
            return txErr
        })
        return result
    }
    
    public func info() -> AsyncResult<DatabaseInfo> {
        let result = AsyncResult<DatabaseInfo>()
        countDocs().success(AsyncCallback<Int> { docCount in
            self.db.transaction({
                let maxSeqQ = try self.db.prepare("SELECT MAX(seq) AS seq FROM by_sequence")
                if try self.db.step(maxSeqQ) == SQLITE_ROW {
                    let updateSeq = sqlite3_column_int(maxSeqQ, 0)
                    let fm = NSFileManager.defaultManager()
                    let attrs: NSDictionary = try fm.attributesOfItemAtPath(self.db.path)
                    var d = [String: AnyObject]()
                    d["db_name"] = NSURL(string: self.db.path)!.pathComponents!.last
                    d["doc_count"] = NSNumber(integer: docCount)
                    d["disk_size"] = NSNumber(integer: Int(attrs.fileSize()))
                    d["data_size"] = NSNumber(integer: Int(attrs.fileSize()))
                    d["doc_del_count"] = NSNumber(integer: -1)
                    d["purge_seq"] = NSNumber(integer: -1)
                    d["update_seq"] = NSNumber(integer: Int(updateSeq))
                    d["compact_running"] = NSNumber(bool: false)
                    d["committed_update_seq"] = NSNumber(integer: -1)
                    let dbInfo = try! DatabaseInfo(json: d)
                    result.succeed(dbInfo)
                } else {
                    result.error(-1001, message: "unknown error selecting updateSeq")
                }
            }).failure(AsyncCallback<AsyncError> { txErr in
                result.error(txErr)
                return txErr
            })
            return docCount
        }).failure(AsyncCallback<AsyncError> { countErr in
            result.error(countErr)
            return countErr
        })
        return result
    }
    
    public func ensureFullCommit() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        return result
    }
    
    // prepared statements used by _get()
    private var _getDocHandle: COpaquePointer = nil
    private var _getDocRevHandle: COpaquePointer = nil
    
    // struct used internally to represent the result of a _get() request
    private struct _GetResult {
        var id: String? = nil
        var metadata: SQLite.JSON? = nil
        var doc: SQLite.JSON? = nil
        var rev: String? = nil
        var missing: Bool = false
        var deleted: Bool = false
        
        func docify<T: Document>(returning: T.Type) throws -> T {
            if id == nil || rev == nil {
                throw DocumentLoadingError.InvalidDocument
            }
            var newDoc = try T(json: doc)
            newDoc._id = id!
            newDoc._rev = rev!
            return newDoc
        }
        
        func deserializeMetadata() -> DocumentMetadata? {
            do {
                return try DocumentMetadata(json: metadata)
            } catch {
                return nil
            }
        }
    }
    
    private func _get(id: String, options: [String: [String]]?) -> AsyncResult<_GetResult> {
        let result = AsyncResult<_GetResult>()
        db.transaction({
            // setup prepared statements
            if self._getDocHandle == nil {
                let selectSql = "SELECT by_sequence.seq AS seq, " +         // seq = 0
                                "by_sequence.deleted AS deleted, " +        // deleted = 1
                                "by_sequence.json AS data, " +              // data = 2
                                "by_sequence.rev AS rev, " +                // rev = 3
                                "document_store.json AS metadata " +        // metadata = 4
                                "FROM document_store, by_sequence "
                
                let docSql = selectSql + "JOIN ON by_sequence.seq = document_store.winningseq " +
                                         "WHERE document_store.id=?"
                
                let revDocSql = selectSql + "JOIN ON document_store.id = by_sequence.doc_id " +
                                            "WHERE by_sequence.doc_id=? AND by_sequence.rev=?"
                
                self._getDocHandle = try self.db.prepare(docSql)
                self._getDocRevHandle = try self.db.prepare(revDocSql)
            }
            
            // reset prepared statements
            try self.db.reset(self._getDocHandle)
            try self.db.reset(self._getDocRevHandle)
            
            // logic is slightly different if caller is looking for a speicifc revision: when searching for a revision
            // a deleted document can be returned, not but if searching by id
            var getRev = false
            var selectResult: COpaquePointer = nil
            if let revO = options?["rev"] where revO.count > 0 {
                getRev = true
                // caller is asking for a specific revision
                defer {
                    _ = try? self.db.finalize(self._getDocRevHandle)
                }
                try self.db.bind(id, query: self._getDocRevHandle, index: 0)
                try self.db.bind(revO[0], query: self._getDocRevHandle, index: 1)
                let step = try self.db.step(self._getDocRevHandle)
                if step == SQLITE_ROW {
                    selectResult = self._getDocRevHandle
                } else if step != SQLITE_DONE {
                    result.error(-1001, message: "sqlite did not return a row")
                    return
                }
            } else {
                // caller is asking for document by id
                defer {
                    _ = try? self.db.finalize(self._getDocHandle)
                }
                try self.db.bind(id, query: self._getDocHandle, index: 0)
                let step = try self.db.step(self._getDocHandle)
                if step == SQLITE_ROW {
                    selectResult = self._getDocHandle
                } else if step != SQLITE_DONE {
                    result.error(-1001, message: "sqlite did not return a row")
                    return
                }
            }
            var getResult = _GetResult()
            getResult.id = id
            if selectResult != nil {
                let deleted: Int = self.db.column(selectResult, index: 1)
                let metadata: SQLite.JSON = self.db.column(selectResult, index: 4)
                let data: SQLite.JSON = self.db.column(selectResult, index: 2)
                let rev: String = self.db.column(selectResult, index: 3)
                if deleted > 0 && !getRev {
                    getResult.deleted = true
                    result.succeed(getResult)
                } else {
                    getResult.rev = rev
                    getResult.deleted = deleted > 0
                    getResult.metadata = metadata
                    getResult.doc = data
                    result.succeed(getResult)
                }
            } else {
                getResult.missing = true
                result.succeed(getResult)
            }
        }).failure(AsyncCallback<AsyncError> { txErr in
            return txErr
        })
        return result
    }
    
    public func get<T: Document>(id: String, options: [String: [String]]?, returning: T.Type) -> AsyncResult<T?> {
        let result = AsyncResult<T?>()
        // TODO: implement 'open_revs' option
        
        _get(id, options: options).success(AsyncCallback<_GetResult> { getResult in
            // TODO implement 'conflicts' option
            
            if getResult.deleted {
                result.succeed(nil)
                return getResult
            }
            
            let metadata = getResult.deserializeMetadata()!
            var doc = try! getResult.docify(returning)

            if metadata.isDeleted(doc._rev) {
                doc._deleted = true
            }
            
            // TODO: implement 'revs' and 'revs_info' options
            // TODO: handle attachments
            
            result.succeed(doc)
            
            return getResult
        })
        
        return result
    }
    
    public func put<T : Document>(doc: T, options: [String: [String]]?, returning: T.Type) -> AsyncResult<T> {
        let result = AsyncResult<T>()
        
        
        
        return result
    }
    
    public func allDocs<T : Document>(options: [String: [String]]?) -> AsyncResult<[T]> {
        let result = AsyncResult<[T]>()
        return result
    }
    
    public func _bulkDocs<T: Document>(docs: [T], options: [String: AnyObject]?) -> AsyncResult<[T]> {
        let result = AsyncResult<[T]>()
        
        
        
        return result
    }
    
    public func bulkDocs<T : Document>(docs: [T], options: [String: AnyObject]?) -> AsyncResult<[Bool]> {
        let result = AsyncResult<[Bool]>()
        return result
    }
    
    public func revsDiff(revs: [String: [String]], options: [String : [String]]?) -> AsyncResult<[RevisionDiff]> {
        let result = AsyncResult<[RevisionDiff]>()
        return result
    }
    
    public func changes(options: [String : [String]]?) -> AsyncResult<Changes> {
        let result = AsyncResult<Changes>()
        return result
    }
}
