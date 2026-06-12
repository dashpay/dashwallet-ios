//
//  CoinJoinRecovery.swift
//  DashWallet
//
//  One-time CoinJoin "mixed coins" recovery bookkeeping for the DashSync →
//  SwiftDashSDK migration.
//
//  CoinJoin mixed coins live on a separate derivation path (BIP44 purpose 4')
//  that the SDK scans at a narrow default address gap limit (30). DashSync used
//  400. CoinJoin scatters address usage with large holes, so a fresh
//  post-migration scan at gap 30 would silently miss deep coins → balance
//  understated, funds appear lost.
//
//  The wide recovery window runs ONCE on the first launch (per network) of
//  every wallet, then reverts to the fast default gap. We deliberately do NOT
//  detect "did this wallet use CoinJoin?" first: that signal (DashSync's
//  used-address state) isn't reliably loaded when the SDK SPV start reads it,
//  so detection silently skipped the widen and understated balances. A one-time
//  wide scan for every wallet (a near-empty scan for those that never mixed) is
//  the robust trade — a wider gap means more watched scripts → more BIP158
//  false positives → more full-block downloads, but only on that first scan.
//
//    • `needsWideRecoveryGap` (this file) returns true until a terminal
//      per-network flag is set — no DashSync read.
//    • `SwiftDashSDKSPVCoordinator.performStart` widens the CoinJoin gap (via
//      the SDK's `setCoinJoinGapLimit`) before `startSpv` while the flag is
//      unset, so the recovery scan covers the full window.
//    • Recovery is marked complete — reverting future launches to the fast
//      default gap — when the first full recovery-scan sync completes (the deep
//      coins it found are then persisted and reload at the default gap), or
//      when the coins are swept (`WalletSendService`). See
//      `SwiftDashSDKSPVCoordinator.maybeCompleteCoinJoinRecovery`.
//
//  This file no longer touches DashSync — it relies only on the SDK `Network`
//  and UserDefaults.
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWCoinJoinRecovery)
final class CoinJoinRecovery: NSObject {

    @objc static let shared = CoinJoinRecovery()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.coinjoin-recovery")

    /// Wide gap limit applied for the recovery scan. DashSync used 400
    /// (`SEQUENCE_GAP_LIMIT_INITIAL_COINJOIN`); we use a narrower window here.
    static let recoveryGapLimit: UInt32 = 100

    /// CoinJoin balances at or below this (duffs) are treated as "nothing worth
    /// sweeping" — the floor below which the post-sync "move funds" surfaces
    /// stay hidden (see `HomeViewModel`). Mirrors
    /// `SettingsMenuViewModel.minCoinJoinSweepDuffs`.
    static let recoveryDustThresholdDuffs: UInt64 = 1000

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private override init() { super.init() }

    // MARK: - Per-network UserDefaults keys

    private func networkTag(_ network: Network) -> String {
        network == .mainnet ? "mainnet" : "testnet"
    }
    /// Terminal per-network flag: set once the first full wide-gap scan
    /// completes (the deep coins it found are persisted thereafter) or the
    /// coins are swept. Once set we never widen again, even though DashSync's
    /// used-address history persists. (The older `…evaluated` / `…needed` keys
    /// are no longer used; any stale values are harmless.)
    private func recoveredKey(_ network: Network) -> String {
        "coinJoinRecovery.v1.recovered.\(networkTag(network))"
    }

    // MARK: - API

    /// Whether the one-time wide CoinJoin recovery gap should be applied for
    /// `network`. True until the recovery scan has completed once (then the
    /// terminal flag turns it off). Applied to every wallet on its first launch
    /// per network — no "did this wallet use CoinJoin?" detection, because that
    /// signal isn't reliably loaded when the SDK SPV start reads it. The full
    /// window is scanned once; the deep UTXOs it finds are persisted, so later
    /// launches load them at the default gap.
    func needsWideRecoveryGap(for network: Network) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !defaults.bool(forKey: recoveredKey(network))
    }

    /// Mark recovery complete for `network` — the first wide-gap scan completed
    /// (deep coins now persisted), or the coins were swept — so future launches
    /// revert to the fast default gap. Idempotent and thread-safe.
    func markRecovered(for network: Network) {
        lock.lock(); defer { lock.unlock() }
        guard !defaults.bool(forKey: recoveredKey(network)) else { return }
        defaults.set(true, forKey: recoveredKey(network))
        Self.logger.info(
            "🪙 CJRECOV :: recovery complete for \(self.networkTag(network), privacy: .public) — reverting to default gap")
    }

    /// Clear the terminal per-network recovery flags on a wallet wipe so a
    /// wallet restored afterwards re-runs the one-time wide CoinJoin scan. The
    /// flag is app-level (UserDefaults), not per-wallet, and a wipe deletes the
    /// persisted deep UTXOs, so without this a restored heavy-mixer wallet would
    /// skip the wide scan and understate its balance. Clears BOTH networks —
    /// the wipe removes all wallet material and we don't know the next restored
    /// wallet's network; `recoveredKey` only ever produces those two keys.
    /// Thread-safe.
    func resetForWipe() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: recoveredKey(.mainnet))
        defaults.removeObject(forKey: recoveredKey(.testnet))
        Self.logger.info(
            "🪙 CJRECOV :: recovery flags cleared on wipe — next wallet re-runs the one-time wide scan")
    }
}
