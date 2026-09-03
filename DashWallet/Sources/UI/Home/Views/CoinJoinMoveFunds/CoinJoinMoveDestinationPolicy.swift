//
//  CoinJoinMoveDestinationPolicy.swift
//  DashWallet
//
//  One place deciding whether a "move mixed coins" surface may offer the
//  Shielded destination, so the post-sync popup and the durable Settings /
//  Tools rows cannot drift apart on what the user is offered.
//

import Foundation

/// Whether a "move mixed coins" surface can offer the Shielded destination.
///
/// Shared by every entry point — the post-sync popup and the durable
/// Settings / Tools "Move CoinJoin Funds" rows — so they cannot drift apart on
/// which destinations the user is offered. Before this existed the choice sheet
/// was reachable only from the popup, and because any dismissal of that popup is
/// persisted as "Later" (`HomeViewModel.deferCoinJoinSweep`) a single swipe left
/// the Shielded route unreachable for good: re-arming needs the CoinJoin balance
/// to rise above the dismissed amount, and with mixing removed from the app it
/// can only fall.
enum CoinJoinMoveDestinationPolicy {

    /// `true` when the wallet has a shielded address and `balanceDuffs` clears
    /// the economic floor for a Type 18 drain (pool fee + an L1-fee allowance
    /// for a spend of many mixed-coin inputs, doubled for headroom).
    static func shieldedDestinationAvailable(forBalanceDuffs balanceDuffs: UInt64) -> Bool {
        // Host + manager are `@MainActor`-isolated — reuse the wallet source's
        // main-thread trampoline.
        SwiftDashSDKWalletSource.onMain {
            guard let manager = SwiftDashSDKHost.shared.manager,
                  let wallet = SwiftDashSDKHost.shared.wallet,
                  ((try? manager.shieldedDefaultAddress(walletId: wallet.walletId)) ?? nil) != nil,
                  let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits
            else { return false }
            let overheadDuffs = poolFeeCredits / 1000 + WalletBalance.sendFeeReserveDuffs
            return balanceDuffs >= overheadDuffs * 2
        }
    }
}
