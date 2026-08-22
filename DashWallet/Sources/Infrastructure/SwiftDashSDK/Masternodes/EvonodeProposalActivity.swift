//
//  EvonodeProposalActivity.swift
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

// MARK: - EvonodeProposalActivity

/// Longitudinal view of each owned evonode's block proposals, derived from
/// the per-epoch tallies the monitor fetches over time. Platform only
/// reports totals per epoch, not when each block was proposed, so "has this
/// node proposed recently?" is answered locally: every successful tally is
/// compared with the previous one and the moment a node's count is seen to
/// grow is remembered. Persisted across launches (UserDefaults), keyed by
/// proTxHash.
struct EvonodeProposalActivity: Codable, Equatable {
    struct Node: Codable, Equatable {
        /// Epoch of `count` (tallies reset at an epoch boundary).
        var epochIndex: UInt32
        /// Last observed count for `epochIndex`.
        var count: UInt64
        /// When this node was first observed at all — the baseline before
        /// any increase has been seen.
        var firstSeenAt: Date
        /// When the count was last seen to increase; `nil` until it has.
        var lastIncreaseAt: Date?
    }

    /// Keyed by the proTxHash bytes (stored wire order).
    var nodes: [Data: Node] = [:]

    /// A node counts as "not proposing" once this long has passed without an
    /// observed increase (from its first observation, or its last increase).
    static let staleInterval: TimeInterval = 2 * 24 * 60 * 60

    /// Fold a fresh tally in. Nodes absent from `blocks` are dropped (no
    /// longer owned / retired); an epoch change makes any positive count an
    /// increase (the previous epoch's total doesn't carry over).
    mutating func record(_ blocks: EvonodeEpochBlocks, now: Date = Date()) {
        guard let epoch = blocks.epochIndex else { return }
        var updated: [Data: Node] = [:]
        for (hash, count) in blocks.blocksByProTxHash {
            if var node = nodes[hash] {
                let previous = node.epochIndex == epoch ? node.count : 0
                if count > previous {
                    node.lastIncreaseAt = now
                }
                node.epochIndex = epoch
                node.count = count
                updated[hash] = node
            } else {
                updated[hash] = Node(
                    epochIndex: epoch,
                    count: count,
                    firstSeenAt: now,
                    lastIncreaseAt: count > 0 ? now : nil)
            }
        }
        nodes = updated
    }

    /// Nodes with no observed proposal in the last `staleInterval` — measured
    /// from the last increase, or from first observation if none was ever
    /// seen. A node observed for less than the interval is never stale yet.
    func staleNodes(now: Date = Date()) -> Set<Data> {
        Set(nodes.compactMap { hash, node in
            let reference = node.lastIncreaseAt ?? node.firstSeenAt
            return now.timeIntervalSince(reference) >= Self.staleInterval ? hash : nil
        })
    }
}

// MARK: - EvonodeProposalActivityStore

/// UserDefaults persistence for `EvonodeProposalActivity`, per network (the
/// same wallet sees different masternodes on testnet and mainnet).
struct EvonodeProposalActivityStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, network: String) {
        self.defaults = defaults
        self.key = "org.dash.evonodeProposalActivity.\(network)"
    }

    func load() -> EvonodeProposalActivity {
        guard let data = defaults.data(forKey: key),
              let activity = try? JSONDecoder().decode(EvonodeProposalActivity.self, from: data) else {
            return EvonodeProposalActivity()
        }
        return activity
    }

    func save(_ activity: EvonodeProposalActivity) {
        guard let data = try? JSONEncoder().encode(activity) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - EvonodeHealth

/// What the Nodes icon colour says about the owned evonodes.
enum EvonodeHealth: Equatable {
    /// Every node has proposed recently.
    case healthy
    /// At least one node has not proposed a block in the last 2 days.
    case warning
    /// We are on epoch day 4 or later and at least one node still has no
    /// block in this epoch.
    case critical

    /// Derive the state for `now` from the current tallies and the tracked
    /// activity. `epochDay` is the 0-based day of the epoch.
    static func evaluate(
        blocks: EvonodeEpochBlocks?,
        activity: EvonodeProposalActivity,
        epochDay: Int?,
        now: Date = Date()
    ) -> EvonodeHealth {
        guard let blocks else { return .healthy }
        if let epochDay, epochDay >= 4, blocks.blocksByProTxHash.values.contains(0) {
            return .critical
        }
        if !activity.staleNodes(now: now).isEmpty {
            return .warning
        }
        return .healthy
    }
}
