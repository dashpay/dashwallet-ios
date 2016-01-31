//
//  SQLiteDB.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


public class LocalSQLiteDB: ReplicationClient {
    var path: String
    public var id: String {
        return path
    }
    // this holds the sqlite3* pointer
    private var _handle: COpaquePointer = nil
    
    // used to convert an sqlite result code into a useful error
    private enum SqliteResult: ErrorType, CustomStringConvertible {
        private static let successCodes: Set = [SQLITE_OK, SQLITE_ROW, SQLITE_DONE]
        
        case Error(message: String, code: Int32)
        
        init?(errorCode: Int32, connection: COpaquePointer) {
            guard !SqliteResult.successCodes.contains(errorCode) else { return nil }
            
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
    
    private var createDatabaseStatements: [String] = [
        "CREATE TABLE 'attach-store' (digest UNIQUE, escaped TINYINT(1), body BLOB)",
        "CREATE TABLE 'local-store' (id UNIQUE, rev, json)",
        "CREATE TABLE 'attach-seq-store' (digest, seq INTEGER)",
        "CREATE TABLE 'document-store' (id unique, json, winningseq, max_seq INTEGER UNIQUE)",
        "CREATE TABLE 'by-sequence' (seq INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, json, deleted TINYINT(1), doc_id, rev)",
        "CREATE TABLE 'metadata-store' (dbid, db_version INTEGER)",
        "DELETE FROM sqlite_sequence",
        "CREATE INDEX 'attach-seq-seq-idx' ON 'attach-seq-store' (seq)",
        "CREATE UNIQUE INDEX 'attach-seq-digest-idx' ON 'attach-seq-store' (digest, seq)",
        "CREATE INDEX 'doc-winningseq-idx' ON 'document-store' (winningseq)",
        "CREATE INDEX 'by-seq-deleted-idx' ON 'by-sequence' (seq, deleted)",
        "CREATE UNIQUE INDEX 'by-seq-doc-id-rev' ON 'by-sequence' (doc_id, rev)"
    ]
    
    init(path p: String) {
        path = p
    }
    
    deinit {
        sqlite3_close(_handle)
    }
    
    // check the result of an sqlite3 liberary call and throw if it is an error
    private func check(resultCode: Int32) throws -> Int32 {
        guard let error = SqliteResult(errorCode: resultCode, connection: _handle) else {
            return resultCode
        }
        throw error
    }
    
    private var _beginHandle: COpaquePointer = nil
    private var _commitHandle: COpaquePointer = nil
    private var _rollbackHandle: COpaquePointer = nil
    
    // asynchronously executes a transaction on the database
    private func transaction(block: () throws -> Void) -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        dispatch_async(Q) {
            var didBegin = false
            do {
                if self._beginHandle == nil {
                    try self.check(sqlite3_prepare_v2(self._handle, "BEGIN DEFERRED TRANSACTION", -1, &self._beginHandle, nil))
                    try self.check(sqlite3_prepare_v2(self._handle, "COMMIT TRANSACTION", -1, &self._commitHandle, nil))
                    try self.check(sqlite3_prepare_v2(self._handle, "ROLLBACK TRANSACTION", -1, &self._rollbackHandle, nil))
                } else {
                    try self.check(sqlite3_reset(self._beginHandle))
                    try self.check(sqlite3_reset(self._commitHandle))
                    try self.check(sqlite3_reset(self._rollbackHandle))
                }
                // BEGIN
                self.log("transaction: BEGIN DEFERRED TRANSACTION")
                try self.check(sqlite3_step(self._beginHandle))
                didBegin = true
                // EXECUTE
                try block()
            } catch SqliteResult.Error(let txErr) {
                if didBegin {
                    var didRollback = false
                    // ROLLBACK
                    do {
                        self.log("transaction: ROLLBACK TRANSACTION")
                        try self.check(sqlite3_step(self._rollbackHandle))
                        didRollback = true
                        self.log("transaction: rollback success")
                    } catch SqliteResult.Error(let e) {
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
                self.log("transaction: COMMIT TRANSACTION")
                try self.check(sqlite3_step(self._commitHandle))
                self.log("transaction: commit success")
            } catch SqliteResult.Error(let commitErr) {
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
        return result
    }
    
    private func execute(query: String) throws {
        log("execute: \(query)")
        try self.check(sqlite3_exec(self._handle, query, nil, nil, nil))
    }
    
    private func log(s: String) {
        print("[LocalSQLiteDB] \(s)")
    }
    
    public func exists() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        return result
    }
    
    public func create() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        
        dispatch_async(Q) {
            do {
                let flags = SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
                try self.check(sqlite3_open_v2(self.path, &self._handle, flags, nil))
            } catch SqliteResult.Error(let e) {
                self.log("Error opening sqlite database \(e)")
                result.error(Int(e.code), message: e.message)
                return
            } catch let e {
                self.log("Unknown error opening sqlite database \(e)")
                result.error(-1001, message: "\(e)")
                return
            }
            self.transaction({
                for stmt in self.createDatabaseStatements {
                    try self.execute(stmt)
                }
            }).success(AsyncCallback<Bool> { res in
                result.succeed(res)
                return res
            }).failure(AsyncCallback<AsyncError> { txErr in
                result.error(txErr.code, message: txErr.message)
                return txErr
            })
        }
        
        return result
    }
    
    public func info() -> AsyncResult<DatabaseInfo> {
        let result = AsyncResult<DatabaseInfo>()
        return result
    }
    
    public func ensureFullCommit() -> AsyncResult<Bool> {
        let result = AsyncResult<Bool>()
        return result
    }
    
    public func get<T: Document>(id: String, options: [String : [String]]?, returning: T.Type) -> AsyncResult<T?> {
        let result = AsyncResult<T?>()
        return result
    }
    
    public func put<T : Document>(doc: T, options: [String : [String]]?, returning: T.Type) -> AsyncResult<T> {
        let result = AsyncResult<T>()
        return result
    }
    
    public func allDocs<T : Document>(options: [String: [String]]?) -> AsyncResult<[T]> {
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
