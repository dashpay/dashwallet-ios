//
//  VoteHistoryDAO.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
@preconcurrency import SQLite

// MARK: - CastVoteRecord

/// A vote this device cast with one of the wallet's masternodes.
///
/// Records what *we* did, not what Platform holds. Platform is the authority on
/// tallies, but it cannot cheaply answer "which of my nodes already voted
/// here": `getContestedResourceVotersForIdentity` is per contender, keyed by
/// voter identity, and cannot see abstain or lock voters at all. Voting one
/// node at a time needs that answer on every tap, so it is kept locally.
struct CastVoteRecord: Hashable {
    /// Raw wire byte order, matching `PlatformMasternode.proTxHash`.
    let proTxHash: Data
    let normalizedLabel: String
    let choice: VoteChoice
    let castAt: Date
}

// MARK: - VoteHistoryDAO

protocol VoteHistoryDAO {
    /// Upsert — a node re-voting on the same contest replaces its own row,
    /// mirroring Platform, where a masternode has one live vote per poll.
    func record(_ record: CastVoteRecord, network: String) async
    /// Votes this device cast on one contest, newest first.
    func votes(forContest normalizedLabel: String, network: String) async -> [CastVoteRecord]
    /// Every contest this device has voted on, mapped to its vote count.
    /// One query for the whole list screen rather than one per row.
    func voteCountsByContest(network: String) async -> [String: Int]
    func deleteAll()
}

// MARK: - VoteHistoryDAOImpl

actor VoteHistoryDAOImpl: VoteHistoryDAO {
    static let shared = VoteHistoryDAOImpl()

    private nonisolated var db: Connection { DatabaseConnection.shared.db }

    private init() {}

    func record(_ record: CastVoteRecord, network: String) async {
        let query = """
            INSERT INTO masternode_vote_history
                (proTxHash, normalizedLabel, network, choice, contenderIdentityId, castAt)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (proTxHash, normalizedLabel, network) DO UPDATE SET
                choice = excluded.choice,
                contenderIdentityId = excluded.contenderIdentityId,
                castAt = excluded.castAt
        """
        let bindings: [Binding?] = [
            Blob(bytes: [UInt8](record.proTxHash)),
            record.normalizedLabel,
            network,
            record.choice.storageKind,
            record.choice.storageContenderId,
            Int64(record.castAt.timeIntervalSince1970 * 1000),
        ]

        do {
            try db.run(query, bindings)
        } catch {
            DWLogger.log("VoteHistoryDAO: record failed: \(error)")
        }
    }

    func votes(forContest normalizedLabel: String, network: String) async -> [CastVoteRecord] {
        let query = """
            SELECT proTxHash, normalizedLabel, choice, contenderIdentityId, castAt
            FROM masternode_vote_history
            WHERE normalizedLabel = ? AND network = ?
            ORDER BY castAt DESC
        """
        do {
            // `prepare` yields positional `[Binding?]` rows, which is what a
            // hand-written SELECT needs; `Row` subscripting is for typed
            // `Expression` columns.
            return try db.prepare(query, [normalizedLabel, network]).compactMap { row -> CastVoteRecord? in
                guard let blob = row[0] as? Blob,
                      let label = row[1] as? String,
                      let kind = row[2] as? String,
                      let castAt = row[4] as? Int64,
                      let choice = VoteChoice(storageKind: kind, contenderId: row[3] as? String)
                else { return nil }
                return CastVoteRecord(
                    proTxHash: Data(blob.bytes),
                    normalizedLabel: label,
                    choice: choice,
                    castAt: Date(timeIntervalSince1970: Double(castAt) / 1000))
            }
        } catch {
            DWLogger.log("VoteHistoryDAO: votes(forContest:) failed: \(error)")
            return []
        }
    }

    func voteCountsByContest(network: String) async -> [String: Int] {
        let query = """
            SELECT normalizedLabel, COUNT(*)
            FROM masternode_vote_history
            WHERE network = ?
            GROUP BY normalizedLabel
        """
        do {
            var counts: [String: Int] = [:]
            for row in try db.prepare(query, [network]) {
                guard let label = row[0] as? String, let count = row[1] as? Int64 else { continue }
                counts[label] = Int(count)
            }
            return counts
        } catch {
            DWLogger.log("VoteHistoryDAO: voteCountsByContest failed: \(error)")
            return [:]
        }
    }

    nonisolated func deleteAll() {
        do {
            try db.run("DELETE FROM masternode_vote_history")
        } catch {
            DWLogger.log("VoteHistoryDAO: deleteAll failed: \(error)")
        }
    }
}

// MARK: - VoteChoice storage

extension VoteChoice {
    /// Stored as a discriminator plus an optional id rather than a formatted
    /// string, so reading it back is a lookup instead of prefix-parsing.
    var storageKind: String {
        switch self {
        case .towards: return "towards"
        case .abstain: return "abstain"
        case .lock: return "lock"
        }
    }

    var storageContenderId: String? {
        if case .towards(let identityId) = self { return identityId }
        return nil
    }

    init?(storageKind: String, contenderId: String?) {
        switch storageKind {
        case "towards":
            guard let contenderId else { return nil }
            self = .towards(identityId: contenderId)
        case "abstain":
            self = .abstain
        case "lock":
            self = .lock
        default:
            return nil
        }
    }
}
