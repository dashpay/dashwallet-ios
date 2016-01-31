//
//  Replicator.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


public struct ReplicationStep<T> {
    let fn: (T) -> AsyncResult<T>
}

public class Replicator {
    let source: ReplicationClient
    let destination: ReplicationClient
    public var running: Bool = false
    
    public struct ReplicationConfig {
        let id: String = NSUUID().UUIDString
        let batchSize: Int = 100
        let maxRequests: Int = 4
        let heartbeat: Int = 10 // sec
        let docIds: [String] = [String]()
        let queryParams: [String: [String]] = [String: [String]]()
        let filter: String? = nil
        let continuous: Bool = false
    }
    
    public struct ReplicationState {
        let config: ReplicationConfig = ReplicationConfig()
        
        var id: String = ""
        var idVersion: Int = 3
        
        let sessionId: String = NSUUID().UUIDString
        let startTime: NSDate = NSDate()
        var missingChecked: Int = 0
        var missingFound: Int = 0
        var docsRead: Int = 0
        var docsWritten: Int = 0
        var docsWriteFailures: Int = 0
        var startLastSeq: Int = -1 // -1 == no previous start
        var endLastSeq: Int = -1
        var recordedSeq: Int = -1
        
        var sourceInfo: DatabaseInfo? = nil
        var destinationInfo: DatabaseInfo? = nil
        
        var sourceReplicationLog: ReplicationLog? = nil
        var destinationReplicationLog: ReplicationLog? = nil
        
        var docs: [DefaultDocument] = [DefaultDocument]()
        var uploadedDocs: [DefaultDocument] = [DefaultDocument]()
        var changedDocs: [RevisionDiff] = [RevisionDiff]()
        
        func changedDoc(id: String) -> RevisionDiff? {
            for rd in changedDocs {
                if rd.id == id {
                    return rd
                }
            }
            return nil
        }
    }
    
    public class ReplicationItem: DefaultDocument {
        var sessionId: String!
        var startTime: String! // iso-8601 date
        var endTime: String! // iso-8601 date
        var missingChecked: Int!
        var missingFound: Int!
        var docsRead: Int!
        var docsWritten: Int!
        var docWriteFailures: Int!
        var startLastSeq: Int!
        var recordedSeq: Int!
        var endLastSeq: Int!
        
        public override func load(json: NSDictionary) {
            sessionId = json["session_id"] as! String
            startTime = json["start_time"] as! String
            endTime = json["end_time"] as! String
            missingChecked = (json["missing_checked"] as! NSNumber).integerValue
            missingFound = (json["missing_found"] as! NSNumber).integerValue
            docsRead = (json["docs_read"] as! NSNumber).integerValue
            docsWritten = (json["docs_written"] as! NSNumber).integerValue
            docWriteFailures = (json["doc_write_failures"] as! NSNumber).integerValue
            startLastSeq = (json["start_last_seq"] as! NSNumber).integerValue
            recordedSeq = (json["recorded_seq"] as! NSNumber).integerValue
            endLastSeq = (json["end_last_seq"] as! NSNumber).integerValue
        }
        
        public override func dict() -> [String: AnyObject] {
            var d = [String: AnyObject]()
            d["_id"] = _id
            if _rev != "" {
                d["_rev"] = _rev
            }
            d["session_id"] = sessionId
            d["start_time"] = startTime
            d["end_time"] = endTime
            d["missing_checked"] = NSNumber(integer: missingChecked)
            d["missing_found"] = NSNumber(integer: missingFound)
            d["docs_read"] = NSNumber(integer: docsRead)
            d["docs_written"] = NSNumber(integer: docsWritten)
            d["doc_write_failures"] = NSNumber(integer: docWriteFailures)
            d["start_last_seq"] = NSNumber(integer: startLastSeq)
            d["recorded_seq"] = NSNumber(integer: recordedSeq)
            d["end_last_seq"] = NSNumber(integer: endLastSeq)
            return d
        }
        
        public override func dump(json: [String : AnyObject]) -> [String : AnyObject] {
            return dict()
        }
    }
    
    public class ReplicationLog: DefaultDocument {
        var sessionId: String!
        var replicationIdVersion: Int!
        var sourceLastSeq: Int!
        var history: [ReplicationItem]!
        
        public override func load(json: NSDictionary) {
            sessionId = json["session_id"] as! String
            replicationIdVersion = (json["replication_id_version"] as! NSNumber).integerValue
            sourceLastSeq = (json["source_last_seq"] as! NSNumber).integerValue
            history = (json["history"] as! [AnyObject]).map({ (historyJson) -> ReplicationItem in
                return try! ReplicationItem(json: historyJson)
            })
        }
        
        public override func dump(json: [String : AnyObject]) -> [String : AnyObject] {
            var d = json
            d["history"] = history.map({ (historyItem) -> NSDictionary in return historyItem.dict() })
            d["session_id"] = sessionId
            d["replication_id_version"] = replicationIdVersion
            d["source_last_seq"] = NSNumber(integer: sourceLastSeq)
            return d
        }
    }
    
    // Ensure that both source and destination databases exist via parallel .exists() requests
    public var verifyPeers: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("begin verify peers")
            let result = AsyncResult<ReplicationState>()
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                let dgroup = dispatch_group_create()
                var exists = ["source": false, "destination": false]
                
                dispatch_group_enter(dgroup); dispatch_group_enter(dgroup)
                
                dispatch_apply(2, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { (i) -> Void in
                    let c = i == 0 ? self.source : self.destination
                    let n = (i == 0 ? "source" : "destination")
                    c.exists().success(AsyncCallback<Bool> { doesExist in
                        self.log("verify peers - \(n) exists=\(doesExist)")
                        if doesExist {
                            exists[n] = true
                        }
                        dispatch_group_leave(dgroup)
                        return doesExist
                        }).failure(AsyncCallback<AsyncError> { existsError in
                            self.log("verify peers - exists error = \(existsError)")
                            dispatch_group_leave(dgroup)
                            return existsError
                            })
                })
                
                dispatch_group_notify(dgroup, dispatch_get_main_queue(), { () -> Void in
                    if exists["source"]! && exists["destination"]! {
                        result.succeed(replState)
                    } else {
                        result.error(404, message: "both source and destination must exist")
                    }
                })
            })
            
            return result
        }
    }
    
    // Loads the .info() results (DatabaseInfo object) into the ReplicationState for source and destination
    public var getPeersInformation: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("getting peers information")
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                let dgroup = dispatch_group_create()
                dispatch_group_enter(dgroup); dispatch_group_enter(dgroup)
                dispatch_apply(2, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { (i) -> Void in
                    let c = i == 0 ? self.source : self.destination
                    c.info().success(AsyncCallback<DatabaseInfo> { dbInfo in
                        if i == 0 {
                            self.log("got source info")
                            retReplState.sourceInfo = dbInfo
                        } else {
                            self.log("got destination info")
                            retReplState.destinationInfo = dbInfo
                        }
                        dispatch_group_leave(dgroup)
                        return dbInfo
                        }).failure(AsyncCallback<AsyncError> { infoFailure in
                            self.log("error getting database info \(infoFailure)")
                            dispatch_group_leave(dgroup)
                            return infoFailure
                            })
                })
                dispatch_group_notify(dgroup, dispatch_get_main_queue(), { () -> Void in
                    if retReplState.sourceInfo == nil || retReplState.destinationInfo == nil {
                        result.error(-1001, message: "could not retrieve both source and destination info()")
                    } else {
                        result.succeed(retReplState)
                    }
                })
            })
            
            return result
        }
    }
    
    // Generate a unique identifier for this replication session
    public var generateReplicationId: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("generating replication id")
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            var idParts = [replState.config.id, self.source.id, self.destination.id]
            
            // retrieves the javascript function body for a given filter name
            func getFilter(filterSpec: String?) -> AsyncResult<String?> {
                self.log("getting filter \(filterSpec)")
                let gfresult = AsyncResult<String?>()
                if let filterSpec = filterSpec {
                    let designDocNameParts = filterSpec.componentsSeparatedByString("/")
                    if designDocNameParts.count < 2 { // invalid filter spec
                        gfresult.succeed(nil)
                        return gfresult
                    }
                    let designDocName = designDocNameParts[0]
                    let filterName = designDocNameParts[1]
                    self.source.get("_design/" + designDocName, options: nil, returning: DesignDocument.self)
                        .success(AsyncCallback<DesignDocument?> { designDoc in
                            self.log("got design doc for \(designDocName)")
                            if let designDoc = designDoc, filters = designDoc.filters, filter = filters[filterName] {
                                gfresult.succeed(filter)
                            } else {
                                gfresult.succeed(nil)
                            }
                            
                            return designDoc
                            })
                        .failure(AsyncCallback<AsyncError> { designDocError in
                            // dont care about an error here
                            self.log("failed to get design doc for \(designDocName)")
                            gfresult.succeed(nil)
                            return designDocError
                            })
                } else {
                    gfresult.succeed(nil)
                }
                
                return gfresult
            }
            
            getFilter(replState.config.filter).success(AsyncCallback<String?> { filterValue in
                if let filterValue = filterValue {
                    idParts.append(filterValue)
                }
                if replState.config.queryParams.count > 0 {
                    idParts.append(replState.config.queryParams.description)
                }
                if replState.config.docIds.count > 0 {
                    idParts.append(replState.config.docIds.description)
                }
                self.log("replication id parts = \(idParts)")
                retReplState.id = idParts.joinWithSeparator("").MD5()
                self.log("replication id = \(retReplState.id)")
                result.succeed(retReplState)
                return filterValue
                })
            
            return result
        }
    }
    
    // Determines the startup checkpoint if the replication state is being reused
    public var findCommonAncestry: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("begin find common ancestry")
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
                let dgroup = dispatch_group_create()
                var docs: [String: ReplicationLog?] = ["source": nil, "destination": nil]
                dispatch_group_enter(dgroup); dispatch_group_enter(dgroup)
                
                // fetch replication logs
                dispatch_apply(2, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { i in
                    let c = i == 0 ? self.source : self.destination
                    let n = i == 0 ? "source" : "destination"
                    c.get("_local/" + replState.id, options: nil, returning: ReplicationLog.self)
                        .success(AsyncCallback<ReplicationLog?> { log in
                            if let l = log {
                                self.log("repl log for \(n) found, sourceLastSeq=\(l.sourceLastSeq)")
                            } else {
                                self.log("repl log for \(n) not found")
                            }
                            docs[n] = log // it's ok for this to be nil
                            dispatch_group_leave(dgroup)
                            return log
                            })
                        .failure(AsyncCallback<AsyncError> { logErr in
                            self.log("error retrieving repl log for \(n)")
                            dispatch_group_leave(dgroup)
                            return logErr
                            })
                }
                
                dispatch_group_notify(dgroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
                    retReplState.destinationReplicationLog = docs["destination"]!
                    retReplState.sourceReplicationLog = docs["source"]!
                    guard let destLog = retReplState.destinationReplicationLog,
                        sourceLog = retReplState.sourceReplicationLog else {
                            // there is no common history - force full replication
                            self.log("no common history found - missing repl doc - forcing full replication")
                            result.succeed(retReplState)
                            return
                    }
                    // we are already at the most recent seq
                    if destLog.sessionId == sourceLog.sessionId {
                        self.log("find common ancestry - already at most recent seq \(sourceLog.sourceLastSeq)")
                        retReplState.startLastSeq = sourceLog.sourceLastSeq
                        result.succeed(retReplState)
                        return
                    }
                    // find the most recent common seq
                    let histories = sourceLog.history.filter({ (histItem) -> Bool in
                        let destHistories = destLog.history.filter({ (destHistItem) -> Bool in
                            return destHistItem.sessionId == histItem.sessionId
                        })
                        return destHistories.count > 0
                    })
                    guard histories.count > 0 else { // there is no common history - force full replication
                        self.log("no common history found - forcing full replication")
                        result.succeed(retReplState)
                        return
                    }
                    self.log("common history found - startSeq = \(retReplState.startLastSeq)")
                    retReplState.startLastSeq = histories[0].recordedSeq
                    result.succeed(retReplState)
                }
            }
            
            return result
        }
    }
    
    // Get all documents since the last checkpoint
    public var locateChangedDocs: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("begin locate changed docs")
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            // get the options object together
            var changeOptions: [String: [String]] = [
                "style": ["all_docs"],
                "limit": [String(replState.config.batchSize)]
            ]
            if replState.startLastSeq != -1 { changeOptions["since"] = [String(replState.startLastSeq)] }
            if replState.endLastSeq != -1 { changeOptions["since"] = [String(replState.endLastSeq)] }
            if replState.config.continuous {
                changeOptions["feed"] = ["continuous"]
                changeOptions["heartbeat"] = [String(replState.config.heartbeat)]
            }
            if let f = replState.config.filter { changeOptions["filter"] = [f] }
            if replState.config.queryParams.count > 0 {
                changeOptions["query_params"] = [String(replState.config.queryParams)]
            }
            if replState.config.docIds.count > 0 {
                changeOptions["doc_ids"] = replState.config.docIds
            }
            
            // fetch changes from source database
            self.source.changes(changeOptions).success(AsyncCallback<Changes> { changes in
                self.log("successfully got changes lastSeq = \(changes.lastSeq)")
                retReplState.endLastSeq = changes.lastSeq
                
                guard changes.results.count > 0 else {
                    self.log("no changes found")
                    result.succeed(retReplState)
                    return changes
                }
                // amount of checked revisions on source
                retReplState.missingChecked = changes.results.reduce(0, combine: { (i, chng) -> Int in
                    return i + chng.changes.count
                })
                self.log("there are \(retReplState.missingChecked) docs")
                
                var revs = [String: [String]]()
                for chng in changes.results {
                    revs[chng.id] = chng.changes.map({ (changeBit) -> String in
                        return changeBit["rev"]!
                    })
                }
                for (id, rev) in revs {
                    for r in rev {
                        self.log("changed doc id=\(id) rev=\(r)")
                    }
                }
                // find revisions the destination is missing
                self.destination.revsDiff(revs, options: nil).success(AsyncCallback<[RevisionDiff]> { diffs in
                    retReplState.changedDocs = diffs
                    // amount of missing revisions on source
                    retReplState.missingFound = diffs.reduce(0, combine: { (i, d) -> Int in
                        return i + d.misssing.count
                    })
                    self.log("found missing \(retReplState.missingFound) docs")
                    result.succeed(retReplState)
                    return diffs
                    }).failure(AsyncCallback<AsyncError> { revsError in
                        self.log("error fetching rev diffs \(revsError)")
                        result.error(revsError.code, message: revsError.message)
                        return revsError
                        })
                
                return changes
                }).failure(AsyncCallback<AsyncError> { changeError in
                    self.log("error fetching changes \(changeError)")
                    result.error(changeError.code, message: changeError.message)
                    return changeError
                    })
            
            return result
        }
    }
    
    // retrieve documents that have changed from the source
    public var fetchChangedDocs: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("begin fetch changed docs")
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            retReplState.docs = [DefaultDocument]()
            guard retReplState.changedDocs.count > 0 else {
                self.log("changed docs count is 0, nothing to do...")
                result.succeed(retReplState) // nothing to do if there are no changed docs
                return result
            }
            let missingIds = retReplState.changedDocs.map({ (rev) -> String in
                return rev.id
            })
            guard missingIds.count > 0 else {
                self.log("missing ids is 0, nothing to do...")
                result.succeed(retReplState) // nothing to do if there are no missing ids
                return result
            }
            
            func fetch(id: String) -> AsyncResult<DefaultDocument?> {
                let omissing = replState.changedDoc(id)?.misssing ?? []
                let orevsj = try! NSJSONSerialization.dataWithJSONObject(omissing, options: [])
                let orevs = NSString(data: orevsj, encoding: NSUTF8StringEncoding) as! String
                let opts = ["revs": ["true"], "attachments": ["true"], "latest": ["true"], "open_revs": [orevs]]
                return self.source.get(id, options: opts, returning: DefaultDocument.self)
            }
            
            func fetchSingleDocuments(ids: [String]) -> AsyncResult<[DefaultDocument]> {
                let docsResult = AsyncResult<[DefaultDocument]>()
                var docs = [DefaultDocument]()
                
                let fetchOpQ = NSOperationQueue()
                fetchOpQ.maxConcurrentOperationCount = retReplState.config.maxRequests
                let grp = dispatch_group_create()
                
                for did in ids {
                    self.log("fetch chnaged docs - fetching doc id=\(did)")
                    dispatch_group_enter(grp)
                    fetchOpQ.addOperationWithBlock() {
                        fetch(did).success(AsyncCallback<DefaultDocument?> { doc in
                            if let doc = doc {
                                objc_sync_enter(docs)
                                self.log("fetch changed docs - doc found id=\(did)")
                                if doc.isMany {
                                    for i in 0..<doc.manyCount {
                                        docs.append(doc.objectAtIndex(i) as! DefaultDocument)
                                    }
                                } else {
                                    docs.append(doc)
                                }
                                objc_sync_exit(docs)
                            } else {
                                self.log("fetch changed docs - doc not found id=\(did)")
                            }
                            dispatch_group_leave(grp)
                            return doc
                            }).failure(AsyncCallback<AsyncError> { docErr in
                                // uhhh... try to figure out what to do here
                                self.log("fetch changed docs - individual doc fetch error \(docErr)")
                                dispatch_group_leave(grp)
                                return docErr
                                })
                    }
                }
                
                dispatch_group_notify(grp, dispatch_get_main_queue()) {
                    docsResult.succeed(docs)
                }
                
                return docsResult
            }
            
            // TODO: optimization for first generation documents - fetch from bulkDocs
            
            fetchSingleDocuments(missingIds).success(AsyncCallback<[DefaultDocument]> { docs in
                retReplState.docs = docs
                retReplState.docsRead += docs.count
                result.succeed(retReplState)
                return docs
                }).failure(AsyncCallback<AsyncError> { docsErr in
                    result.error(docsErr.code, message: docsErr.message)
                    return docsErr
                    })
            
            return result
        }
    }
    
    // upload changed documents to destination
    public var uploadDocuments: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("begin upload documents")
            let result = AsyncResult<ReplicationState>()
            guard replState.docs.count > 0 else {
                self.log("no documents to upload")
                result.succeed(replState)
                return result
            }
            
            self.destination.bulkDocs(replState.docs, options: ["new_edits": false])
                .success(AsyncCallback<[Bool]> { bulkResults in
                    self.log("finished upload documents results=\(bulkResults)")
                    var retReplState = replState
                    // TODO: update doc write failures
                    retReplState.docsWritten += bulkResults.count
                    retReplState.uploadedDocs = retReplState.docs
                    result.succeed(retReplState)
                    return bulkResults
                    }).failure(AsyncCallback<AsyncError> { bulkErr in
                        self.log("upload documents error \(bulkErr)")
                        result.error(bulkErr.code, message: bulkErr.message)
                        return bulkErr
                        })
            
            return result
        }
    }
    
    // ensure the destination has fully committed its state
    public var ensureFullCommit: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("begin ensure full commit")
            let result = AsyncResult<ReplicationState>()
            self.destination.ensureFullCommit().success(AsyncCallback<Bool> { ok in
                self.log("full commit ok=\(ok)")
                if ok {
                    result.succeed(replState)
                } else {
                    result.error(-1001, message: "database did not report an ok result for full commit")
                }
                return ok
                }).failure(AsyncCallback<AsyncError> { okErr in
                    self.log("ensure full commit error \(okErr)")
                    result.error(okErr.code, message: okErr.message)
                    return okErr
                    })
            return result
        }
    }
    
    // save the replication state document to _local to both destination and source
    public var recordReplicationCheckpoint: ReplicationStep<ReplicationState> {
        return ReplicationStep<ReplicationState> { replState in
            self.log("begin record replication checkpoint")
            let result = AsyncResult<ReplicationState>()
            var retReplState = replState
            
            let newReplItem = try! ReplicationItem(json: nil)
            newReplItem.sessionId = replState.sessionId
            newReplItem.startTime = replState.startTime.description
            newReplItem.endTime = NSDate().description
            newReplItem.missingChecked = replState.missingChecked
            newReplItem.missingFound = replState.missingFound
            newReplItem.docsRead = replState.docsRead
            newReplItem.docsWritten = replState.docsWritten
            newReplItem.docWriteFailures = replState.docsWriteFailures
            newReplItem.startLastSeq = replState.startLastSeq
            newReplItem.recordedSeq = replState.endLastSeq
            newReplItem.endLastSeq = replState.endLastSeq
            
            if retReplState.sourceReplicationLog == nil {
                retReplState.sourceReplicationLog = try! ReplicationLog(json: nil)
            }
            if retReplState.destinationReplicationLog == nil {
                retReplState.destinationReplicationLog = try! ReplicationLog(json: nil)
            }
            
            func saveReplDoc(db: ReplicationClient, d: ReplicationLog) -> AsyncResult<ReplicationLog> {
                d._id = "_local/" + replState.id
                d.replicationIdVersion = replState.idVersion
                d.sessionId = newReplItem.sessionId
                d.sourceLastSeq = newReplItem.recordedSeq
                d.history = [ReplicationItem]()
                d.history.insert(newReplItem, atIndex: 0)
                return db.put(d, options: nil, returning: ReplicationLog.self)
            }
            
            let dgrp = dispatch_group_create()
            let saves = [
                (self.source, retReplState.sourceReplicationLog!, "source"),
                (self.destination, retReplState.destinationReplicationLog!, "dest")
            ]
            
            for (db, d, loc) in saves {
                dispatch_group_enter(dgrp)
                saveReplDoc(db, d: d)
                    .success(AsyncCallback<ReplicationLog> { replLog in
                        dispatch_group_leave(dgrp)
                        self.log("saved \(loc) replication log")
                        if loc == "source" {
                            retReplState.sourceReplicationLog!._rev = replLog._rev
                        } else {
                            retReplState.destinationReplicationLog!._rev = replLog._rev
                        }
                        return replLog
                        })
                    .failure(AsyncCallback<AsyncError> { replErr in
                        dispatch_group_leave(dgrp)
                        self.log("save replication doc error \(replErr)")
                        return replErr
                        })
            }
            
            dispatch_group_notify(dgrp, dispatch_get_main_queue()) {
                retReplState.recordedSeq = retReplState.endLastSeq
                result.succeed(retReplState)
            }
            
            return result
        }
    }
    
    public init(source s: ReplicationClient, destination d: ReplicationClient) {
        source = s
        destination = d
    }
    
    public func performSteps<T>(arg: T, steps: [ReplicationStep<T>]) -> AsyncResult<T> {
        let result = AsyncResult<T>()
        
        var steps = Array(steps.reverse())
        var prevResult: T = arg
        func doStep() {
            if let step = steps.popLast() {
                step.fn(prevResult).success(AsyncCallback<T> { newResult in
                    prevResult = newResult
                    dispatch_async(dispatch_get_main_queue()) {
                        doStep()
                    }
                    return newResult
                    }).failure(AsyncCallback<AsyncError> { newError in
                        // send error directly without calling doStep() again
                        result.error(newError.code, message: newError.message)
                        return newError
                        })
            } else {
                result.succeed(prevResult)
            }
        }
        doStep()
        
        return result
    }
    
    public func prepare() -> AsyncResult<ReplicationState> {
        let replState = ReplicationState()
        let result = AsyncResult<ReplicationState>()
        let steps = [
            verifyPeers,
            getPeersInformation,
            generateReplicationId,
            findCommonAncestry
        ]
        self.log("begin prepare")
        performSteps(replState, steps: steps).success(AsyncCallback<ReplicationState> { replState in
            result.succeed(replState)
            self.log("end prepare")
            return replState
            }).failure(AsyncCallback<AsyncError> { replErr in
                self.log("end prepare failure = \(replErr)")
                return replErr
                })
        return result
    }
    
    public func replicate(state: ReplicationState) -> AsyncResult<ReplicationState> {
        let result = AsyncResult<ReplicationState>()
        var replicatedOnce = false
        var lastMissingChecked = state.missingChecked
        
        func _replicate(replState: ReplicationState) {
            let replResult = AsyncResult<ReplicationState>()
            let steps = [
                locateChangedDocs,
                fetchChangedDocs,
                uploadDocuments,
                ensureFullCommit,
                recordReplicationCheckpoint
            ]
            self.log("begin replicate lastMissingChecked = \(lastMissingChecked)")
            performSteps(replState, steps: steps).success(AsyncCallback<ReplicationState> { updatedReplState in
                if replicatedOnce && updatedReplState.missingChecked < 1 {
                    // no changes
                    self.log("replicated once with no changes detected")
                    result.succeed(updatedReplState)
                    return updatedReplState
                }
                if replicatedOnce && lastMissingChecked == updatedReplState.missingChecked {
                    // something else happend... but whaat?
                    // TODO: what to do here?
                    self.log("replicaed once with lastMissingChecked==replState.missingChecked \(lastMissingChecked)")
                    result.succeed(updatedReplState)
                    return updatedReplState
                }
                replicatedOnce = true
                lastMissingChecked = updatedReplState.missingChecked
                self.log("replicated with lastMissingChecked = \(lastMissingChecked) continuing...")
                _replicate(updatedReplState)
                return updatedReplState
                }).failure(AsyncCallback<AsyncError> { stepsErr in
                    self.log("replicate error \(stepsErr)")
                    replResult.error(stepsErr.code, message: stepsErr.message)
                    return stepsErr
                    })
        }
        _replicate(state)
        return result
    }
    
    public func start() -> AsyncResult<ReplicationState> {
        self.log("starting replication")
        let result = AsyncResult<ReplicationState>()
        prepare().success(AsyncCallback<ReplicationState> { replState in
            self.replicate(replState).success(AsyncCallback<ReplicationState> { doneReplState in
                result.succeed(doneReplState)
                self.log("replication finished")
                return doneReplState
                }).failure(AsyncCallback<AsyncError> { doneReplStateErr in
                    result.error(doneReplStateErr.code, message: doneReplStateErr.message)
                    return doneReplStateErr
                    })
            return replState
            })
        return result
    }
    
    private func log(s: String) {
        print("[Replicator] \(s)")
    }
}
