//
//  Utils.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/31/16.
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


// KeyTree = [Path ... ]
// Path = {pos: position_from_root, ids: Tree}
// Tree = [Key, Opts, [Tree, ...]], in particular single node: [Key, []]
struct KT {
    enum Status: CustomStringConvertible {
        case Available
        case Deleted
        
        init?(string: String) {
            switch string {
            case "available":
                self = .Available
            case "deleted":
                self = .Deleted
            default:
                return nil
            }
        }
        
        var description: String {
            switch self {
            case .Available:
                return "available"
            case .Deleted:
                return "deleted"
            }
        }
    }
    
    struct Tree {
        let key: String
        let status: Status
        let branches: [Tree]
    }
    
    struct Path {
        let pos: Int
        let ids: Tree
    }
    
    typealias KeyTree = [Path]
}

// DocumentMetadata describes data about a given document
class DocumentMetadata: DocumentLoading {
    // id is the id of the document being described
    //
    // key: id
    // json type: string
    var id: String
    
    // revTree is the KeyTree used to descrie the versions of the document
    //
    // key: rev_tree
    // json type: array[subtype_pos]
    // json subtype_pos: dictionary -> {pos: int, ids: subtype_tree}
    // json subtype_tree: dictionary -> {id: string, status: string, branches: array[subtype]}
    var revTree: KT.KeyTree
    
    // seq is the...
    // key: seq
    // json type: whole number
    var seq: Int
    
    required init(json: AnyObject?) throws {
        let j = json as! NSDictionary
        id = j["id"] as! String
        seq = (j["seq"] as! NSNumber).integerValue
        func deserializeKeyTree(d: NSDictionary) -> KT.Tree {
            var branches: [KT.Tree] = []
            if let branchJA = d["branches"] as? NSArray {
                for branchJ in branchJA {
                    branches.append(deserializeKeyTree(branchJ as! NSDictionary))
                }
            }
            return KT.Tree(
                key: d["id"] as! String,
                status: KT.Status(string: d["status"] as! String)!,
                branches: branches)
        }
        revTree = (j["rev_tree"] as! NSArray).map({ (t) -> KT.Path in
            let tj = t as! NSDictionary
            let pos = (tj["pos"] as! NSNumber).integerValue
            let ids = deserializeKeyTree(tj["ids"] as! NSDictionary)
            return KT.Path(pos: pos, ids: ids)
        })
    }
    
    func dump() throws -> NSData {
        return try! NSJSONSerialization.dataWithJSONObject(dict(), options: [])
    }
    
    func dict() -> [String: AnyObject] {
        var ret = [String: AnyObject]()
        ret["id"] = id
        ret["seq"] = NSNumber(integer: seq)
        
        func dumpTree(tree: KT.Tree) -> NSDictionary {
            var ret = [String: AnyObject]()
            ret["id"] = tree.key
            ret["status"] = String(tree.status)
            ret["branches"] = tree.branches.map(dumpTree)
            return ret as NSDictionary
        }
        
        ret["rev_tree"] = revTree.map({ (path) -> NSDictionary in
            var ret = [String: AnyObject]()
            ret["pos"] = NSNumber(integer: path.pos)
            ret["ids"] = dumpTree(path.ids)
            return ret as NSDictionary
        })
        return ret
    }
    
    // get the winning revision
    func winningRev() -> String {
        var revs = revTree
        var winningId: String? = nil
        var winningPos: Int = -1
        var winningDeleted = false
        while let node = revs.popLast() {
            if node.ids.branches.count > 0 { // not a leaf
                for branch in node.ids.branches {
                    revs.insert(KT.Path(pos: node.pos + 1, ids: branch), atIndex: 0)
                }
            } else {
                let deleted = node.ids.status == .Deleted
                let currentNodeShouldWin = (
                    winningDeleted != deleted ? winningDeleted
                        : winningPos != node.pos ? winningPos < node.pos
                        : winningId < node.ids.key
                )
                if (winningId == nil || currentNodeShouldWin) {
                    winningId = node.ids.key
                    winningPos = node.pos
                    winningDeleted = deleted
                }
            }
        }
        return "\(winningPos)-\(winningId!)"
    }
    
    // check if a given revision is deleted given the metadata object from the database, and optionally a revision
    // (defaults to winning revision)
    func isDeleted(revision: String? = nil) -> Bool {
        let useRev = revision == nil ? winningRev() : revision!
        let id = useRev.substringToIndex(useRev.rangeOfString("-")!.startIndex)
        var trees = revTree.map { (p) -> KT.Tree in return p.ids }
        while let t = trees.popLast() {
            if t.key == id {
                return t.status == .Deleted
            }
            var treesNew = trees;
            treesNew.appendContentsOf(t.branches)
            trees = treesNew
        }
        return false
    }
}
