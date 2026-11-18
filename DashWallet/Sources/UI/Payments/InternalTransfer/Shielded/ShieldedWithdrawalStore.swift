//
//  ShieldedWithdrawalStore.swift
//  DashWallet
//
//  Persists the destination Core addresses of Shielded → Core withdrawals the
//  app performed, so the home screen can classify the resulting incoming L1
//  transaction as "Shielded received".
//
//  Address tagging (not txid tagging) is deliberate: the SDK's
//  `shieldedWithdraw` is an opaque call that returns no txid, so the only
//  app-side handle on the payout is the fresh receive address resolved right
//  before the withdraw. Receive addresses are single-use in practice (the app
//  always hands out the next unused one), so an incoming tx paying a recorded
//  address is the withdrawal's payout.
//
//  Mirrors `CoinJoinWithdrawalStore`'s shape: per-wallet UserDefaults key,
//  NSLock-guarded in-memory cache (readable from the home screen's background
//  grouping queue), and the same wipe/remove lifecycle hooks in
//  `SwiftDashSDKWalletWiper`. No legacy-key migration — the store postdates
//  multi-wallet support.
//

import Foundation

final class ShieldedWithdrawalStore {

    static let shared = ShieldedWithdrawalStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    /// Per-wallet key prefix; the effective key is `<keyPrefix>_<walletIdHex>`
    /// so an address recorded under wallet A isn't tagged as A's withdrawal
    /// while wallet B is active. Falls back to the bare prefix when no wallet
    /// is active. `WalletEnvironment.activeWalletIdHex` reads only
    /// UserDefaults (safe from the background grouping queue).
    private let keyPrefix = "shieldedWithdrawal.v1.addresses"
    /// Cache keyed by the resolved (per-wallet) key, so a wallet switch
    /// between accesses re-reads the new wallet's set instead of serving the
    /// previous wallet's cached addresses.
    private var cacheKey: String?
    private var cache: Set<String>?

    /// Allows isolated persistence in tests while production uses the standard domain.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Resolve the active wallet for direct send/receipt callers that do not carry a snapshot id.
    private func resolvedKey() -> String {
        guard let walletIdHex = WalletEnvironment.activeWalletIdHex as String?,
              !walletIdHex.isEmpty else {
            return keyPrefix
        }
        return "\(keyPrefix)_\(walletIdHex)"
    }

    /// Load one explicit wallet key, replacing the single-wallet cache when its owner changes.
    /// Callers hold `lock` across this lookup and any following write.
    private func loaded(forKey key: String) -> Set<String> {
        if cacheKey == key, let cache { return cache }
        let stored = (defaults.array(forKey: key) as? [String]) ?? []
        let set = Set(stored)
        cacheKey = key
        cache = set
        return set
    }

    /// Record a withdrawal's destination Core address (Base58Check).
    /// Idempotent and thread-safe.
    func record(address: String) {
        guard !address.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let key = resolvedKey()
        var set = loaded(forKey: key)
        guard !set.contains(address) else { return }
        set.insert(address)
        cache = set
        defaults.set(Array(set), forKey: key)
    }

    /// Whether `address` is a recorded shielded-withdrawal destination.
    /// Thread-safe; cheap (in-memory `Set` lookup).
    func contains(_ address: String, walletIdHex: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let key = walletIdHex.map { "\(keyPrefix)_\($0)" } ?? resolvedKey()
        return loaded(forKey: key).contains(address)
    }

    /// Reconcile one wallet's observed withdrawal outcomes. A failed attempt
    /// retracts an earlier tag only when no non-failed attempt in the same
    /// snapshot shares its address. Tags for other addresses absent from the
    /// snapshot remain intact. The explicit wallet key
    /// prevents a background history refresh from affecting a newly selected wallet.
    func reconcile(walletIdHex: String, failed: Set<String>, nonFailed: Set<String>) {
        guard !walletIdHex.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let key = "\(keyPrefix)_\(walletIdHex)"
        let previous = loaded(forKey: key)
        let updated = previous.subtracting(failed.subtracting(nonFailed)).union(nonFailed)
        guard updated != previous else { return }
        cache = updated
        defaults.set(Array(updated), forKey: key)
    }

    /// Clear a SINGLE wallet's recorded addresses (per-wallet Remove flow —
    /// the removed wallet may not be the active one). Thread-safe.
    func clearForWallet(walletIdHex: String) {
        guard !walletIdHex.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let key = "\(keyPrefix)_\(walletIdHex)"
        defaults.removeObject(forKey: key)
        if cacheKey == key {
            cacheKey = nil
            cache = nil
        }
    }

    /// Clear ALL recorded addresses on a full wallet wipe (walletIds are gone
    /// by wipe time, so enumerate by prefix). Also resets the in-memory cache
    /// on the long-lived `shared` singleton. Thread-safe.
    func resetForWipe() {
        lock.lock(); defer { lock.unlock() }
        for key in defaults.dictionaryRepresentation().keys {
            if key == keyPrefix || key.hasPrefix("\(keyPrefix)_") {
                defaults.removeObject(forKey: key)
            }
        }
        cacheKey = nil
        cache = nil
    }
}
