//
//  ShieldedTransferStepList.swift
//  DashWallet
//

import SwiftUI
import DashUIKit
import SwiftDashSDK


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

#if DEBUG


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
#endif

