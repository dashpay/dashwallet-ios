//
//  AssetLockProbeStore.swift
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

/// Wallet-scoped, unverified consumption reports for exact asset-lock outpoints.
/// Automatic recovery skips these reports; an explicit authenticated user action
/// can recheck the same lock. A report never proves success or authorizes a new lock.
final class AssetLockProbeStore {

    static let shared = AssetLockProbeStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    /// V1 reports have no output index and cannot safely be migrated to a
    /// specific outpoint. Leave them unused until wallet cleanup; never turn
    /// them into a report about every output in their transaction.
    /// Scoped per wallet (`<storageKey>_<activeWalletIdHex>`) exactly as
    /// `CoinJoinWithdrawalStore` is: an outpoint probed while wallet A was
    /// active says nothing about wallet B. The bare key is the no-active-wallet
    /// fallback.
    private let legacyKey = "assetLockProbe.v1.alreadySpentTxids"
    private let storageKey = "assetLockProbe.v2.alreadySpentOutpoints"
    private var cacheKey: String?
    private var cache: Set<Data>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The storage key for an EXPLICIT wallet. Callers that suspend before
    /// writing must resolve their wallet up front and pass it here: the active
    /// wallet can change mid-flight, and using the active wallet would then file the
    /// result under whichever wallet happens to be active at write time.
    private func key(forWalletIdHex walletIdHex: String?) -> String {
        guard let walletIdHex, !walletIdHex.isEmpty else { return storageKey }
        return "\(storageKey)_\(walletIdHex)"
    }

    /// Hex id of the wallet a probe should be filed under, captured BEFORE the
    /// work that will report it. Nil when no wallet is active.
    static func currentWalletIdHex() -> String? {
        WalletEnvironment.activeWalletIdHex as String?
    }

    private func loaded(key: String) -> Set<Data> {
        if cacheKey == key, let cache { return cache }
        let stored = (defaults.array(forKey: key) as? [Data]) ?? []
        let set = Set(stored)
        cacheKey = key
        cache = set
        return set
    }

    private func outpointKey(_ txid: Data, vout: UInt32) -> Data {
        var index = vout.littleEndian
        return txid + withUnsafeBytes(of: &index) { Data($0) }
    }

    /// Record that `(txid, vout)` (WIRE order) was reported already spent.
    /// Idempotent and thread-safe.
    /// `walletIdHex` is the wallet the probe belongs to, captured before the
    /// network round-trip that produced it — passing it explicitly is what
    /// keeps a wallet switch during that round-trip from filing the result
    /// under the wrong wallet.
    func record(txid: Data, vout: UInt32, walletIdHex: String?) {
        let outpoint = outpointKey(txid, vout: vout)
        let key = key(forWalletIdHex: walletIdHex)
        lock.lock(); defer { lock.unlock() }
        var set = loaded(key: key)
        guard !set.contains(outpoint) else { return }
        set.insert(outpoint)
        cacheKey = key
        cache = set
        defaults.set(Array(set), forKey: key)
    }

    /// Whether this exact outpoint (WIRE-order txid) was reported already spent.
    /// Thread-safe; cheap. This report is not proof of consumption.
    func contains(_ txid: Data, vout: UInt32) -> Bool {
        contains(txid, vout: vout, walletIdHex: Self.currentWalletIdHex())
    }

    /// Explicit-wallet lookup for work that has already captured its runtime.
    func contains(_ txid: Data, vout: UInt32, walletIdHex: String?) -> Bool {
        let key = key(forWalletIdHex: walletIdHex)
        lock.lock(); defer { lock.unlock() }
        return loaded(key: key).contains(outpointKey(txid, vout: vout))
    }

    /// Clear a SINGLE wallet's probes (per-wallet Remove flow — the removed
    /// wallet may not be the active one, so it is addressed by explicit
    /// `walletIdHex`). Thread-safe.
    func clearForWallet(walletIdHex: String) {
        guard !walletIdHex.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let key = "\(storageKey)_\(walletIdHex)"
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: "\(legacyKey)_\(walletIdHex)")
        if cacheKey == key {
            cacheKey = nil
            cache = nil
        }
    }

    /// Clear every wallet's probes on a full wipe (walletIds are gone by then,
    /// so the per-wallet keys are enumerated by prefix), plus the dormant bare
    /// key, plus the in-memory cache on this long-lived singleton.
    func resetForWipe() {
        lock.lock(); defer { lock.unlock() }
        for key in defaults.dictionaryRepresentation().keys
        where key == legacyKey || key.hasPrefix("\(legacyKey)_")
            || key == storageKey || key.hasPrefix("\(storageKey)_") {
            defaults.removeObject(forKey: key)
        }
        cacheKey = nil
        cache = nil
    }
}
