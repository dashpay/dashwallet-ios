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
///                         Broadcasting). Sheet dismissal is disabled.
///   - `.success`        → green check + amount + Done.
///   - `.failed(msg)`    → summary card with red error + Try again / Close.
///
/// Confirm executes `route` via the coordinator:
///   - `.coreToShielded`     → `performAssetLock(recipientAmountDuffs:)`
///   - `.platformToShielded` → `performShield(amountCredits:)`
///   - `.shieldedToCore`     → `performWithdraw(amountCredits:)`
///   - `.shieldedToPlatform` → `performUnshield(amountCredits:)`
///   - `.coreToPlatform`     → `performFundPlatform(recipientAmountDuffs:)`
///   - `.platformToCore`     → `performPlatformWithdrawAll()` (full balance)
struct InternalTransferConfirmSheet: View {

    let route: InternalTransferRoute
    let dashDuffs: Int64
    let amountDuffsUnsigned: UInt64
    let creditsAmount: UInt64
    let fiatText: String
    /// Resolved "Network fee" row value (credits), computed by
    /// `InternalTransferViewModel.confirmNetworkFeeCredits` and frozen into
    /// the submission — fee math is banned inside View structs. `nil`
    /// renders as "—".
    var networkFeeCredits: UInt64? = nil
    /// Resolved "Total" row value (duffs) — what actually leaves the source
    /// balance (`InternalTransferViewModel.confirmTotalDuffs`). `nil`
    /// renders as "—".
    var totalDuffs: Int64? = nil
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
        DashUIKit.BottomSheet(
            title: NSLocalizedString("Confirm", comment: ""),
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!isInFlight),
            // Supplying `onClose` makes the close button live regardless of
            // `isDismissalEnabled`, so the protected phases have to gate it here.
            isCloseButtonEnabled: !isInFlight,
            onClose: closeAction
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

    /// The close button has to do what the visible button of the current phase
    /// does. In the terminal phases that is `onCompleted`, which tells the
    /// transfer screen the transfer finished; `onCancel` only closes the sheet.
    private var closeAction: () -> Void {
        switch coordinator.phase {
        case .success, .submittedUnconfirmed:
            return onCompleted
        default:
            return onCancel
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
                privacyTipCard
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

    // MARK: - Network fee estimate

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// Network-fee estimate as fiat (e.g. "~ $0.08"), or "—" if unavailable.
    /// Display-only: the value is resolved by the ViewModel and frozen into
    /// the submission.
    private var networkFeeString: String {
        guard let credits = networkFeeCredits else { return "—" }
        let dash = Decimal(credits) / Self.creditsPerDash
        return "~ " + CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    /// "Total" as DASH text — what actually leaves the source balance,
    /// resolved by the ViewModel. "—" when unavailable — `canContinue`
    /// fails closed before that can be confirmed, but the row must never
    /// show an un-inflated number.
    private var totalString: String {
        totalDuffs?.formattedDashAmount ?? "—"
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
    private var fromLabel: String { Self.balanceName(routeEndpoints.from) }
    private var toLabel: String { Self.balanceName(routeEndpoints.to) }

    private var routeEndpoints: (from: ChainNetwork, to: ChainNetwork) {
        switch route {
        case .coreToShielded: return (.core, .shielded)
        case .platformToShielded: return (.platform, .shielded)
        case .shieldedToCore: return (.shielded, .core)
        case .shieldedToPlatform: return (.shielded, .platform)
        case .coreToPlatform: return (.core, .platform)
        case .platformToCore: return (.platform, .core)
        }
    }

    private static func balanceName(_ network: ChainNetwork) -> String {
        switch network {
        case .core:
            return NSLocalizedString("Transparent balance", comment: "The transparent (Core) balance of the Dash Wallet")
        case .platform:
            return NSLocalizedString("Platform balance", comment: "The Dash Platform credits balance")
        case .shielded:
            return NSLocalizedString("Shielded balance", comment: "")
        }
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

    // MARK: - Privacy tip

    private var privacyTipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 30, height: 30)
                Image(systemName: privacyTipIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(privacyTipTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Text(privacyTipBody)
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

    /// The tip card is route-aware:
    /// - to Shielded (either source): privacy nudge.
    /// - Shielded → Core (L1 withdraw): up-to-10-minute spend delay.
    /// - Shielded → Platform (unshield) / Core → Platform: settles fast.
    /// - Platform → Core: full-balance withdrawal + network processing delay.
    private var privacyTipIcon: String {
        switch route {
        case .shieldedToCore, .platformToCore: return "clock.fill"
        default: return "shield.fill"
        }
    }

    private var privacyTipTitle: String {
        switch route {
        case .shieldedToCore:
            return NSLocalizedString("Up to 10 minutes to spend", comment: "")
        case .platformToCore:
            return isFullPlatformWithdrawal
                ? NSLocalizedString("Withdraws the entire balance", comment: "Full-balance Platform → Transparent withdrawal")
                : NSLocalizedString("Processing time", comment: "Platform → Transparent withdrawal")
        default:
            return NSLocalizedString("Privacy tip", comment: "")
        }
    }

    private var privacyTipBody: String {
        switch route {
        case .coreToShielded, .platformToShielded:
            return NSLocalizedString(
                "For best privacy, wait at least 2 hours before using these funds.",
                comment: "")
        case .shieldedToCore:
            return NSLocalizedString(
                "After this transfer, it can take up to 10 minutes before you can use your Dash. This delay is part of how your privacy is protected.",
                comment: "")
        case .shieldedToPlatform:
            // Unshield to Platform Payment settles quickly.
            return NSLocalizedString(
                "These funds move to your Platform Payment balance and are ready to spend right away.",
                comment: "")
        case .coreToPlatform:
            return NSLocalizedString(
                "These funds move to your Platform balance and are ready to spend as soon as the transfer completes. The network fee is a reserve — whatever the network doesn't use is credited to your Platform balance too.",
                comment: "")
        case .platformToCore:
            return isFullPlatformWithdrawal
                ? NSLocalizedString(
                    "This withdraws your entire Platform balance in one transfer. The Dash arrives in your Transparent balance once the network processes the withdrawal.",
                    comment: "")
                : NSLocalizedString(
                    "The Dash arrives in your Transparent balance once the network processes the withdrawal.",
                    comment: "")
        }
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
                await coordinator.performFundPlatform(recipientAmountDuffs: amountDuffsUnsigned)
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

/// Recovery sheet for a stuck "to Shielded" transfer (Core→Shielded). The
/// transfer's L1 asset lock is committed on-chain but the shield state
/// transition never landed, so the funds sit on an unconsumed
/// `PersistentAssetLock` — recoverable, not lost. "Finish now" resumes that
/// exact outpoint via `ShieldedTransferCoordinator.resumeAssetLock`
/// (re-auth → Orchard proof → ShieldFromAssetLock ST → consume), rather than
/// building a second lock.
///
/// Presented from the home tx list when the user taps a row flagged
/// `Transaction.isPendingShieldedTransfer`. Owns its own coordinator so it is
/// independent of any live confirm-sheet flow.
struct ShieldedRecoverySheet: View {

    let transaction: Transaction
    var onDismiss: () -> Void

    @StateObject private var coordinator = ShieldedTransferCoordinator()

    /// Set when "Finish now" finds the lock already consumed (a background sync
    /// landed the shield since the history row's snapshot was captured) — shows
    /// the success state immediately instead of paying for a doomed ~30s proof.
    @State private var alreadyComplete = false

    var body: some View {
        DashUIKit.BottomSheet(
            title: NSLocalizedString("Finish shielded transfer", comment: "InternalTransfer recovery"),
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!isInFlight),
            // Supplying `onClose` makes the close button live regardless of
            // `isDismissalEnabled`, so the protected phases have to gate it here.
            isCloseButtonEnabled: !isInFlight,
            onClose: onDismiss
        ) {
            switch coordinator.phase {
            case .success:
                successBody
            case .submittedUnconfirmed:
                ShieldedSubmittedUnconfirmedView(onDone: onDismiss)
            case .signing, .locking, .proving, .broadcasting:
                inFlightBody
            default:
                if alreadyComplete {
                    successBody
                } else {
                    idleOrFailedBody
                }
            }
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

    // MARK: - Bodies

    private var idleOrFailedBody: some View {
        VStack(spacing: 0) {
            DashAmount(
                amount: Int64(transaction.dashAmount),
                font: .largeTitle,
                dashSymbolFactor: 0.7,
                showDirection: false)
                .padding(.top, 14)

            infoCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if case let .failed(message) = coordinator.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveButtonText: NSLocalizedString("Finish now", comment: "InternalTransfer recovery"),
                positiveButtonAction: finish,
                negativeButtonText: NSLocalizedString("Close", comment: ""),
                negativeButtonAction: onDismiss)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var inFlightBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Same stepped checklist as the original transfer so the user sees
            // what's happening during the (~30s+) Orchard proof build. Resume
            // skips `.locking` (the lock is already on-chain), so only
            // Authorizing → Generating proof → Broadcasting are shown.
            ShieldedTransferStepList(
                currentPhase: coordinator.phase,
                steps: [
                    .init(label: NSLocalizedString("Authorizing", comment: ""), phase: .signing),
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
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

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
                amount: Int64(transaction.dashAmount),
                font: .title,
                dashSymbolFactor: 0.7,
                showDirection: false)

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

    // MARK: - Pieces

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 30, height: 30)
                Image(systemName: "shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Your Dash is safe", comment: "InternalTransfer recovery"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Text(NSLocalizedString(
                    "This transfer's funds were locked on-chain but the private transfer didn't finish. Tap Finish now to complete it.",
                    comment: "InternalTransfer recovery"))
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

    // MARK: - Action

    private func finish() {
        guard let op = transaction.shieldedOutPoint else {
            onDismiss()
            return
        }
        Task { @MainActor in
            // Re-check live status before paying for a ~30s Orchard proof: a
            // background shielded sync may have consumed this lock since the
            // history row's snapshot was captured. The resume FFI builds the
            // full proof before Platform reports "already consumed", so without
            // this guard a just-completed transfer would dead-end after ~30s.
            await ShieldedTxLookup.shared.refresh(reason: "shield-transfer-recovery-preflight")
            let displayTxid = op.txidWire.reversed().map { String(format: "%02x", $0) }.joined()
            let statusRaw = ShieldedTxLookup.shared.info(forTxidHex: displayTxid)?.statusRaw
            if statusRaw == 4 {
                // Already consumed by a background sync since the row snapshot was
                // captured → it's done; show success without a doomed ~30s resume.
                alreadyComplete = true
                return
            }
            // statusRaw 1...3 (still pending), 5 (Core-final — consumption
            // unknown), or nil/0 (status unavailable, e.g. a failed refresh):
            // attempt the resume. Both a local Consumed tombstone and a remote
            // already-consumed report map to unconfirmed rather than false success.
            await coordinator.resumeAssetLock(outPointTxidWire: op.txidWire, outPointVout: op.vout)
            // On success the shield ST consumed the lock; refresh the snapshot so
            // the history row flips pending → completed even before the next
            // scheduled shielded sync pass lands.
            if case .success = coordinator.phase {
                await ShieldedTxLookup.shared.refresh(reason: "shield-transfer-recovery-completed")
            }
        }
    }
}

/// Vertical step checklist shared by the shielded transfer confirm sheet and
/// the recovery sheet. Each `Step` maps to the
/// `ShieldedTransferCoordinator.Phase` it represents; the row's
/// done/active/pending state is derived from where the current phase sits in
/// the canonical ordering (signing → locking → proving → broadcasting →
/// success). A terminal `.idle`/`.failed` phase renders every step pending (the
/// host sheet surfaces the summary/error separately).
struct ShieldedTransferStepList: View {
    struct Step: Identifiable {
        let label: String
        let phase: ShieldedTransferCoordinator.Phase
        var id: String { label }
    }

    /// Pre-resolved (label, state) rows — both inits reduce to this.
    private let rows: [(label: String, state: StepState)]

    /// Phase-based rows: each step's done/active/pending state derives from
    /// where `currentPhase` sits in the canonical ordering (see type doc).
    init(currentPhase: ShieldedTransferCoordinator.Phase, steps: [Step]) {
        rows = steps.map { step -> (label: String, state: StepState) in
            (label: step.label, state: Self.state(for: step.phase, current: currentPhase))
        }
    }

    /// Positional rows, for flows with stages the coordinator phases can't
    /// express (e.g. the CoinJoin → Shielded flow's sweep leg): rows before
    /// `currentIndex` are complete, the row at it active, the rest pending.
    /// `nil` renders every row pending (idle/failed — the host sheet surfaces
    /// the error separately); an index past the last row renders all complete.
    init(labels: [String], currentIndex: Int?) {
        rows = labels.enumerated().map { index, label -> (label: String, state: StepState) in
            guard let current = currentIndex else { return (label: label, state: .pending) }
            if index < current { return (label: label, state: .complete) }
            if index == current { return (label: label, state: .active) }
            return (label: label, state: .pending)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.element.label) { _, row in
                stepRow(label: row.label, state: row.state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum StepState {
        case pending
        case active
        case complete
    }

    /// Where `phase` sits relative to `current`. The phase enum is ordered
    /// .signing → .locking → .proving → .broadcasting → .success, so a numeric
    /// comparison drives the state.
    private static func state(
        for phase: ShieldedTransferCoordinator.Phase,
        current: ShieldedTransferCoordinator.Phase
    ) -> StepState {
        guard let currentIdx = Self.phaseIndex(current),
              let targetIdx = Self.phaseIndex(phase) else {
            return .pending
        }
        if targetIdx < currentIdx { return .complete }
        if targetIdx == currentIdx { return .active }
        return .pending
    }

    private static func phaseIndex(_ phase: ShieldedTransferCoordinator.Phase) -> Int? {
        switch phase {
        case .signing: return 0
        case .locking: return 1
        case .proving: return 2
        case .broadcasting: return 3
        case .success: return 4
        case .idle, .failed, .submittedUnconfirmed: return nil
        }
    }

    private func stepRow(label: String, state: StepState) -> some View {
        HStack(spacing: 12) {
            stepIndicator(state: state)
            Text(label)
                .font(.system(size: 15, weight: state == .active ? .semibold : .regular))
                .foregroundColor(state == .pending ? .dash.secondaryText : .dash.primaryText)
            Spacer()
            if state == .active {
                SwiftUI.ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.7)
            }
        }
    }

    @ViewBuilder
    private func stepIndicator(state: StepState) -> some View {
        switch state {
        case .pending:
            Circle()
                .stroke(Color.dash.gray300.opacity(0.6), lineWidth: 1.5)
                .frame(width: 20, height: 20)
        case .active:
            ZStack {
                Circle()
                    .stroke(Color.dash.blue, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 10, height: 10)
            }
        case .complete:
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.dash.whiteText)
            }
        }
    }
}

/// Terminal "submitted but unconfirmed" state shared by the shielded transfer
/// confirm sheet and the recovery sheet. Shown when the SDK reports
/// `shieldedSpendUnconfirmed` — the broadcast was accepted by relay but its
/// result isn't yet confirmed, so the user must NOT resend; there is
/// deliberately no "Try again". The transfer resolves via the next shielded
/// sync.
struct ShieldedSubmittedUnconfirmedView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "paperplane.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .foregroundColor(.dash.blue)
                .padding(.top, 24)

            Text(NSLocalizedString("Submitted — confirming", comment: "InternalTransfer"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            Text(NSLocalizedString(
                "Your transfer was broadcast and is confirming on the network. Don't resend it — it will appear once the network confirms it.",
                comment: "InternalTransfer"))
                .font(.callout)
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: onDone)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }
}
