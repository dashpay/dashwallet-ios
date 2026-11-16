//
//  VoteLimit.swift
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

/// One contest's local vote history reduced to what the casting rules read:
/// each masternode's live vote and how many casts it has spent.
///
/// The five-cast ceiling is applied by this one rule: looking only at the
/// live choice would offer exhausted nodes that Platform then rejects.
/// An unknown history (`nil`) answers `nil` to every query, never "no votes".
struct VoteLimit {
    /// `votes_allowed_per_masternode` in the platform version this app talks
    /// to; the sixth cast is refused with `MasternodeVotedTooManyTimesError`.
    static let maxCastsPerNode = 5

    private var latest: [Data: CastVoteRecord] = [:]
    private var casts: [Data: Int] = [:]

    /// Whether the history was read at all; `[]` is known, with no votes.
    let isKnown: Bool

    init(_ records: [CastVoteRecord]?) {
        isKnown = records != nil
        // One row per node per contest — a change overwrites the row it
        // came from — so the ceiling is read from the row's own
        // `castCount`, not from how many rows a node has. Counting rows
        // could never reach five.
        for record in records ?? [] {
            casts[record.proTxHash] = max(casts[record.proTxHash] ?? 0, record.castCount)
            if let seen = latest[record.proTxHash], seen.castAt >= record.castAt { continue }
            latest[record.proTxHash] = record
        }
    }

    /// This node's live choice, when it has one.
    func liveChoice(of node: Data) -> VoteChoice? {
        latest[node]?.choice
    }

    /// How many more votes Platform would accept from this node here.
    func votesLeft(_ node: Data) -> Int? {
        guard isKnown else { return nil }
        return max(0, Self.maxCastsPerNode - (casts[node] ?? 0))
    }

    /// The smallest `votesLeft` over `nodes`; `nil` when unknown or `nodes` is empty.
    func fewestVotesLeft(among nodes: Set<Data>) -> Int? {
        guard isKnown else { return nil }
        return nodes.compactMap { votesLeft($0) }.min()
    }

    func nodesWithVotesLeft(among nodes: Set<Data>) -> Set<Data>? {
        guard isKnown else { return nil }
        return nodes.filter { (votesLeft($0) ?? 0) > 0 }
    }

    /// Whether any node with a vote here holds `choice`; `nil` when unknown.
    func anyNode(holding choice: VoteChoice) -> Bool? {
        guard isKnown else { return nil }
        return latest.values.contains { $0.choice == choice }
    }

    /// The nodes of `nodes` whose live vote is `choice`, abstain included.
    func nodes(holding choice: VoteChoice, among nodes: Set<Data>) -> Set<Data>? {
        guard isKnown else { return nil }
        return nodes.filter { latest[$0]?.choice == choice }
    }

    /// The live choices of `nodes` that fill a pill, for marking "my vote" on
    /// a list row. Abstain has no pill and is left out.
    func filledChoices(of nodes: Set<Data>) -> Set<VoteChoice>? {
        guard isKnown else { return nil }
        return Set(nodes.compactMap { latest[$0]?.choice }.filter { $0 != .abstain })
    }

    /// Whether `node`'s live vote was cast at `date` or later.
    func hasCast(of node: Data, since date: Date) -> Bool {
        guard let castAt = latest[node]?.castAt else { return false }
        return castAt >= date
    }

    /// One more cast by `node`, as the store records it. It becomes the live
    /// choice unless the node already holds a later one.
    mutating func recordCast(of node: Data, on normalizedLabel: String, choice: VoteChoice, at date: Date) {
        casts[node, default: 0] += 1
        if let seen = latest[node], seen.castAt > date { return }
        latest[node] = CastVoteRecord(
            proTxHash: node,
            normalizedLabel: normalizedLabel,
            choice: choice,
            castAt: date,
            castCount: casts[node] ?? 1)
    }
}
