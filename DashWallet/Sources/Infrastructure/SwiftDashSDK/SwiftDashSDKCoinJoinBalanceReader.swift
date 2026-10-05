//
//  SwiftDashSDKCoinJoinBalanceReader.swift
//  DashWallet
//
//  Reads the balance held in the wallet's CoinJoin account.
//
//  "Mixed coins" produced by CoinJoin live on a separate derivation path
//  (BIP44 purpose 4') and SwiftDashSDK tracks them in a distinct CoinJoin
//  account, scanned and balance-counted independently of the standard
//  BIP44 account. This reader asks the core wallet for the spendable
//  balance of CoinJoin account 0 — the same UTXO set the sweep moves.
//
//  Used by the post-migration "move your mixed coins" flow: CoinJoin is no
//  longer supported, so after SPV sync completes we check whether any funds
//  remain stranded in the CoinJoin account and, if so, offer to sweep them
//  into the user's spendable balance.
//
//  Returns nil (never throws) when the read fails, so a failed read stays
//  distinct from an empty account — callers treat 0 as "nothing to move".
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKCoinJoinBalanceReader)
final class SwiftDashSDKCoinJoinBalanceReader: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.coinjoin-balance")

    /// Only CoinJoin account 0 is created (`createDefaultAccounts`), and the
    /// sweep moves account 0 only — so the detection gate must match it, or it
    /// could report a balance the sweep won't move. If multi-index CoinJoin is
    /// ever added, update this reader AND the sweep together.
    private static let coinJoinAccountIndex: UInt32 = 0

    /// Dedicated queue parking the blocking read. The read waits on the
    /// wallet-manager read lock, which SPV block processing or a persister
    /// commit can hold for seconds, so it must not run on the main thread. A
    /// plain GCD queue, never `Task.detached` — the blocking FFI would park a
    /// cooperative-pool thread. Serial on purpose: the caller coalesces to one
    /// read in flight.
    private static let readQueue = DispatchQueue(
        label: "org.dashfoundation.dash.coinjoin-balance-read",
        qos: .utility)

    /// Spendable balance (in duffs) of `wallet`'s CoinJoin account 0, read on
    /// `readQueue`, or `nil` when the read fails.
    ///
    /// `pooledSpendableBalance(accountType: .coinJoin)` sums the account's
    /// `spendable_utxos` — unlocked, mature, 0-conf included — which is what
    /// the sweep moves, so the gate never hides funds the sweep would move.
    /// That is the account's `confirmed + unconfirmed`, read for one account
    /// instead of walking every account the wallet has.
    static func coinJoinSpendableDuffs(for wallet: ManagedPlatformWallet) async -> UInt64? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: read(wallet))
            }
        }
    }

    private static func read(_ wallet: ManagedPlatformWallet) -> UInt64? {
        do {
            let total = try wallet.coreWallet().pooledSpendableBalance(
                accountType: .coinJoin,
                accountIndex: coinJoinAccountIndex)
            // Logged HERE, on the read queue, so offMain= is evidence of where
            // the read actually ran.
            Self.logger.info(
                "🪙 CJBAL :: coinjoin spendable balance = \(total, privacy: .public) duffs offMain=\(!Thread.isMainThread, privacy: .public)")
            return total
        } catch {
            // A wallet without CoinJoin account 0 lands here too: a pooled
            // read naming a single account requires that account to exist.
            Self.logger.warning(
                "🪙 CJBAL :: coinjoin balance read failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
