//
//  SwiftDashSDKCoinJoinBalanceReader.swift
//  DashWallet
//
//  Reads the balance held in the wallet's CoinJoin account(s).
//
//  "Mixed coins" produced by CoinJoin live on a separate derivation path
//  (BIP44 purpose 4') and SwiftDashSDK tracks them in a distinct CoinJoin
//  account, scanned and balance-counted independently of the standard
//  BIP44 account. This reader sums the spendable (confirmed) balance across
//  those CoinJoin account(s) by querying the platform wallet manager's
//  per-account balances and filtering to the CoinJoin type tag.
//
//  Used by the post-migration "move your mixed coins" flow: CoinJoin is no
//  longer supported, so after SPV sync completes we check whether any funds
//  remain stranded in the CoinJoin account and, if so, offer to sweep them
//  into the user's spendable balance.
//
//  Returns 0 (never throws) when the host hasn't bound a wallet yet or the
//  read fails — callers treat 0 as "nothing to move".
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKCoinJoinBalanceReader)
final class SwiftDashSDKCoinJoinBalanceReader: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.coinjoin-balance")

    /// `AccountTypeTagFFI.CoinJoin` discriminant — see
    /// `platform-wallet-ffi.h` (`ACCOUNT_TYPE_TAG_FFI_COIN_JOIN = 1`).
    private static let coinJoinTypeTag: UInt8 = 1

    /// Only CoinJoin account 0 is created (`createDefaultAccounts`), and the
    /// sweep moves account 0 only — so the detection gate must match it, or it
    /// could report a balance the sweep won't move. If multi-index CoinJoin is
    /// ever added, update this reader AND the sweep together.
    private static let coinJoinAccountIndex: UInt32 = 0

    /// Total confirmed balance (in duffs) sitting across the wallet's
    /// CoinJoin account(s). Reads the live in-memory per-account balances
    /// maintained during SPV processing — no disk I/O.
    @objc
    static func coinJoinSpendableDuffs() -> UInt64 {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { readOnMain() }
        }
        var result: UInt64 = 0
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated { readOnMain() }
        }
        return result
    }

    @MainActor
    private static func readOnMain() -> UInt64 {
        let host = SwiftDashSDKHost.shared
        guard let manager = host.manager, let wallet = host.wallet else {
            Self.logger.warning("🪙 CJBAL :: host has no wallet/manager yet")
            return 0
        }

        let coinJoinEntries = manager
            .accountBalances(for: wallet.walletId)
            .filter { $0.typeTag == Self.coinJoinTypeTag && $0.index == Self.coinJoinAccountIndex }

        // confirmed + unconfirmed mirrors the sweep's `spendable_utxos` (mature,
        // unlocked, incl. 0-conf), so the gate never hides funds the sweep
        // would actually move.
        let total = coinJoinEntries.reduce(UInt64(0)) { $0 &+ $1.confirmed &+ $1.unconfirmed }

        Self.logger.info(
            "🪙 CJBAL :: coinjoin spendable balance = \(total, privacy: .public) duffs across \(coinJoinEntries.count, privacy: .public) entry(ies)")

        return total
    }

    /// 🧪 CJTEST (temporary): dump EVERY per-account balance entry the SDK
    /// tracks — type tag / index / confirmed / unconfirmed / keys — so we can
    /// see WHERE (if anywhere) funded coins land. If funded coins appear under a
    /// tag/index other than (1, 0) the reader+sweep filter is wrong; if they
    /// appear nowhere, the SDK isn't watching that address (path mismatch).
    /// Remove with the debug console before release.
    @MainActor
    static func debugDumpAllBalances() -> [String] {
        let host = SwiftDashSDKHost.shared
        guard let manager = host.manager, let wallet = host.wallet else {
            return ["host has no wallet/manager yet"]
        }
        let entries = manager.accountBalances(for: wallet.walletId)
        guard !entries.isEmpty else { return ["accountBalances: (empty)"] }
        return entries.map { e in
            "tag=\(e.typeTag) std=\(e.standardTag) idx=\(e.index) conf=\(e.confirmed) unconf=\(e.unconfirmed) imm=\(e.immature) keys=\(e.keysUsed)/\(e.keysTotal)"
        }
    }
}
