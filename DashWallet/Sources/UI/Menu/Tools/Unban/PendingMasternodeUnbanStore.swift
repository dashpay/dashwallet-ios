//
//  Created by Claude Code
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// An unban (ProUpServTx) the user funded from the shielded pool and has not
/// submitted yet. The shielded→L1 withdrawal settles through the Platform
/// withdrawal queue minutes later with no txid, so the flow is a persisted
/// two-step: record the intent when the top-up is submitted, and offer
/// "Complete unban" — with the same parameters — once the funds land, even
/// across an app relaunch.
struct PendingMasternodeUnban: Codable, Equatable {
    /// proTxHash in forward/wire hex — the orientation
    /// `PlatformMasternode.proTxHash` stores.
    let proTxHashHex: String
    /// Evonode platform P2P port the user confirmed (nil for regular nodes).
    let platformP2PPort: UInt16?
    /// Operator payout address the user confirmed (nil when the node has no
    /// operator reward).
    let operatorPayoutAddress: String?
    let createdAt: Date
}

/// UserDefaults-backed, keyed per wallet like `ShieldedWithdrawalStore`, so
/// a pending unban funded from wallet A never surfaces while wallet B is
/// active.
final class PendingMasternodeUnbanStore {

    static let shared = PendingMasternodeUnbanStore()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private let keyPrefix = "masternodeUnban.v1.pending"

    private init() {}

    private func resolvedKey() -> String {
        guard let walletIdHex = WalletEnvironment.activeWalletIdHex as String?,
              !walletIdHex.isEmpty else {
            return keyPrefix
        }
        return "\(keyPrefix)_\(walletIdHex)"
    }

    private func loaded() -> [PendingMasternodeUnban] {
        guard let data = defaults.data(forKey: resolvedKey()),
              let entries = try? JSONDecoder().decode([PendingMasternodeUnban].self, from: data) else {
            return []
        }
        return entries
    }

    private func store(_ entries: [PendingMasternodeUnban]) {
        if entries.isEmpty {
            defaults.removeObject(forKey: resolvedKey())
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: resolvedKey())
        }
    }

    func pending(forProTxHash proTxHash: Data) -> PendingMasternodeUnban? {
        let hex = proTxHash.map { String(format: "%02x", $0) }.joined()
        lock.lock()
        defer { lock.unlock() }
        return loaded().first { $0.proTxHashHex == hex }
    }

    func record(_ entry: PendingMasternodeUnban) {
        lock.lock()
        defer { lock.unlock() }
        var entries = loaded().filter { $0.proTxHashHex != entry.proTxHashHex }
        entries.append(entry)
        store(entries)
    }

    func clear(forProTxHash proTxHash: Data) {
        let hex = proTxHash.map { String(format: "%02x", $0) }.joined()
        lock.lock()
        defer { lock.unlock() }
        store(loaded().filter { $0.proTxHashHex != hex })
    }
}
