//
//  ShieldedRecoverySheet.swift
//  DashWallet
//

import SwiftUI
import DashUIKit
import SwiftDashSDK

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

#if DEBUG

/// The sheet owns its coordinator and `phase` is `private(set)`, so a preview
/// can only reach the idle state — the in-flight, success and
/// submitted-unconfirmed bodies are previewed through
/// `ShieldedTransferStepList` and `ShieldedSubmittedUnconfirmedView`.
///
/// The synthetic initialiser is what makes this previewable at all: a real
/// `Transaction` wraps a `PersistentTransaction` out of SwiftData, and there is
/// none in a canvas. `shieldedOutPoint` is therefore nil here, so "Finish now"
/// would bail — which is the honest preview of a row whose lock is missing.
@MainActor
private func recoverySheetSample(netAmount: Int64 = -125_000_000) -> some View {
    ShieldedRecoverySheet(
        transaction: Transaction(
            syntheticTxid: Data(repeating: 0xAB, count: 32),
            directionRaw: 1,
            netAmount: netAmount,
            fee: 1_000,
            contextRaw: 2,
            date: Date(timeIntervalSince1970: 1_770_000_000)),
        onDismiss: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Color.dash.primaryText.opacity(0.4).ignoresSafeArea())
}

@available(iOS 17, *)
#Preview("Idle") {
    recoverySheetSample()
}

@available(iOS 17, *)
#Preview("Dark") {
    recoverySheetSample()
        .preferredColorScheme(.dark)
}

/// The amount and the copy both have to survive the largest type sizes — this
/// sheet is mostly explanation, and it is the one the user meets after a
/// transfer already went wrong.
@available(iOS 17, *)
#Preview("Large type") {
    recoverySheetSample()
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
