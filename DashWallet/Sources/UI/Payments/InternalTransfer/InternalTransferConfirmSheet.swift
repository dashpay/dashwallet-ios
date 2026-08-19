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
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Confirm", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 20)

            switch coordinator.phase {
            case .success:
                successBody
            case .submittedUnconfirmed:
                ShieldedSubmittedUnconfirmedView(onDone: onCompleted)
            default:
                detailsBody
            }
        }
        .background(Color.dash.primaryBackground)
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

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.dash.grabberFill)
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }

    private var secondaryLine: some View {
        Text(fiatText)
            .font(.subheadline)
            .foregroundColor(.dash.secondaryText)
    }

    // MARK: - Network fee estimate

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// Flat fee estimate (credits) for the active route, computed offline by
    /// the SDK against the latest protocol version (so it matches the fee the
    /// SDK will charge). `nil` if the estimate is unavailable → the row
    /// shows "—".
    private var networkFeeCredits: UInt64? {
        switch route {
        case .coreToShielded:
            // The lock charges the fee rounded UP to a whole duff — display
            // that, so Amount + Network fee equals Total exactly.
            return CoreToShieldedAmountPolicy.currentPoolFeeDuffs.map { $0 * 1000 }
        case .platformToShielded:
            // Shield (Type 15): base shielded fee. Real metered storage is
            // extra and only knowable on-chain, so this is a lower bound.
            return try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 2)
        case .shieldedToCore:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 2)
        case .shieldedToPlatform:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 2)
        case .coreToPlatform:
            // Address-funding asset lock: the required processing balance
            // (the same 50k-duff base the Rust side reserves for address
            // funding). The funding ST's metered fee is extra and only
            // knowable on-chain, so this is a lower bound.
            return CoreToShieldedAmountPolicy.assetLockBaseCostCredits
        case .platformToCore:
            // The exact transition fee the preflight already netted out of
            // the payout amount.
            return withdrawalFeeCredits
        }
    }

    /// Network-fee estimate as fiat (e.g. "~ $0.08"), or "—" if unavailable.
    private var networkFeeString: String {
        guard let credits = networkFeeCredits else { return "—" }
        let dash = Decimal(credits) / Self.creditsPerDash
        return "~ " + CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    /// What actually leaves the source balance. Core→Shielded charges the
    /// pool fee on top of the amount (the executed lock value); every other
    /// route's total is the amount itself. "—" when the fee estimate is
    /// unavailable — `canContinue` fails closed before that can be confirmed,
    /// but the row must never show the un-inflated number.
    private var totalString: String {
        guard route == .coreToShielded else {
            return dashDuffs.formattedDashAmount
        }
        guard let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits,
              let lockDuffs = CoreToShieldedAmountPolicy.lockValueDuffs(
                  forAmountDuffs: amountDuffsUnsigned,
                  poolFeeCredits: poolFeeCredits),
              let signedLockDuffs = Int64(exactly: lockDuffs)
        else { return "—" }
        return signedLockDuffs.formattedDashAmount
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
                "These funds move to your Platform balance and are ready to spend as soon as the transfer completes.",
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
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Finish shielded transfer", comment: "InternalTransfer recovery"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 20)

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
        .background(Color.dash.primaryBackground)
        .interactiveDismissDisabled(isInFlight)
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

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.dash.grabberFill)
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }

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
            ShieldedTxLookup.shared.refresh()
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
                ShieldedTxLookup.shared.refresh()
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

#if DEBUG

// MARK: - Previews

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

// MARK: Step list

private let shieldedSteps: [ShieldedTransferStepList.Step] = [
    .init(label: "Signing", phase: .signing),
    .init(label: "Locking funds", phase: .locking),
    .init(label: "Generating proof", phase: .proving),
    .init(label: "Broadcasting", phase: .broadcasting),
]

private func stepListSample(_ phase: ShieldedTransferCoordinator.Phase) -> some View {
    ShieldedTransferStepList(currentPhase: phase, steps: shieldedSteps)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

/// Every position in the ordering — pending, first active, mid-run, and all
/// complete — side by side, since the row states are derived rather than set.
@available(iOS 17, *)
#Preview("Steps · idle") {
    stepListSample(.idle)
}

@available(iOS 17, *)
#Preview("Steps · signing") {
    stepListSample(.signing)
}

@available(iOS 17, *)
#Preview("Steps · proving") {
    stepListSample(.proving)
}

@available(iOS 17, *)
#Preview("Steps · success") {
    stepListSample(.success)
}

/// Positional init — the CoinJoin → Shielded flow's extra sweep leg, whose
/// stages have no coordinator phase.
@available(iOS 17, *)
#Preview("Steps · positional") {
    ShieldedTransferStepList(
        labels: ["Sweeping CoinJoin funds", "Signing", "Generating proof", "Broadcasting"],
        currentIndex: 1)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

// MARK: Submitted-unconfirmed terminal state

@available(iOS 17, *)
#Preview("Submitted — confirming") {
    ShieldedSubmittedUnconfirmedView(onDone: {})
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Submitted — large type") {
    ShieldedSubmittedUnconfirmedView(onDone: {})
        .background(Color.dash.primaryBackground)
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
