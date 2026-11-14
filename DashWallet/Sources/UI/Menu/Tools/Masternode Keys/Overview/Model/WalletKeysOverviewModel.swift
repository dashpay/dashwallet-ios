//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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
import SwiftDashSDK

// MARK: - MNKey

/// The four masternode key families a ProRegTx references: Owner and Voting
/// (ECDSA, on-chain P2PKH addresses), Operator (BLS), and Evonode Operator
/// (Ed25519 platform-node key, formerly "HPMN Operator").
enum MNKey: CaseIterable {
    case owner
    case voting
    case `operator`
    case evonodeOperator
}

extension MNKey {
    var title: String {
        switch self {
        case .owner:
            return NSLocalizedString("Owner keys", comment: "")
        case .voting:
            return NSLocalizedString("Voting keys", comment: "")
        case .operator:
            return NSLocalizedString("Operator keys", comment: "")
        case .evonodeOperator:
            return NSLocalizedString("Evonode Operator keys", comment: "")
        }
    }
}

// MARK: - MasternodeKeyUsage

/// Which key indexes of each masternode key family this wallet's masternodes
/// use, resolved from the Rust masternode aggregation
/// (`PlatformWalletManager.masternodes(for:)`).
///
/// Operator (BLS) and Evonode Operator (Ed25519) ownership is resolved by
/// Rust itself (derive-and-compare; `operatorInWallet`/`operatorKeyIndex`,
/// `platformInWallet`/`platformKeyIndex`). Owner and Voting keys have
/// on-chain P2PKH addresses, so they're joined in Swift by matching the
/// aggregation's Rust-encoded base58 addresses against the wallet's derived
/// address at each index.
@MainActor
struct MasternodeKeyUsage {
    struct KeyUse {
        /// The masternode's `ip:port`, when known.
        let serviceAddress: String?
        /// True when that registration was since revoked.
        let revoked: Bool
    }

    private let used: [MNKey: [UInt32: KeyUse]]

    private init(used: [MNKey: [UInt32: KeyUse]]) {
        self.used = used
    }

    func use(for key: MNKey, at index: Int) -> KeyUse? {
        guard index >= 0 else { return nil }
        return used[key]?[UInt32(index)]
    }

    func usedCount(for key: MNKey) -> Int {
        used[key]?.count ?? 0
    }

    /// The index after the highest used one (0 when the family is unused) —
    /// DashSync's `firstUnusedIndex` semantics, which the key screens use as
    /// the initially visible keypair.
    func firstUnusedIndex(for key: MNKey) -> Int {
        guard let maxUsed = used[key]?.keys.max() else { return 0 }
        return Int(maxUsed) + 1
    }

    static func resolve() -> MasternodeKeyUsage {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            return MasternodeKeyUsage(used: [:])
        }
        let masternodes = manager.masternodes(for: walletId)
        guard !masternodes.isEmpty else {
            return MasternodeKeyUsage(used: [:])
        }

        var used: [MNKey: [UInt32: KeyUse]] = [:]
        // A revoked registration never overrides a live one at the same index.
        func record(_ key: MNKey, _ index: UInt32, _ use: KeyUse) {
            if let current = used[key]?[index], !current.revoked, use.revoked {
                return
            }
            used[key, default: [:]][index] = use
        }

        // Operator / Evonode Operator: Rust already resolved the in-wallet
        // key index for these no-address key types.
        for mn in masternodes {
            let use = KeyUse(serviceAddress: mn.serviceAddress, revoked: mn.revoked)
            if mn.operatorInWallet {
                record(.operator, mn.operatorKeyIndex, use)
            }
            if mn.platformOwnershipChecked, mn.platformInWallet {
                record(.evonodeOperator, mn.platformKeyIndex, use)
            }
        }

        // Owner / Voting: join the aggregation's base58 addresses against
        // the wallet's derived address at each index in the scan window.
        for key in [MNKey.owner, .voting] {
            var useByAddress: [String: KeyUse] = [:]
            for mn in masternodes {
                let address = (key == .owner) ? mn.ownerAddress : mn.votingAddress
                guard let address, !address.isEmpty else { continue }
                let use = KeyUse(serviceAddress: mn.serviceAddress, revoked: mn.revoked)
                if let current = useByAddress[address], !current.revoked, use.revoked {
                    continue
                }
                useByAddress[address] = use
            }
            for (address, index) in indexByAddress(family: key, targets: Set(useByAddress.keys)) {
                guard let use = useByAddress[address] else { continue }
                record(key, index, use)
            }
        }

        return MasternodeKeyUsage(used: used)
    }

    /// Base58 address → derived key index, for the two address-carrying key
    /// families (owner / voting).
    ///
    /// The on-chain aggregation gives a masternode's owner and voting
    /// *addresses*; turning those into "which of this wallet's derived keys is
    /// that" means deriving each index and comparing. Shared by this type's
    /// ownership resolution, the Masternodes screen's ownership labels, and
    /// `MasternodeVoterRegistry`'s voting-key lookup — the same join must not
    /// be reimplemented per call site.
    ///
    /// Walks the pool's full depth rather than a fixed window: SPV extends the
    /// pool as ProRegTx/ProUpRegTx matches mark deeper indexes used, so a
    /// capped scan would silently hide those masternodes. An unreadable pool
    /// yields an empty range — no pool means no addresses to join against.
    ///
    /// Returns an empty map for key families with no on-chain address
    /// (operator / evonode operator); Rust resolves those instead.
    static func indexByAddress(family: MNKey, targets: Set<String>) -> [String: UInt32] {
        guard !targets.isEmpty,
              let deriver = MasternodeProviderKeyDeriver(key: family) else { return [:] }
        var map: [String: UInt32] = [:]
        let upperBound = deriver.highestAddressIndex.map { $0 + 1 } ?? 0
        for index in 0..<upperBound {
            guard let address = deriver.address(at: index),
                  targets.contains(address) else { continue }
            map[address] = index
        }
        return map
    }
}
