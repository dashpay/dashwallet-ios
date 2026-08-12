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

import Combine
import Foundation
import SwiftDashSDK

/// Why wallet material was registered with SwiftDashSDK. Imported material
/// scans from the historical floor; only restore/reconstruction origins arm
/// the one-time Core-spend gate.
enum WalletMaterialOrigin {
    case fresh
    case userRestore
    case legacyMigration
    case reconstructed

    var scansHistoricalRange: Bool { self != .fresh }
    var armsInitialRestoreSync: Bool {
        switch self {
        case .userRestore, .legacyMigration, .reconstructed: return true
        case .fresh: return false
        }
    }
}

/// Durable lifecycle of the first Core scan for a restored wallet.
///
/// `completed` is deliberately retained as a tombstone: retrying an import is
/// idempotent and must not re-arm the gate. A reconstruction after local
/// SwiftData loss explicitly overrides it back to `pending`.
@MainActor
final class InitialRestoreSyncStore {
    enum State: String, Equatable {
        case pending
        case completed
    }

    static let shared = InitialRestoreSyncStore()
    static let didChangeNotification = Notification.Name(
        "DWInitialRestoreSyncStoreDidChange")

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let statesKey = "coreSpend.initialRestoreSync.v2.states"

    init(defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func state(walletId: Data) -> State? {
        guard let raw = states()[walletId.hexEncodedString()] else { return nil }
        return State(rawValue: raw)
    }

    func isPending(walletId: Data) -> Bool {
        state(walletId: walletId) == .pending
    }

    func markImportedIfNeeded(walletId: Data) {
        guard state(walletId: walletId) == nil else { return }
        set(.pending, walletId: walletId)
    }

    func markReconstructed(walletId: Data) {
        set(.pending, walletId: walletId)
    }

    func completeIfPending(walletId: Data) {
        guard state(walletId: walletId) == .pending else { return }
        set(.completed, walletId: walletId)
    }

    func remove(walletId: Data) {
        var values = states()
        guard values.removeValue(forKey: walletId.hexEncodedString()) != nil else { return }
        persist(values)
    }

    func removeAll() {
        guard defaults.object(forKey: statesKey) != nil else { return }
        defaults.removeObject(forKey: statesKey)
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }

    private func states() -> [String: String] {
        defaults.dictionary(forKey: statesKey) as? [String: String] ?? [:]
    }

    private func set(_ state: State, walletId: Data) {
        var values = states()
        let key = walletId.hexEncodedString()
        guard values[key] != state.rawValue else { return }
        values[key] = state.rawValue
        persist(values)
    }

    private func persist(_ values: [String: String]) {
        defaults.set(values, forKey: statesKey)
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}

enum CoreSpendAvailabilityError: LocalizedError, Equatable {
    case initialRestoreSync

    var errorDescription: String? {
        NSLocalizedString(
            "Your restored wallet is completing its initial sync. Sending from your Transparent balance will be available once it finishes.",
            comment: "Core spend blocked during a restored wallet's first sync")
    }
}

/// Thread-safe projection for legacy UIKit/ObjC call sites whose protocol
/// requirements are not actor-isolated. The policy owner writes it on the
/// main actor; readers never touch the wallet runtime directly.
private enum CoreSpendAvailabilitySnapshot {
    static let lock = NSLock()
    nonisolated(unsafe) static var blocked = false

    static func read() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    static func write(_ value: Bool) {
        lock.lock()
        blocked = value
        lock.unlock()
    }
}

/// One observable policy shared by UI projections and hard transaction
/// boundaries. The decision is scoped to the wallet actually bound by the
/// host, never the registry target (which changes before a wallet switch has
/// finished rebuilding the runtime).
@objc(DWCoreSpendAvailability)
@MainActor
final class CoreSpendAvailability: NSObject, ObservableObject {
    enum Decision: Equatable {
        case allowed
        case blockedInitialRestoreSync

        var isBlocked: Bool { self == .blockedInitialRestoreSync }
    }

    static let shared = CoreSpendAvailability()
    static let didChangeNotification = Notification.Name(
        "DWCoreSpendAvailabilityDidChange")

    @Published private(set) var decision: Decision = .allowed

    private let store: InitialRestoreSyncStore
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private let legacyMigrationSentinel = "coreSpend.initialRestoreSync.v2.legacyMigrated"

    init(store: InitialRestoreSyncStore? = nil,
         defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default,
         observesRuntime: Bool = true) {
        self.store = store ?? .shared
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        super.init()

        if observesRuntime {
            for name in [
                InitialRestoreSyncStore.didChangeNotification,
                SwiftDashSDKWalletState.activeWalletDidChangeNotification,
                .DWCurrentNetworkDidChange,
            ] {
                observers.append(notificationCenter.addObserver(
                    forName: name, object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.refresh() }
                    })
            }
            refresh()
        }
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    var isBlocked: Bool { decision.isBlocked }

    func requireAllowed() throws {
        guard !isBlocked else { throw CoreSpendAvailabilityError.initialRestoreSync }
    }

    /// ObjC pre-auth seam used by interactive BIP70.
    nonisolated static var blockedSnapshot: Bool {
        CoreSpendAvailabilitySnapshot.read()
    }

    @objc nonisolated class func coreSpendBlockedError() -> NSError? {
        guard blockedSnapshot else { return nil }
        return CoreSpendAvailabilityError.initialRestoreSync as NSError
    }

    func refresh() {
        guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            apply(.allowed)
            return
        }

        migrateLegacyFlagIfNeeded(to: walletId)
        apply(store.isPending(walletId: walletId)
            ? .blockedInitialRestoreSync
            : .allowed)
    }

    private func apply(_ newDecision: Decision) {
        CoreSpendAvailabilitySnapshot.write(newDecision.isBlocked)
        guard decision != newDecision else { return }
        decision = newDecision
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }

    private func migrateLegacyFlagIfNeeded(to walletId: Data) {
        guard !defaults.bool(forKey: legacyMigrationSentinel) else { return }
        let options = DWGlobalOptions.sharedInstance()
        if options.isResyncingWallet {
            // Crash-safe order: durable scoped marker, sentinel, legacy clear.
            store.markImportedIfNeeded(walletId: walletId)
        }
        defaults.set(true, forKey: legacyMigrationSentinel)
        options.isResyncingWallet = false
    }
}

/// DashSync-free network identity + wallet presence for the app.
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

    /// The persisted network selection. A missing key means mainnet — testnet
    /// is reached only through `switchToNetwork(_:)`, the key's sole writer.
    /// Unknown raw values classify as `.devnet` (unsupported).
    public static var networkKind: NetworkKind {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: currentChainTypeKey) != nil else { return .mainnet }
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
    /// Posting `DWCurrentNetworkDidChangeNotification` is what actually moves
    /// the app: the SDK wallet runtime restarts SPV for the new network and
    /// DWRootModel rebuilds the home stack.
    @MainActor
    @discardableResult
    public static func switchToNetwork(_ kind: NetworkKind) -> Bool {
        guard kind != networkKind else { return true }
        guard kind != .devnet else { return false }

        // The DashPay mirror (username + registration flag) is a single
        // global slot while identities are per-network — without this, a
        // testnet-registered username keeps rendering after switching to
        // mainnet (avatar, menu, Join DashPay gating all read the mirror).
        // Clearing is safe: re-entering a network that has a registered
        // identity re-backfills the mirror from the SDK's
        // `PersistentIdentity` rows on the next read
        // (`DWCurrentUserIdentityInfo`'s self-heal).
        DWGlobalOptions.sharedInstance().dashpayUsername = nil
        DWGlobalOptions.sharedInstance().dashpayRegistrationCompleted = false

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
    /// `WalletEnvironment.network`. devnet/unsupported network ⇒ `false`
    /// (fail-fast, same contract as the wallet runtime). The app's single
    /// expression of this rule — replaces DashSync's
    /// `isValidDashAddress(on: DSChain)` at every call site.
    var isValidDashAddressForCurrentNetwork: Bool {
        guard let network = WalletEnvironment.network else { return false }
        return Address.validate(self, network: network)
    }
}
