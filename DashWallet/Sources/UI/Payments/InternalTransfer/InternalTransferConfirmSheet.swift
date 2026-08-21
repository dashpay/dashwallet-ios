//
//  InternalTransferConfirmSheet.swift
//  DashWallet
//

import SwiftUI
import DashUIKit
import SwiftDashSDK

/// Confirmation half-sheet shown when the user taps `Continue` on the
/// Internal transfer screen. Body swaps based on the embedded
/// `ShieldedTransferCoordinator.phase`:
///   - `.idle`           → summary card + Cancel/Confirm buttons.
///   - in-flight phases  → step checklist (Signing / Locking / Proving /
///                         Broadcasting). Drag-dismiss is disabled.
///   - `.success`        → green check + amount + Done.
///   - `.failed(msg)`    → summary card with red error + Try again / Close.
///
/// Confirm executes `route` via the coordinator:
///   - `.coreToShielded`     → `performAssetLock(recipientAmountDuffs:)`
///   - `.platformToShielded` → `performShield(amountCredits:)`
///   - `.shieldedToCore`     → `performWithdraw(amountCredits:)`
///   - `.shieldedToPlatform` → `performUnshield(amountCredits:)`
///   - `.coreToPlatform`     → `performFundPlatform(amountDuffs:)`
///   - `.platformToCore`     → `performPlatformWithdrawAll()` (full balance)
struct InternalTransferConfirmSheet: View {

    let route: InternalTransferRoute
    let dashDuffs: Int64
    let amountDuffsUnsigned: UInt64
    let creditsAmount: UInt64
    let fiatText: String
    /// Preflighted `AddressCreditWithdrawalTransition` fee — only meaningful
    /// for `.platformToCore` (the fee headroom / netting basis).
    var withdrawalFeeCredits: UInt64? = nil
    /// `.platformToCore` only: the amount equals the full-balance net payout,
    /// so Confirm runs the AUTO (all-addresses) withdrawal instead of the
    /// single-input partial form.
    var isFullPlatformWithdrawal: Bool = false
    /// Shielded reverse routes only: execute the note-aware Max plan and
    /// revalidate it immediately before proving.
    var isFullShieldedSweep: Bool = false
    /// Frozen with the submitted amount so a capacity refresh can update only
    /// a value the user explicitly derived via Platform Shield Max.
    var platformShieldAmountWasMax: Bool = false
    var onCancel: () -> Void
    var onCompleted: () -> Void
    var onPlatformShieldCapacityChanged: (UInt64?, Bool) -> Void

    @StateObject private var coordinator = ShieldedTransferCoordinator()
    @State private var handledPlatformShieldCapacityChange = false

    var body: some View {
        // Grabber, title and background come from the design system rather
        // than being drawn here. `fillsHeight: true` because the host asks for
        // a `.large` detent — the sheet is a fixed size, not content-sized.
        DashUIKit.BottomSheet(
            title: NSLocalizedString("Confirm", comment: ""),
            showBackButton: .constant(false)
        ) {
            switch coordinator.phase {
            case .success:
                successBody
            case .submittedUnconfirmed:
                ShieldedSubmittedUnconfirmedView(onDone: onCompleted)
            default:
                detailsBody
            }
        }
        .interactiveDismissDisabled(isInFlight)
        .onChange(of: coordinator.phase) { phase in
            handlePlatformShieldCapacityChange(phase)
        }
    }

    private var isInFlight: Bool {
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

            secondaryLine
                .padding(.top, 6)

            summaryCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if case let .failed(message) = coordinator.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else {
                TransferPrivacyTip(
                    route: route,
                    isFullWithdrawal: isFullPlatformWithdrawal)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

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
                progressChecklist
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

            case .success, .submittedUnconfirmed:
                // Handled by `successBody` / `ShieldedSubmittedUnconfirmedView`.
                EmptyView()
            }
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

            Text(NSLocalizedString("Transfer complete", comment: ""))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            DashAmount(
                amount: dashDuffs,
                font: .title,
                dashSymbolFactor: 0.7,
                showDirection: false)

            secondaryLine

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

    private var secondaryLine: some View {
        Text(fiatText)
            .font(.subheadline)
            .foregroundColor(.dash.secondaryText)
    }

    // MARK: - Summary figures

    /// All of this is `InternalTransferSummaryFigures`' — see there for why the
    /// fee math does not live in the view. `nil` becomes an em dash: the sheet
    /// shows no number it cannot stand behind.

    private var networkFeeString: String {
        InternalTransferSummaryFigures.networkFeeFiat(
            route: route,
            withdrawalFeeCredits: withdrawalFeeCredits) ?? "—"
    }

    private var totalString: String {
        InternalTransferSummaryFigures.totalLeavingSource(
            route: route,
            dashDuffs: dashDuffs,
            amountDuffsUnsigned: amountDuffsUnsigned) ?? "—"
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                label: NSLocalizedString("From", comment: ""),
                value: fromLabel)
            divider
            summaryRow(
                label: NSLocalizedString("To", comment: ""),
                value: toLabel)
            divider
            summaryRow(
                label: NSLocalizedString("Network fee", comment: ""),
                value: networkFeeString)
            divider
            summaryRow(
                label: NSLocalizedString("Total", comment: ""),
                value: totalString)
        }
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    /// From/To endpoint names for the summary card, straight off the route.
    private var fromLabel: String {
        InternalTransferSummaryFigures.balanceName(
            InternalTransferSummaryFigures.endpoints(of: route).from)
    }

    private var toLabel: String {
        InternalTransferSummaryFigures.balanceName(
            InternalTransferSummaryFigures.endpoints(of: route).to)
    }

    private func summaryRow(label: String, value: String) -> some View {
        summaryRow(
            label: label,
            valueView: AnyView(
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.dash.primaryText)))
    }

    private func summaryRow(label: String, valueView: AnyView) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            Spacer()
            valueView
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

    // MARK: - Progress checklist

    /// Vertical step checklist for the in-flight phases. Only the forward
    /// asset-lock route has the `.locking` stage; the transparent shield and
    /// the reverse withdraw routes hide it because the FFI doesn't surface that
    /// intermediate step. Rendering is delegated to the shared
    /// `ShieldedTransferStepList` (also used by `ShieldedRecoverySheet`).
    private var progressChecklist: some View {
        ShieldedTransferStepList(currentPhase: coordinator.phase, steps: progressSteps)
    }

    private var progressSteps: [ShieldedTransferStepList.Step] {
        var steps: [ShieldedTransferStepList.Step] = [
            .init(label: NSLocalizedString("Authorizing", comment: ""), phase: .signing)
        ]
        // Asset-lock routes have the on-chain locking stage.
        if route == .coreToShielded || route == .coreToPlatform {
            steps.append(.init(label: NSLocalizedString("Locking funds", comment: ""), phase: .locking))
        }
        // Only shielded legs build an Orchard proof.
        switch route {
        case .coreToShielded, .platformToShielded, .shieldedToCore, .shieldedToPlatform:
            steps.append(.init(label: NSLocalizedString("Generating proof", comment: ""), phase: .proving))
        case .coreToPlatform, .platformToCore:
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
                await coordinator.performAssetLock(recipientAmountDuffs: amountDuffsUnsigned)
            case .platformToShielded:
                await coordinator.performShield(amountCredits: creditsAmount)
            case .shieldedToCore:
                await coordinator.performWithdraw(
                    amountCredits: creditsAmount,
                    sweepAll: isFullShieldedSweep)
            case .shieldedToPlatform:
                await coordinator.performUnshield(
                    amountCredits: creditsAmount,
                    sweepAll: isFullShieldedSweep)
            case .coreToPlatform:
                await coordinator.performFundPlatform(amountDuffs: amountDuffsUnsigned)
            case .platformToCore:
                await coordinator.performPlatformWithdraw(
                    amountCredits: creditsAmount,
                    fullBalance: isFullPlatformWithdrawal,
                    feeHeadroomCredits: withdrawalFeeCredits)
            }
        }
    }

    private func tryAgain() {
        // If the just-failed asset-lock attempt (Core→Shielded or
        // Core→Platform) already committed a lock, RESUME that exact outpoint
        // instead of building a second lock (which strands the first).
        // Capture before reset() clears it. Every other case (no committed
        // lock — auth-cancel / preflight failure — or a non-asset-lock route)
        // falls through to a fresh retry.
        if let op = coordinator.lastAssetLockOutPoint {
            switch route {
            case .coreToShielded:
                coordinator.reset()
                Task { await coordinator.resumeAssetLock(outPointTxidWire: op.txidWire, outPointVout: op.vout) }
                return
            case .coreToPlatform:
                coordinator.reset()
                Task { await coordinator.resumeFundPlatform(outPointTxidWire: op.txidWire, outPointVout: op.vout) }
                return
            default:
                break
            }
        }
        coordinator.reset()
        confirm()
    }

    private func handlePlatformShieldCapacityChange(
        _ phase: ShieldedTransferCoordinator.Phase
    ) {
        guard !handledPlatformShieldCapacityChange,
              case .failed = phase,
              let error = coordinator.lastFailure as? ShieldedTransferCoordinator.CoordinatorError,
              case .platformShieldCapacityChanged(let maxShieldableCredits) = error
        else { return }

        handledPlatformShieldCapacityChange = true
        onPlatformShieldCapacityChanged(
            maxShieldableCredits,
            platformShieldAmountWasMax)
    }
}

#if DEBUG

/// The sheet owns its coordinator and `phase` is `private(set)`, so previews
/// can only reach the idle summary. The in-flight, success and failure bodies
/// are previewed through `ShieldedTransferStepList` and
/// `ShieldedSubmittedUnconfirmedView` below.
///
/// Network-fee and total rows ask the SDK to price the route; without a wallet
/// those return `nil` and the rows render "—". `.coreToPlatform` prices from a
/// constant, so it is the route to use when the fee row itself matters.
private func confirmSheetSample(
    route: InternalTransferRoute,
    dash: Decimal = 0.5,
    withdrawalFeeCredits: UInt64? = nil,
    isFullPlatformWithdrawal: Bool = false,
    isFullShieldedSweep: Bool = false
) -> some View {
    let duffs = Int64(truncating: NSDecimalNumber(decimal: dash * 100_000_000))
    return InternalTransferConfirmSheet(
        route: route,
        dashDuffs: duffs,
        amountDuffsUnsigned: UInt64(duffs),
        creditsAmount: UInt64(duffs) * 1000,
        fiatText: "$32.75",
        withdrawalFeeCredits: withdrawalFeeCredits,
        isFullPlatformWithdrawal: isFullPlatformWithdrawal,
        isFullShieldedSweep: isFullShieldedSweep,
        platformShieldAmountWasMax: false,
        onCancel: {},
        onCompleted: {},
        onPlatformShieldCapacityChanged: { _, _ in })
}

@available(iOS 17, *)
#Preview("Core → Platform") {
    confirmSheetSample(route: .coreToPlatform)
}

@available(iOS 17, *)
#Preview("Core → Shielded") {
    confirmSheetSample(route: .coreToShielded)
}

@available(iOS 17, *)
#Preview("Shielded → Core · sweep") {
    confirmSheetSample(route: .shieldedToCore, isFullShieldedSweep: true)
}

/// Full-balance withdrawal: the fee is already netted out of the payout, and
/// the preflight fee is the only one the sheet can show.
@available(iOS 17, *)
#Preview("Platform → Core · full") {
    confirmSheetSample(
        route: .platformToCore,
        withdrawalFeeCredits: 1_240_000,
        isFullPlatformWithdrawal: true)
}

@available(iOS 17, *)
#Preview("Dark") {
    confirmSheetSample(route: .coreToPlatform)
        .preferredColorScheme(.dark)
}

/// Presented the way the screen presents it — verifies the drag handle and the
/// `.large` detent, which the bare-content previews above can't show.
@available(iOS 17, *)
#Preview("As a sheet") {
    Color.dash.primaryBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            confirmSheetSample(route: .coreToPlatform)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
}

#endif
