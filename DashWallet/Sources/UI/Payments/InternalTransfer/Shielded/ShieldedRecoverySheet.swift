//
//  ShieldedRecoverySheet.swift
//  DashWallet
//

import Combine
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
// MARK: - AssetLockStatus

/// `PersistentAssetLock.statusRaw`, named.
///
/// The recovery decision turns on these numbers, and spelling them as literals
/// where that decision is made hid what a `4` or a `1...3` meant. The Rust side
/// is the authority (`rs-platform-wallet-ffi/src/asset_lock_persistence.rs`);
/// this mirrors it for the one reader that has to branch on it.
///
/// TODO(asset-lock-status): `TxDetailModel.lockStatusText` still maps the same
/// raw values by hand — it should read this rather than repeat it.
enum AssetLockStatus: Int {
    case built = 0
    case broadcast = 1
    case instantSendLocked = 2
    case chainLocked = 3
    /// The shield transition consumed the lock — the transfer is finished.
    case consumed = 4
    /// Recovered from chain after a restore: final on Core, but whether it
    /// completed on Platform cannot be authenticated.
    case recoveredFromChain = 5
}

// MARK: - ShieldedRecoveryViewModel

/// Everything the recovery sheet does, kept out of the sheet.
///
/// It holds the coordinator, asks the lookup what the lock's live status is,
/// and runs the resume. The view reads `phase` and calls `finish()`.
///
/// TODO(shielded-recovery-service): the resume is still tied to this object's
/// lifetime, and this object is tied to the sheet's. Dismissal is refused while
/// a resume is in flight, which is what keeps it alive today, but the ownership
/// `InternalTransferRunner` documents — a service the work outlives its
/// presenter through — is the shape this should end up in.
@MainActor
final class ShieldedRecoveryViewModel: ObservableObject {

    /// The coordinator's phase, republished: a nested `ObservableObject` does
    /// not announce through its owner.
    @Published private(set) var phase: ShieldedTransferCoordinator.Phase = .idle

    /// "Finish now" found the lock already consumed — a background sync landed
    /// the shield after the history row's snapshot was taken. Shows success
    /// rather than paying for a proof that cannot land.
    @Published private(set) var alreadyComplete = false

    private let outPoint: (txidWire: Data, vout: UInt32)?
    private let coordinator = ShieldedTransferCoordinator()
    private var cancellables = Set<AnyCancellable>()

    init(transaction: Transaction) {
        outPoint = transaction.shieldedOutPoint.map { ($0.txidWire, $0.vout) }

        coordinator.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.phase = $0 }
            .store(in: &cancellables)
    }

    var isInFlight: Bool {
        switch phase {
        case .signing, .locking, .proving, .broadcasting: return true
        default: return false
        }
    }

    /// Resume the transfer, unless it turns out to be finished already.
    ///
    /// The live status is re-read first because the resume FFI builds the whole
    /// Orchard proof before Platform reports the lock consumed — without this a
    /// transfer that completed in the background would dead-end after ~30s of
    /// work. Returns false when there is no outpoint to resume, which the sheet
    /// answers by closing.
    @discardableResult
    func finish() -> Bool {
        guard let outPoint else { return false }

        Task { @MainActor in
            await ShieldedTxLookup.shared.refresh(reason: "shield-recovery-preflight")

            if Self.status(ofOutPoint: outPoint.txidWire) == .consumed {
                alreadyComplete = true
                return
            }

            // Every other status resumes: broadcast through chain-locked is
            // still pending, `recoveredFromChain` is Core-final with the
            // Platform side unknown, and a missing status means the refresh
            // told us nothing. A local tombstone and a remote already-consumed
            // report both land on unconfirmed rather than false success.
            await coordinator.resumeAssetLock(
                outPointTxidWire: outPoint.txidWire,
                outPointVout: outPoint.vout)

            // The shield consumed the lock; refresh so the history row flips
            // pending → completed without waiting for the next sync pass.
            if case .success = coordinator.phase {
                await ShieldedTxLookup.shared.refresh(reason: "shield-recovery-completed")
            }
        }
        return true
    }

    /// The lookup is keyed by display-order txid; an outpoint carries wire
    /// order, which is the reverse.
    private static func status(ofOutPoint txidWire: Data) -> AssetLockStatus? {
        let displayTxid = txidWire.reversed().map { String(format: "%02x", $0) }.joined()
        guard let raw = ShieldedTxLookup.shared.info(forTxidHex: displayTxid)?.statusRaw else {
            return nil
        }
        return AssetLockStatus(rawValue: raw)
    }
}

/// Presented from the home tx list when the user taps a row flagged
/// `Transaction.isPendingShieldedTransfer`. Drawing only — the coordinator, the
/// status lookup and the resume are `ShieldedRecoveryViewModel`'s, which keeps
/// it independent of any live confirm-sheet flow.
struct ShieldedRecoverySheet: View {

    let transaction: Transaction
    var onDismiss: () -> Void

    @StateObject private var viewModel: ShieldedRecoveryViewModel

    init(transaction: Transaction, onDismiss: @escaping () -> Void) {
        self.transaction = transaction
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: ShieldedRecoveryViewModel(transaction: transaction))
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Finish shielded transfer", comment: "InternalTransfer recovery"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 20)

            switch viewModel.phase {
            case .success:
                successBody
            case .submittedUnconfirmed:
                ShieldedSubmittedUnconfirmedView(onDone: onDismiss)
            case .signing, .locking, .proving, .broadcasting:
                inFlightBody
            default:
                if viewModel.alreadyComplete {
                    successBody
                } else {
                    idleOrFailedBody
                }
            }
        }
        .background(Color.dash.primaryBackground)
        .interactiveDismissDisabled(viewModel.isInFlight)
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

            if case let .failed(message) = viewModel.phase {
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
                currentPhase: viewModel.phase,
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

    private func finish() {
        // No outpoint means nothing to resume — the row that opened this sheet
        // has no tracked lock behind it.
        if !viewModel.finish() {
            onDismiss()
        }
    }
}

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
