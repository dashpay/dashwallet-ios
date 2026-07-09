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
/// Owns the persisted network selection — the `CURRENT_CHAIN_TYPE_KEY`
/// UserDefaults integer holding a DashSync `ChainType_Tag` raw value
/// (`0` mainnet / `1` testnet / `2` devnet; `dash_shared_core.h`).
/// `switchToNetwork(_:)` is the sole writer of the key; everything else here
/// is a static reader. A stored devnet value is reported as-is (devnet ⇒
/// `network == nil`, both bools false), matching the runtime's fail-fast
/// handling of unsupported networks.
///
/// Not a singleton — a stateless namespace of static members over
/// UserDefaults (no instances, no mutable state, nothing to inject).
@objc(DWWalletEnvironment)
public final class WalletEnvironment: NSObject {
    /// Raw values mirror DashSync's `ChainType_Tag` C enum — the historical
    /// (and still persisted) encoding of `CURRENT_CHAIN_TYPE_KEY`.
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

    /// Display name of the current network ("Mainnet"/"Testnet"/"Devnet") —
    /// same strings DashSync's `DSChain.name` produced for the supported nets.
    @objc public static var networkDisplayName: String {
        switch networkKind {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        case .devnet: return "Devnet"
        }
    }

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

    /// Switches the persisted network selection. Returns `true` when the app
    /// is on `kind` afterwards (including the already-there no-op), `false`
    /// for `.devnet` (no SDK network exists for it).
    ///
    /// Before writing the key, mirrors the frozen DashSync wallet registry
    /// onto the destination chain from the SDK-persisted mnemonic — nonnull
    /// `DWEnvironment.currentWallet` consumers (DashPay, xpub export, watch)
    /// must keep resolving on the new network until the C6-E dual-write cut.
    /// The mirror derives BIP39 material synchronously (~100 ms).
    ///
    /// Posting `DWCurrentNetworkDidChangeNotification` is what actually moves
    /// the app: the SDK wallet runtime restarts SPV for the new network and
    /// DWRootModel rebuilds the home stack.
    @MainActor
    @discardableResult
    public static func switchToNetwork(_ kind: NetworkKind) -> Bool {
        guard kind != networkKind else { return true }
        guard kind != .devnet else { return false }

        let mnemonic = SwiftDashSDKHost.persistedMnemonics().first?.mnemonic
        guard DWEnvironment.sharedInstance().mirrorWalletRegistry(toChainType: kind.rawValue,
                                                                  seedPhrase: mnemonic) else {
            return false
        }

        UserDefaults.standard.set(kind.rawValue, forKey: currentChainTypeKey)
        NotificationCenter.default.post(name: NSNotification.Name.DWCurrentNetworkDidChange, object: nil)
        return true
    }

    /// SwiftDashSDK wallet presence — a mnemonic persisted in `WalletStorage`'s
    /// keychain (see `SwiftDashSDKHost.hasPersistedSDKWallet`). The SDK
    /// runtime's own start gate; app-level existence checks use `hasWallet`.
    @objc public static var hasSDKWallet: Bool {
        SwiftDashSDKHost.hasPersistedSDKWallet()
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
