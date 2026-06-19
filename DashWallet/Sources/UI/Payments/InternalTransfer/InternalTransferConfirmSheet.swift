//
//  InternalTransferConfirmSheet.swift
//  DashWallet
//

import SwiftUI
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
/// Confirm routes to one of three SDK paths via the coordinator, keyed by
/// `direction` then `source`:
///   - `.toShielded` + `.core`     → `performAssetLock(amountDuffs:)`
///   - `.toShielded` + `.platform` → `performShield(amountCredits:)`
///   - `.fromShielded`             → `performWithdraw(amountCredits:)`
struct InternalTransferConfirmSheet: View {

    let source: InternalTransferSource
    let direction: InternalTransferDirection
    let dashDuffs: Int64
    let amountDuffsUnsigned: UInt64
    let creditsAmount: UInt64
    let fiatText: String
    var onCancel: () -> Void
    var onCompleted: () -> Void

    @StateObject private var coordinator = ShieldedTransferCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Confirm", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
                .padding(.top, 20)

            switch coordinator.phase {
            case .success:
                successBody
            default:
                detailsBody
            }
        }
        .background(Color.primaryBackground)
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

            case .success:
                // Handled by `successBody`.
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
                .foregroundColor(.primaryText)

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
            .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }

    private var secondaryLine: some View {
        Text(fiatText)
            .font(.subheadline)
            .foregroundColor(.secondaryText)
    }

    // MARK: - Network fee estimate

    /// Asset-lock processing base cost folded into a ShieldFromAssetLock
    /// (Type 18) pool fee on top of `compute_minimum_shielded_fee`. Mirrors
    /// the Rust `shield_from_asset_lock_pool_fee`:
    /// `required_asset_lock_duff_balance_for_processing_start_for_address_funding`
    /// (50_000 duffs) × 1000 credits/duff. Versioned constant; estimate-only.
    private static let assetLockBaseCostCredits: UInt64 = 50_000_000

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// Flat shielded fee (credits) for the active route, computed offline by
    /// the SDK against the latest protocol version (so it matches the carved
    /// fee). `nil` if the SDK estimate is unavailable.
    private var networkFeeCredits: UInt64? {
        switch (direction, source) {
        case (.toShielded, .core):
            // ShieldFromAssetLock: base shielded fee + asset-lock base cost.
            guard let base = try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 2)
            else { return nil }
            return base + Self.assetLockBaseCostCredits
        case (.toShielded, .platform):
            // Shield (Type 15): base shielded fee. Real metered storage is
            // extra and only knowable on-chain, so this is a lower bound.
            return try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 2)
        case (.fromShielded, .core):
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 2)
        case (.fromShielded, .platform):
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 2)
        }
    }

    /// Network-fee estimate as fiat (e.g. "~ $0.08"), or "—" if unavailable.
    private var networkFeeString: String {
        guard let credits = networkFeeCredits else { return "—" }
        let dash = Decimal(credits) / Self.creditsPerDash
        return "~ " + CurrencyExchanger.shared.fiatAmountString(for: dash)
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
                value: dashDuffs.formattedDashAmount)
        }
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    /// "From" side of the summary. Forward = the picked source; reverse =
    /// the shielded balance.
    private var fromLabel: String {
        switch direction {
        case .toShielded:
            return sourceLabel
        case .fromShielded:
            return NSLocalizedString("Shielded balance", comment: "")
        }
    }

    /// "To" side of the summary. Forward = the shielded balance; reverse =
    /// the transparent Dash Wallet.
    private var toLabel: String {
        switch direction {
        case .toShielded:
            return NSLocalizedString("Shielded balance", comment: "")
        case .fromShielded:
            // Reverse destination is the picked transparent endpoint.
            return sourceLabel
        }
    }

    private var sourceLabel: String {
        switch source {
        case .core:
            return NSLocalizedString("Dash Wallet", comment: "")
        case .platform:
            return NSLocalizedString("Platform Payment", comment: "")
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        summaryRow(
            label: label,
            valueView: AnyView(
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primaryText)))
    }

    private func summaryRow(label: String, valueView: AnyView) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
            Spacer()
            valueView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray300.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Privacy tip

    private var privacyTipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dashBlue)
                    .frame(width: 30, height: 30)
                Image(systemName: privacyTipIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(privacyTipTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(privacyTipBody)
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    /// The tip card is route-aware:
    /// - forward (any source): privacy nudge.
    /// - reverse → Dash Wallet (L1 withdraw): up-to-10-minute spend delay.
    /// - reverse → Platform Payment (unshield): settles fast, so a privacy nudge.
    private var showsWithdrawDelayTip: Bool {
        direction == .fromShielded && source == .core
    }

    private var privacyTipIcon: String {
        showsWithdrawDelayTip ? "clock.fill" : "shield.fill"
    }

    private var privacyTipTitle: String {
        showsWithdrawDelayTip
            ? NSLocalizedString("Up to 10 minutes to spend", comment: "")
            : NSLocalizedString("Privacy tip", comment: "")
    }

    private var privacyTipBody: String {
        if showsWithdrawDelayTip {
            return NSLocalizedString(
                "After this transfer, it can take up to 10 minutes before you can use your Dash. This delay is part of how your privacy is protected.",
                comment: "")
        }
        switch direction {
        case .toShielded:
            return NSLocalizedString(
                "For best privacy, wait at least 2 hours before using these funds.",
                comment: "")
        case .fromShielded:
            // Unshield to Platform Payment settles quickly.
            return NSLocalizedString(
                "These funds move to your Platform Payment balance and are ready to spend right away.",
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
        if direction == .toShielded && source == .core {
            steps.append(.init(label: NSLocalizedString("Locking funds", comment: ""), phase: .locking))
        }
        steps.append(.init(label: NSLocalizedString("Generating proof", comment: ""), phase: .proving))
        steps.append(.init(label: NSLocalizedString("Broadcasting", comment: ""), phase: .broadcasting))
        return steps
    }

    // MARK: - Actions

    private func confirm() {
        Task {
            switch direction {
            case .toShielded:
                switch source {
                case .core:
                    await coordinator.performAssetLock(amountDuffs: amountDuffsUnsigned)
                case .platform:
                    await coordinator.performShield(amountCredits: creditsAmount)
                }
            case .fromShielded:
                switch source {
                case .core:
                    await coordinator.performWithdraw(amountCredits: creditsAmount)
                case .platform:
                    await coordinator.performUnshield(amountCredits: creditsAmount)
                }
            }
        }
    }

    private func tryAgain() {
        // If the just-failed Core→Shielded attempt already committed an asset
        // lock, RESUME that exact outpoint instead of building a second lock
        // (which strands the first). Capture before reset() clears it. Every
        // other case (no committed lock — auth-cancel / preflight failure — or
        // a non-asset-lock route) falls through to a fresh retry.
        if direction == .toShielded, source == .core,
           let op = coordinator.lastAssetLockOutPoint {
            coordinator.reset()
            Task { await coordinator.resumeAssetLock(outPointTxidWire: op.txidWire, outPointVout: op.vout) }
        } else {
            coordinator.reset()
            confirm()
        }
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
                .foregroundColor(.primaryText)
                .padding(.top, 20)

            switch coordinator.phase {
            case .success:
                successBody
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
        .background(Color.primaryBackground)
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
                .foregroundColor(.secondaryText)
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
                .foregroundColor(.primaryText)

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
            .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dashBlue)
                    .frame(width: 30, height: 30)
                Image(systemName: "shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Your Dash is safe", comment: "InternalTransfer recovery"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(NSLocalizedString(
                    "This transfer's funds were locked on-chain but the private transfer didn't finish. Tap Finish now to complete it.",
                    comment: "InternalTransfer recovery"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.secondaryBackground)
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
            guard let statusRaw, (1...3).contains(statusRaw) else {
                // Consumed (4) or gone → already complete; show success, no resume.
                alreadyComplete = true
                return
            }

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

    let currentPhase: ShieldedTransferCoordinator.Phase
    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(steps) { step in
                stepRow(label: step.label, state: state(for: step.phase))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum StepState {
        case pending
        case active
        case complete
    }

    /// Where `phase` sits relative to `currentPhase`. The phase enum is ordered
    /// .signing → .locking → .proving → .broadcasting → .success, so a numeric
    /// comparison drives the state.
    private func state(for phase: ShieldedTransferCoordinator.Phase) -> StepState {
        guard let currentIdx = Self.phaseIndex(currentPhase),
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
        case .idle, .failed: return nil
        }
    }

    private func stepRow(label: String, state: StepState) -> some View {
        HStack(spacing: 12) {
            stepIndicator(state: state)
            Text(label)
                .font(.system(size: 15, weight: state == .active ? .semibold : .regular))
                .foregroundColor(state == .pending ? .secondaryText : .primaryText)
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
                .stroke(Color.gray300.opacity(0.6), lineWidth: 1.5)
                .frame(width: 20, height: 20)
        case .active:
            ZStack {
                Circle()
                    .stroke(Color.dashBlue, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(Color.dashBlue)
                    .frame(width: 10, height: 10)
            }
        case .complete:
            ZStack {
                Circle()
                    .fill(Color.dashBlue)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}
