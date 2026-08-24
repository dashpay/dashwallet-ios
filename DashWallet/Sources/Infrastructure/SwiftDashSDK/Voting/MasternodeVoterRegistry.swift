//
//  MasternodeVoterRegistry.swift
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
import OSLog
import SwiftDashSDK

// MARK: - VoterNode

/// A masternode or evonode this wallet can vote with: registered on-chain,
/// still active, and with a voting key that this wallet derives.
///
/// Nothing here is user-entered. The set comes from the on-chain masternode
/// aggregation joined against the wallet's derived voting-key pool, so a node
/// appears if and only if the wallet actually holds the key Platform will
/// check the signature against.
/// Where a votable node's voting private key lives.
enum VotingKeySource: Hashable {
    /// Derived from the wallet's `ProviderVotingKeys` account at this index.
    case walletIndex(UInt32)
    /// Attached by the user to a TRACKED masternode; the key text is in the
    /// app's keychain vault.
    case trackedVault
}

struct VoterNode: Identifiable, Hashable {
    /// The masternode's pro_tx_hash in raw wire byte order — the orientation
    /// `SDK.castContestedResourceVote` expects. Reverse it only for display
    /// (block explorers show the reversed form).
    let proTxHash: Data
    let isEvonode: Bool
    /// 1-based index within this node's type, for "Evonode 2" / "Masternode 5".
    let typeIndex: UInt32
    /// `ip:port`, when the registration carried one.
    let serviceAddress: String?
    /// Where this node's voting private key comes from.
    let keySource: VotingKeySource

    var id: Data { proTxHash }

    /// Voting weight Platform applies to this node's vote. Evonodes count 4×,
    /// regular masternodes 1× — enforced by drive-abci from the masternode
    /// list, not by anything the client sends.
    var voteWeight: UInt32 { isEvonode ? 4 : 1 }

    var displayName: String {
        let type = isEvonode
            ? NSLocalizedString("Evonode", comment: "Voting")
            : NSLocalizedString("Masternode", comment: "Voting")
        return "\(type) \(typeIndex)"
    }

    /// Block-explorer (reversed) hex of the pro_tx_hash, truncated for display.
    var shortProTxHash: String {
        let hex = proTxHash.reversed().map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8)) + "…" + String(hex.suffix(8))
    }
}

// MARK: - MasternodeVoterRegistry

/// Resolves which of the wallet's masternodes can cast contested-username
/// votes, and derives their voting private keys on demand.
///
/// Injected rather than shared: the voting screens own one instance, and tests
/// (once the unit-test target builds again) can substitute a stub through
/// `VotingViewModel`'s initializer.
@MainActor
final class MasternodeVoterRegistry {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.voting")

    init() {}

    /// Outcome of a votable-node resolution.
    ///
    /// `mayBeIncomplete` says the answer cannot be trusted as exhaustive: the
    /// voting address pool was read from the degraded fallback (gap-limit
    /// deep) *and* at least one active registration went unmatched, so a node
    /// this wallet really can vote with may be missing from `nodes`. The UI
    /// says so rather than presenting a short list as the full picture.
    struct Resolution {
        let nodes: [VoterNode]
        let mayBeIncomplete: Bool

        static let empty = Resolution(nodes: [], mayBeIncomplete: false)
    }

    /// The wallet's votable nodes, ordered by registration.
    ///
    /// A masternode is votable when all of the following hold:
    ///  - it is not revoked and its DML status is `.active` — Platform rejects
    ///    a vote from a node that is not in the current masternode list;
    ///  - it published a voting address;
    ///  - that address matches a key this wallet derives, so we can sign.
    ///
    /// Returns empty (not an error) when the wallet has no masternodes, when
    /// the SDK is not running, or when the masternode phase has not synced —
    /// the caller renders the browse-only state.
    func votableNodes() -> Resolution {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            return .empty
        }

        let eligible = manager.masternodes(for: walletId)
            .filter { !$0.revoked && MasternodeStatus(rawValue: $0.status) == .active }
        guard !eligible.isEmpty else { return .empty }

        let resolution = MasternodeKeyUsage.resolveAddressIndexes(
            family: .voting,
            targets: Set(eligible.compactMap(\.votingAddress)))
        let indexByAddress = resolution.map

        let nodes = eligible
            .compactMap { masternode -> (PlatformMasternode, UInt32)? in
                guard let address = masternode.votingAddress else {
                    Self.logger.info(
                        "🗳️ VOTING :: skipping a node with no published voting address")
                    return nil
                }
                guard let index = indexByAddress[address] else {
                    Self.logger.info(
                        "🗳️ VOTING :: a registered voting address is not in this wallet's pool — not votable: \(address, privacy: .private)")
                    return nil
                }
                Self.logger.info(
                    "🗳️ VOTING :: matched a registered voting address at pool index \(index, privacy: .public): \(address, privacy: .private)")
                return (masternode, index)
            }
            .sorted { $0.0.orderIndex < $1.0.orderIndex }
            .map { masternode, index in
                VoterNode(
                    proTxHash: masternode.proTxHash,
                    isEvonode: masternode.isEvonode,
                    typeIndex: masternode.typeIndex,
                    serviceAddress: masternode.serviceAddress,
                    keySource: .walletIndex(index))
            }

        // Only a degraded pool read can hide a node we own; if every active
        // registration matched, depth did not matter.
        let mayBeIncomplete = !resolution.poolIsLive && nodes.count < eligible.count
        Self.logger.info(
            "🗳️ VOTING :: votable nodes=\(nodes.count, privacy: .public) of \(eligible.count, privacy: .public) active registrations livePool=\(resolution.poolIsLive, privacy: .public)")
        let all = nodes + trackedVotableNodes(excluding: Set(nodes.map(\.proTxHash)))
        return Resolution(nodes: all, mayBeIncomplete: mayBeIncomplete)
    }

    /// Tracked (wallet-independent) masternodes whose voting key the user
    /// attached on this device — votable with that key. A node already
    /// votable through the wallet is skipped (the derived key wins).
    private func trackedVotableNodes(excluding walletHashes: Set<Data>) -> [VoterNode] {
        guard let manager = SwiftDashSDKHost.shared.manager else { return [] }
        let vault = TrackedMasternodeKeyVault()
        return manager.trackedMasternodes()
            .filter { node in
                !walletHashes.contains(node.proTxHash)
                    && !node.revoked
                    && MasternodeStatus(rawValue: node.status) == .active
                    && vault.attachedRoles(for: node.proTxHash).contains(.voting)
            }
            .map { node in
                VoterNode(
                    proTxHash: node.proTxHash,
                    isEvonode: node.isEvonode,
                    typeIndex: node.typeIndex,
                    serviceAddress: node.serviceAddress,
                    keySource: .trackedVault)
            }
    }

    /// The 32-byte voting private key for `node`.
    ///
    /// - Important: The caller must have passed `AuthenticationGate` first —
    ///   this returns spendable-equivalent key material and performs no prompt
    ///   of its own. The bytes are handed straight to the FFI, which zeroizes
    ///   its copy; keep the returned value's lifetime as short as possible.
    /// - Returns: `nil` when the provider-voting account cannot be derived
    ///   (wallet locked or not loaded) or the WIF fails to parse. Never
    ///   substitutes a placeholder.
    func votingPrivateKey(for node: VoterNode) -> Data? {
        let index: UInt32
        switch node.keySource {
        case .trackedVault:
            return trackedVotingPrivateKey(for: node)
        case .walletIndex(let walletIndex):
            index = walletIndex
        }
        guard let deriver = MasternodeProviderKeyDeriver(key: .voting) else {
            Self.logger.error("🗳️ VOTING :: no provider-voting deriver available")
            return nil
        }

        // The index came from joining the node's registered address against
        // the live pool; the key is resolved Rust-side from the running wallet
        // (platform#4338), which cross-checks it against the account xpub
        // before returning. So a key that does not match this node's registered
        // voting address cannot reach the signer — Platform would only be able
        // to report that as "no voter identity exists", which is
        // indistinguishable from a node that was never registered.
        Self.logger.info(
            "🗳️ VOTING :: signing with the key at pool index \(index, privacy: .public) for \(deriver.address(at: index) ?? "unknown address", privacy: .private)")

        guard let hex = deriver.privateKeyHex(at: index),
              let key = Data(hex: hex) else {
            Self.logger.error(
                "🗳️ VOTING :: failed to derive voting key at index \(index, privacy: .public)")
            return nil
        }
        guard key.count == 32 else {
            Self.logger.error(
                "🗳️ VOTING :: derived voting key has \(key.count, privacy: .public) bytes, expected 32")
            return nil
        }
        return key
    }

    /// The 32-byte voting key of a tracked node, from the keychain vault
    /// (WIF or hex, exactly as the user attached it). Same
    /// authenticate-first contract as the derived path.
    private func trackedVotingPrivateKey(for node: VoterNode) -> Data? {
        let vault = TrackedMasternodeKeyVault()
        guard let text = vault.key(for: node.proTxHash, role: .voting) else {
            Self.logger.error("🗳️ VOTING :: tracked node has no voting key in the vault")
            return nil
        }
        let key = WIFParser.parseWIF(text) ?? Data(hex: text)
        guard let key, key.count == 32 else {
            Self.logger.error("🗳️ VOTING :: the vaulted voting key is not a 32-byte WIF/hex key")
            return nil
        }
        Self.logger.info("🗳️ VOTING :: signing with a tracked node's vaulted voting key")
        return key
    }
}

// MARK: - Aggregate weight

extension Array where Element == VoterNode {
    /// Combined Platform voting weight of these nodes.
    var totalVoteWeight: UInt32 {
        reduce(UInt32(0)) { $0 &+ $1.voteWeight }
    }
}
