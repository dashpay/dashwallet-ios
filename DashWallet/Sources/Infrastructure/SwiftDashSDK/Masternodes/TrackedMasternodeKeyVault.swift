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
import Security
import SwiftData
import SwiftDashSDK

// MARK: - TrackedMasternodeKeyVaulting

/// Secure storage for the private keys a user attaches to a TRACKED
/// (wallet-independent) masternode.
///
/// The SDK deliberately never stores these: Rust receives a key per signing
/// call and retains nothing (`trackedMasternodeWithdraw`,
/// `castContestedResourceVote`). The app owns them, in the keychain, keyed by
/// `(network, proTxHash, role)`. Values are the key TEXT exactly as the user
/// supplied it (WIF / hex / node-key base64) — kept verbatim so it can be
/// re-shown and re-parsed by the same SDK parser that validated it.
///
/// Callers gate every read behind `AuthenticationGate` — this type performs
/// no prompting of its own. Main-actor-bound like the SDK `KeychainManager`
/// APIs it wraps (and every caller already is).
@MainActor
protocol TrackedMasternodeKeyVaulting {
    /// The stored key text for a role, or `nil`.
    func key(for proTxHash: Data, role: MasternodeKeyRole) -> String?
    /// Store (or replace) a role's key text. Returns `false` on a keychain
    /// write failure — callers surface that, never assume success.
    @discardableResult
    func store(_ keyText: String, for proTxHash: Data, role: MasternodeKeyRole) -> Bool
    /// Remove one role's key.
    @discardableResult
    func removeKey(for proTxHash: Data, role: MasternodeKeyRole) -> Bool
    /// The roles that currently have a key attached for this node.
    func attachedRoles(for proTxHash: Data) -> Set<MasternodeKeyRole>
    /// Remove every key of this node (untrack).
    func removeAllKeys(for proTxHash: Data)
}

// MARK: - TrackedMasternodeKeyVault

/// Keychain-backed vault (SwiftDashSDK `KeychainManager`, the same unified
/// service the SDK's identity keys use). Entries are per network so a node
/// tracked on both networks keeps distinct keys.
final class TrackedMasternodeKeyVault: TrackedMasternodeKeyVaulting {
    private let keychain: KeychainManager
    /// Resolved per call — the vault outlives network switches. Defaults to
    /// the persisted network selection (`WalletEnvironment`), which is
    /// readable off the main actor, unlike the host's published state.
    private let network: () -> Network?

    nonisolated init(keychain: KeychainManager = .shared,
         network: @escaping () -> Network? = {
             WalletEnvironment.isTestnet ? .testnet : .mainnet
         }) {
        self.keychain = keychain
        self.network = network
    }

    /// The roles the tracked-masternode UI manages. `platformNode` and
    /// `operatorPayout` are deliberately absent — no app action uses them
    /// (owner decision 2026-08-24).
    static let managedRoles: [MasternodeKeyRole] = [.owner, .voting, .operator, .ownerPayout]

    private func identifier(_ proTxHash: Data, _ role: MasternodeKeyRole) -> String? {
        guard let network = network() else { return nil }
        let hex = proTxHash.map { String(format: "%02x", $0) }.joined()
        return "masternode.\(network.rawValue).\(hex).\(role.rawValue)"
    }

    func key(for proTxHash: Data, role: MasternodeKeyRole) -> String? {
        guard let identifier = identifier(proTxHash, role),
              let data = keychain.retrieveKeyData(identifier: identifier) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func store(_ keyText: String, for proTxHash: Data, role: MasternodeKeyRole) -> Bool {
        guard let identifier = identifier(proTxHash, role) else { return false }
        return keychain.storeKeyData(Data(keyText.utf8), identifier: identifier) != nil
    }

    @discardableResult
    func removeKey(for proTxHash: Data, role: MasternodeKeyRole) -> Bool {
        guard let identifier = identifier(proTxHash, role) else { return false }
        return keychain.deleteKeyData(identifier: identifier)
    }

    func attachedRoles(for proTxHash: Data) -> Set<MasternodeKeyRole> {
        Set(Self.managedRoles.filter { role in
            guard let identifier = identifier(proTxHash, role) else { return false }
            return keychain.retrieveKeyData(identifier: identifier) != nil
        })
    }

    func removeAllKeys(for proTxHash: Data) {
        for role in Self.managedRoles {
            removeKey(for: proTxHash, role: role)
        }
    }
}


// MARK: - Reset-all cleanup

extension TrackedMasternodeKeyVault {
    /// Reset-all teardown (owner decision 2026-08-24: tracked masternodes
    /// survive deleting one wallet of several, die on reset-all): untrack
    /// everything the running manager knows (clears the Rust registry and
    /// the current network's persisted rows), sweep any remaining
    /// `PersistentTrackedMasternode` rows (the other network), and delete
    /// every vaulted key. Idempotent and best-effort — a failed step logs
    /// and the rest still runs.
    @MainActor
    static func wipeAllTrackedState() {
        if let manager = SwiftDashSDKHost.shared.manager {
            for node in manager.trackedMasternodes() {
                _ = try? manager.untrackMasternode(proTxHash: node.proTxHash)
            }
        }
        if let container = SwiftDashSDKHost.shared.modelContainer {
            let context = ModelContext(container)
            try? context.delete(model: PersistentTrackedMasternode.self)
            try? context.save()
        }
        removeAllVaultedKeys()
    }

    /// Delete every `masternode.*` entry in the unified keychain service,
    /// across networks and nodes.
    @MainActor
    static func removeAllVaultedKeys() {
        let service = KeychainManager.shared.serviceName
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix("masternode.") else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
    }
}
