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

/// Funding asset locks we have already asked Platform about and been told are
/// already spent.
///
/// The SDK deliberately does NOT advance such a lock's status: the
/// already-consumed report arrives as a plain rejection from one DAPI node, not
/// as a quorum-authenticated proof, and stamping `Consumed` on an unverified
/// negative would permanently hide a lock that may still be recoverable
/// (`rs-platform-wallet` records it as "consumption unknown" instead).
///
/// That is the right call for the *status*, but it leaves the answer itself
/// nowhere: the coordinator's phase dies with the sheet, so the next launch
/// looks exactly like the first — "Completion unknown" and a live retry action
/// on every restored transfer. A wallet restored with a hundred shielded
/// transfers then shows a hundred permanently unfinished-looking rows.
///
/// This store records the weaker, honest fact — *we asked, and the network said
/// spent* — without claiming the transfer is proven complete. It is app-owned
/// and advisory: losing it costs one redundant probe, never money.
///
/// Superseded by a proved read of Platform's `SpentAssetLockTransactions` tree,
/// which would settle consumption authoritatively and let the status advance on
/// its own. Until that query exists client-side, this is the honest middle.
final class AssetLockProbeStore {

    static let shared = AssetLockProbeStore()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    /// Scoped per wallet (`<legacyKey>_<activeWalletIdHex>`) exactly as
    /// `CoinJoinWithdrawalStore` is: an outpoint probed while wallet A was
    /// active says nothing about wallet B. The bare key is the no-active-wallet
    /// fallback.
    private let legacyKey = "assetLockProbe.v1.alreadySpentTxids"
    private var cacheKey: String?
    private var cache: Set<Data>?

    private init() {}

    private func resolvedKey() -> String {
        guard let walletIdHex = WalletEnvironment.activeWalletIdHex as String?,
              !walletIdHex.isEmpty else {
            return legacyKey
        }
        return "\(legacyKey)_\(walletIdHex)"
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

    /// Record that `txid` (WIRE order) was probed and reported already spent.
    /// Idempotent and thread-safe.
    func record(txid: Data) {
        lock.lock(); defer { lock.unlock() }
        var set = loaded()
        guard !set.contains(txid) else { return }
        set.insert(txid)
        cache = set
        defaults.set(Array(set), forKey: resolvedKey())
    }

    /// Whether `txid` (WIRE order, e.g. `Transaction.txHashData`) has already
    /// been probed and answered "already spent". Thread-safe; cheap.
    func contains(_ txid: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return loaded().contains(txid)
    }

    /// Clear a SINGLE wallet's probes (per-wallet Remove flow — the removed
    /// wallet may not be the active one, so it is addressed by explicit
    /// `walletIdHex`). Thread-safe.
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

    /// Clear every wallet's probes on a full wipe (walletIds are gone by then,
    /// so the per-wallet keys are enumerated by prefix), plus the dormant bare
    /// key, plus the in-memory cache on this long-lived singleton.
    func resetForWipe() {
        lock.lock(); defer { lock.unlock() }
        for key in defaults.dictionaryRepresentation().keys
        where key == legacyKey || key.hasPrefix("\(legacyKey)_") {
            defaults.removeObject(forKey: key)
        }
        cacheKey = nil
        cache = nil
    }
}
