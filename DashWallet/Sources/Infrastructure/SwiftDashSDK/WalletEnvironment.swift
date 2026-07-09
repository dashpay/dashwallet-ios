//
//  Created by Bartosz Rozwarski
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

/// DashSync-free network identity + wallet presence for the app.
/// (One deliberate DashSync read remains: `hasWallet`'s migration-window
/// union term — see its doc.)
///
/// Reads the same persisted network selection `DWEnvironment` maintains —
/// the `CURRENT_CHAIN_TYPE_KEY` UserDefaults integer holding a DashSync
/// `ChainType_Tag` raw value (`0` mainnet / `1` testnet / `2` devnet;
/// `dash_shared_core.h`) — so call sites that only need to know *which
/// network the app is on* can stop touching the `DWEnvironment.currentChain`
/// DashSync object graph.
///
/// Read-only by design: `DWEnvironment.switchToNetwork` remains the sole
/// writer of the key (and posts `DWCurrentNetworkDidChangeNotification`).
/// One deliberate divergence from `DWEnvironment.reset`: when the key holds
/// devnet but no devnet chain exists, DWEnvironment rewrites the key back to
/// mainnet during its init — this reader does not replicate that write-back
/// and reports the stored value as-is (devnet ⇒ `network == nil`, both
/// bools false), matching the runtime's fail-fast handling of unsupported
/// networks.
///
/// Not a singleton — a stateless namespace of static readers over
/// UserDefaults (no instances, no mutable state, nothing to inject).
@objc(DWWalletEnvironment)
public final class WalletEnvironment: NSObject {
    /// Raw values mirror DashSync's `ChainType_Tag` C enum, which is what
    /// `DWEnvironment` persists under `CURRENT_CHAIN_TYPE_KEY`.
    public enum NetworkKind: Int {
        case mainnet = 0
        case testnet = 1
        case devnet = 2
    }

    private static let currentChainTypeKey = "CURRENT_CHAIN_TYPE_KEY"

    /// The persisted network selection. A missing key means a fresh install
    /// that hasn't run `DWEnvironment`'s init yet — testnet, matching the
    /// deliberate migration-era default (`DWEnvironment.m`, owner decision
    /// 2026-07-03). Unknown raw values classify as `.devnet` (unsupported).
    public static var networkKind: NetworkKind {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: currentChainTypeKey) != nil else { return .testnet }
        return NetworkKind(rawValue: defaults.integer(forKey: currentChainTypeKey)) ?? .devnet
    }

    @objc public static var isMainnet: Bool { networkKind == .mainnet }

    @objc public static var isTestnet: Bool { networkKind == .testnet }

    /// The SwiftDashSDK network for the current selection, or `nil` for
    /// devnet/unsupported — callers fail fast instead of silently mapping
    /// to a supported network (same contract as the wallet runtime).
    public static var network: SwiftDashSDK.Network? {
        switch networkKind {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return nil
        }
    }

    /// SwiftDashSDK wallet presence — a mnemonic persisted in `WalletStorage`'s
    /// keychain (see `SwiftDashSDKHost.hasPersistedSDKWallet`). The SDK
    /// runtime's own start gate; app-level existence checks use `hasWallet`.
    @objc public static var hasSDKWallet: Bool {
        SwiftDashSDKHost.hasPersistedSDKWallet()
    }

    // MARK: - Active-wallet registry

    /// UserDefaults key holding the raw walletId `Data` chosen as active on
    /// `network`. One key per network — the app tracks a distinct active
    /// wallet on mainnet and testnet (the same posture as the per-network
    /// SwiftData store `SwiftDashSDKHost.buildModelContainer` builds). A
    /// missing key means "unset" — no wallet has been resolved on this
    /// network yet, and `SwiftDashSDKHost` falls back to `firstWallet`.
    private static func activeWalletIdKey(for network: NetworkKind) -> String {
        "DW_ACTIVE_WALLET_ID_\(network.rawValue)"
    }

    /// The walletId last resolved as active for `network`, or `nil` when
    /// unset. Written by `SwiftDashSDKHost` whenever it binds a wallet
    /// (including the `firstWallet` fallback and after `createOrImportWallet`),
    /// so the registry becomes concrete after first launch. The stored value
    /// is the raw 32-byte walletId `Data`.
    public static func activeWalletId(for network: NetworkKind) -> Data? {
        UserDefaults.standard.data(forKey: activeWalletIdKey(for: network))
    }

    /// Persist (or clear, when `id` is `nil`) the active walletId for
    /// `network`. Sole writer of the per-network active-wallet key.
    public static func setActiveWalletId(_ id: Data?, for network: NetworkKind) {
        let defaults = UserDefaults.standard
        let key = activeWalletIdKey(for: network)
        if let id {
            defaults.set(id, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The active walletId for the app's CURRENT network, hex-encoded, or nil
    /// when no wallet is resolved yet (fresh install, or between wipe and first
    /// create). ObjC-facing so `DWGlobalOptions` can scope its per-wallet
    /// UserDefaults keys (backup / has-balance) by the active wallet without
    /// importing SwiftDashSDK. Resolves through the same per-network registry
    /// the Swift side reads (`activeWalletId(for:)`) — one place owns the
    /// registry. `devnet`/unsupported network ⇒ nil.
    @objc public static var activeWalletIdHex: NSString? {
        let kind: NetworkKind
        switch networkKind {
        case .mainnet: kind = .mainnet
        case .testnet: kind = .testnet
        case .devnet: return nil
        }
        guard let id = activeWalletId(for: kind) else { return nil }
        return id.map { String(format: "%02x", $0) }.joined() as NSString
    }

    /// App-level wallet existence. MIGRATION-WINDOW UNION: SDK presence OR
    /// DashSync `chain.hasAWallet` — DashSync-only wallets exist transiently
    /// (the recover flow's async SDK import; migrator-deferred multi-wallet /
    /// unknown-chain cases), so existence checks must not flip false for them.
    /// This is WalletEnvironment's one deliberate DashSync read.
    /// TODO(C6-E): drop the DashSync term when the
    /// `standardWalletWithSeedPhrase` dual-write is deleted.
    @objc public static var hasWallet: Bool {
        hasSDKWallet || DWEnvironment.sharedInstance().currentChain.hasAWallet
    }

    private override init() {}
}

extension String {
    /// Dash address validity for the app's CURRENT network, via SwiftDashSDK's
    /// `Address.validate` (P2PKH + P2SH version bytes) against
    /// `WalletEnvironment.network`. devnet/unsupported network ⇒ `false`
    /// (fail-fast, same contract as the wallet runtime). The app's single
    /// expression of this rule — replaces DashSync's
    /// `isValidDashAddress(on: DSChain)` at every call site.
    var isValidDashAddressForCurrentNetwork: Bool {
        guard let network = WalletEnvironment.network else { return false }
        return Address.validate(self, network: network)
    }
}
