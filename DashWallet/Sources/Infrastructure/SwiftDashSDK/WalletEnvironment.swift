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
///
/// Owns the persisted network selection — the `CURRENT_CHAIN_TYPE_KEY`
/// UserDefaults integer holding a DashSync `ChainType_Tag` raw value
/// (`0` mainnet / `1` testnet / `2` devnet; `dash_shared_core.h`).
/// `switchToNetwork(_:)` is the sole writer of the key; everything else here
/// is a static reader. All three networks are selectable; devnet additionally
/// requires the user-supplied coordinates in `DevnetConfiguration` before the
/// runtime can start on it.
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

    /// The persisted network selection. A missing key means mainnet —
    /// testnet/devnet are reached only through `switchToNetwork(_:)`, the
    /// key's sole writer. Unknown raw values (which the writer never
    /// produces) classify as `.mainnet`, same as a missing key — devnet is a
    /// real, startable network now, so garbage must not select it.
    public static var networkKind: NetworkKind {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: currentChainTypeKey) != nil else { return .mainnet }
        return NetworkKind(rawValue: defaults.integer(forKey: currentChainTypeKey)) ?? .mainnet
    }

    @objc public static var isMainnet: Bool { networkKind == .mainnet }

    @objc public static var isTestnet: Bool { networkKind == .testnet }

    @objc public static var isDevnet: Bool { networkKind == .devnet }

    /// True on any test network (testnet OR devnet). The gate for features
    /// that mean "not real funds / not mainnet" — distinct from `isTestnet`,
    /// which stays literally "the testnet chain" (testnet faucet, testnet
    /// service endpoints, testnet-pinned contract ids).
    @objc public static var isTestNetwork: Bool { isTestnet || isDevnet }

    /// Display name of the current network ("Mainnet"/"Testnet"/"Devnet") —
    /// same strings DashSync's `DSChain.name` produced for the supported nets.
    @objc public static var networkDisplayName: String {
        switch networkKind {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        case .devnet: return "Devnet"
        }
    }

    /// The SwiftDashSDK network for the current selection. Optional for
    /// source compatibility with the fail-fast era (callers `guard let`);
    /// today every persisted `NetworkKind` maps to a concrete SDK network —
    /// devnet included — so this only returns `nil` if a future kind gains
    /// no SDK mapping.
    public static var network: SwiftDashSDK.Network? {
        switch networkKind {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        }
    }

    /// Origin of a network switch, carried in the change notification's
    /// `userInfo` so `SwiftDashSDKWalletRuntime`'s observer can tell a
    /// managed switch (the runtime's `switchNetwork(to:)` owns the mirror
    /// zeroing and the lifecycle refresh itself) from an external write
    /// (recovery, sole-network selection), which still gets the full
    /// observer behavior. Other listeners (DWRootModel, HomeViewModel,
    /// CrowdNode, …) ignore `userInfo` and are unaffected.
    public enum NetworkSwitchSource {
        case external
        case managedSwitch(transitionID: String)
    }

    /// `userInfo` keys of `DWCurrentNetworkDidChangeNotification`.
    static let networkChangeSourceKey = "DWNetworkChangeSource"
    static let networkChangeTransitionIDKey = "DWNetworkChangeTransitionID"
    private static let managedSwitchSourceValue = "managed-switch"

    /// Whether this `DWCurrentNetworkDidChange` notification was posted by a
    /// managed switch (`switchNetwork(to:)`), i.e. the runtime observer must
    /// NOT drive the lifecycle for it.
    nonisolated static func isManagedSwitchNotification(_ note: Notification) -> Bool {
        note.userInfo?[networkChangeSourceKey] as? String == managedSwitchSourceValue
    }

    /// Switches the persisted network selection. Returns `true` when the app
    /// is on `kind` afterwards (including the already-there no-op). All
    /// three kinds are accepted; whether devnet can actually START is the
    /// runtime's concern (`DevnetConfiguration.isConfigured`), not this
    /// key's.
    ///
    /// Posting `DWCurrentNetworkDidChangeNotification` is what actually moves
    /// the app: the SDK wallet runtime restarts SPV for the new network and
    /// DWRootModel rebuilds the home stack. A `.managedSwitch` source marks
    /// the notification so the runtime observer skips its lifecycle reaction
    /// (the caller owns exactly one refresh); every other listener behaves
    /// identically for both sources.
    @MainActor
    @discardableResult
    public static func switchToNetwork(
        _ kind: NetworkKind,
        source: NetworkSwitchSource = .external
    ) -> Bool {
        guard kind != networkKind else { return true }

        // The DashPay mirror (username + registration flag) is a single
        // global slot while identities are per-network — without this, a
        // testnet-registered username keeps rendering after switching to
        // mainnet (avatar, menu, Join DashPay gating all read the mirror).
        // This clears on every switch to a different network, including
        // attempts whose destination then fails to start. Re-entering a
        // network restores the mirror only when
        // `DWCurrentUserIdentityInfo`'s next snapshot read resolves a
        // confirmed username (the SDK DPNS cache, or the persisted
        // SwiftData name sources as its fallback); the self-heal never
        // re-sets the flag from identity existence alone, so an identity
        // with no resolvable name stays unmirrored.
        DWGlobalOptions.sharedInstance().dashpayUsername = nil
        DWGlobalOptions.sharedInstance().dashpayRegistrationCompleted = false

        UserDefaults.standard.set(kind.rawValue, forKey: currentChainTypeKey)
        var userInfo: [AnyHashable: Any]?
        if case .managedSwitch(let transitionID) = source {
            userInfo = [
                networkChangeSourceKey: managedSwitchSourceValue,
                networkChangeTransitionIDKey: transitionID,
            ]
        }
        NotificationCenter.default.post(
            name: NSNotification.Name.DWCurrentNetworkDidChange,
            object: nil,
            userInfo: userInfo)
        return true
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
    /// wallet on each of mainnet, testnet and devnet (the same posture as
    /// the per-network SwiftData store `SwiftDashSDKHost.buildModelContainer`
    /// builds). A missing key means "unset" — no wallet has been resolved on
    /// this network yet, and `SwiftDashSDKHost` falls back to `firstWallet`.
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
    /// registry. Nil only while no wallet is resolved on the current network.
    @objc public static var activeWalletIdHex: NSString? {
        guard let id = activeWalletId(for: networkKind) else { return nil }
        return id.map { String(format: "%02x", $0) }.joined() as NSString
    }

    /// App-level wallet existence is the SDK-owned mnemonic store. Upgrade-time
    /// DashSync mnemonics are imported by `SwiftDashSDKKeyMigrator` before the
    /// wallet runtime starts.
    @objc public static var hasWallet: Bool {
        hasSDKWallet
    }

    private override init() {}
}

extension Notification.Name {
    static let DWCurrentNetworkDidChange =
        Notification.Name("DWCurrentNetworkDidChangeNotification")
}

extension String {
    /// Dash address validity for the app's CURRENT network, via SwiftDashSDK's
    /// `Address.validate` (P2PKH + P2SH version bytes) against
    /// `WalletEnvironment.network` — devnet shares testnet's version bytes,
    /// which the SDK resolves itself. The app's single
    /// expression of this rule — replaces DashSync's
    /// `isValidDashAddress(on: DSChain)` at every call site.
    var isValidDashAddressForCurrentNetwork: Bool {
        guard let network = WalletEnvironment.network else { return false }
        return Address.validate(self, network: network)
    }
}
