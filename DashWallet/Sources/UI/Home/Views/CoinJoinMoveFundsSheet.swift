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
//   - Shielded balance — a single CoinJoin-drain asset lock
//     (`ShieldedTransferCoordinator.performAssetLock(funding: .coinJoinDrain)`):
//     every mixed-coin UTXO funds the Type 18 lock directly and the shielded
//     pool receives `lock_value − pool_fee` — no transparent intermediate hop.
//
//  Failure posture of the shielded flow: a committed asset lock is resumed on
//  its exact outpoint via `resumeAssetLock` (mirroring the internal transfer
//  confirm sheet's "Try again"); a stuck lock that survives the session is
//  picked up by the home tx list's `ShieldedRecoverySheet` on the next
//  launch. A pre-broadcast failure moves nothing — the coins stay in the
//  CoinJoin account and the popup/Settings surfaces keep offering the move.
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

// MARK: - Sheet

struct CoinJoinMoveFundsSheet: View {

    @StateObject private var viewModel: CoinJoinMoveFundsViewModel
    @ObservedObject private var coreSpendAvailability = CoreSpendAvailability.shared
    @ObservedObject private var proofAvailability = AssetLockProofAvailability.shared
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
            case .shielding:
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
                    isEnabled: true,
                    action: { Task { await viewModel.moveToWallet() } })
                destinationCard(
                    icon: "shield.fill",
                    title: NSLocalizedString("Shielded balance", comment: "CoinJoin"),
                    subtitle: NSLocalizedString(
                        "Keep these coins private. Network and privacy fees apply.",
                        comment: "CoinJoin"),
                    isEnabled: !isShieldedDestinationBlocked,
                    action: { Task { await viewModel.moveToShielded() } })
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            if isShieldedDestinationBlocked {
                SyncGateNote(message: shieldedDestinationBlockedMessage)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

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
        icon: String,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        action: @escaping () -> Void
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
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
            // Same steps as the internal transfer's Core → Shielded route —
            // the drain is one asset lock, driven by the same coordinator.
            ShieldedTransferStepList(
                currentPhase: viewModel.coordinator.phase,
                steps: [
                    .init(label: NSLocalizedString("Authorizing", comment: ""), phase: .signing),
                    .init(label: NSLocalizedString("Locking funds", comment: ""), phase: .locking),
                    .init(label: NSLocalizedString("Generating proof", comment: ""), phase: .proving),
                    .init(label: NSLocalizedString("Broadcasting", comment: ""), phase: .broadcasting),
                ])

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
                positiveActionEnabled: destination != .shielded || !isShieldedRetryBlocked,
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

    private var isShieldedDestinationBlocked: Bool {
        coreSpendAvailability.isBlocked || proofAvailability.isBlocked
    }

    private var isShieldedRetryBlocked: Bool {
        if viewModel.coordinator.lastAssetLockOutPoint != nil {
            return proofAvailability.isBlocked
        }
        return isShieldedDestinationBlocked
    }

    private var shieldedDestinationBlockedMessage: String {
        if coreSpendAvailability.isBlocked {
            return CoreSpendAvailabilityError.initialRestoreSync.localizedDescription
        }
        return AssetLockProofAvailabilityError.masternodeSync.localizedDescription
    }

    // MARK: Pieces

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.dash.grabberFill)
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }
}
