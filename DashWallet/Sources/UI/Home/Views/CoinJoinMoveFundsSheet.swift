//
//  CoinJoinMoveFundsSheet.swift
//  DashWallet
//
//  Post-sync "move your mixed coins" destination sheet. Shown instead of the
//  plain BIP44-only popup (HomeViewController.showCoinJoinSweepDialog) when
//  the leftover CoinJoin balance is large enough to shield
//  (HomeViewModel.coinJoinShieldDestinationAvailable): the user picks between
//
//   - Dash Wallet balance — the existing one-hop sweep
//     (`WalletSendService.sweepCoinJoin`), and
//   - Shielded balance — a two-hop flow: sweep the CoinJoin account to the
//     user's own BIP44 receive address (`sweepCoinJoinForShielding`), wait for
//     the swept outputs to become spendable (`waitForSweptCoinJoinFunds`),
//     then asset-lock the net amount into the shielded pool via
//     `ShieldedTransferCoordinator.performAssetLock` (authorized once, at the
//     sweep — `alreadyAuthorized` skips the second PIN prompt).
//
//  Failure posture of the two-hop flow: the sweep leg is recorded on the
//  ViewModel, so "Try again" after a post-sweep failure never re-sweeps — it
//  resumes from the wait (or, when the asset lock already committed, resumes
//  that exact outpoint via `resumeAssetLock`, mirroring the internal transfer
//  confirm sheet). A stuck lock that survives the session is picked up by the
//  home tx list's `ShieldedRecoverySheet` on the next launch.
//

import Combine
import DashUIKit
import SwiftUI

// MARK: - ViewModel

@MainActor
final class CoinJoinMoveFundsViewModel: ObservableObject {

    enum Destination: Equatable {
        case wallet
        case shielded
    }

    enum Stage: Equatable {
        /// Destination choice screen.
        case choice
        /// One-hop BIP44 sweep in flight.
        case movingToWallet
        /// Two-hop flow, leg 1–2: auth + sweep + wait for spendable UTXOs.
        case sweepingForShield
        /// Two-hop flow, leg 3: the coordinator drives the asset-lock shield;
        /// progress detail comes from `coordinator.phase`.
        case shielding
        case success(Destination)
        /// Shield broadcast accepted but unconfirmed — terminal, non-retryable
        /// (see `ShieldedTransferCoordinator.Phase.submittedUnconfirmed`).
        case submittedUnconfirmed
        /// `destination` picks the retry path: a failed wallet sweep retries
        /// the one-hop sweep, a failed shielded flow re-enters the two-hop
        /// flow at the leg that failed.
        case failed(message: String, destination: Destination)
    }

    @Published private(set) var stage: Stage = .choice

    /// CoinJoin balance snapshot at presentation time — the sweep zeroes the
    /// live balance mid-flow, but the sheet keeps showing what's being moved.
    let amountDuffs: UInt64

    let coordinator = ShieldedTransferCoordinator()

    /// Sweep-leg result, kept across retries so "Try again" never re-sweeps
    /// an already-emptied CoinJoin account.
    private var sweep: WalletSendService.CoinJoinShieldedSweep?
    /// Lock amount resolved by the wait leg, kept for the same reason.
    private var lockAmountDuffs: UInt64?

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
        case .movingToWallet, .sweepingForShield, .shielding:
            return true
        default:
            return false
        }
    }

    /// Row index for the shielded flow's positional step list
    /// (Moving funds → Locking funds → Generating proof → Broadcasting).
    var shieldStepIndex: Int? {
        switch stage {
        case .sweepingForShield:
            return 0
        case .shielding:
            switch coordinator.phase {
            case .signing, .locking:
                return 1
            case .proving:
                return 2
            case .broadcasting:
                return 3
            case .success:
                return 4
            case .idle, .failed, .submittedUnconfirmed:
                return nil
            }
        default:
            return nil
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

    /// Destination 2: the two-hop CoinJoin → Shielded flow. Each leg's result
    /// is kept so a retry resumes where the previous attempt failed instead of
    /// repeating side-effectful work.
    func moveToShielded() async {
        guard !isInFlight else { return }
        stage = .sweepingForShield
        do {
            if sweep == nil {
                sweep = try await WalletSendService.shared.sweepCoinJoinForShielding()
            }
            if lockAmountDuffs == nil, let sweep {
                lockAmountDuffs = try await WalletSendService.shared.waitForSweptCoinJoinFunds(sweep)
            }
        } catch {
            if WalletSendService.isAuthenticationCancelledError(error as NSError), sweep == nil {
                stage = .choice
            } else {
                stage = .failed(message: (error as NSError).localizedDescription, destination: .shielded)
            }
            return
        }
        guard let lockAmountDuffs else {
            stage = .failed(
                message: NSLocalizedString(
                    "Couldn't move your CoinJoin funds. Please try again.", comment: "CoinJoin"),
                destination: .shielded)
            return
        }

        stage = .shielding
        // A prior failed attempt leaves the coordinator terminal; reset so
        // `beginTransfer()` doesn't silently bail.
        if coordinator.phase != .idle {
            coordinator.reset()
        }
        // The sweep leg already ran the spend authorization for this action.
        await coordinator.performAssetLock(amountDuffs: lockAmountDuffs, alreadyAuthorized: true)
        finishFromCoordinatorPhase()
    }

    /// "Try again" from a failed shielded attempt. Mirrors
    /// `InternalTransferConfirmSheet.tryAgain`: a committed asset lock is
    /// RESUMED on its exact outpoint (building a second lock would strand the
    /// first); otherwise the flow re-enters `moveToShielded`, which skips the
    /// legs that already completed.
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
        switch coordinator.phase {
        case .success:
            stage = .success(.shielded)
        case .submittedUnconfirmed:
            stage = .submittedUnconfirmed
        case .failed(let message):
            stage = .failed(message: message, destination: .shielded)
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

// MARK: - Sheet

struct CoinJoinMoveFundsSheet: View {

    @StateObject private var viewModel: CoinJoinMoveFundsViewModel
    var onDismiss: () -> Void

    init(amountDuffs: UInt64, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: CoinJoinMoveFundsViewModel(amountDuffs: amountDuffs))
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Move your mixed coins", comment: "CoinJoin"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 20)

            switch viewModel.stage {
            case .choice:
                choiceBody
            case .movingToWallet:
                walletInFlightBody
            case .sweepingForShield, .shielding:
                shieldInFlightBody
            case .success(let destination):
                successBody(destination: destination)
            case .submittedUnconfirmed:
                ShieldedSubmittedUnconfirmedView(onDone: onDismiss)
            case .failed(let message, let destination):
                failedBody(message: message, destination: destination)
            }
        }
        .background(Color.dash.primaryBackground)
        .interactiveDismissDisabled(viewModel.isInFlight)
    }

    // MARK: Choice

    private var choiceBody: some View {
        VStack(spacing: 0) {
            DashAmount(
                amount: Int64(viewModel.amountDuffs),
                font: .largeTitle,
                dashSymbolFactor: 0.7,
                showDirection: false)
                .padding(.top, 14)

            Text(NSLocalizedString(
                "CoinJoin is no longer supported — choose where to move your mixed coins.",
                comment: "CoinJoin"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            VStack(spacing: 10) {
                destinationCard(
                    icon: "wallet.pass.fill",
                    title: NSLocalizedString("Dash Wallet balance", comment: "CoinJoin"),
                    subtitle: NSLocalizedString(
                        "Move to your regular spendable balance.", comment: "CoinJoin"),
                    action: { Task { await viewModel.moveToWallet() } })
                destinationCard(
                    icon: "shield.fill",
                    title: NSLocalizedString("Shielded balance", comment: "CoinJoin"),
                    subtitle: NSLocalizedString(
                        "Keep these coins private. Network and privacy fees apply.",
                        comment: "CoinJoin"),
                    action: { Task { await viewModel.moveToShielded() } })
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Later", comment: "CoinJoin"),
                style: .plain,
                stretch: true,
                action: onDismiss)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private func destinationCard(
        icon: String, title: String, subtitle: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.dash.blue)
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.dash.whiteText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.dash.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
            }
            .padding(14)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: In flight

    private var walletInFlightBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShieldedTransferStepList(
                labels: [NSLocalizedString("Moving funds", comment: "CoinJoin")],
                currentIndex: 0)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private var shieldInFlightBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShieldedTransferStepList(
                labels: [
                    NSLocalizedString("Moving funds", comment: "CoinJoin"),
                    NSLocalizedString("Locking funds", comment: ""),
                    NSLocalizedString("Generating proof", comment: ""),
                    NSLocalizedString("Broadcasting", comment: ""),
                ],
                currentIndex: viewModel.shieldStepIndex)

            Text(NSLocalizedString(
                "Building the privacy proof can take up to a minute. Keep the app open.",
                comment: "InternalTransfer recovery"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    // MARK: Terminal

    private func successBody(destination: CoinJoinMoveFundsViewModel.Destination) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
                .padding(.top, 24)

            Text(NSLocalizedString("Funds moved", comment: "CoinJoin"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            Text(destination == .shielded
                ? NSLocalizedString(
                    "Your mixed coins were moved to your Shielded balance. For best privacy, wait at least 2 hours before using these funds.",
                    comment: "CoinJoin")
                : NSLocalizedString(
                    "Your mixed coins were moved to your Dash Wallet balance.",
                    comment: "CoinJoin"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: onDismiss)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private func failedBody(message: String, destination: CoinJoinMoveFundsViewModel.Destination) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundColor(.orange)
                .padding(.top, 24)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Spacer(minLength: 12)

            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveButtonText: NSLocalizedString("Try again", comment: ""),
                positiveButtonAction: {
                    Task {
                        switch destination {
                        case .wallet:
                            await viewModel.moveToWallet()
                        case .shielded:
                            await viewModel.retryShielded()
                        }
                    }
                },
                negativeButtonText: NSLocalizedString("Close", comment: ""),
                negativeButtonAction: onDismiss)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: Pieces

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.dash.grabberFill)
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }
}
