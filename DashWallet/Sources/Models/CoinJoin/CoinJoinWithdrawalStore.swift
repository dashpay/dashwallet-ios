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
//  `SwiftDashSDKTransactionSender` hands back a display-order (byte-reversed)
//  hash, so the recording site reverses it before calling `record`.
//

import Foundation

final class CoinJoinWithdrawalStore {

    static let shared = CoinJoinWithdrawalStore()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    /// Single global set: txids are globally unique, so no per-network scoping
    /// is needed (and we avoid touching DashSync's main-thread-affine
    /// `currentChain` from the background grouping queue).
    private let key = "coinJoinWithdrawal.v1.txids"
    private var cache: Set<Data>?

    private init() {}

    private func loaded() -> Set<Data> {
        if let cache { return cache }
        let stored = (defaults.array(forKey: key) as? [Data]) ?? []
        let set = Set(stored)
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
        defaults.set(Array(set), forKey: key)
    }

    /// Whether `txid` (WIRE order, e.g. `Transaction.txHashData`) is a recorded
    /// CoinJoin sweep. Thread-safe; cheap (in-memory `Set` lookup).
    func contains(_ txid: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return loaded().contains(txid)
    }
}
