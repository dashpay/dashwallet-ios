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
//  To keep normal sync fast for everyone (a wider gap means more watched
//  scripts → more BIP158 false positives → more full-block downloads), the
//  wide recovery window is applied ONLY for wallets that actually used CoinJoin
//  and ONLY until recovery is complete:
//
//    • Detection (this file) reads DashSync's persisted used-CoinJoin-address
//      state — reconstructed from Core Data on account load, no network sync
//      needed — once per network, while DashSync is still linked. If the wallet
//      used CoinJoin, the per-network "recovery needed" flag is set.
//    • `SwiftDashSDKSPVCoordinator.performStart` widens the CoinJoin gap (via
//      the SDK's `setCoinJoinGapLimit`) before `startSpv` whenever the flag is
//      set, so the recovery scan covers the full window.
//    • Recovery is marked complete — reverting future launches to the fast
//      default gap — when the coins are swept (`WalletSendService`) or when a
//      full recovery-scan sync confirms there is nothing (left) to recover
//      (`SwiftDashSDKSPVCoordinator`).
//
//  This is the single app-side place that reads DashSync's CoinJoin history, so
//  it is the only file to revisit when DashSync is eventually unlinked.
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

    /// Wide gap limit applied for the recovery scan — matches DashSync's
    /// `SEQUENCE_GAP_LIMIT_INITIAL_COINJOIN`.
    static let recoveryGapLimit: UInt32 = 400

    /// CoinJoin balances at or below this (duffs) are treated as "nothing to
    /// recover". Mirrors `SettingsMenuViewModel.minCoinJoinSweepDuffs` so the
    /// flag clears exactly when the sweep surfaces stop offering to move funds.
    static let recoveryDustThresholdDuffs: UInt64 = 1000

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private override init() { super.init() }

    // MARK: - Per-network UserDefaults keys

    private func networkTag(_ network: Network) -> String {
        network == .mainnet ? "mainnet" : "testnet"
    }
    private func evaluatedKey(_ network: Network) -> String {
        "coinJoinRecovery.v1.evaluated.\(networkTag(network))"
    }
    private func neededKey(_ network: Network) -> String {
        "coinJoinRecovery.v1.needed.\(networkTag(network))"
    }

    // MARK: - API

    /// Whether the wide CoinJoin recovery gap should be applied for `network`.
    /// Lazily evaluates once per network (reading DashSync's persisted
    /// used-CoinJoin-address state); thereafter returns the stored flag.
    ///
    /// `@MainActor` because evaluation touches DashSync's `DSAccount`
    /// (Core Data, main-thread-affine). Called from `performStart` (@MainActor).
    @MainActor
    func needsWideRecoveryGap(for network: Network) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if !defaults.bool(forKey: evaluatedKey(network)) {
            evaluateLocked(for: network)
        }
        return defaults.bool(forKey: neededKey(network))
    }

    /// Mark recovery complete for `network` — coins swept, or the wide scan
    /// confirmed there is nothing to recover — so future launches revert to
    /// the fast default gap. Idempotent and thread-safe.
    func markRecovered(for network: Network) {
        lock.lock(); defer { lock.unlock() }
        guard defaults.bool(forKey: neededKey(network)) else { return }
        defaults.set(false, forKey: neededKey(network))
        Self.logger.info(
            "🪙 CJRECOV :: recovery complete for \(self.networkTag(network), privacy: .public) — reverting to default gap")
    }

    /// Convenience for callers that don't carry an SDK `Network` (e.g. the
    /// sweep success path): mark recovery complete for whatever network
    /// DashSync's chain is currently on. Call on the main thread.
    @objc func markCurrentNetworkRecovered() {
        let network: Network = DWEnvironment.sharedInstance().currentChain.isMainnet() ? .mainnet : .testnet
        markRecovered(for: network)
    }

    // MARK: - Detection (DashSync-backed, one-time per network)

    @MainActor
    private func evaluateLocked(for network: Network) {
        // Only evaluate when DashSync's current chain matches the network we're
        // about to scan, so we read the right chain's CoinJoin history. If they
        // don't match yet, defer (leave unevaluated) and retry next launch.
        let chainIsMainnet = DWEnvironment.sharedInstance().currentChain.isMainnet()
        guard (network == .mainnet) == chainIsMainnet else {
            Self.logger.info(
                "🪙 CJRECOV :: chain/network mismatch — deferring evaluation for \(self.networkTag(network), privacy: .public)")
            return
        }

        // `usedCoinJoinReceiveAddresses` is reconstructed from DashSync's
        // persisted address-usage (Core Data) on account load — no fresh sync
        // required. count > 0 ⇒ this wallet has CoinJoin history. `currentAccount`
        // is non-optional (NS_ASSUME_NONNULL) and loaded by the time the SDK
        // SPV start runs; only the addresses array itself is nullable.
        let usedCount = DWEnvironment.sharedInstance().currentAccount
            .usedCoinJoinReceiveAddresses?.count ?? 0
        let needed = usedCount > 0

        defaults.set(needed, forKey: neededKey(network))
        defaults.set(true, forKey: evaluatedKey(network))
        Self.logger.info(
            "🪙 CJRECOV :: evaluated \(self.networkTag(network), privacy: .public) — usedCoinJoinAddresses=\(usedCount, privacy: .public) → recoveryNeeded=\(needed, privacy: .public)")
    }
}
