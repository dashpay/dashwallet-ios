//
//  InternalTransferConfirmSheet.swift
//  DashWallet
//

import SwiftUI

/// Confirmation half-sheet shown when the user taps `Continue` on the
/// Internal transfer screen. Body swaps based on the embedded
/// `ShieldedTransferCoordinator.phase`:
///   - `.idle`           → summary card + Cancel/Confirm buttons.
///   - in-flight phases  → step checklist (Signing / Locking / Proving /
///                         Broadcasting). Drag-dismiss is disabled.
///   - `.success`        → green check + amount + Done.
///   - `.failed(msg)`    → summary card with red error + Try again / Close.
///
/// Confirm routes to one of the two SDK paths via the coordinator:
///   - `.core`     → `performAssetLock(amountDuffs:)`
///   - `.platform` → `performShield(amountCredits:)`
struct InternalTransferConfirmSheet: View {

    let source: InternalTransferSource
    let dashDuffs: Int64
    let amountDuffsUnsigned: UInt64
    let creditsAmount: UInt64
    let creditsText: String
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
        HStack(spacing: 4) {
            Text("~ \(creditsText)")
                .font(.subheadline)
                .foregroundColor(.secondaryText)
            Text("c")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondaryText)
            Text("/ \(fiatText)")
                .font(.subheadline)
                .foregroundColor(.secondaryText)
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                label: NSLocalizedString("From", comment: ""),
                value: sourceLabel)
            divider
            summaryRow(
                label: NSLocalizedString("To", comment: ""),
                value: NSLocalizedString("Shielded balance", comment: ""))
            divider
            summaryRow(
                label: NSLocalizedString("Network fee", comment: ""),
                value: "~ $X")
            divider
            summaryRow(
                label: NSLocalizedString("Total credits", comment: ""),
                valueView: AnyView(
                    HStack(spacing: 4) {
                        Text("~ \(creditsText)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primaryText)
                        Text("c")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primaryText)
                    }))
        }
        .background(Color.secondaryBackground)
        .cornerRadius(12)
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
                Image(systemName: "shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Privacy tip", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(NSLocalizedString(
                    "For best privacy, wait at least 2 hours before using these credits.",
                    comment: ""))
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

    // MARK: - Progress checklist

    /// Vertical step list — one row per phase the route advances through.
    /// Asset-lock has 4 stages; the transparent shield route hides
    /// `.locking` because the FFI doesn't surface that intermediate step.
    private var progressChecklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepRow(label: NSLocalizedString("Authorizing", comment: ""), state: stepState(for: .signing))

            if source == .core {
                stepRow(label: NSLocalizedString("Locking funds", comment: ""), state: stepState(for: .locking))
            }

            stepRow(label: NSLocalizedString("Generating proof", comment: ""), state: stepState(for: .proving))
            stepRow(label: NSLocalizedString("Broadcasting", comment: ""), state: stepState(for: .broadcasting))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum StepState {
        case pending
        case active
        case complete
    }

    /// Where this step sits relative to the current phase. The phase enum
    /// is intentionally ordered .signing → .locking → .proving →
    /// .broadcasting so a numeric comparison drives the state.
    private func stepState(for phase: ShieldedTransferCoordinator.Phase) -> StepState {
        let current = coordinator.phase
        guard let currentIdx = phaseIndex(current), let targetIdx = phaseIndex(phase) else {
            return .pending
        }
        if targetIdx < currentIdx { return .complete }
        if targetIdx == currentIdx { return .active }
        return .pending
    }

    private func phaseIndex(_ phase: ShieldedTransferCoordinator.Phase) -> Int? {
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

    // MARK: - Actions

    private func confirm() {
        Task {
            switch source {
            case .core:
                await coordinator.performAssetLock(amountDuffs: amountDuffsUnsigned)
            case .platform:
                await coordinator.performShield(amountCredits: creditsAmount)
            }
        }
    }

    private func tryAgain() {
        coordinator.reset()
        confirm()
    }
}
