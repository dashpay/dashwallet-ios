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
import UIKit

/// DashSync-free network identity + wallet presence for the app.
///
/// Owns the persisted network selection — the `CURRENT_CHAIN_TYPE_KEY`
/// UserDefaults integer holding a DashSync `ChainType_Tag` raw value
/// (`0` mainnet / `1` testnet / `2` devnet; `dash_shared_core.h`).
/// `switchToNetwork(_:)` is the sole writer of the key; everything else here
/// is a static reader. Mainnet and testnet are always selectable; devnet is
/// offered only by internal builds (`isDevnetAvailable`) and additionally
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

    /// Whether this build offers devnet at all.
    ///
    /// Devnet is a development network whose coordinates the user types in;
    /// it exists only in internal builds, which compile with `DASH_DEVNET`
    /// (see the `DASH_DEVNET_FLAGS` build setting). Shipping builds define
    /// nothing, and then the network is unreachable end to end:
    /// `networkKind` never resolves to it, `switchToNetwork(_:)` refuses it,
    /// and neither the network-picker entry nor the Devnet Settings row is
    /// built.
    #if DASH_DEVNET
    public static let isDevnetAvailable = true
    #else
    public static let isDevnetAvailable = false
    #endif

    /// The persisted network selection. A missing key means mainnet —
    /// testnet/devnet are reached only through `switchToNetwork(_:)`, the
    /// key's sole writer. Unknown raw values (which the writer never
    /// produces) classify as `.mainnet`, same as a missing key — devnet is a
    /// real, startable network now, so garbage must not select it.
    ///
    /// A persisted devnet selection also classifies as `.mainnet` in a build
    /// without `DASH_DEVNET`: an internal build can be replaced in place by
    /// a shipping one, and the shipping one has no UI left to switch back.
    public static var networkKind: NetworkKind {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: currentChainTypeKey) != nil else { return .mainnet }
        let kind = NetworkKind(rawValue: defaults.integer(forKey: currentChainTypeKey)) ?? .mainnet
        guard kind != .devnet || isDevnetAvailable else { return .mainnet }
        return kind
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
    /// is on `kind` afterwards (including the already-there no-op). Devnet is
    /// rejected outright in a build without `DASH_DEVNET`; where it is
    /// offered, whether it can actually START is the runtime's concern
    /// (`DevnetConfiguration.isConfigured`), not this key's.
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
        // Devnet exists only in internal builds. Refuse it elsewhere rather
        // than persisting a selection nothing downstream can act on.
        guard kind != .devnet || isDevnetAvailable else { return false }
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

    /// The registry kind for an SDK `Network`. Total over the three
    /// selectable networks; `.regtest` (which nothing can persist a wallet
    /// on) falls back to testnet rather than silently claiming mainnet.
    static func networkKind(for network: SwiftDashSDK.Network) -> NetworkKind {
        switch network {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        default: return .testnet
        }
    }

    // MARK: - Devnet first-entry provisioning

    private static let devnetProvisioningSourceWalletIdKey =
        "DW_DEVNET_PROVISIONING_SOURCE_WALLET_ID"

    /// The wallet that was active when the user asked to enter devnet.
    ///
    /// First devnet entry provisions the phrase the user was actually on and
    /// binds its devnet twin. Which wallet that is used to be read only from
    /// `WalletLifecycleTransitionState`, which is in-memory: kill the app
    /// mid-switch — the switch persists the network selection before it
    /// awaits discovery and startup — and the next launch would come up on
    /// devnet with no source, provision every stored phrase, and pin an
    /// arbitrary `firstWallet`. Persisting the id here is what survives that
    /// suspension.
    ///
    /// Kept (not cleared) after provisioning: a devnet→devnet restart, such
    /// as pointing the app at a different devnet, is not a network switch
    /// and would otherwise fall back to the same arbitrary pin. It is
    /// overwritten on the next switch into devnet, and a stale id whose
    /// mnemonic is gone simply resolves to nil.
    static var devnetProvisioningSourceWalletId: Data? {
        get { UserDefaults.standard.data(forKey: devnetProvisioningSourceWalletIdKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: devnetProvisioningSourceWalletIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: devnetProvisioningSourceWalletIdKey)
            }
        }
    }

    /// SwiftDashSDK wallet presence — a mnemonic persisted in `WalletStorage`'s
    /// keychain (see `SwiftDashSDKHost.hasPersistedSDKWallet`). The SDK
    /// runtime's own start gate; app-level existence checks use `hasWallet`.
    @objc public static var hasSDKWallet: Bool {
        SwiftDashSDKHost.hasPersistedSDKWallet()
    }

    /// App-level wallet presence with the locked-device case kept apart.
    ///
    /// `hasWallet` answers "is there definitely a wallet this build can
    /// select?" and stays `false` whenever that cannot be established — the
    /// right posture for every gate that merely skips work. The launch
    /// decision, wallet creation and the recover screen's wipe branch are
    /// different: acting on a `false` that only means "the Keychain could not
    /// be read" offers Create/Recover over a funded wallet, or generates a
    /// second one. Those callers read this instead and hold on `.unknown`.
    @objc(DWWalletPresence)
    public enum WalletPresence: Int {
        case absent = 0
        case present = 1
        /// The mnemonic inventory could not be read — the device is locked
        /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), or the Keychain
        /// failed for another reason. Says nothing about whether a wallet
        /// exists; re-read once protected data is available.
        case unknown = 2
    }

    /// Whether keychain items stored "when unlocked" — the mnemonics, the
    /// DashSync material — are readable right now. False for a background
    /// launch on a locked device. `UIApplication.isProtectedDataAvailable`
    /// is main-thread state; a reader on a worker queue (the receive model's
    /// presence check) hops over for the one Bool. The migrator reads it on
    /// its caller's thread before hopping to its own queue. Injectable so
    /// the presence classification can be tested without an application.
    nonisolated(unsafe) static var isProtectedDataAvailable: () -> Bool = {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable }
        }
    }

    /// Pure composition of the Keychain read and the selectable-material
    /// gate, so the routing can be tested without a Keychain. The gate
    /// answers nil when its own Keychain read failed: a present inventory
    /// whose material cannot be classified is unknown, not selectable.
    static func walletPresence(
        hostPresence: SwiftDashSDKHost.PersistedWalletPresence,
        hasSelectableMaterial: () -> Bool?
    ) -> WalletPresence {
        switch hostPresence {
        case .unknown: return .unknown
        case .absent: return .absent
        case .present:
            switch hasSelectableMaterial() {
            case .some(true): return .present
            case .some(false): return .absent
            case .none: return .unknown
            }
        }
    }

    @objc public static var walletPresence: WalletPresence {
        walletPresence(
            hostPresence: SwiftDashSDKHost.persistedSDKWalletPresence(),
            hasSelectableMaterial: { isDevnetAvailable ? true : hasSelectableWalletMaterial })
    }

    @objc public static var isWalletPresenceUnknown: Bool {
        walletPresence == .unknown
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
    ///
    /// Material this build cannot select does not count. A devnet-only
    /// inventory is reachable in an internal build and invisible in a shipping
    /// one: `networkKind` maps the persisted devnet selection to mainnet,
    /// `switchToNetwork` refuses devnet, and `recoverPersistedWallet` rightly
    /// refuses to replay a devnet id through a mainnet or testnet manager. If
    /// this gate still claimed a wallet, startup would fail `walletNotFound`
    /// with no onboarding offered — a dead end with the user's phrase sitting
    /// in the keychain. Reporting "no wallet" routes them to restore, and the
    /// devnet material is left untouched for the next internal build.
    @objc public static var hasWallet: Bool {
        guard hasSDKWallet else { return false }
        guard !isDevnetAvailable else { return true }
        // nil — the material could not be read — is not a wallet this build
        // can select; `walletPresence` reports it as unknown.
        return hasSelectableWalletMaterial == true
    }

    /// Whether any persisted wallet belongs to a network this build can
    /// select. Cached: the answer needs `SwiftDashSDKStoredWalletNetworkResolver`
    /// to derive ids from each stored phrase, which is far too expensive for a
    /// gate read on every launch and background-task path. Invalidated by
    /// `invalidateWalletMaterialCache()` wherever wallet material changes:
    /// creation and the key migrator (`SwiftDashSDKWalletRuntime`'s
    /// `handleWalletMaterialChanged()`), the full wipe, and the per-wallet
    /// removal the Wallets screen runs (`deleteLogicalWallet`).
    ///
    /// Guarded by `walletMaterialCacheLock`: the getter above is `@objc` and,
    /// as its own doc says, read from background-task paths, so this is not
    /// confined to one actor. The lock is never held across the derivation
    /// below — two concurrent misses recompute the same answer, which is
    /// idempotent, and holding it would serialize a Keychain-heavy read.
    ///
    /// `walletMaterialCacheGeneration` is what makes that safe against an
    /// invalidation that lands WHILE a derivation is in flight. Without it the
    /// deriving reader would store its now-obsolete verdict after
    /// `invalidateWalletMaterialCache()` cleared the cache, silently undoing
    /// the invalidation for the rest of the process — exactly the
    /// `walletNotFound` dead end the invalidation exists to prevent. The
    /// generation is read before deriving and re-checked before storing.
    private static let walletMaterialCacheLock = NSLock()
    private static var cachedSelectableWalletMaterial: Bool?
    private static var walletMaterialCacheGeneration: UInt64 = 0

    /// Durable memo of that verdict, keyed by the Keychain inventory it was
    /// derived from.
    ///
    /// Computing it needs `SwiftDashSDKStoredWalletNetworkResolver`, which
    /// constructs a SwiftDashSDK wallet for every stored phrase on every
    /// storable network — native mnemonic derivation and account creation,
    /// reached synchronously through the `@objc` presence getter the
    /// root-controller check calls during launch. The in-memory cache above
    /// does not survive a cold start, so that work was repeated on every
    /// launch of a build without `DASH_DEVNET`. Persisting the answer next to
    /// a fingerprint of the ids it was computed from keeps later launches to
    /// one attributes-only Keychain enumeration; the derivation runs again
    /// only when the stored set actually changes.
    struct SelectableWalletMaterialMemo: Equatable {
        static let valueKey = "DW_SELECTABLE_WALLET_MATERIAL"
        static let fingerprintKey = "DW_SELECTABLE_WALLET_MATERIAL_FINGERPRINT"

        let fingerprint: String
        let selectable: Bool

        /// Order-independent identity of a wallet-id inventory. Wallet ids are
        /// derived from the phrases, so the set changing is exactly when the
        /// classification can change.
        static func fingerprint(of walletIds: [Data]) -> String {
            walletIds
                .map { $0.map { byte in String(format: "%02x", byte) }.joined() }
                .sorted()
                .joined(separator: ",")
        }

        /// The memoized verdict, or nil when it was computed for a different
        /// inventory and must not be trusted.
        func verdict(for fingerprint: String) -> Bool? {
            self.fingerprint == fingerprint ? selectable : nil
        }

        static func load(from defaults: UserDefaults) -> SelectableWalletMaterialMemo? {
            guard let fingerprint = defaults.string(forKey: fingerprintKey),
                  defaults.object(forKey: valueKey) != nil else { return nil }
            return SelectableWalletMaterialMemo(
                fingerprint: fingerprint,
                selectable: defaults.bool(forKey: valueKey))
        }

        func save(to defaults: UserDefaults) {
            defaults.set(fingerprint, forKey: Self.fingerprintKey)
            defaults.set(selectable, forKey: Self.valueKey)
        }
    }

    /// nil when the Keychain read behind the verdict failed (the device is
    /// locked, or the Keychain is failing): unknown, not empty and not
    /// selectable — and never cached, so the next read after unlock derives
    /// the real answer instead of inheriting a verdict the lock produced.
    private static var hasSelectableWalletMaterial: Bool? {
        walletMaterialCacheLock.lock()
        let cached = cachedSelectableWalletMaterial
        let generation = walletMaterialCacheGeneration
        walletMaterialCacheLock.unlock()
        if let cached { return cached }
        let selectable: Bool
        do {
            let fingerprint = SelectableWalletMaterialMemo.fingerprint(
                of: try SwiftDashSDKHost.persistedWalletIds())
            if let memoized = SelectableWalletMaterialMemo
                .load(from: .standard)?.verdict(for: fingerprint) {
                selectable = memoized
            } else {
                let networks = try SwiftDashSDKHost.persistedSDKWalletNetworks()
                selectable = networks.contains { $0 != .devnet }
                SelectableWalletMaterialMemo(fingerprint: fingerprint, selectable: selectable)
                    .save(to: .standard)
            }
        } catch {
            return nil
        }
        walletMaterialCacheLock.lock()
        // Only if nothing invalidated the cache while this derivation ran: a
        // verdict that predates the change is stale, and storing it would
        // reinstate the answer the invalidation just dropped.
        if walletMaterialCacheGeneration == generation {
            cachedSelectableWalletMaterial = selectable
        }
        walletMaterialCacheLock.unlock()
        return selectable
    }

    /// Drop the cached verdict above. Called wherever wallet material is
    /// created, imported or deleted.
    @objc public static func invalidateWalletMaterialCache() {
        walletMaterialCacheLock.lock()
        cachedSelectableWalletMaterial = nil
        // Bumped under the same lock, so a derivation already in flight sees a
        // changed generation and discards its result instead of storing it.
        walletMaterialCacheGeneration &+= 1
        walletMaterialCacheLock.unlock()
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
