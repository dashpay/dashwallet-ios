//
//  DevnetConfiguration.swift
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
import SwiftDashSDK

/// The user-editable devnet coordinates, over UserDefaults.
///
/// Two of the keys are READ DIRECTLY BY SwiftDashSDK and must keep their
/// exact names:
///   - `platformQuorumURL` — `SDK.init(network: .devnet, …)` reads it and
///     auto-discovers DAPI addresses from `{quorumURL}/masternodes`. Without
///     it, devnet SDK creation fails.
///   - `platformDevnetName` — the `dashd -devnet=<name>` chain name. The app
///     passes it into `PlatformSpvStartConfig.devnetName` so the SPV user
///     agent embeds `devnet.devnet-<name>` (Core devnet peers drop the
///     handshake without it).
/// The third key is app-owned: the DashConnect `loginKeyResponse` contract
/// id on devnet (the contract is registered separately per devnet, so its id
/// differs from the pinned testnet one).
///
/// Values are trimmed on read; empty-after-trim counts as unset. The quorum
/// URL and devnet name are seeded with the current team devnet
/// (`devnet-moutai`) through the registration domain, so a fresh install can
/// select Devnet without typing anything — a user-saved value (including an
/// explicitly emptied one, stored as `""`) always wins over the seed. The
/// DashConnect contract id deliberately has NO default: it is unknown for
/// moutai, and an absent value must surface as a normal error, never a guess.
///
/// NOTE: the SDK's own built-in devnet quorum template
/// (`https://quorums.devnet.<name>.networks.dash.org`) does not match real
/// deployments (moutai lives at `quorums.moutai.networks.dash.org`), so the
/// app always passes an explicit quorum URL and never falls back to the
/// SDK template.
enum DevnetConfiguration {
    /// Read by `SDK.init` inside SwiftDashSDK — do not rename.
    static let quorumURLKey = "platformQuorumURL"
    /// Same key the SwiftDashSDK sample app uses — do not rename.
    static let devnetNameKey = "platformDevnetName"
    /// App-owned: base58 id of the devnet `loginKeyResponse` contract.
    static let dashConnectContractIdKey = "devnetDashConnectLoginContractId"

    /// devnet-moutai, verified reachable 2026-09-01 (13 enabled masternodes,
    /// Core P2P on :20001, DAPI on :1443).
    static let defaultQuorumURL = "https://quorums.moutai.networks.dash.org"
    static let defaultDevnetName = "moutai"

    /// Puts the moutai defaults into the registration domain so both the
    /// app's readers AND the SDK's raw `string(forKey: "platformQuorumURL")`
    /// read see them until the user saves an override. Registration is
    /// per-process (not persisted), hence the lazy once-token touched by
    /// every accessor, plus an explicit call before any devnet SDK build
    /// (`SwiftDashSDKHost.makeRuntime`).
    static func ensureDefaultsRegistered() {
        _ = registrationToken
    }

    private static let registrationToken: Void = {
        UserDefaults.standard.register(defaults: [
            quorumURLKey: defaultQuorumURL,
            devnetNameKey: defaultDevnetName,
        ])
    }()

    /// The quorum-list-server base URL, or nil when unset/blank.
    static var quorumURL: String? {
        ensureDefaultsRegistered()
        return normalized(UserDefaults.standard.string(forKey: quorumURLKey))
    }

    /// The devnet chain name (`dashd -devnet=<name>`), or nil when unset,
    /// blank, or malformed.
    ///
    /// Malformed is filtered here as well as at the point of entry: a name
    /// that violates the native contract cannot start SPV, so letting it
    /// read as "configured" would only trade an inline error for a failed
    /// network switch. `DevnetSettingsScreen` refuses to save one, so this
    /// path is reached only by a value an earlier build stored.
    static var devnetName: String? {
        ensureDefaultsRegistered()
        guard let trimmed = normalized(UserDefaults.standard.string(forKey: devnetNameKey)),
              devnetNameValidationError(trimmed) == nil else { return nil }
        return trimmed
    }

    /// Why `name` cannot be used as a devnet chain name, or nil when it can.
    ///
    /// Mirrors `platform_wallet_manager_spv_start`, which rejects an empty
    /// name, any whitespace (leading, trailing or interior — a
    /// `devnet.devnet- foo ` user agent is silently dropped by Dash Core
    /// peers), and `/`. Rejecting rather than repairing keeps the rule the
    /// same on both sides of the FFI. An empty string is not an error here:
    /// clearing the field is how the user deliberately unconfigures devnet,
    /// and `isConfigured` reports that.
    static func devnetNameValidationError(_ name: String) -> String? {
        guard !name.isEmpty else { return nil }
        if name.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return NSLocalizedString(
                "The devnet name cannot contain spaces.", comment: "Devnet")
        }
        if name.contains("/") {
            return NSLocalizedString(
                "The devnet name cannot contain a slash.", comment: "Devnet")
        }
        return nil
    }

    /// The devnet DashConnect `loginKeyResponse` contract id (base58), or nil
    /// when unset/blank. Stored as entered; validity (32-byte identifier) is
    /// the consumer's check so a typo surfaces as an error there, not a crash.
    static var dashConnectContractId: String? {
        ensureDefaultsRegistered()
        return normalized(UserDefaults.standard.string(forKey: dashConnectContractIdKey))
    }

    /// Writers store the raw (trimmed) text — including the empty string, so
    /// clearing a field genuinely unsets it instead of resurfacing the
    /// registered default.
    static func setQuorumURL(_ value: String) {
        ensureDefaultsRegistered()
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: quorumURLKey)
    }

    static func setDevnetName(_ value: String) {
        ensureDefaultsRegistered()
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: devnetNameKey)
    }

    static func setDashConnectContractId(_ value: String) {
        ensureDefaultsRegistered()
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: dashConnectContractIdKey)
    }

    /// Whether devnet can start: quorum URL AND devnet name are both present.
    /// The DashConnect contract id is deliberately not part of this — it only
    /// gates DashConnect approvals, not the network itself.
    static var isConfigured: Bool {
        quorumURL != nil && devnetName != nil
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension SwiftDashSDK.Network {
    /// Directory (and process-cache) scope for this network's persisted
    /// chain state: the Platform SwiftData store, the shielded commitment
    /// tree, and the SPV data directory.
    ///
    /// Mainnet and testnet return `networkName` unchanged, so their existing
    /// paths are byte-identical. Devnet appends the configured chain name,
    /// because "devnet" is not one chain: switching from devnet A to devnet B
    /// would otherwise open A's wallet, identity, SPV and shielded state
    /// against B's peers, where none of those records mean anything. Each
    /// devnet therefore gets its own directory, and moving between them is
    /// just a different path rather than a reset.
    ///
    /// The name is safe to place in a path because `DevnetConfiguration`
    /// rejects whitespace and `/` before it is ever stored. An unconfigured
    /// devnet falls back to the bare `networkName` — nothing can start on it,
    /// so the scope is never actually opened.
    var persistenceScope: String {
        guard self == .devnet, let name = DevnetConfiguration.devnetName else {
            return networkName
        }
        return "\(networkName)-\(name)"
    }
}
