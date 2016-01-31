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
    
    private func prepare(query: String, inout handle: COpaquePointer) throws {
        log("prepare: \(query)")
        try check(sqlite3_prepare_v2(self._handle, query, -1, &handle, nil))
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
    
    private func log(s: String) {
        print("[LocalSQLiteDB] \(s)")
    }
    
    // PRAGMA MARK - API helper functions
    
    private var _countHandle: COpaquePointer = nil // counts all documents in storage
    
    func countDocs() -> AsyncResult<Int> {
        let result = AsyncResult<Int>()
        transaction({
            if self._countHandle == nil {
                let sql =
                    "SELECT COUNT(document_store.id) AS num " +
                    "FROM document_store " +
                    "JOIN by_sequence " +
                    "ON by_sequence.seq = document_store.winningseq " +
                    "WHERE by_sequence.deleted = 0"
                try self.prepare(sql, handle: &self._countHandle)
            }
            defer {
                _ = try? self.finalize(self._countHandle)
            }
            try self.reset(self._countHandle)
            if try self.step(self._countHandle) == SQLITE_ROW {
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
