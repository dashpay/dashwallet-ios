//
//  CoinJoinMoveDestinationPolicy.swift
//  DashWallet
//
//  One place deciding what a "move mixed coins" surface may offer, so the
//  post-sync popup and the durable Settings / Tools rows cannot drift apart on
//  what the user is shown.
//
//  Every decision is split in two: a pure form taking the inputs as
//  parameters, and a thin wrapper that reads them off the SDK singletons. The
//  pure forms are what `CoinJoinMoveDestinationPolicyTests` covers — the
//  singletons need a live wallet and cannot be stood up in a test.
//

import Foundation

/// What a "move mixed coins" surface may offer, and whether it may offer
/// anything at all.
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

    /// Which surface a "Move CoinJoin Funds" tap opens.
    enum Route: Equatable {
        /// The destination-choice sheet (Dash Wallet vs Shielded).
        case destinationChoice
        /// The transparent-only confirmation — the shielded route is not
        /// viable for this wallet or this balance.
        case transparentConfirmation
    }

    // MARK: - Shielded viability

    /// `true` when the wallet has a shielded address and `balanceDuffs` clears
    /// the economic floor for a Type 18 drain.
    ///
    /// The floor is the pool fee (credits → duffs is ÷ 1000) plus
    /// `sendFeeReserveDuffs`, which allows for the L1 fee of a drain spending
    /// hundreds of mixed-coin inputs, doubled for headroom. Fails closed: a
    /// missing shielded binding or an unavailable fee estimate means the answer
    /// is no, never "probably".
    static func shieldedDestinationAvailable(
        hasShieldedAddress: Bool,
        poolFeeCredits: UInt64?,
        balanceDuffs: UInt64
    ) -> Bool {
        guard hasShieldedAddress, let poolFeeCredits else { return false }
        let overheadDuffs = poolFeeCredits / 1000 + WalletBalance.sendFeeReserveDuffs
        return balanceDuffs >= overheadDuffs * 2
    }

    /// `shieldedDestinationAvailable(hasShieldedAddress:poolFeeCredits:balanceDuffs:)`
    /// with the two wallet-side inputs read from the SDK.
    static func shieldedDestinationAvailable(forBalanceDuffs balanceDuffs: UInt64) -> Bool {
        // Host + manager are `@MainActor`-isolated — reuse the wallet source's
        // main-thread trampoline.
        SwiftDashSDKWalletSource.onMain {
            guard let manager = SwiftDashSDKHost.shared.manager,
                  let wallet = SwiftDashSDKHost.shared.wallet
            else { return false }
            let hasShieldedAddress =
                ((try? manager.shieldedDefaultAddress(walletId: wallet.walletId)) ?? nil) != nil
            return shieldedDestinationAvailable(
                hasShieldedAddress: hasShieldedAddress,
                poolFeeCredits: CoreToShieldedAmountPolicy.poolFeeCredits,
                balanceDuffs: balanceDuffs)
        }
    }

    // MARK: - Durable menu surfaces

    /// Whether the Settings / Tools "Move CoinJoin Funds" row may be shown.
    ///
    /// The row is gated on a finished sync for the same reason the popup is
    /// (`HomeViewModel.maybeShowCoinJoinSweepDialog`), and the gate matters more
    /// here: the Shielded destination drains the *whole* CoinJoin account
    /// SDK-side, while the sheet shows the balance snapshotted at presentation.
    /// Mid-scan those two disagree — the widened CoinJoin recovery scan keeps
    /// discovering UTXOs — so the lock either consumes more than the user was
    /// shown, or moves a subset and leaves the rest needing a second lock and a
    /// second fee.
    static func menuRowAvailable(hasLeftover: Bool, isChainSynced: Bool) -> Bool {
        hasLeftover && isChainSynced
    }

    /// Which surface a menu row's tap opens, or `nil` when it must open none.
    ///
    /// An unfinished sync yields `nil` rather than `.transparentConfirmation`:
    /// mid-scan the shielded route's viability is simply unknown, and answering
    /// "transparent" would quietly undo the user's mixing on the strength of a
    /// balance that is still being discovered.
    static func menuRoute(isChainSynced: Bool, shieldedAvailable: Bool) -> Route? {
        guard isChainSynced else { return nil }
        return shieldedAvailable ? .destinationChoice : .transparentConfirmation
    }
}
