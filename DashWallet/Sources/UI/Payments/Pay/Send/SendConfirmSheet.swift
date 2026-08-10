//
//  SendConfirmSheet.swift
//  DashWallet
//
//  Confirmation half-sheet for every external send route.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

// MARK: - CoreSendConfirmController

/// Drives the Core → Core leg of `SendConfirmSheet`. Every other route runs
/// through `ShieldedTransferCoordinator`; a plain L1 send has no shielding/
/// asset-lock/platform stages, so it gets its own minimal state machine
/// instead of borrowing a coordinator phase that doesn't apply to it.
///
/// Shape: `prepareStandardSendForConfirmation` runs the auth gate and
/// builds + signs the transaction WITHOUT broadcasting — that happens on
/// appear, so the sheet can show the real fee off the signed transaction
/// instead of an estimate. `.ready` is the only phase with a live Confirm
/// button; tapping it calls `PreparedStandardSend.broadcast()`, the explicit
/// user-confirm step.
@MainActor
final class CoreSendConfirmController: ObservableObject {

    enum Phase: Equatable {
        /// Nothing attempted yet, or the user backed out of the PIN — the
        /// same resting state, because a cancelled prompt is a decision and
        /// has nothing to report.
        case idle
        /// Auth gate + build/sign in flight (`prepareStandardSendForConfirmation`).
        case signing
        /// Prepared: `feeDuffs` holds the real fee off the signed transaction.
        case ready
        /// `PreparedStandardSend.broadcast()` in flight.
        case broadcasting
        case success
        /// Broadcast accepted by relay but its result couldn't be confirmed —
        /// terminal + non-retryable, mirrors
        /// `ShieldedTransferCoordinator.Phase.submittedUnconfirmed`.
        case submittedUnconfirmed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// The exact fee (duffs) off the signed transaction. `nil` until
    /// `.ready` — the summary row shows "—" rather than a guess until then.
    @Published private(set) var feeDuffs: UInt64?

    /// Signed and waiting for the user's confirmation.
    var isReady: Bool { phase == .ready }

    /// Why the signature could not be produced, for the step that asked.
    var failureMessage: String? {
        if case let .failed(message) = phase { return message }
        return nil
    }

    private var prepared: PreparedStandardSend?

    /// Build + sign, without broadcasting. Run by the amount step before it
    /// presents the confirm sheet — the PIN this puts up cannot be presented
    /// over a sheet that is still appearing. Safe to call again from `retry`
    /// after a prepare-time failure (auth cancelled, offline, chain not
    /// synced, ...).
    func prepare(address: String, amountDuffs: UInt64) async {
        phase = .signing
        prepared = nil
        feeDuffs = nil
        do {
            let result = try await WalletSendService.shared.prepareStandardSendForConfirmation(
                address: address, amount: amountDuffs)
            prepared = result
            feeDuffs = result.fee
            phase = .ready
        } catch {
            phase = WalletSendService.isAuthenticationCancelledError(error as NSError)
                ? .idle
                : .failed(Self.message(for: error))
        }
    }

    /// Explicit user-confirm step: broadcasts the already-prepared, already-
    /// signed transaction. No-op unless a prepare succeeded.
    func confirmBroadcast() async {
        guard case .ready = phase else { return }
        await broadcastPrepared()
    }

    /// `Try again` from `.failed`. A broadcast-time failure (e.g. rejected)
    /// leaves the signed transaction retryable — `PreparedStandardSend`
    /// resets its own claim state to `.ready` on a rejected/local failure —
    /// so retry re-broadcasts the SAME transaction rather than re-signing. A
    /// prepare-time failure (nothing was ever signed) re-prepares.
    func retry(address: String, amountDuffs: UInt64) async {
        guard case .failed = phase else { return }
        if prepared != nil {
            await broadcastPrepared()
        } else {
            await prepare(address: address, amountDuffs: amountDuffs)
        }
    }

    private func broadcastPrepared() async {
        guard let prepared else { return }
        phase = .broadcasting
        do {
            try prepared.broadcast()
            phase = .success
        } catch {
            if WalletSendService.isBroadcastUnknownError(error as NSError) {
                phase = .submittedUnconfirmed
            } else {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    private static func message(for error: Error) -> String {
        (error as NSError).localizedDescription
    }
}

// MARK: - SendConfirmSheet

/// Confirmation half-sheet for every external send route. Same skeleton as
/// `InternalTransferConfirmSheet` (summary → progress checklist → success);
/// the To row is the recipient's address. Every route except Core → Core
/// executes via `ShieldedTransferCoordinator`'s external-destination legs;
/// Core → Core executes via `CoreSendConfirmController` /
/// `WalletSendService` instead — see that type's doc for why it doesn't
/// share the coordinator.
struct SendConfirmSheet: View {

    let route: SendViewModel.Route
    let destinationAddress: String
    /// The recipient's raw 43-byte Orchard payload — required for
    /// `.shieldedToShielded`, nil otherwise.
    let destinationRaw43: Data?
    let dashDuffs: Int64
    let creditsAmount: UInt64
    let fiatText: String
    /// Preflighted withdrawal fee — only meaningful for `.platformToCore`.
    var withdrawalFeeCredits: UInt64? = nil
    var isFullPlatformWithdrawal: Bool = false
    var isFullShieldedSweep: Bool = false
    /// Core route only: prepared by the amount step BEFORE this sheet is
    /// presented. Preparing from here raced the sheet's own presentation —
    /// `PinPromptPresenter` cannot put the PIN over a sheet that is still
    /// animating in, UIKit rejects it silently, and its watchdog resolved the
    /// send as an authentication failure.
    @ObservedObject var coreSend: CoreSendConfirmController

    var onCancel: () -> Void
    var onCompleted: () -> Void

    @StateObject private var coordinator = ShieldedTransferCoordinator()
    /// Core → Core only — see `CoreSendConfirmController`.

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Confirm", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 20)

            if route == .coreToCore {
                switch coreSend.phase {
                case .success:
                    successBody
                case .submittedUnconfirmed:
                    ShieldedSubmittedUnconfirmedView(onDone: onCompleted)
                default:
                    detailsBody
                }
            } else {
                switch coordinator.phase {
                case .success:
                    successBody
                case .submittedUnconfirmed:
                    ShieldedSubmittedUnconfirmedView(onDone: onCompleted)
                default:
                    detailsBody
                }
            }
        }
        .background(Color.dash.primaryBackground)
        .interactiveDismissDisabled(isInFlight)

    }

    private var isInFlight: Bool {
        if route == .coreToCore {
            switch coreSend.phase {
            case .signing, .broadcasting:
                return true
            default:
                return false
            }
        }
        switch coordinator.phase {
        case .signing, .locking, .proving, .broadcasting:
            return true
        default:
            return false
        }
    }

    // MARK: - Idle / in-flight / failed body

    private var detailsBody: some View {
        VStack(spacing: 0) {
            DashAmount(
                amount: dashDuffs,
                font: .largeTitle,
                dashSymbolFactor: 0.7,
                showDirection: false)
                .padding(.top, 14)

            Text(fiatText)
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)
                .padding(.top, 6)

            summaryCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if let failureMessage {
                Text(failureMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else {
                infoCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            actionSection
        }
    }

    private var failureMessage: String? {
        if route == .coreToCore {
            if case let .failed(message) = coreSend.phase { return message }
            return nil
        }
        if case let .failed(message) = coordinator.phase { return message }
        return nil
    }

    @ViewBuilder
    private var actionSection: some View {
        if route == .coreToCore {
            switch coreSend.phase {
            case .ready:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Confirm", comment: ""),
                    positiveButtonAction: confirm,
                    negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .failed:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Try again", comment: ""),
                    positiveButtonAction: tryAgain,
                    negativeButtonText: NSLocalizedString("Close", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .signing, .broadcasting:
                ShieldedTransferStepList(labels: coreProgressLabels, currentIndex: coreProgressIndex)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

            case .success, .submittedUnconfirmed:
                EmptyView()

            // Unreachable: the amount step only presents this sheet once the
            // transaction is signed, and a cancelled PIN keeps it there.
            case .idle:
                EmptyView()
            }
        } else {
            switch coordinator.phase {
            case .idle:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Confirm", comment: ""),
                    positiveButtonAction: confirm,
                    negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .failed:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Try again", comment: ""),
                    positiveButtonAction: tryAgain,
                    negativeButtonText: NSLocalizedString("Close", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .signing, .locking, .proving, .broadcasting:
                ShieldedTransferStepList(currentPhase: coordinator.phase, steps: progressSteps)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

            case .success, .submittedUnconfirmed:
                EmptyView()
            }
        }
    }

    /// Core → Core's two-stage checklist (`CoreSendConfirmController.Phase`
    /// has no `.locking`/`.proving` — a plain L1 send doesn't pass through
    /// them), rendered with `ShieldedTransferStepList`'s positional
    /// initializer since its phase-based one is typed to
    /// `ShieldedTransferCoordinator.Phase`.
    private var coreProgressLabels: [String] {
        [NSLocalizedString("Authorizing", comment: ""), NSLocalizedString("Broadcasting", comment: "")]
    }

    private var coreProgressIndex: Int? {
        switch coreSend.phase {
        case .signing: return 0
        case .broadcasting: return 1
        default: return nil
        }
    }

    // MARK: - Success body

    private var successBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
                .padding(.top, 24)

            Text(NSLocalizedString("Sent", comment: "Send confirm sheet"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            DashAmount(
                amount: dashDuffs,
                font: .title,
                dashSymbolFactor: 0.7,
                showDirection: false)

            Text(fiatText)
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: onCompleted)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Pieces

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.dash.grabberFill)
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                label: NSLocalizedString("From", comment: ""),
                value: fromLabel)
            divider
            HStack {
                Text(NSLocalizedString("To", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text(truncateMiddle(destinationAddress))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            divider
            summaryRow(
                label: NSLocalizedString("Network fee", comment: ""),
                value: networkFeeString)
            divider
            summaryRow(
                label: NSLocalizedString("Total", comment: ""),
                value: dashDuffs.formattedDashAmount)
        }
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var fromLabel: String {
        switch route {
        case .platformToPlatform, .platformToCore:
            return NSLocalizedString("Platform balance", comment: "The Dash Platform credits balance")
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            return NSLocalizedString("Shielded balance", comment: "")
        case .coreToCore, .coreToShielded:
            return NSLocalizedString("Transparent balance", comment: "The transparent (Core) balance of the Dash Wallet")
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.dash.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dash.gray300.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Network fee estimate

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// Flat fee estimate (credits) for the active route — same estimators as
    /// the internal transfer's confirm sheet. `nil` → the row shows "—".
    private var networkFeeCredits: UInt64? {
        switch route {
        case .coreToShielded:
            return CoreToShieldedAmountPolicy.poolFeeCredits
        case .platformToPlatform:
            // Credit transfer: the metered transition fee. The executor
            // states ~0.001 DASH as the conservative max.
            return 100_000_000
        case .platformToCore:
            return withdrawalFeeCredits
        case .shieldedToCore:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 2)
        case .shieldedToPlatform:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 2)
        case .shieldedToShielded:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 2)
        case .coreToCore:
            // The one route with a real (not projected) fee: off the signed
            // transaction, once `CoreSendConfirmController` finishes
            // preparing. `nil` while unknown — the row shows "—", not a guess.
            guard let feeDuffs = coreSend.feeDuffs else { return nil }
            return feeDuffs * 1000
        }
    }

    private var networkFeeString: String {
        guard let credits = networkFeeCredits else { return "—" }
        let dash = Decimal(credits) / Self.creditsPerDash
        let formatted = CurrencyExchanger.shared.fiatAmountString(for: dash)
        // Every other route estimates; Core → Core's fee is the exact amount
        // off the signed transaction, so it doesn't get the "~" prefix.
        return route == .coreToCore ? formatted : "~ " + formatted
    }

    // MARK: - Info card

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 30, height: 30)
                Image(systemName: infoIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(infoTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Text(infoBody)
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var infoIcon: String {
        switch route {
        case .platformToCore, .shieldedToCore: return "clock.fill"
        default: return "exclamationmark.shield.fill"
        }
    }

    private var infoTitle: String {
        switch route {
        case .platformToCore, .shieldedToCore:
            return NSLocalizedString("Processing time", comment: "")
        default:
            return NSLocalizedString("Double-check the address", comment: "Send confirm sheet")
        }
    }

    private var infoBody: String {
        switch route {
        case .shieldedToCore:
            return NSLocalizedString(
                "The Dash arrives at the recipient's address after the network processes the withdrawal — this can take up to 10 minutes.",
                comment: "Send confirm sheet")
        case .platformToCore:
            return isFullPlatformWithdrawal
                ? NSLocalizedString(
                    "This withdraws your entire Platform balance in one transfer. The Dash arrives at the recipient's address once the network processes the withdrawal.",
                    comment: "Send confirm sheet")
                : NSLocalizedString(
                    "The Dash arrives at the recipient's address once the network processes the withdrawal.",
                    comment: "Send confirm sheet")
        default:
            return NSLocalizedString(
                "Dash sent to a wrong address can't be recovered. Make sure the address is exactly the one you intend to pay.",
                comment: "Send confirm sheet")
        }
    }

    // MARK: - Progress checklist

    private var progressSteps: [ShieldedTransferStepList.Step] {
        var steps: [ShieldedTransferStepList.Step] = [
            .init(label: NSLocalizedString("Authorizing", comment: ""), phase: .signing)
        ]
        // Only the asset-lock route has the on-chain locking stage.
        if route == .coreToShielded {
            steps.append(.init(label: NSLocalizedString("Locking funds", comment: ""), phase: .locking))
        }
        // Only shielded legs build an Orchard proof.
        switch route {
        case .coreToShielded, .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            steps.append(.init(label: NSLocalizedString("Generating proof", comment: ""), phase: .proving))
        case .platformToPlatform, .platformToCore, .coreToCore:
            break
        }
        steps.append(.init(label: NSLocalizedString("Broadcasting", comment: ""), phase: .broadcasting))
        return steps
    }

    // MARK: - Actions

    private func confirm() {
        Task {
            switch route {
            case .coreToShielded:
                guard let destinationRaw43 else {
                    coordinator.reset()
                    return
                }
                await coordinator.performAssetLock(
                    amountDuffs: UInt64(dashDuffs),
                    recipientRaw43: destinationRaw43)
            case .platformToPlatform:
                await coordinator.performPlatformSend(
                    destination: destinationAddress,
                    amountCredits: creditsAmount)
            case .platformToCore:
                await coordinator.performPlatformWithdraw(
                    amountCredits: creditsAmount,
                    fullBalance: isFullPlatformWithdrawal,
                    feeHeadroomCredits: withdrawalFeeCredits,
                    toCoreAddress: destinationAddress)
            case .shieldedToCore:
                await coordinator.performWithdraw(
                    amountCredits: creditsAmount,
                    sweepAll: isFullShieldedSweep,
                    toCoreAddress: destinationAddress)
            case .shieldedToPlatform:
                await coordinator.performUnshield(
                    amountCredits: creditsAmount,
                    sweepAll: isFullShieldedSweep,
                    toPlatformAddress: destinationAddress)
            case .shieldedToShielded:
                guard let destinationRaw43 else {
                    coordinator.reset()
                    return
                }
                await coordinator.performShieldedTransfer(
                    amountCredits: creditsAmount,
                    recipientRaw43: destinationRaw43)
            case .coreToCore:
                // Already prepared (auth + build/sign) on appear — Confirm
                // only broadcasts the signed transaction.
                await coreSend.confirmBroadcast()
            }
        }
    }

    private func tryAgain() {
        if route == .coreToCore {
            Task {
                await coreSend.retry(address: destinationAddress, amountDuffs: UInt64(dashDuffs))
            }
            return
        }
        // If the just-failed Core → Shielded attempt already committed its
        // asset lock, RESUME that exact outpoint with the same recipient
        // instead of building a second lock (which strands the first) —
        // mirrors the internal transfer's retry.
        if route == .coreToShielded,
           let op = coordinator.lastAssetLockOutPoint,
           let destinationRaw43 {
            coordinator.reset()
            Task {
                await coordinator.resumeAssetLock(
                    outPointTxidWire: op.txidWire,
                    outPointVout: op.vout,
                    recipientRaw43: destinationRaw43)
            }
            return
        }
        coordinator.reset()
        confirm()
    }
}
