//
//  CoinJoinMoveFundsViewModel.swift
//  DashWallet
//
//  Stage machine behind `CoinJoinMoveFundsSheet` — the post-migration
//  "move your mixed coins" flow. The user picks between
//
//   - Dash Wallet balance — the existing one-hop sweep
//     (`WalletSendService.sweepCoinJoin`), and
//   - Shielded balance — a single CoinJoin-drain asset lock
//     (`ShieldedTransferCoordinator.performAssetLock(funding: .coinJoinDrain)`):
//     every mixed-coin UTXO funds the Type 18 lock directly and the shielded
//     pool receives `lock_value - pool_fee` — no transparent intermediate hop.
//
//  Failure posture of the shielded flow: a committed asset lock is resumed on
//  its exact outpoint via `resumeAssetLock` (mirroring the internal transfer
//  confirm sheet's "Try again"); a stuck lock that survives the session is
//  picked up by the home tx list's `ShieldedRecoverySheet` on the next
//  launch. A pre-broadcast failure moves nothing — the coins stay in the
//  CoinJoin account and the popup / Settings / Tools surfaces keep offering
//  the move.
//

import Combine
import Foundation

@MainActor
final class CoinJoinMoveFundsViewModel: ObservableObject {

    enum Destination: Equatable {
        case wallet
        case shielded
    }

    enum Stage: Equatable {
        /// Destination choice screen.
        case choice
        /// BIP44 sweep in flight.
        case movingToWallet
        /// CoinJoin-drain asset lock in flight; progress detail comes from
        /// `coordinator.phase`.
        case shielding
        case success(Destination)
        /// Shield broadcast accepted but unconfirmed — terminal, non-retryable
        /// (see `ShieldedTransferCoordinator.Phase.submittedUnconfirmed`).
        case submittedUnconfirmed
        /// `destination` picks the retry path: a failed wallet sweep retries
        /// the sweep, a failed shielded flow retries (or resumes) the drain
        /// asset lock.
        case failed(message: String, destination: Destination)
    }

    @Published private(set) var stage: Stage = .choice

    /// CoinJoin balance snapshot at presentation time — the sweep zeroes the
    /// live balance mid-flow, but the sheet keeps showing what's being moved.
    let amountDuffs: UInt64

    let coordinator = ShieldedTransferCoordinator()

    private var cancellables = Set<AnyCancellable>()

    init(amountDuffs: UInt64) {
        self.amountDuffs = amountDuffs
        // The step checklist reads `coordinator.phase` — republish its
        // changes so SwiftUI re-renders while `stage` itself is stable.
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isInFlight: Bool {
        switch stage {
        case .movingToWallet, .shielding:
            return true
        default:
            return false
        }
    }

    // MARK: Actions

    /// Destination 1: the existing one-hop sweep into the spendable BIP44
    /// balance. Auth-cancel returns to the choice screen silently.
    func moveToWallet() async {
        guard !isInFlight else { return }
        stage = .movingToWallet
        do {
            _ = try await WalletSendService.shared.sweepCoinJoin()
            stage = .success(.wallet)
        } catch {
            if let message = WalletSendService.coinJoinSweepUserMessage(for: error) {
                stage = .failed(message: message, destination: .wallet)
            } else {
                stage = .choice
            }
        }
    }

    /// Destination 2: one CoinJoin-drain asset lock — every mixed-coin UTXO
    /// funds the Type 18 lock directly (no transparent hop) and the shielded
    /// pool receives the drained value minus the pool fee. The coordinator
    /// runs its own PIN/biometric gate, so this is the flow's single prompt.
    func moveToShielded() async {
        guard !isInFlight else { return }
        stage = .shielding
        // A prior failed attempt leaves the coordinator terminal; reset so
        // `beginTransfer()` doesn't silently bail.
        if coordinator.phase != .idle {
            coordinator.reset()
        }
        await coordinator.performAssetLock(funding: .coinJoinDrain)
        finishFromCoordinatorPhase()
    }

    /// "Try again" from a failed shielded attempt. Mirrors
    /// `InternalTransferConfirmSheet.tryAgain`: a committed asset lock is
    /// RESUMED on its exact outpoint (building a second lock would strand the
    /// first); otherwise a fresh drain build runs — a pre-broadcast failure
    /// left the CoinJoin account untouched.
    func retryShielded() async {
        guard !isInFlight else { return }
        if let op = coordinator.lastAssetLockOutPoint {
            stage = .shielding
            coordinator.reset()
            // Resume re-authorizes on its own (fresh user action).
            await coordinator.resumeAssetLock(outPointTxidWire: op.txidWire, outPointVout: op.vout)
            finishFromCoordinatorPhase()
            return
        }
        coordinator.reset()
        await moveToShielded()
    }

    private func finishFromCoordinatorPhase() {
        // The drain consumed (or may have consumed) the CoinJoin balance —
        // re-tally so the popup/Settings surfaces self-clear without waiting
        // for the next SPV balance event. Also correct for failures: the
        // re-tally just reads the SDK's current UTXO set.
        SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
        switch coordinator.phase {
        case .success:
            stage = .success(.shielded)
        case .submittedUnconfirmed:
            stage = .submittedUnconfirmed
        case .failed(let message):
            // A cancelled PIN prompt is a user decision, not an error —
            // return to the destination choice (mirrors the wallet leg's
            // auth-cancel handling). Message-compare against the same
            // localized source the coordinator maps the cancel to.
            if message == ShieldedTransferCoordinator.CoordinatorError.authCancelled.errorDescription {
                coordinator.reset()
                stage = .choice
            } else {
                stage = .failed(message: message, destination: .shielded)
            }
        default:
            // The coordinator's single-flight gate refused the call (phase
            // wasn't idle). Surface a retryable failure rather than hang.
            stage = .failed(
                message: NSLocalizedString(
                    "Couldn't move your CoinJoin funds. Please try again.", comment: "CoinJoin"),
                destination: .shielded)
        }
    }
}

#if DEBUG
extension CoinJoinMoveFundsViewModel {

    /// Preview-only constructor: builds the model and forces it to `stage`.
    ///
    /// `stage` is `private(set)`, so this has to live in the same file as the
    /// property rather than beside the previews that use it.
    static func preview(amountDuffs: UInt64, stage: Stage) -> CoinJoinMoveFundsViewModel {
        let model = CoinJoinMoveFundsViewModel(amountDuffs: amountDuffs)
        model.stage = stage
        return model
    }
}
#endif
