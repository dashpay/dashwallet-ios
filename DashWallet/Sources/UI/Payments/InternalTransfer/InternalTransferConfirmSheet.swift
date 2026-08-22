//
//  InternalTransferConfirmSheet.swift
//  DashWallet
//

import SwiftUI
import DashUIKit
import SwiftDashSDK

/// Confirmation half-sheet shown when the user taps `Continue` on the
/// Internal transfer screen. Body swaps based on the display phase both
/// executors reduce to:
///   - idle          → summary card + Cancel/Confirm buttons.
///   - in-flight     → the route checklist (Signing / Locking / Proving /
///                     Broadcasting), or the identity top-up's step line.
///                     Drag-dismiss is disabled.
///   - success       → green check + amount + Done.
///   - failed(msg)   → summary card with red error + Try again / Close.
///
/// Confirm executes `route` via the coordinator:
///   - `.coreToShielded`     → `performAssetLock(recipientAmountDuffs:)`
///   - `.platformToShielded` → `performShield(amountCredits:)`
///   - `.shieldedToCore`     → `performWithdraw(amountCredits:)`
///   - `.shieldedToPlatform` → `performUnshield(amountCredits:)`
///   - `.coreToPlatform`     → `performFundPlatform(amountDuffs:)`
///   - `.platformToCore`     → `performPlatformWithdrawAll()` (full balance)
/// …or, when one of the identity inputs is set, runs that executor instead —
/// neither identity side has a balance-to-balance route:
///   - `identityTopUp`      → `IdentityTopUpViewModel.topUp(identityId:amountDuffs:source:)`
///   - `identityWithdrawal` → `IdentityWithdrawViewModel.withdraw(identityId:amountCredits:target:)`
struct InternalTransferConfirmSheet: View {

    /// Balance-to-balance route to execute; `nil` exactly when one of the
    /// identity inputs is set.
    let route: InternalTransferRoute?
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
    /// Identity-destination mode: Confirm runs the identity top-up from
    /// `identityTopUp.source` instead of a route executor, and the summary
    /// prices from the top-up policy. Mutually exclusive with `route`.
    var identityTopUp: IdentityTopUpTransfer? = nil
    /// Identity-source mode: Confirm runs the withdrawal to
    /// `identityWithdrawal.target`. Mutually exclusive with both `route` and
    /// `identityTopUp`.
    var identityWithdrawal: IdentityWithdrawalTransfer? = nil
    var onCancel: () -> Void
    var onCompleted: () -> Void
    var onPlatformShieldCapacityChanged: (UInt64?, Bool) -> Void

    @StateObject private var coordinator = ShieldedTransferCoordinator()
    @StateObject private var identityTopUpViewModel = IdentityTopUpViewModel()
    @StateObject private var identityWithdrawViewModel = IdentityWithdrawViewModel()
    @State private var handledPlatformShieldCapacityChange = false

    /// Whether Confirm runs an identity transfer rather than a balance
    /// route. Exactly one of the three inputs is ever set.
    private var isIdentityTransfer: Bool {
        identityTopUp != nil || identityWithdrawal != nil
    }

    /// The identity transfers' shared lifecycle, kept apart from the
    /// coordinator's phases — neither executor reports typed stages, only a
    /// text step (the top-up) or nothing at all (the withdrawal).
    private enum IdentityPhase: Equatable {
        case idle
        case processing
        case success
        case failed(String)
    }

    @State private var identityPhase: IdentityPhase = .idle

    /// Chrome-level phase both executors reduce to; `detailsBody` renders
    /// from this so the route coordinator and the identity top-up share one
    /// layout.
    private enum DisplayPhase: Equatable {
        case idle
        case inFlight
        case failed(String)
    }

    private var displayPhase: DisplayPhase {
        if isIdentityTransfer {
            switch identityPhase {
            case .processing: return .inFlight
            case .failed(let message): return .failed(message)
            case .idle, .success: return .idle
            }
        }
        switch coordinator.phase {
        case .signing, .locking, .proving, .broadcasting:
            return .inFlight
        case .failed(let message):
            return .failed(message)
        default:
            return .idle
        }
    }

    var body: some View {
        // Grabber, title and background come from the design system rather
        // than being drawn here. `fillsHeight: true` because the host asks for
        // a `.large` detent — the sheet is a fixed size, not content-sized.
        DashUIKit.BottomSheet(
            title: NSLocalizedString("Confirm", comment: ""),
            showBackButton: .constant(false)
        ) {
            if isIdentityTransfer {
                if identityPhase == .success {
                    successBody
                } else {
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
        .interactiveDismissDisabled(isInFlight)
        .onChange(of: coordinator.phase) { phase in
            handlePlatformShieldCapacityChange(phase)
        }
    }

    private var isInFlight: Bool {
        displayPhase == .inFlight
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

            if case let .failed(message) = displayPhase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else {
                privacyTip
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            switch displayPhase {
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

            case .inFlight:
                progressSection
            }
        }
    }

    @ViewBuilder
    private var privacyTip: some View {
        if let identityTopUp {
            TransferPrivacyTip(context: .identityTopUp(from: identityTopUp.source))
        } else if let identityWithdrawal {
            TransferPrivacyTip(context: .identityWithdrawal(to: identityWithdrawal.target))
        } else if let route {
            TransferPrivacyTip(context: .route(route, isFullWithdrawal: isFullPlatformWithdrawal))
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if isIdentityTransfer {
            identityProgress
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        } else {
            progressChecklist
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    /// The identity top-up reports its progress as a text step (the shielded
    /// funding's two steps), not typed stages — a spinner plus that line
    /// stands in for the route checklist. The withdrawal is a single
    /// transition with no steps to name, so it shows the spinner alone.
    private var identityProgress: some View {
        VStack(spacing: 10) {
            SwiftUI.ProgressView()
            if let step = identityTopUpViewModel.stepLabel {
                Text(step)
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
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
        if let identityTopUp {
            return InternalTransferSummaryFigures.identityTopUpFeeFiat(
                source: identityTopUp.source) ?? "—"
        }
        if identityWithdrawal != nil {
            return InternalTransferSummaryFigures.identityWithdrawalFeeFiat ?? "—"
        }
        guard let route else { return "—" }
        return InternalTransferSummaryFigures.networkFeeFiat(
            route: route,
            withdrawalFeeCredits: withdrawalFeeCredits) ?? "—"
    }

    private var totalString: String {
        if isIdentityTransfer {
            return InternalTransferSummaryFigures.identityTopUpTotal(dashDuffs: dashDuffs)
        }
        guard let route else { return "—" }
        return InternalTransferSummaryFigures.totalLeavingSource(
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

    /// From/To endpoint names for the summary card: straight off the route,
    /// or the funding source + the identity for a top-up.
    private var fromLabel: String {
        if let identityTopUp {
            return InternalTransferSummaryFigures.balanceName(identityTopUp.source)
        }
        if identityWithdrawal != nil {
            return InternalTransferSummaryFigures.identityEndpointName
        }
        guard let route else { return "—" }
        return InternalTransferSummaryFigures.balanceName(
            InternalTransferSummaryFigures.endpoints(of: route).from)
    }

    private var toLabel: String {
        if identityTopUp != nil {
            return InternalTransferSummaryFigures.identityEndpointName
        }
        if let identityWithdrawal {
            return InternalTransferSummaryFigures.balanceName(identityWithdrawal.target.network)
        }
        guard let route else { return "—" }
        return InternalTransferSummaryFigures.balanceName(
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
        // Identity modes render `identityProgress` instead of the checklist.
        guard let route else { return [] }
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
        if let identityTopUp {
            confirmIdentityTopUp(identityTopUp)
            return
        }
        if let identityWithdrawal {
            confirmIdentityWithdrawal(identityWithdrawal)
            return
        }
        guard let route else { return }
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

    /// Runs the top-up, reducing its outcome to a phase: a returned balance
    /// is success, an error message is failure, and a backed-out PIN prompt
    /// returns to the summary. Retrying a failure re-runs the whole top-up —
    /// the same semantics as the profile sheet's top-up flow.
    private func confirmIdentityTopUp(_ topUp: IdentityTopUpTransfer) {
        Task {
            identityPhase = .processing
            let newBalance = await identityTopUpViewModel.topUp(
                identityId: topUp.identityId,
                amountDuffs: amountDuffsUnsigned,
                source: .init(spending: topUp.source))
            if newBalance != nil {
                identityPhase = .success
            } else if let message = identityTopUpViewModel.errorMessage {
                identityTopUpViewModel.errorMessage = nil
                identityPhase = .failed(message)
            } else {
                identityPhase = .idle
            }
        }
    }

    /// Runs the withdrawal, reducing its outcome to the same phase the
    /// top-up uses: success, an error message, or a backed-out PIN prompt
    /// that returns to the summary.
    private func confirmIdentityWithdrawal(_ withdrawal: IdentityWithdrawalTransfer) {
        Task {
            identityPhase = .processing
            let succeeded = await identityWithdrawViewModel.withdraw(
                identityId: withdrawal.identityId,
                amountCredits: creditsAmount,
                target: withdrawal.target)
            if succeeded {
                identityPhase = .success
            } else if let message = identityWithdrawViewModel.errorMessage {
                identityWithdrawViewModel.errorMessage = nil
                identityPhase = .failed(message)
            } else {
                identityPhase = .idle
            }
        }
    }

    private func tryAgain() {
        if let identityTopUp {
            identityPhase = .idle
            confirmIdentityTopUp(identityTopUp)
            return
        }
        if let identityWithdrawal {
            identityPhase = .idle
            confirmIdentityWithdrawal(identityWithdrawal)
            return
        }
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
    route: InternalTransferRoute?,
    dash: Decimal = 0.5,
    withdrawalFeeCredits: UInt64? = nil,
    isFullPlatformWithdrawal: Bool = false,
    isFullShieldedSweep: Bool = false,
    identityTopUp: IdentityTopUpTransfer? = nil,
    identityWithdrawal: IdentityWithdrawalTransfer? = nil
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
        identityTopUp: identityTopUp,
        identityWithdrawal: identityWithdrawal,
        onCancel: {},
        onCompleted: {},
        onPlatformShieldCapacityChanged: { _, _ in })
}

/// Identity destination funded from `source`. Without a wallet the shielded
/// funding's fee row renders "—"; the transparent-side sources price from
/// the observed transition-fee constant, so their fee row shows a number.
private func identityConfirmSheetSample(source: ChainNetwork) -> some View {
    confirmSheetSample(
        route: nil,
        identityTopUp: IdentityTopUpTransfer(
            identityId: Data(repeating: 0x07, count: 32),
            source: source))
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

/// Identity destination from the Transparent balance — the linkability
/// warning replaces the route privacy tip and To reads "Identity".
@available(iOS 17, *)
#Preview("→ Identity · from Transparent") {
    identityConfirmSheetSample(source: .core)
}

@available(iOS 17, *)
#Preview("→ Identity · from Shielded") {
    identityConfirmSheetSample(source: .shielded)
}

private func withdrawalConfirmSheetSample(target: IdentityWithdrawalTarget) -> some View {
    confirmSheetSample(
        route: nil,
        identityWithdrawal: IdentityWithdrawalTransfer(
            identityId: Data(repeating: 0x07, count: 32),
            target: target))
}

/// Identity source: From reads "Identity" and the fee row is the em dash —
/// neither withdrawal transition has an SDK fee estimate to print.
@available(iOS 17, *)
#Preview("Identity → · Transparent") {
    withdrawalConfirmSheetSample(target: .transparent)
}

@available(iOS 17, *)
#Preview("Identity → · Platform") {
    withdrawalConfirmSheetSample(target: .platform)
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
