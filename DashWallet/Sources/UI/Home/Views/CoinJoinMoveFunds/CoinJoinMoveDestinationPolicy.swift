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

// MARK: - CoinJoin → Shielded input planning

/// Decides how a "move mixed coins to Shielded" attempt gets from the CoinJoin
/// account's current UTXO set to a single CoinJoin-drain asset lock.
///
/// The drain spends every final CoinJoin UTXO as an input of ONE asset lock,
/// and an asset lock may carry at most `maxAssetLockInputs` inputs: Dash Core
/// v24 refuses more as non-standard (`assetlocktx-too-many-inputs`,
/// `MAX_STANDARD_ASSET_LOCK_INPUTS`) and peers drop it silently, and Platform
/// consensus applies the same cap (`max_asset_lock_transaction_inputs`).
/// That is the hard limit, but not the binding one: the drain is shielded by
/// a ShieldFromAssetLock transition whose InstantSend proof embeds the whole
/// asset-lock transaction, and Platform caps a transition at 20 480 bytes.
/// That cap is exceeded from about 65 inputs (dashpay/platform#4460: 83 inputs
/// gave a 23 KB transition), so a 65–100-input drain is accepted by Core and
/// then stuck as an asset lock Platform cannot consume until the ChainLock
/// fallback (dashpay/platform#5460) ships in the SDK. An account above
/// `consolidationThreshold` is therefore first consolidated — swept to one fresh
/// address of its own CoinJoin account in ≤500-input regular transactions —
/// and drained once those outputs are final. The coins never leave the
/// CoinJoin account until the drain, so an interrupted attempt leaves them on
/// one CoinJoin address, and the next attempt drains them directly.
///
/// Pure: the inputs come from `SwiftDashSDKTransactionSender.coinJoinUtxoState()`
/// so `CoinJoinShieldPlannerTests` can pin every branch without a wallet.
enum CoinJoinShieldPlanner {

    /// Most inputs a single asset lock may carry (Dash Core v24 policy and
    /// Platform consensus agree on 100). The hard limit — never drain above it.
    static let maxAssetLockInputs = 100

    /// Most UTXOs drained directly; above this the account is consolidated
    /// first. Tighter than `maxAssetLockInputs` because the ShieldFromAssetLock
    /// transition carrying an InstantSend proof outgrows Platform's 20 480-byte
    /// transition limit at about 65 inputs (see the type doc); 50 leaves
    /// headroom for input size variance. Revisit once the ChainLock-proof
    /// fallback (dashpay/platform#5460) is in the SDK the app builds against.
    static let consolidationThreshold = 50

    /// What the next step towards the drain is.
    enum Step: Equatable {
        /// The account holds no spendable UTXO — there is nothing to shield.
        case nothingToMove
        /// More UTXOs than one drain may safely spend
        /// (`consolidationThreshold`): consolidate first.
        case consolidate
        /// Few enough UTXOs, but `pending` of them are not final yet. The
        /// drain builder spends only final inputs (confirmed or
        /// InstantSend-locked), so draining now would leave them behind.
        case awaitFinality(pending: Int)
        /// Every UTXO is final and one asset lock can spend them all.
        case drain
    }

    /// The next step for an account with `utxoCount` spendable UTXOs of which
    /// `finalCount` are final.
    static func nextStep(utxoCount: Int, finalCount: Int) -> Step {
        guard utxoCount > 0 else { return .nothingToMove }
        if utxoCount > consolidationThreshold { return .consolidate }
        let pending = utxoCount - min(finalCount, utxoCount)
        return pending > 0 ? .awaitFinality(pending: pending) : .drain
    }

    /// The finality the drain builder applies (`is_confirmed ||
    /// is_instantlocked`), recovered from what the SDK exposes per UTXO: a
    /// mined UTXO carries its block height, and an InstantSend-locked one has
    /// its txid in the wallet's IS-lock set. Both txid forms are wire order.
    static func isFinal(height: UInt32, txid: Data, instantLockedTxids: Set<Data>) -> Bool {
        height > 0 || instantLockedTxids.contains(txid)
    }

    /// Whether every consolidation transaction in `consolidationTxids` (wire
    /// order) has produced a final output back in the CoinJoin account.
    /// `utxos` is the account's current (txid, isFinal) snapshot. An empty
    /// txid list is trivially settled.
    static func consolidationSettled(
        consolidationTxids: [Data],
        utxos: [(txid: Data, isFinal: Bool)]
    ) -> Bool {
        let finalTxids = Set(utxos.lazy.filter { $0.isFinal }.map { $0.txid })
        return consolidationTxids.allSatisfy { finalTxids.contains($0) }
    }
}
