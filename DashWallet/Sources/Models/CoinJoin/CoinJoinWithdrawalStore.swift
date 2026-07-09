//
//  CoinJoinWithdrawalStore.swift
//  DashWallet
//
//  Persists the txids of CoinJoin "offload" sweeps the app performed, so the
//  home screen can group them into the "CoinJoin Withdrawals" cell.
//
//  Tagging (not role-based detection) is deliberate: a coinjoin→BIP44 move can
//  also be a historical/manual move or a payment, so only the sweep the app
//  itself broadcast (via `WalletSendService.sweepCoinJoin`) is recorded here.
//
//  txids are stored in WIRE order — the orientation of
//  `PersistentTransaction.txid` / `Transaction.txHashData` — so callers can
//  match with `contains(tx.txHashData)` directly. The sweep's
//  `SwiftDashSDKTransactionSender` returns WIRE-order txids, which are recorded
//  here directly with no reversal; byte-reversal to display order happens only
//  at logging sites (to match block explorers).
//

import Foundation

final class CoinJoinWithdrawalStore {

    static let shared = CoinJoinWithdrawalStore()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    /// Legacy (pre-multi-wallet) global key. Kept as the migration source and as
    /// the fallback when no wallet is active; the effective key is scoped per
    /// wallet (`<legacyKey>_<activeWalletIdHex>`) so a swept txid recorded under
    /// wallet A isn't tagged as A's withdrawal while wallet B is active. Though
    /// txids are globally unique, the sweep belongs to one wallet's UTXOs, so the
    /// tag set is per wallet. `WalletEnvironment.activeWalletIdHex` reads only
    /// UserDefaults, so it stays off DashSync's main-thread-affine `currentChain`
    /// (safe from the background grouping queue).
    private let legacyKey = "coinJoinWithdrawal.v1.txids"
    /// Cache keyed by the resolved (per-wallet) key, so a wallet switch between
    /// accesses naturally re-reads the new wallet's set instead of serving the
    /// previous wallet's cached txids.
    private var cacheKey: String?
    private var cache: Set<Data>?

    private init() {}

    /// The active wallet's per-wallet key, or the legacy global key when no
    /// wallet is active. Seeds the per-wallet key once from the legacy value so a
    /// pre-multi-wallet install's recorded sweeps carry over to its wallet.
    private func resolvedKey() -> String {
        guard let walletIdHex = WalletEnvironment.activeWalletIdHex as String?,
              !walletIdHex.isEmpty else {
            return legacyKey
        }
        let key = "\(legacyKey)_\(walletIdHex)"
        if defaults.object(forKey: key) == nil,
           let legacyValue = defaults.array(forKey: legacyKey) {
            defaults.set(legacyValue, forKey: key)
        }
        return key
    }

    private func loaded() -> Set<Data> {
        let key = resolvedKey()
        if cacheKey == key, let cache { return cache }
        let stored = (defaults.array(forKey: key) as? [Data]) ?? []
        let set = Set(stored)
        cacheKey = key
        cache = set
        return set
    }

    /// Record a swept tx's txid (WIRE order). Idempotent and thread-safe.
    func record(txid: Data) {
        lock.lock(); defer { lock.unlock() }
        var set = loaded()
        guard !set.contains(txid) else { return }
        set.insert(txid)
        cache = set
        defaults.set(Array(set), forKey: resolvedKey())
    }

    /// Whether `txid` (WIRE order, e.g. `Transaction.txHashData`) is a recorded
    /// CoinJoin sweep. Thread-safe; cheap (in-memory `Set` lookup).
    func contains(_ txid: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return loaded().contains(txid)
    }

    /// Clear a SINGLE wallet's recorded sweep txids (used by the per-wallet
    /// Remove flow — the removed wallet may not be the active one, so address it
    /// by explicit `walletIdHex`). Thread-safe. Invalidates the in-memory cache
    /// if it currently holds that wallet's set.
    func clearForWallet(walletIdHex: String) {
        guard !walletIdHex.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let key = "\(legacyKey)_\(walletIdHex)"
        defaults.removeObject(forKey: key)
        if cacheKey == key {
            cacheKey = nil
            cache = nil
        }
    }

    /// Clear ALL recorded sweep txids on a full wallet wipe (which destroys every
    /// wallet): every wallet's per-wallet set (enumerated by prefix, since the
    /// walletIds are gone by wipe time) plus the dormant legacy key. Also resets
    /// the in-memory cache on the long-lived `shared` singleton so stale txids
    /// don't linger until the next process launch. Thread-safe.
    func resetForWipe() {
        lock.lock(); defer { lock.unlock() }
        for key in defaults.dictionaryRepresentation().keys {
            if key == legacyKey || key.hasPrefix("\(legacyKey)_") {
                defaults.removeObject(forKey: key)
            }
        }
        cacheKey = nil
        cache = nil
    }
}
