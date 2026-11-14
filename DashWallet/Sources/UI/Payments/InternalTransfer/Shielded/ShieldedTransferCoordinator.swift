//
//  ShieldedTransferCoordinator.swift
//  DashWallet
//
//  Drives a single user-initiated transfer: the six internal
//  InternalTransferRoute legs between the wallet's own balances, plus the
//  external Send routes (the withdraw/unshield/platform-withdraw legs with a
//  recipient destination override, shielded → shielded `shieldedTransfer`,
//  and platform → platform `PlatformSendExecutor.transfer`):
//   - PIN/biometric gate via `DWIdentityAuthorizer`.
//   - Shielded-centric legs call `PlatformWalletManager` directly:
//       * Core → Shielded   `shieldedFundFromAssetLock` (Type 18 lock,
//         Halo 2 proof); Platform → Shielded `shieldedShield` (Type 15);
//       * Shielded → Core   `shieldedWithdraw`; Shielded → Platform
//         `shieldedUnshield`.
//   - Core ↔ Platform legs go through `PlatformAddressSyncCoordinator`
//     (the app's platform address-wallet seam): `fundFromCore` (asset-lock
//     address top-up) and `withdrawAllToCore` (full-balance withdrawal).
//   - Publishes a stage `phase` so the confirm sheet can show a multi-step
//     progress checklist. For the asset-lock route, real stage transitions
//     are mirrored from `PersistentAssetLock.statusRaw` (0/1 → .locking,
//     2/3 → .proving, 4 → .broadcasting) — same polling pattern as
//     `DWIdentityRegistrationCoordinator.startAssetLockPolling`.
//   - Best-effort `syncShieldedNow()` after a successful broadcast so the
//     screen's To-card readback refreshes promptly.
//
//  Scope of this v1:
//   - `fundingAccountIndex`, `shieldedAccount`, `paymentAccount` all pinned
//     to 0 (single-account wallet). Mirrors `DWIdentityRegistrationCoordinator
//     .defaultAccountIndex`.
//   - The internal legs' shielded recipient is the wallet's own default
//     Orchard address — resolved once via
//     `PlatformWalletManager.shieldedDefaultAddress(...)`. The Send screen's
//     external legs pass the recipient's address/raw bytes instead.
//   - No mid-call cancellation. The FFI doesn't expose it; the sheet
//     disables drag-dismiss + Cancel while a transfer is in flight.
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

/// How many Orchard actions the app may put in one shielded transition.
///
/// Consensus allows 16 (`system_limits.max_shielded_transition_actions`), but
/// the 20 KiB `system_limits.max_state_transition_size` binds first: the Halo 2
/// proof grows ~2,681 bytes per action. Platform's
/// `seed_pool_batch_fits_max_state_transition_size` test measures 2 actions →
/// 8,294 B, 6 → 19,018 B, 7 → 21,699 B — and the 7-action bundle is rejected,
/// which reaches the app as "State Transition exceeds maximum size of 20480
/// bytes" from DAPI's broadcast check. Rust's pool seeder pins the same bound
/// as `MAX_ACTIONS_PER_BATCH` in `rs-platform-wallet/src/wallet/shielded/seed_pool.rs`.
///
/// Spending more notes than this needs a second transition, which the sweep
/// planner reports as `ShieldedSweepPlan.remainingCredits`.
enum ShieldedActionBudget {
    static let maxActionsPerTransition = 6
}

/// A note-aware full-balance spend plan. Unlike the amount screens' normal
/// affordability reserve, a sweep prices the fee from the notes that will
/// actually enter the Orchard bundle. That keeps a one-note withdrawal from
/// reserving the worst-case fee for a full
/// `ShieldedActionBudget.maxActionsPerTransition` bundle and returning the
/// difference as a persistent change note.
struct ShieldedSweepPlan: Equatable {
    let amountCredits: UInt64
    let feeCredits: UInt64
    let inputCredits: UInt64
    /// Funds that necessarily stay in the pool after this bundle. Normally
    /// zero; non-zero when the notes do not all fit, or when some are worth
    /// less than the fee of the action that would spend them.
    let remainingCredits: UInt64
    /// What a FOLLOW-UP sweep of the leftover notes could actually pay out,
    /// once its own fee is deducted. Zero when the leftovers are dust: they
    /// cost more to spend than they carry, so no later sweep can move them
    /// and telling the user to retry would loop forever.
    let followUpCredits: UInt64
}

struct ShieldedSweepCandidate: Equatable {
    let amountCredits: UInt64
    let inputCredits: UInt64
    let feeCredits: UInt64
    let noteCount: Int
}

/// Pure counterpart of Rust's largest-first shielded note selector. Keeping
/// prefix optimization separate from SwiftData makes the dust/action-fee edge
/// cases deterministic and regression-testable.
enum ShieldedSweepPlanner {
    static func bestCandidate(
        noteValues: [UInt64],
        maxActions: Int = ShieldedActionBudget.maxActionsPerTransition,
        feeForActions: (Int) -> UInt64?
    ) -> ShieldedSweepCandidate? {
        guard maxActions > 0 else { return nil }

        let values = noteValues.sorted(by: >).prefix(maxActions)
        var prefixInput: UInt64 = 0
        var best: ShieldedSweepCandidate?

        for (offset, value) in values.enumerated() {
            let next = prefixInput.addingReportingOverflow(value)
            guard !next.overflow else { return nil }
            prefixInput = next.partialValue

            let noteCount = offset + 1
            guard let fee = feeForActions(max(noteCount, 2)),
                  prefixInput > fee
            else { continue }

            let candidate = ShieldedSweepCandidate(
                amountCredits: prefixInput - fee,
                inputCredits: prefixInput,
                feeCredits: fee,
                noteCount: noteCount)

            // Keep the earlier/smaller prefix on a tie. Rust will stop at that
            // prefix too, and the payout is identical without an extra action.
            if let currentBest = best {
                if candidate.amountCredits > currentBest.amountCredits {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    /// Re-run Rust's iterative selection for the chosen amount and require an
    /// exact spend (`inputs == amount + fee`). A best-prefix plan should never
    /// create change; failing closed here protects against policy drift.
    static func revalidate(
        noteValues: [UInt64],
        amountCredits: UInt64,
        maxActions: Int = ShieldedActionBudget.maxActionsPerTransition,
        feeForActions: (Int) -> UInt64?
    ) -> ShieldedSweepCandidate? {
        let values = noteValues.sorted(by: >)
        guard let initialFee = feeForActions(2) else { return nil }
        var feeEstimate = initialFee

        for _ in 0..<6 {
            let required = amountCredits.addingReportingOverflow(feeEstimate)
            guard !required.overflow else { return nil }

            var accumulated: UInt64 = 0
            var count = 0
            for value in values {
                let next = accumulated.addingReportingOverflow(value)
                guard !next.overflow else { return nil }
                accumulated = next.partialValue
                count += 1
                if accumulated >= required.partialValue { break }
            }
            guard accumulated >= required.partialValue, count <= maxActions,
                  let exactFee = feeForActions(max(count, 2))
            else { return nil }

            let exactRequired = amountCredits.addingReportingOverflow(exactFee)
            guard !exactRequired.overflow else { return nil }
            if accumulated >= exactRequired.partialValue {
                guard accumulated == exactRequired.partialValue else {
                    return nil
                }
                return ShieldedSweepCandidate(
                    amountCredits: amountCredits,
                    inputCredits: accumulated,
                    feeCredits: exactFee,
                    noteCount: count)
            }
            feeEstimate = exactFee
        }

        return nil
    }
}

enum ShieldedSweepAvailability: Equatable {
    case ready(ShieldedSweepPlan)
    /// A previous outgoing activity is still pending, so persisted notes can
    /// temporarily include inputs that Rust has reserved in memory.
    case waitingForConfirmation(UInt64)
    case unavailable
}

@MainActor
final class ShieldedTransferCoordinator: ObservableObject {

    enum Phase: Equatable {
        case idle
        case signing
        case locking
        case proving
        case broadcasting
        case success
        /// Broadcast was accepted by relay but its result couldn't be
        /// confirmed (SDK `shieldedSpendUnconfirmed`). Terminal + NON-retryable:
        /// re-submitting risks a double-spend / wasted fee. The effect lands via
        /// the next shielded sync.
        case submittedUnconfirmed
        case failed(String)

        /// Work is running: the sheet must stay up and a tap must not start a
        /// second attempt.
        var isInFlight: Bool {
            switch self {
            case .signing, .locking, .proving, .broadcasting: return true
            case .idle, .success, .submittedUnconfirmed, .failed: return false
            }
        }
    }

    enum Source {
        case core
        case platform
    }

    @Published private(set) var phase: Phase = .idle {
        didSet {
            if !phase.isInFlight {
                releaseInFlightOutPoint()
            }
        }
    }

    /// The typed error behind the current `.failed(_)` phase. `Phase`
    /// carries only display text (that's what the confirm sheets render), so
    /// programmatic callers that must branch on the *kind* of failure —
    /// `AssetLockRecoveryService` telling a PIN cancel from a real error —
    /// read the error itself here rather than matching localized strings.
    /// Cleared when a transfer starts and on `reset()`.
    private(set) var lastFailure: Error?

    /// The lock to re-check after combining coins when the current failure is
    /// the asset-lock input limit (`CoreCoinConsolidationSheet`); nil otherwise.
    var inputLimitCheck: AssetLockInputLimit.Check? {
        lastFailure.flatMap(AssetLockInputLimit.check(for:))
    }

    /// The input check for a Core → Shielded lock of `lockValueDuffs`.
    static func shieldInputCheck(lockValueDuffs: UInt64) -> AssetLockInputLimit.Check {
        AssetLockInputLimit.Check(amountDuffs: lockValueDuffs, inputBudget: AssetLockInputPolicy.platformInputBudget)
    }

    /// What a resume established beyond its terminal phase. `.submittedUnconfirmed`
    /// has two producers — `alreadyConsumedAssetLockResumePhase` (Platform says
    /// this outpoint is already spent) and `handleSpendError`
    /// (`shieldedSpendUnconfirmed`: the transition was accepted but its result
    /// could not be read back) — and only the first is evidence about the
    /// outpoint. Callers that persist a verdict, such as
    /// `AssetLockRecoveryService` writing an already-spent probe, must branch on
    /// this rather than on the phase, which cannot tell the two apart.
    /// Cleared when a transfer starts and on `reset()`.
    private(set) var lastResumeReport: ResumeReport?

    /// The distinctions a terminal phase flattens away.
    enum ResumeReport: Equatable {
        /// Platform reported this exact outpoint already consumed. Not
        /// quorum-authenticated, so it proves there is nothing left to retry
        /// without proving this transfer is what spent it.
        case alreadyConsumed
    }

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.shielded-transfer")

    /// Matches `PersistentAssetLock.fundingTypeRaw` for
    /// `AssetLockShieldedAddressTopUp` (see
    /// `rs-platform-wallet-ffi/src/asset_lock_persistence.rs`).
    static let shieldedAssetLockFundingType: Int = 5

    /// `PersistentAssetLock.fundingTypeRaw` for `AssetLockAddressTopUp` —
    /// the Core → Platform address-funding lock (same Rust source).
    static let addressAssetLockFundingType: Int = 4

    /// Same 0.5 s cadence as `DWIdentityRegistrationCoordinator` — enough
    /// for the four observable transitions (Built → Broadcast → IS/CL →
    /// Consumed) without burning CPU.
    private static let assetLockPollInterval: TimeInterval = 0.5

    private var lastAssetLockContext: CoreShieldedDrainContext?

    private let authorizer: TransferAuthorizing
    private var assetLockPollingTask: Task<Void, Never>?

    /// Where a resume whose network call threw records the error as the
    /// lock's last failure. Injected so a test reads what it wrote without
    /// touching the shared store.
    private let failureStore: AssetLockFailureStore

    /// The Core → Platform funding, check and resume calls (route 5).
    private let platformFunding: CoreToPlatformFunding

    /// The host's manager, wallet, network and storage every route starts
    /// from (`resolveBasicEnvironment`).
    private let hostEnvironment: () throws -> BasicEnvironment

    /// `platformFunding` nil = `PlatformAddressSyncCoordinator.shared`;
    /// `hostEnvironment` nil = what `SwiftDashSDKHost.shared` holds now.
    init(
        failureStore: AssetLockFailureStore = .shared,
        platformFunding: CoreToPlatformFunding? = nil,
        authorizer: TransferAuthorizing = DWIdentityAuthorizer(),
        hostEnvironment: (() throws -> BasicEnvironment)? = nil
    ) {
        self.failureStore = failureStore
        self.platformFunding = platformFunding ?? PlatformAddressSyncCoordinator.shared
        self.authorizer = authorizer
        self.hostEnvironment = hostEnvironment ?? Self.sdkHostEnvironment
    }

    /// Outpoint (wire-order txid + vout) of the asset lock the most recent
    /// `performAssetLock` or `performWalletDrain` built, as the SDK reported
    /// it, so a failed attempt's "Try again" can RESUME the existing lock
    /// instead of building a second one. Set when a fresh attempt fails,
    /// unless its broadcast was definitely rejected, and when a resume of a
    /// lock is refused (another attempt has it, or a removal is reloading the
    /// wallet). A Max drain records the outpoint it reported too, but its
    /// screens resume a drain from its marker, not from here. Cleared on
    /// `reset()` and at the start of a fresh attempt. A failed fresh Core →
    /// Platform attempt sets it too; with no `lastAssetLockContext` it only
    /// reports the kept lock, and `retryLastAssetLock` does nothing for it.
    private(set) var lastAssetLockOutPoint: ShieldedAssetLocksInFlight.OutPoint?

    /// The lock this coordinator has registered in `ShieldedAssetLocksInFlight`.
    private var inFlightOutPoint: ShieldedAssetLocksInFlight.OutPoint?

    // MARK: - Errors

    enum CoordinatorError: LocalizedError {
        case noWallet
        case noNetwork
        case noModelContainer
        case noManager
        case noShieldedAddress
        case noReceiveAddress
        case noPlatformAddress
        case authCancelled
        case authFailed
        case shieldedBalanceUnavailable
        case shieldedPoolFeeUnavailable
        case addressFundingFeeUnavailable
        case platformShieldCapacityChanged(maxShieldableCredits: UInt64?)
        case shieldedSweepWaiting(UInt64)
        case shieldedSweepChanged
        case shieldedAmountExceedsBundle(UInt64)
        case coinJoinDrainRequiresSync
        /// Another attempt is still consuming this asset lock — typically a
        /// transfer waiting for its ChainLock. A second resume would race it.
        case assetLockInFlight
        /// A removed transaction is being dropped and the wallet runtime
        /// reloaded; a transfer started meanwhile would be stopped by it.
        case walletReloading
        /// A Max drain's lock whose recipient cannot be established.
        case drainRecipientUnknown
        /// A Max drain's marker could not be read right now.
        case drainRecipientUnavailable
        /// A resume named a different recipient than the one its lock was
        /// built for. Nothing was sent; the lock stays tracked.
        case resumeRecipientMismatch
        /// An external Max would now sweep more than the user confirmed.
        case drainBalanceChanged
        case transferFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noWallet:
                return NSLocalizedString("Wallet is not ready for transfer", comment: "InternalTransfer")
            case .noNetwork:
                return NSLocalizedString("Network is not configured", comment: "InternalTransfer")
            case .noModelContainer:
                return NSLocalizedString("Storage is not configured", comment: "InternalTransfer")
            case .noManager:
                return NSLocalizedString("Platform wallet manager unavailable", comment: "InternalTransfer")
            case .noShieldedAddress:
                return NSLocalizedString("Shielded address is not bound for this wallet", comment: "InternalTransfer")
            case .noReceiveAddress:
                return NSLocalizedString("Could not resolve a destination wallet address", comment: "InternalTransfer")
            case .noPlatformAddress:
                return NSLocalizedString("Could not resolve a destination Platform Payment address", comment: "InternalTransfer")
            case .authCancelled:
                return NSLocalizedString("Authentication cancelled", comment: "InternalTransfer")
            case .authFailed:
                return NSLocalizedString("Authentication failed", comment: "InternalTransfer")
            case .shieldedBalanceUnavailable:
                return NSLocalizedString("Shielded balance is unavailable. Try again after syncing.", comment: "Shielded transfer requires a known balance")
            case .shieldedPoolFeeUnavailable:
                return NSLocalizedString(
                    "There was an error, please try again later",
                    comment: "Core to Shielded pool fee estimate unavailable")
            case .addressFundingFeeUnavailable:
                return NSLocalizedString(
                    "There was an error, please try again later",
                    comment: "Core to Platform funding fee estimate unavailable")
            case .platformShieldCapacityChanged(let maxShieldableCredits):
                guard let maxShieldableCredits else {
                    return NSLocalizedString(
                        "Your available Platform balance changed, but the new maximum could not be checked. Return to the amount and try again.",
                        comment: "Platform Shield capacity changed but refresh failed")
                }
                let maximum = (maxShieldableCredits / 1000)
                    .formattedDashAmountWithoutCurrencySymbol
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Your available Platform balance changed. The new maximum is %@ DASH. Review and confirm the transfer again.",
                        comment: "Platform Shield capacity changed before authorization"),
                    maximum)
            case .shieldedSweepWaiting(let credits):
                let formatted = (credits / 1000).formattedDashAmountWithoutCurrencySymbol
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "%@ DASH is still confirming. Try again once it settles.",
                        comment: "Shielded sweep pending change"),
                    formatted)
            case .shieldedSweepChanged:
                return NSLocalizedString(
                    "Your Shielded balance changed. Close this confirmation and tap Max again.",
                    comment: "Shielded sweep changed before submit")
            case .shieldedAmountExceedsBundle(let ceiling):
                let formatted = (ceiling / 1000).formattedDashAmountWithoutCurrencySymbol
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Your Shielded balance is split across notes, and at most %@ DASH of it can be sent in one transaction.",
                        comment: "Shielded amount above the single-transaction ceiling"),
                    formatted)
            case .coinJoinDrainRequiresSync:
                return NSLocalizedString(
                    "Your wallet is still syncing. Moving your mixed coins to Shielded will be available once it finishes.",
                    comment: "CoinJoin drain blocked while the chain is syncing")
            case .assetLockInFlight:
                return NSLocalizedString(
                    "This transfer is still in progress. Check its status again in a few minutes.",
                    comment: "A resume was refused because the same transfer is still running")
            case .walletReloading:
                return ShieldedAssetLocksInFlight.walletReloadingMessage
            case .drainRecipientUnknown:
                return NSLocalizedString(
                    "This transfer was started by a Max operation this app can no longer identify, so it cannot be finished from here. Your funds remain locked and safe.",
                    comment: "InternalTransfer recovery: drain recipient unknown")
            case .drainRecipientUnavailable:
                return NSLocalizedString("Wallet unavailable. Try again.", comment: "Core drain")
            case .resumeRecipientMismatch:
                return NSLocalizedString(
                    "This transfer can only be finished to the recipient it was started with. Nothing was sent. Your funds remain locked and safe.",
                    comment: "InternalTransfer recovery: resume recipient differs from the recorded one")
            case .drainBalanceChanged:
                return NSLocalizedString(
                    "Your Transparent balance changed after you reviewed this transfer. Go back and tap Max again.",
                    comment: "Send: external Max drain, balance grew before confirm")
            case .transferFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    // MARK: - Full-balance shielded sweep

    /// Builds the Max plan from the active wallet's persisted unspent notes.
    /// The Rust selector is largest-first and the app caps a transition at
    /// `ShieldedActionBudget.maxActionsPerTransition` actions, so the first
    /// bundle consumes at most that many of the largest notes. Any remainder is
    /// reported to the amount screen instead of being left behind silently.
    static func sweepAvailability(
        feeKind: PlatformWalletManager.ShieldedFeeKind
    ) -> ShieldedSweepAvailability {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer
        else { return .unavailable }

        let walletId = wallet.walletId
        let context = modelContainer.mainContext

        let pendingDescriptor = FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate {
                $0.walletId == walletId && $0.accountIndex == 0 && $0.status == 0
            })
        let hasPendingSpend = ((try? context.fetch(pendingDescriptor)) ?? [])
            .contains { !$0.spentNullifiers.isEmpty }

        let balanceCoordinator = PlatformAddressSyncCoordinator.shared
        guard balanceCoordinator.shieldedBalanceState.isAvailable else { return .unavailable }
        if hasPendingSpend || balanceCoordinator.isShieldedBalanceReconciling {
            return .waitingForConfirmation(balanceCoordinator.shieldedBalance)
        }

        let noteDescriptor = FetchDescriptor<PersistentShieldedNote>(
            predicate: PersistentShieldedNote.unspentPredicate(walletId: walletId))
        let noteValues = ((try? context.fetch(noteDescriptor)) ?? [])
            .filter { $0.accountIndex == 0 }
            .map(\.value)
            .sorted(by: >)

        guard !noteValues.isEmpty else { return .unavailable }

        let allCredits = noteValues.reduce(into: UInt64(0)) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            partial = overflow ? UInt64.max : sum
        }
        guard allCredits != UInt64.max else { return .unavailable }

        let feeForActions: (Int) -> UInt64? = { actionCount in
            try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
                kind: feeKind,
                numActions: actionCount)
        }
        guard let best = ShieldedSweepPlanner.bestCandidate(
            noteValues: noteValues,
            feeForActions: feeForActions),
              let exact = ShieldedSweepPlanner.revalidate(
                noteValues: noteValues,
                amountCredits: best.amountCredits,
                feeForActions: feeForActions)
        else { return .unavailable }

        // Persisted notes and the published balance must describe the same
        // snapshot. A mismatch is the post-spend indexing window; do not build
        // a Max plan from stale inputs Rust may already have reserved/spent.
        let publishedBalance = balanceCoordinator.shieldedBalance
        guard publishedBalance == allCredits else {
            return .waitingForConfirmation(publishedBalance)
        }

        // What a follow-up sweep of the untouched notes could pay out. The
        // planner drops a note whose value is below the fee of the action that
        // would carry it, so a leftover is not automatically sendable later —
        // price it instead of assuming.
        let leftovers = Array(noteValues.dropFirst(exact.noteCount))
        let followUpCredits = ShieldedSweepPlanner.bestCandidate(
            noteValues: leftovers,
            feeForActions: feeForActions)?.amountCredits ?? 0

        return .ready(
            ShieldedSweepPlan(
                amountCredits: exact.amountCredits,
                feeCredits: exact.feeCredits,
                inputCredits: exact.inputCredits,
                remainingCredits: allCredits - exact.inputCredits,
                followUpCredits: followUpCredits))
    }

    /// Largest amount the pool can fund inside ONE transition — the sweep
    /// plan's payout, which is by construction the best `ShieldedActionBudget`
    /// notes can do. A larger amount needs more notes than the 20 KiB
    /// state-transition limit admits, so it would be rejected at broadcast
    /// after the proof was built.
    ///
    /// `nil` while the note set is mid-reconcile — the caller then has no
    /// note-aware bound and falls back to its balance envelope.
    static func spendCeilingCredits(
        feeKind: PlatformWalletManager.ShieldedFeeKind
    ) -> UInt64? {
        guard case .ready(let plan) = sweepAvailability(feeKind: feeKind) else { return nil }
        return plan.amountCredits
    }

    /// Fails closed when a non-sweep amount needs more notes than one
    /// transition can carry. The amount screens check this too, but the guard
    /// belongs here as well: it is the last point before authorization and
    /// proof generation, and it covers callers that never ran that check.
    private func rejectIfAboveSpendCeiling(
        _ amountCredits: UInt64,
        feeKind: PlatformWalletManager.ShieldedFeeKind
    ) -> Bool {
        guard PlatformAddressSyncCoordinator.shared.shieldedBalanceState.isAvailable else {
            handleFailure(CoordinatorError.shieldedBalanceUnavailable)
            return true
        }
        guard let ceiling = Self.spendCeilingCredits(feeKind: feeKind),
              amountCredits > ceiling
        else { return false }
        handleFailure(CoordinatorError.shieldedAmountExceedsBundle(ceiling))
        return true
    }

    /// The credits a Shielded spend submits: on a sweep, the plan re-priced against the notes as they stand now,
    /// which must still pay `amountCredits`; otherwise `amountCredits` within the one-transition ceiling. nil after
    /// the failure is reported.
    private func submittableAmount(
        _ amountCredits: UInt64,
        sweepAll: Bool,
        feeKind: PlatformWalletManager.ShieldedFeeKind
    ) -> UInt64? {
        guard sweepAll else {
            return rejectIfAboveSpendCeiling(amountCredits, feeKind: feeKind) ? nil : amountCredits
        }
        switch Self.sweepAvailability(feeKind: feeKind) {
        case .ready(let plan) where plan.amountCredits == amountCredits:
            return plan.amountCredits
        case .waitingForConfirmation(let credits):
            handleFailure(CoordinatorError.shieldedSweepWaiting(credits))
            return nil
        case .ready, .unavailable:
            handleFailure(CoordinatorError.shieldedSweepChanged)
            return nil
        }
    }

    // MARK: - Public API

    /// Whole eligible-wallet intent. Correlation uses this call's durable UUID,
    /// never the newest asset lock or a timestamp shared with another caller.
    /// `recipient` is written into that marker before dispatch. The SDK also
    /// records it on the lock's row before broadcast; a resume reads the
    /// marker's only for a row the SDK tracked before it recorded recipients.
    func performWalletDrain(_ confirmation: CoreShieldedDrainConfirmation, recipient: CoreShieldedDrainRecipient = .ownWallet) async {
        guard beginTransfer() else { return }
        lastAssetLockOutPoint = nil
        Self.logger.info("🛡️ SHIELD-TX :: wallet drain external=\(recipient.isExternal)")
        // As in `performAssetLock`: activity from here on, so a removal cannot
        // reload the runtime while this drain authorizes and builds its lock.
        guard ShieldedAssetLocksInFlight.shared.beginFundingCall() else {
            handleFailure(CoordinatorError.walletReloading)
            return
        }
        defer { ShieldedAssetLocksInFlight.shared.endFundingCall() }
        let service = CoreShieldedDrainService()
        let env: Environment
        let operation: CoreShieldedDrainOperation
        do {
            try await authorize()
            _ = try service.manager(for: confirmation.context)
            guard SyncingActivityMonitor.shared.state == .syncDone else {
                throw CoreShieldedDrainService.ServiceError.requiresSync
            }
            guard try await service.pending(confirmation.context) == nil else {
                throw CoreShieldedDrainFileStore.StoreError.pendingOperation
            }
            let manager = try service.manager(for: confirmation.context)
            guard SyncingActivityMonitor.shared.state == .syncDone else {
                throw CoreShieldedDrainService.ServiceError.requiresSync
            }
            if recipient.isExternal {
                // The drain sweeps whatever is eligible when it builds. For
                // the wallet's own address any excess is harmless; for a third
                // party it is money the user never saw on the confirm sheet.
                // This re-read refuses growth that happened before it; it does
                // not bind the SDK's own input selection that follows.
                // TODO(drain-balance-cap): pass the confirmed candidate balance
                // as a limit the SDK enforces on the inputs it selects, once
                // the drain accepts one (dashpay/platform#5607).
                let preview = try await manager.shieldedWalletDrainPreview(walletId: confirmation.context.walletId)
                _ = try service.manager(for: confirmation.context)
                guard Self.drainStillMatches(preview, confirmation) else {
                    throw CoordinatorError.drainBalanceChanged
                }
            }
            env = try resolveEnvironment()
            operation = try service.prepare(confirmation.context, recipient: recipient)
        } catch {
            handleFailure(error)
            return
        }

        // The drain reports no built lock, only its outpoint once it returns,
        // while the lock's row carries the operation id from the moment it is
        // persisted. Claimed by that id for the whole call, so no surface
        // offers to finish, and no resume starts on, a lock still waiting for
        // its proof. A completed drain keeps the claim until the lock's row
        // reads as no longer pending (`releaseDrainClaim`).
        var completed = false
        ShieldedAssetLocksInFlight.shared.claimDrain(operation.id)
        defer { Self.releaseDrainClaim(operation.id, completed: completed) }

        phase = .locking
        let result = await env.manager.shieldedFundFromWalletDrain(
            walletId: env.walletId, operationId: operation.id,
            recipientRaw43: Self.drainRecipientRaw43(operation.recipient, ownAddress: env.shieldedRecipient))
        if let outpoint = result.outpoint {
            lastAssetLockOutPoint = .init(txidWire: outpoint.txidWire, vout: outpoint.vout)
        }
        // Not marked consumed in `ShieldedTxLookup`, unlike a fresh
        // `performAssetLock`: a drain's `.completed` may rest on an
        // unauthenticated "already consumed" report, and a consumed mark would
        // hide the lock from every recovery surface for the session.
        if case .completed = result.drainVerdict { completed = true }
        do {
            try service.settle(operation, outcome: result)
        } catch {
            // The result may be successful but cleanup failed. Keep the marker
            // and resolve it by UUID before allowing another drain.
            phase = .submittedUnconfirmed
            await ShieldedTxLookup.shared.refresh(reason: "wallet-drain-settle-failed")
            NotificationCenter.default.post(name: .swiftDashSDKTransactionProjectionDidChange, object: nil)
            scheduleShieldedResync(manager: env.manager)
            return
        }
        switch result.drainVerdict {
        case .notSent:
            if let error = result.error {
                // More final coins than one lock may spend: the preview warns
                // of it, and the shared sheet offers to combine them.
                if case PlatformWalletError.assetLockTooManyInputs = error {
                    handleFailure(AssetLockInputLimit.TooManyInputsError(
                        check: .drain(inputBudget: AssetLockInputPolicy.platformInputBudget)))
                } else {
                    handleFailure(error)
                }
            } else {
                handleFailure(CoreShieldedDrainService.ServiceError.unavailable)
            }
            return
        case .pending:
            phase = .submittedUnconfirmed
        case .completed:
            phase = .broadcasting
            phase = .success
        }
        await ShieldedTxLookup.shared.refresh(reason: "wallet-drain-settled")
        NotificationCenter.default.post(name: .swiftDashSDKTransactionProjectionDidChange, object: nil)
        scheduleShieldedResync(manager: env.manager)
    }

    /// Route 1: BIP44 Core UTXOs → asset-lock → Type 18 shield.
    /// Stages: `.signing → .locking → .proving → .broadcasting → .success`.
    /// The intermediate stages are polled from `PersistentAssetLock.statusRaw`;
    /// the SDK returns `Void` only on `Consumed`/success.
    ///
    /// Which balance funds the asset lock.
    enum AssetLockFundingSource: Equatable {
        /// Amount the shielded recipient receives, coin-selected from the
        /// BIP44 spendable balance — the historical route behind the internal
        /// transfer and Send. The coordinator locks this plus the Type-18
        /// pool fee on top.
        case bip44(recipientAmountDuffs: UInt64)
        /// Whole-balance drain of the CoinJoin account: every mixed-coin
        /// UTXO funds the lock directly (lock value = Σ inputs − L1 fee,
        /// computed SDK-side) — the post-migration "move mixed coins to
        /// Shielded" path. No transparent intermediate hop.
        case coinJoinDrain
    }

    /// Why the transfer must stop after the prompt, before anything is built
    /// or broadcast, or nil.
    private func executionRefusal(
        funding: AssetLockFundingSource,
        expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding?,
        env: Environment
    ) -> Error? {
        // After the prompt, so a switch while it was open is caught too; the
        // sync gate below then reads the pinned wallet's state.
        guard isStillBound(binding, env: env) else {
            Self.logger.error("🛡️ SHIELD-TX :: asset lock refused — the active wallet changed")
            return CoordinatorError.noWallet
        }

        // A cancelled task stops here, before anything is built or broadcast.
        // Reported as a cancel: the caller went away, nothing failed.
        if Task.isCancelled {
            Self.logger.error("🛡️ SHIELD-TX :: asset lock refused — task cancelled")
            return CoordinatorError.authCancelled
        }

        // Re-check at the execution boundary, not only where the surface was
        // offered. The drain is whole-account and its value is computed
        // SDK-side, so a scan that restarted while the sheet or the PIN prompt
        // was open would lock a UTXO set the user never saw. The BIP44 route
        // carries an explicit amount and its own screens gate on
        // `isChainSynced`, so this is the drain's check alone.
        if case .coinJoinDrain = funding,
           SyncingActivityMonitor.shared.state != .syncDone {
            Self.logger.error("🛡️ SHIELD-TX :: coinjoin drain refused — chain not synced")
            return CoordinatorError.coinJoinDrainRequiresSync
        }
        return nil
    }

    /// `recipientRaw43` nil = the wallet's own default Orchard address (the
    /// internal transfer); an external Send passes the recipient's raw
    /// 43-byte payload. The recipient receives exactly `recipientAmountDuffs`:
    /// the coordinator inflates the lock by the Type-18 pool fee, which the
    /// SDK then subtracts back out (`shield_amount = lock − pool_fee`).
    func performAssetLock(recipientAmountDuffs: UInt64, recipientRaw43 recipientOverride: Data? = nil) async {
        await performAssetLock(
            funding: .bip44(recipientAmountDuffs: recipientAmountDuffs),
            recipientRaw43: recipientOverride)
    }

    /// Funding-parameterized form of `performAssetLock(recipientAmountDuffs:)`
    /// — same stages, polling, and resume semantics for both funding sources
    /// (a stuck lock resumes by outpoint regardless of what funded it).
    /// - Parameter binding: When set, the transfer fails unless this is still
    ///   the active wallet and network (the CoinJoin move pins the wallet it
    ///   was authorized for).
    func performAssetLock(
        funding: AssetLockFundingSource,
        recipientRaw43 recipientOverride: Data? = nil,
        expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding? = nil
    ) async {
        guard beginTransfer() else { return }
        lastAssetLockOutPoint = nil
        Self.logger.info("🛡️ SHIELD-TX :: asset-lock route funding=\(String(describing: funding), privacy: .public) external=\(recipientOverride != nil)")

        // The single fee-on-top point: the BIP44 form carries the amount the
        // recipient must receive, and the lock is inflated by the pool fee
        // here so the SDK's `shield_amount = lock − pool_fee` lands back on
        // exactly that amount. Fails closed — a missing fee estimate, a zero
        // amount, or overflow must never submit an un-inflated lock. The
        // CoinJoin drain's lock value is computed SDK-side, which preflights
        // it against the pool fee before broadcasting.
        let bip44LockValueDuffs: UInt64?
        if case .bip44(let recipientAmountDuffs) = funding {
            guard recipientAmountDuffs > 0,
                  let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits,
                  let lockDuffs = CoreToShieldedAmountPolicy.lockValueDuffs(
                      forAmountDuffs: recipientAmountDuffs,
                      poolFeeCredits: poolFeeCredits)
            else {
                handleFailure(CoordinatorError.shieldedPoolFeeUnavailable)
                return
            }
            bip44LockValueDuffs = lockDuffs
            Self.logger.info("🛡️ SHIELD-TX :: fee-on-top lock recipient=\(recipientAmountDuffs) lock=\(lockDuffs)")
        } else {
            bip44LockValueDuffs = nil
        }

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }
        // Counts as activity from here on, so a removal cannot reload the
        // runtime while this attempt authorizes and builds its lock.
        guard ShieldedAssetLocksInFlight.shared.beginFundingCall() else {
            handleFailure(CoordinatorError.walletReloading)
            return
        }
        defer { ShieldedAssetLocksInFlight.shared.endFundingCall() }

        // Before the prompt: a lock over the input limit is never built, so
        // it asks for nothing (`AssetLockInputPolicy`).
        let inputCheck = bip44LockValueDuffs.map(Self.shieldInputCheck(lockValueDuffs:))
        if let inputCheck {
            do {
                try AssetLockInputLimit.requireFits(inputCheck)
            } catch {
                handleFailure(error)
                return
            }
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        if let refusal = executionRefusal(funding: funding, expecting: binding, env: env) {
            handleFailure(refusal)
            return
        }

        lastAssetLockContext = CoreShieldedDrainContext(walletId: env.walletId, networkScope: env.network.persistenceScope)
        phase = .locking
        let (newLock, onAssetLockBuilt) = beginNewAssetLock(modelContainer: env.modelContainer)

        do {
            let recipient = ShieldedFundFromAssetLockRecipient(
                recipientRaw43: recipientOverride ?? env.shieldedRecipient,
                credits: nil)
            switch funding {
            case .bip44:
                guard let lockValueDuffs = bip44LockValueDuffs, let inputCheck else {
                    // Unreachable: the entry guard derives it for every .bip44.
                    throw CoordinatorError.shieldedPoolFeeUnavailable
                }
                try await AssetLockInputLimit.mappingRefusal(inputCheck) {
                    try await env.manager.shieldedFundFromAssetLock(
                        walletId: env.walletId,
                        fundingAccountIndex: 0,
                        amountDuffs: lockValueDuffs,
                        recipients: [recipient],
                        onAssetLockBuilt: onAssetLockBuilt)
                }
            case .coinJoinDrain:
                try await env.manager.shieldedFundFromCoinJoinDrain(
                    walletId: env.walletId,
                    recipients: [recipient],
                    onAssetLockBuilt: onAssetLockBuilt)
            }
        } catch {
            // Records the built lock's outpoint, so "Try again" RESUMES the
            // lock instead of building a second one.
            finishNewAssetLock(newLock, armingRetryAfter: error)
            handleSpendError(error, manager: env.manager)
            return
        }

        finishNewAssetLock(newLock)
        Self.logger.info("🛡️ SHIELD-TX :: asset-lock route completed")
        // The success phase releases the lock's claim. The lookup reports the
        // lock as consumed until a snapshot shows it consumed, so the Home row
        // and the details do not offer to finish it in between.
        markInFlightLockConsumed()
        phase = .success
        await ShieldedTxLookup.shared.refresh(reason: "shield-transfer-completed")
        NotificationCenter.default.post(
            name: .swiftDashSDKTransactionProjectionDidChange,
            object: nil)
        scheduleShieldedResync(manager: env.manager)
    }

    /// Resume a stuck "to Shielded" transfer whose asset lock is already
    /// tracked (built, broadcast or locked) but whose shield state transition
    /// never landed. Picks up the existing outpoint and drives the remaining stages
    /// via `shieldedResumeFundFromAssetLock` — instead of building a SECOND
    /// asset lock (which is what a fresh `performAssetLock` would do, stranding
    /// the first). The recipient is the one the original attempt was built
    /// for, resolved by `ShieldedResumeRecipient`: the recipient the SDK
    /// recorded on the lock's row, or — for a row tracked before the SDK
    /// recorded recipients — the Max drain marker's, the caller's
    /// `recipientRaw43`, or the wallet's own default shielded address. The
    /// SDK re-derives an identical `shield_amount` from the on-chain lock
    /// value, so a resume cannot desync funds and is safe to retry.
    /// Re-authorizes — this moves real funds.
    ///
    /// Used by both confirm sheets' "Try again" (in-session) and the
    /// home-screen recovery sheet (after relaunch).
    /// - Parameters:
    ///   - recipientOverride: the recipient the calling surface knows; it
    ///     must agree with the recorded one, or the resume is refused.
    ///   - binding: as for `performAssetLock(funding:recipientRaw43:expecting:)`.
    func resumeAssetLock(
        outPointTxidWire: Data,
        outPointVout: UInt32,
        recipientRaw43 recipientOverride: Data? = nil,
        expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding? = nil,
        expectedDrainContext: CoreShieldedDrainContext? = nil,
        retryUnverifiedConsumption: Bool = false
    ) async {
        // Read before the resume moves it, for the outcome lines below.
        let lockInfo = ShieldedTxLookup.shared
            .info(forTxidHex: AssetLockFailureStore.displayHex(txidWire: outPointTxidWire))
        let statusBeforeRaw = lockInfo?.statusRaw
        // A lock another attempt is consuming, or a wallet reload, refuses
        // this resume at the gate and leaves an outcome line. A plain double
        // tap (phase not idle) does not.
        guard beginTransfer(
            consuming: outPointTxidWire, vout: outPointVout,
            drainOperation: lockInfo?.drainOperation,
            onRefusal: { refusal in
                Self.logGateRefusal(
                    refusal, event: "resume", txidWire: outPointTxidWire, vout: outPointVout,
                    fundingTypeRaw: Self.shieldedAssetLockFundingType, statusBeforeRaw: statusBeforeRaw)
            }) else { return }
        Self.logger.info("🛡️ SHIELD-TX :: resume asset-lock vout=\(outPointVout) external=\(recipientOverride != nil)")

        // Every attempt past the single-flight gate leaves one outcome line.
        // The confirm sheets, the recovery sheet and the CoinJoin move call
        // this directly, with no service-level logger behind them, so a
        // refusal before the resume call is logged here too. Only an error
        // from the resume call itself is stored as the lock's last failure: a
        // refusal (no wallet, PIN timeout, wallet switched) says nothing about
        // the lock and must not overwrite the failure that does. A cancelled
        // PIN prompt is an outcome, not a failure.
        func logResumeOutcome(_ result: String) {
            AssetLockRetryLog.logOutcome(
                result,
                prefix: AssetLockRetryLog.shieldPrefix,
                event: "resume",
                txidWire: outPointTxidWire,
                vout: outPointVout,
                fundingTypeRaw: Self.shieldedAssetLockFundingType,
                statusBeforeRaw: statusBeforeRaw)
        }
        func recordResumeFailure(_ error: Error) {
            AssetLockRetryLog.recordFailure(
                error,
                prefix: AssetLockRetryLog.shieldPrefix,
                event: "resume",
                txidWire: outPointTxidWire,
                vout: outPointVout,
                fundingTypeRaw: Self.shieldedAssetLockFundingType,
                statusBeforeRaw: statusBeforeRaw,
                store: failureStore)
        }
        func failBeforeResume(_ error: Error) {
            if case CoordinatorError.authCancelled = error {
                logResumeOutcome("outcome=cancelled")
            } else {
                AssetLockRetryLog.logRefusal(
                    error,
                    prefix: AssetLockRetryLog.shieldPrefix,
                    event: "resume",
                    txidWire: outPointTxidWire,
                    vout: outPointVout,
                    fundingTypeRaw: Self.shieldedAssetLockFundingType,
                    statusBeforeRaw: statusBeforeRaw)
            }
            handleFailure(error)
        }

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            failBeforeResume(error)
            return
        }

        // Capture the runtime's wallet before any suspension. Both the recovery
        // sheet and the bulk service enter here; neither may lose this advisory
        // result when its presenter closes or file it under a newly active wallet.
        let probeWalletIdHex = env.walletId.map { String(format: "%02x", $0) }.joined()
        if !retryUnverifiedConsumption,
           AssetLockProbeStore.shared.contains(outPointTxidWire, vout: outPointVout, walletIdHex: probeWalletIdHex) {
            logResumeOutcome("outcome=skippedConsumedReport")
            lastResumeReport = .alreadyConsumed
            phase = .submittedUnconfirmed
            return
        }

        // Every resume's recipient is decided here, whichever surface asked,
        // before the PIN prompt so a refusal asks for nothing. The SDK pays
        // only the recipient it recorded on the row; a row tracked before it
        // recorded one falls back to the Max drain marker, the caller's
        // recipient, then the wallet's own address (`ShieldedResumeRecipient`).
        guard let row = Self.resumeRow(
            outPointTxidWire: outPointTxidWire, vout: outPointVout,
            walletId: env.walletId, in: env.modelContainer)
        else {
            failBeforeResume(CoordinatorError.drainRecipientUnavailable)
            return
        }
        Self.logger.info("🛡️ SHIELD-TX :: resume drain row=\(String(describing: row.identity), privacy: .public) recorded=\(row.recordedRecipientRaw43 != nil)")
        // The gate read the drain id from the lookup snapshot, which can lag
        // the row; the row read here is authoritative.
        if case .operation(let id) = row.identity,
           ShieldedAssetLocksInFlight.shared.isDrainClaimed(id) {
            Self.logger.info("🛡️ SHIELD-TX :: resume refused vout=\(outPointVout): the Max drain that built the lock still holds it")
            lastAssetLockOutPoint = .init(txidWire: outPointTxidWire, vout: outPointVout)
            Self.logGateRefusal(
                .assetLockInFlight, event: "resume", txidWire: outPointTxidWire, vout: outPointVout,
                fundingTypeRaw: Self.shieldedAssetLockFundingType, statusBeforeRaw: statusBeforeRaw)
            handleFailure(CoordinatorError.assetLockInFlight)
            return
        }
        // A Max lock's resume holds the Max operation's claim, as a new Max
        // does, so no other attempt starts on it. Every return before
        // `finishResumedAssetLock` hands the claim over releases it at once.
        var drainClaim: UUID?
        if case .operation(let id) = row.identity {
            ShieldedAssetLocksInFlight.shared.claimDrain(id)
            drainClaim = id
        }
        defer { if let drainClaim { Self.releaseDrainClaim(drainClaim, completed: false) } }
        var markerContext: CoreShieldedDrainContext?
        let resolution = row.recipient(
            marker: {
                let (lookup, context) = CoreShieldedDrainService().markerLookup()
                markerContext = context
                return lookup
            },
            callerRaw43: recipientOverride,
            ownRaw43: env.shieldedRecipient)
        let recipientRaw43: Data
        switch resolution {
        case .pay(let raw43, let source):
            Self.logger.info("🛡️ SHIELD-TX :: resume recipient=\(source.rawValue, privacy: .public)")
            recipientRaw43 = raw43
        case .refuse(let refusal):
            Self.logger.error("🛡️ SHIELD-TX :: resume refused — recipient \(String(describing: refusal), privacy: .public)")
            switch refusal {
            case .mismatch: failBeforeResume(CoordinatorError.resumeRecipientMismatch)
            case .drainRecipientUnknown: failBeforeResume(CoordinatorError.drainRecipientUnknown)
            case .drainRecipientUnavailable: failBeforeResume(CoordinatorError.drainRecipientUnavailable)
            }
            return
        }
        // A drain row is resumed only while the wallet and network it was
        // resolved under are still active; checked again after the PIN.
        var drainContext = expectedDrainContext
        if row.identity != .none, drainContext == nil {
            drainContext = markerContext ?? (try? CoreShieldedDrainService.currentContext())
            guard drainContext != nil else {
                failBeforeResume(CoordinatorError.drainRecipientUnavailable)
                return
            }
        }

        do {
            try await authorize()
        } catch {
            failBeforeResume(error)
            return
        }

        guard isStillBound(binding, env: env) else {
            Self.logger.error("🛡️ SHIELD-TX :: resume refused — the active wallet changed")
            failBeforeResume(CoordinatorError.noWallet)
            return
        }

        if let drainContext {
            do {
                _ = try CoreShieldedDrainService().manager(for: drainContext)
            } catch {
                failBeforeResume(error)
                return
            }
        }

        // The lock already exists — the SDK re-broadcasts or waits for it if
        // needed, then the Orchard proof + the shield ST remain, so jump
        // straight to .proving (no .locking stage and no asset-lock polling:
        // there's no new lock to track).
        phase = .proving

        let terminalPhase: Phase
        do {
            let recipient = ShieldedFundFromAssetLockRecipient(
                recipientRaw43: recipientRaw43,
                credits: nil)
            try await env.manager.shieldedResumeFundFromAssetLock(
                walletId: env.walletId,
                outPointTxid: outPointTxidWire,
                outPointVout: outPointVout,
                recipients: [recipient])
            terminalPhase = .success
            logResumeOutcome("outcome=completed")
        } catch {
            guard let mappedPhase = Self.alreadyConsumedAssetLockResumePhase(for: error) else {
                // An ambiguous submission is not a proven failure of this lock.
                switch error {
                case PlatformWalletError.shieldedSpendUnconfirmed,
                     SDKError.stateTransitionResultUnconfirmed,
                     PlatformWalletError.transactionBroadcastUnconfirmed:
                    logResumeOutcome("outcome=submittedUnconfirmed")
                default:
                    recordResumeFailure(error)
                }
                handleSpendError(error, manager: env.manager)
                return
            }
            logResumeOutcome("outcome=alreadyConsumed")
            // A DAPI endpoint reported this exact outpoint as consumed, but
            // rejection responses are not quorum-authenticated. Rust retains
            // the ChainLock proof and records nonterminal consumption-unknown
            // state, so suppress bulk retries without claiming verified success.
            // A later explicit action can authorize another probe of this outpoint.
            terminalPhase = mappedPhase
            lastResumeReport = .alreadyConsumed
            AssetLockProbeStore.shared.record(txid: outPointTxidWire, vout: outPointVout, walletIdHex: probeWalletIdHex)
            Self.logger.info("🛡️ SHIELD-TX :: resume found asset lock reported consumed — completion remains unconfirmed")
        }

        Self.logger.info("🛡️ SHIELD-TX :: resume completed")
        // Hands the Max operation's claim over, so the deferred release
        // above no longer applies.
        finishResumedAssetLock(terminalPhase, drainOperation: drainClaim)
        drainClaim = nil
        await ShieldedTxLookup.shared.refresh(reason: "shield-transfer-resume-completed")
        NotificationCenter.default.post(
            name: .swiftDashSDKTransactionProjectionDidChange,
            object: nil)
        scheduleShieldedResync(manager: env.manager)
    }

    /// The bookkeeping after the resume call returned with `terminalPhase`.
    /// The single call covered proof + submit, so it advances through
    /// `.broadcasting` and the step checklist completes (as in
    /// `performShield`). A lock without a Max operation is marked consumed
    /// on a verified success only (as in `performAssetLock`). A Max lock
    /// (`drainOperation`, whose claim the resume holds) is never marked: its
    /// success may rest on an unauthenticated "already consumed" report, and
    /// its row ends at DrainCompleted, which never retires the mark. Its
    /// claim is released as a new Max's is (`releaseDrainClaim`).
    func finishResumedAssetLock(_ terminalPhase: Phase, drainOperation: UUID?, lookup: ShieldedTxLookup = .shared) {
        phase = .broadcasting
        if let drainOperation {
            Self.releaseDrainClaim(drainOperation, completed: terminalPhase == .success, lookup: lookup)
        } else if terminalPhase == .success {
            markInFlightLockConsumed(in: lookup)
        }
        phase = terminalPhase
    }

    /// Both a local `Consumed` tombstone and a remote already-consumed report
    /// arrive through this typed error. Neither proves that this particular
    /// shield completed, so both suppress retry without claiming success.
    static func alreadyConsumedAssetLockResumePhase(for error: Error) -> Phase? {
        if case PlatformWalletError.assetLockAlreadyConsumed = error {
            return .submittedUnconfirmed
        }
        return nil
    }

    /// What a resume reads from the SDK row of the lock it resumes.
    struct ResumeRow: Equatable {
        /// What the row says about the Max drain that built it.
        let identity: CoreShieldedDrainRowIdentity
        /// The recipient the SDK recorded before broadcasting the lock;
        /// `nil` for a row tracked before the SDK recorded recipients.
        let recordedRecipientRaw43: Data?

        /// The recipient a resume of this lock pays, or why it refuses (`ShieldedResumeRecipient`).
        func recipient(
            marker: () -> CoreShieldedDrainMarkerLookup,
            callerRaw43: Data?,
            ownRaw43: Data
        ) -> ShieldedResumeRecipient {
            ShieldedResumeRecipient.resolve(
                recordedRaw43: recordedRecipientRaw43,
                row: identity,
                marker: marker,
                callerRaw43: callerRaw43,
                ownRaw43: ownRaw43)
        }
    }

    /// The SDK row for this outpoint. `nil` when the row cannot be read or is
    /// missing: unknown is not "no drain" and not "no recipient". Every resume
    /// surface found its lock through this store, so a missing row is never a
    /// legitimate own-address resume. The row must belong to the wallet doing
    /// the resume: the store holds every wallet's locks, and another wallet's
    /// row would be read against this wallet's marker and address.
    static func resumeRow(
        outPointTxidWire: Data,
        vout: UInt32,
        walletId: Data,
        in modelContainer: ModelContainer
    ) -> ResumeRow? {
        let outPointHex = outPointTxidWire.reversed().map { String(format: "%02x", $0) }.joined() + ":\(vout)"
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in row.outPointHex == outPointHex && row.walletId == walletId })
        descriptor.fetchLimit = 1
        do {
            guard let row = try modelContainer.mainContext.fetch(descriptor).first else {
                logger.error("🛡️ SHIELD-TX :: asset-lock row missing for resume")
                return nil
            }
            return ResumeRow(
                identity: CoreShieldedDrainRowIdentity(operationIdBytes: row.operationId),
                recordedRecipientRaw43: row.shieldedRecipientRaw43)
        } catch {
            logger.error("🛡️ SHIELD-TX :: asset-lock row unreadable \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The Orchard payload a drain pays: the marker's external recipient, or
    /// the wallet's own address.
    nonisolated static func drainRecipientRaw43(_ recipient: CoreShieldedDrainRecipient, ownAddress: Data) -> Data {
        recipient.externalRaw43 ?? ownAddress
    }

    /// Whether a fresh preview still describes what the user confirmed: an
    /// external drain must not sweep a larger candidate balance than the one
    /// on the confirm sheet.
    nonisolated static func drainStillMatches(_ preview: WalletDrainPreview, _ confirmation: CoreShieldedDrainConfirmation) -> Bool {
        preview.status != .insufficientFunds
            && preview.candidateBalanceDuffs <= confirmation.candidateBalanceDuffs
    }

    /// Starts tracking the new asset lock of a fresh-build attempt: starts the
    /// status poll and returns the capture it reads with the handler the
    /// funding call reports the built lock to. The handler claims the lock in
    /// `ShieldedAssetLocksInFlight` the moment the SDK reports it, before the
    /// lock's row is persisted, so no surface shows this attempt's lock as an
    /// unclaimed stuck one.
    private func beginNewAssetLock(
        modelContainer: ModelContainer
    ) -> (NewAssetLockCapture, AssetLockBuiltHandler) {
        let capture = NewAssetLockCapture(initialState: nil)
        startAssetLockPolling(modelContainer: modelContainer, capture: capture)
        let handler: AssetLockBuiltHandler = { built in
            let key = ShieldedAssetLocksInFlight.OutPoint(txidWire: built.txid, vout: built.vout)
            ShieldedAssetLocksInFlight.shared.claimBuiltLock(key)
            capture.withLock { $0 = key }
        }
        return (capture, handler)
    }

    /// Ends the status poll of a fresh-build attempt whose funding call
    /// returned and takes over the claim its handler made, so the terminal
    /// phase releases it. After a failure (`armingRetryAfter` set) it also
    /// records the lock's outpoint for "Try again", unless the broadcast was
    /// definitely rejected, which removes the lock again. A lock the SDK kept
    /// stays tracked even when its row could not be saved, so the outpoint is
    /// recorded without reading the row.
    func finishNewAssetLock(_ capture: NewAssetLockCapture, armingRetryAfter failure: Error? = nil) {
        stopAssetLockPolling()
        guard let key = capture.withLock({ $0 }) else { return }
        // A fresh build starts from `beginTransfer()`, which claims nothing,
        // and the terminal phase clears `inFlightOutPoint`, so another claim
        // here means the coordinator was reused while a funding call ran.
        guard inFlightOutPoint == nil else {
            assertionFailure("built asset lock arrived while another lock is claimed")
            DWLogger.log("SHIELD-TX built asset lock vout=\(key.vout) arrived while another lock is claimed")
            ShieldedAssetLocksInFlight.shared.release(key)
            return
        }
        inFlightOutPoint = key
        if let failure, Self.keepsLockForRetry(after: failure) {
            lastAssetLockOutPoint = key
        }
    }

    /// Whether a fresh build's lock is still there after `failure`: every
    /// failure except a definite broadcast rejection, which removes it again.
    static func keepsLockForRetry(after failure: Error) -> Bool {
        if case PlatformWalletError.transactionBroadcastRejected = failure { return false }
        return true
    }

    /// Route 2: DIP-17 transparent Platform Payment credits → Type 15 shield.
    /// Stages: `.signing → .proving → .broadcasting → .success`. No
    /// intermediate signals from the FFI — `.proving` covers the whole opaque
    /// ~30 s call; on return we jump to `.success`.
    ///
    /// `recipientRaw43` nil = the wallet's own pool (the internal
    /// transfer); an external Send passes the recipient's raw 43-byte
    /// Orchard address and the note funds THAT wallet's pool instead
    /// (`shieldedShieldToRecipient`). Capacity preflight and fees are
    /// identical — the recipient does not change input selection.
    func performShield(amountCredits: UInt64, recipientRaw43: Data? = nil) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: shield route amount=\(amountCredits) credits external=\(recipientRaw43 != nil)")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        // Revalidate the frozen confirmation amount against the same Rust
        // selector immediately before asking for authentication or building a
        // proof. The form's cached preflight can become stale while Confirm is
        // open, but the confirmed amount must never be reduced silently.
        do {
            let preflight = try await PlatformAddressSyncCoordinator.shared.preflightShield()
            let capacity = PlatformShieldCapacity(preflight)
            guard PlatformShieldAmountPolicy.canSubmit(
                requestedCredits: amountCredits,
                capacity: capacity)
            else {
                handleFailure(CoordinatorError.platformShieldCapacityChanged(
                    maxShieldableCredits: capacity.maxShieldableCredits))
                return
            }
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        let signer = KeychainSigner(
            modelContainer: env.modelContainer,
            network: env.network)

        do {
            if let recipientRaw43 {
                try await env.manager.shieldedShieldToRecipient(
                    walletId: env.walletId,
                    shieldedAccount: 0,
                    paymentAccount: 0,
                    recipientRaw43: recipientRaw43,
                    amount: amountCredits,
                    addressSigner: signer)
            } else {
                try await env.manager.shieldedShield(
                    walletId: env.walletId,
                    shieldedAccount: 0,
                    paymentAccount: 0,
                    amount: amountCredits,
                    addressSigner: signer)
            }
        } catch {
            if case PlatformWalletError.shieldedInsufficientBalance = error {
                handleFailure(CoordinatorError.platformShieldCapacityChanged(
                    maxShieldableCredits: nil))
                // The rejection came from live Platform state while the
                // preflight reads cache, so another immediate preflight would
                // only repeat the stale maximum. Refresh the address cache and
                // let its published balance re-arm the form preflight.
                schedulePlatformResync()
                return
            }
            handleSpendError(error, manager: env.manager)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: shield route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
        // Shield debits the Platform-address balance; refresh it too (the
        // shielded resync above only updates the shielded side).
        schedulePlatformResync()
    }

    /// Route 3 (reverse): shielded Orchard notes → Core L1 transparent
    /// address. Stages: `.signing → .proving → .broadcasting →
    /// .success`. Like `shieldedShield`, `shieldedWithdraw` is a single opaque
    /// async call with no intermediate signals — `.proving` covers it until it
    /// returns. `amount` is in credits (1e11 / DASH), same scale as
    /// `shieldedShield`. No signer required.
    ///
    /// `toCoreAddress` nil = the wallet's own receive address (the internal
    /// transfer); an external Send passes the recipient's address. The
    /// withdrawal-store tag (which classifies the incoming L1 tx as
    /// "Shielded received") only applies to the own-wallet payout.
    func performWithdraw(
        amountCredits: UInt64,
        sweepAll: Bool = false,
        toCoreAddress destinationOverride: String? = nil
    ) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: withdraw route amount=\(amountCredits) credits external=\(destinationOverride != nil)")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        guard let submittedAmount = submittableAmount(amountCredits, sweepAll: sweepAll, feeKind: .withdrawal) else {
            return
        }

        // Destination Core (BIP44, Base58Check) address. For the internal
        // transfer, resolve the wallet's own receive address before advancing
        // the phase — same ordering as `resolveEnvironment()`. The reader is
        // main-actor-safe and we're already on @MainActor, so call it
        // directly (no GCD hop).
        let coreAddress: String
        let paysOwnWallet: Bool
        if let destinationOverride, !destinationOverride.isEmpty {
            coreAddress = destinationOverride
            paysOwnWallet = false
        } else {
            guard let ownAddress = SwiftDashSDKReceiveAddressReader.receiveAddress(),
                  !ownAddress.isEmpty else {
                handleFailure(CoordinatorError.noReceiveAddress)
                return
            }
            coreAddress = ownAddress
            paysOwnWallet = true
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        do {
            try await env.manager.shieldedWithdraw(
                walletId: env.walletId,
                // Per-operation Orchard spend authority (seedless shielded
                // bind, platform #4125/#4126); the SDK holds the resolver
                // alive across the FFI call via withExtendedLifetime.
                resolver: MnemonicResolver(),
                account: 0,
                toCoreAddress: coreAddress,
                amount: submittedAmount)
        } catch {
            // shieldedSpendUnconfirmed means the spend may already be on
            // chain (non-retryable), so its payout can still arrive — tag
            // the destination so the incoming tx classifies as a shielded
            // withdrawal either way. External payouts never land in this
            // wallet, so there is nothing to tag.
            if paysOwnWallet, case PlatformWalletError.shieldedSpendUnconfirmed = error {
                ShieldedWithdrawalStore.shared.record(address: coreAddress)
            }
            handleSpendError(error, manager: env.manager)
            return
        }

        // Tag the payout destination so the home list can classify the
        // incoming L1 tx as "Shielded received" (the SDK call returns no txid).
        if paysOwnWallet {
            ShieldedWithdrawalStore.shared.record(address: coreAddress)
        }

        Self.logger.info("🛡️ SHIELD-TX :: withdraw route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Route 4 (reverse): shielded Orchard notes → a transparent Platform
    /// Payment balance (DIP-17 credits). Stages: `.signing → .proving →
    /// .broadcasting → .success`. Like `shieldedShield` / `shieldedWithdraw`,
    /// `shieldedUnshield` is a single opaque async call with no intermediate
    /// signals. `amount` is in credits; no signer required.
    ///
    /// `toPlatformAddress` nil = the wallet's own next receive address (the
    /// internal transfer); an external Send passes the recipient's bech32m
    /// Platform address.
    func performUnshield(
        amountCredits: UInt64,
        sweepAll: Bool = false,
        toPlatformAddress destinationOverride: String? = nil
    ) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: unshield route amount=\(amountCredits) credits external=\(destinationOverride != nil)")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        guard let submittedAmount = submittableAmount(amountCredits, sweepAll: sweepAll, feeKind: .unshield) else {
            return
        }

        // Destination Platform Payment (bech32m) address — for the internal
        // transfer, the wallet's own next receive address. Resolve before
        // advancing the phase.
        let platformAddress: String
        let isOwnPlatformDestination: Bool
        if let destinationOverride, !destinationOverride.isEmpty {
            platformAddress = destinationOverride
            isOwnPlatformDestination = false
        } else {
            guard let ownDestination = PlatformAddressSyncCoordinator.shared
                    .derivedAddresses.nextReceiveAddress,
                  !ownDestination.address.isEmpty else {
                handleFailure(CoordinatorError.noPlatformAddress)
                return
            }
            platformAddress = ownDestination.address
            isOwnPlatformDestination = true
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        do {
            try await env.manager.shieldedUnshield(
                walletId: env.walletId,
                // Per-operation Orchard spend authority — see above.
                resolver: MnemonicResolver(),
                account: 0,
                toPlatformAddress: platformAddress,
                amount: submittedAmount)
        } catch {
            // The transition may already have credited our Platform address.
            // There is no proof height on this ambiguous path, so never invent
            // an absolute balance; let the height-aware BLAST sync reconcile it.
            if isOwnPlatformDestination,
               case PlatformWalletError.shieldedSpendUnconfirmed = error {
                schedulePlatformResync()
            }
            handleSpendError(error, manager: env.manager)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: unshield route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
        // Refresh the Platform side after the backend accepts the transition.
        // BLAST remains the source of truth for the persisted balance.
        schedulePlatformResync()
    }

    /// External send: shielded Orchard notes → an existing identity's
    /// credits, in one `IdentityTopUpFromShieldedPool` transition. The
    /// identity does not have to belong to this wallet; the pool fee
    /// (`.identityTopUpFromPool`) is spent from the notes on top of the
    /// amount. Stages: `.signing → .proving → .broadcasting → .success`.
    func performIdentityTopUpFromPool(
        amountCredits: UInt64,
        sweepAll: Bool = false,
        identityId: Data
    ) async {
        guard beginTransfer() else { return }
        DWLogger.log("🛡️ SHIELD-TX :: shielded→identity top-up amount=\(amountCredits) credits")

        let env: BasicEnvironment
        do {
            env = try resolveBasicEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        guard let submittedAmount = submittableAmount(
            amountCredits, sweepAll: sweepAll, feeKind: .identityTopUpFromPool)
        else { return }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        do {
            try await env.manager.shieldedIdentityTopUpFromPool(
                walletId: env.walletId,
                // Per-operation Orchard spend authority — see `performWithdraw`.
                resolver: MnemonicResolver(),
                account: 0,
                identityId: identityId,
                amount: submittedAmount)
        } catch {
            handleSpendError(error, manager: env.manager)
            return
        }

        DWLogger.log("🛡️ SHIELD-TX :: shielded→identity top-up completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Route 5: BIP44 Core UTXOs → asset lock → the wallet's own Platform
    /// address credits (funding type 4, `AssetLockAddressTopUp`). Stages:
    /// `.signing → .locking → .broadcasting → .success` — no Orchard proof,
    /// so `.proving` may only appear transiently via the lock-status polling
    /// (IS/CL-locked) before the funding ST lands. A lock left behind by a
    /// failure is resumed via `resumeFundPlatform` from the asset-lock recovery
    /// surfaces (`AssetLockRecoveryService`); this route offers no in-place
    /// "Try again". `externalDestination` (a Platform address of someone
    /// else, from ExternalSend) pays that address instead of the wallet's own,
    /// through `PlatformAddressSyncCoordinator.fundExternalFromCore`.
    ///
    /// Fee-on-top: the recipient gets an explicit amount and the funding ST's
    /// fee is deducted from the sender-owned remainder output, so
    /// `lockValueDuffs` carries a static reserve on top of
    /// `recipientAmountDuffs`. This coordinator executes the frozen value
    /// verbatim and never recomputes it, so the Total the user confirmed is
    /// exactly the lock executed.
    func performFundPlatform(
        recipientAmountDuffs: UInt64, lockValueDuffs: UInt64?, externalDestination: String? = nil
    ) async {
        guard beginTransfer() else { return }
        lastAssetLockOutPoint = nil

        // Fail closed — a zero amount, a missing/overflowed frozen lock, or
        // a lock that doesn't carry the amount plus a nonzero reserve must
        // never submit an un-inflated lock (which could not cover its own
        // processing cost).
        guard recipientAmountDuffs > 0,
              let lockValueDuffs,
              lockValueDuffs > recipientAmountDuffs
        else {
            handleFailure(CoordinatorError.addressFundingFeeUnavailable)
            return
        }
        Self.logger.info("🛡️ SHIELD-TX :: core→platform fund route recipient=\(recipientAmountDuffs) lock=\(lockValueDuffs)")

        // Counts as activity from here on, so a removal cannot reload the
        // runtime while this attempt reads the wallet, authorizes and builds
        // its lock.
        guard ShieldedAssetLocksInFlight.shared.beginFundingCall() else {
            handleFailure(CoordinatorError.walletReloading)
            return
        }
        defer { ShieldedAssetLocksInFlight.shared.endFundingCall() }

        let env: BasicEnvironment
        do {
            env = try resolveBasicEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        // Before the prompt, as on the shielded route.
        let inputCheck = AssetLockInputLimit.Check(
            amountDuffs: lockValueDuffs, inputBudget: AssetLockInputPolicy.platformInputBudget)
        do {
            try AssetLockInputLimit.requireFits(inputCheck)
        } catch {
            handleFailure(error)
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .locking
        let (newLock, onAssetLockBuilt) = beginNewAssetLock(modelContainer: env.modelContainer)

        do {
            try await AssetLockInputLimit.mappingRefusal(inputCheck) {
                if let externalDestination {
                    try await platformFunding.fundExternalFromCore(
                        destination: externalDestination,
                        recipientAmountDuffs: recipientAmountDuffs,
                        lockValueDuffs: lockValueDuffs,
                        onAssetLockBuilt: onAssetLockBuilt)
                } else {
                    try await platformFunding.fundFromCore(
                        recipientAmountDuffs: recipientAmountDuffs,
                        lockValueDuffs: lockValueDuffs,
                        onAssetLockBuilt: onAssetLockBuilt)
                }
            }
        } catch {
            // Records the lock that is still there, which a caller reads to
            // tell a payment in progress from one that never left Core.
            finishNewAssetLock(newLock, armingRetryAfter: error)
            handlePlatformSpendError(error)
            return
        }

        finishNewAssetLock(newLock)
        Self.logger.info("🛡️ SHIELD-TX :: core→platform fund route completed")
        // As in `performAssetLock`.
        markInFlightLockConsumed()
        phase = .broadcasting
        phase = .success
        schedulePlatformResync()
    }

    /// Resume of route 5 after its asset lock committed but the address-
    /// funding ST never landed — drives the remaining stages on the SAME
    /// outpoint. Mirrors `resumeAssetLock` on the shielded route.
    func resumeFundPlatform(
        outPointTxidWire: Data,
        outPointVout: UInt32,
        recipientAmountDuffs: UInt64,
        retryUnverifiedConsumption: Bool = true
    ) async {
        let statusBeforeRaw = ShieldedTxLookup.shared
            .platformFundingInfo(forTxidHex: AssetLockFailureStore.displayHex(txidWire: outPointTxidWire))?.statusRaw
        guard beginTransfer(
            consuming: outPointTxidWire, vout: outPointVout, drainOperation: nil,
            onRefusal: { refusal in
                Self.logGateRefusal(
                    refusal, event: "resume core→platform", txidWire: outPointTxidWire, vout: outPointVout,
                    fundingTypeRaw: Self.addressAssetLockFundingType, statusBeforeRaw: statusBeforeRaw)
            }) else { return }
        lastAssetLockOutPoint = .init(txidWire: outPointTxidWire, vout: outPointVout)
        Self.logger.info("🛡️ SHIELD-TX :: resume core→platform fund vout=\(outPointVout)")

        guard recipientAmountDuffs > 0 else {
            handleFailure(CoordinatorError.addressFundingFeeUnavailable)
            return
        }

        let env: BasicEnvironment
        do {
            env = try resolveBasicEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        let probeWalletIdHex = env.walletId.map { String(format: "%02x", $0) }.joined()
        if !retryUnverifiedConsumption,
           AssetLockProbeStore.shared.contains(outPointTxidWire, vout: outPointVout, walletIdHex: probeWalletIdHex) {
            lastResumeReport = .alreadyConsumed
            phase = .submittedUnconfirmed
            return
        }

        // Before the prompt: a lock whose recipient cannot be established is
        // refused without asking for the PIN, every time it is tapped.
        do {
            try platformFunding.checkFundFromCoreResumable(
                outPointTxid: outPointTxidWire, outPointVout: outPointVout)
        } catch {
            AssetLockRetryLog.logRefusal(
                error, prefix: AssetLockRetryLog.shieldPrefix, event: "resume core→platform",
                txidWire: outPointTxidWire, vout: outPointVout,
                fundingTypeRaw: Self.addressAssetLockFundingType, statusBeforeRaw: statusBeforeRaw)
            handleFailure(error)
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        guard let current = try? resolveBasicEnvironment(),
              current.walletId == env.walletId, current.network == env.network,
              current.manager === env.manager else {
            handleFailure(CoordinatorError.noWallet)
            return
        }

        // The lock is already on-chain; only the funding ST remains.
        phase = .broadcasting

        do {
            try await platformFunding.resumeFundFromCore(
                outPointTxid: outPointTxidWire,
                outPointVout: outPointVout,
                recipientAmountDuffs: recipientAmountDuffs)
        } catch {
            if let consumedPhase = Self.alreadyConsumedAssetLockResumePhase(for: error) {
                lastResumeReport = .alreadyConsumed
                AssetLockProbeStore.shared.record(
                    txid: outPointTxidWire, vout: outPointVout, walletIdHex: probeWalletIdHex)
                phase = consumedPhase
                schedulePlatformResync()
                return
            }
            switch error {
            case SDKError.stateTransitionResultUnconfirmed, PlatformWalletError.transactionBroadcastUnconfirmed,
                 PlatformWalletError.shieldedSpendUnconfirmed:
                break
            default:
                AssetLockRetryLog.recordFailure(
                    error,
                    prefix: AssetLockRetryLog.shieldPrefix,
                    event: "resume core→platform",
                    txidWire: outPointTxidWire,
                    vout: outPointVout,
                    fundingTypeRaw: Self.addressAssetLockFundingType,
                    statusBeforeRaw: statusBeforeRaw,
                    store: failureStore)
            }
            handlePlatformSpendError(error)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: resume core→platform fund completed")
        markInFlightLockConsumed()
        phase = .success
        schedulePlatformResync()
    }

    /// Route 6: Platform address credits → Core L1 payout
    /// (`AddressCreditWithdrawalTransition`). Stages: `.signing →
    /// .broadcasting → .success` — a single opaque call, no proof and no
    /// asset lock. `fullBalance` picks the execution form: the AUTO
    /// withdrawal (every non-dust address, payout = balance − fee) when the
    /// user withdrew Max, else an explicit partial withdrawal paying out
    /// exactly `amountCredits` from the largest funded address. The L1
    /// payout arrives asynchronously once the chain processes the
    /// withdrawal; it shows as a regular incoming transaction.
    ///
    /// `toCoreAddress` nil = the wallet's own receive address (the internal
    /// transfer); an external Send passes the recipient's L1 address.
    func performPlatformWithdraw(
        amountCredits: UInt64,
        fullBalance: Bool,
        feeHeadroomCredits: UInt64?,
        toCoreAddress destinationOverride: String? = nil
    ) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: platform→core withdraw route full=\(fullBalance) amount=\(amountCredits) external=\(destinationOverride != nil)")

        // Destination Core (BIP44, Base58Check) address — for the internal
        // transfer, the wallet's own receive address (same resolution as the
        // shielded withdraw route).
        let coreAddress: String
        if let destinationOverride, !destinationOverride.isEmpty {
            coreAddress = destinationOverride
        } else {
            guard let ownAddress = SwiftDashSDKReceiveAddressReader.receiveAddress(),
                  !ownAddress.isEmpty else {
                handleFailure(CoordinatorError.noReceiveAddress)
                return
            }
            coreAddress = ownAddress
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .broadcasting

        do {
            if fullBalance {
                try await PlatformAddressSyncCoordinator.shared.withdrawAllToCore(address: coreAddress)
            } else {
                try await PlatformAddressSyncCoordinator.shared.withdrawToCore(
                    amountCredits: amountCredits,
                    address: coreAddress,
                    feeHeadroomCredits: feeHeadroomCredits)
            }
        } catch {
            handlePlatformSpendError(error)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: platform→core withdraw completed")
        phase = .success
        schedulePlatformResync()
    }

    /// External send: shielded Orchard notes → a third-party shielded
    /// payment address (`recipientRaw43` = the recipient's raw 43-byte
    /// Orchard address, decoded from their bech32m display form). Stages:
    /// `.signing → .proving → .broadcasting → .success` — same opaque-call
    /// shape as `performWithdraw`/`performUnshield`.
    func performShieldedTransfer(
        amountCredits: UInt64,
        sweepAll: Bool = false,
        recipientRaw43: Data
    ) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: shielded→shielded send amount=\(amountCredits) credits")

        let env: BasicEnvironment
        do {
            env = try resolveBasicEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        // Re-price the sweep against the note set as it stands now — same
        // guard as `performWithdraw`, so a note that was spent or discovered
        // between Max and confirm fails closed instead of building a bundle
        // the pool can no longer fund exactly.
        guard let submittedAmount = submittableAmount(amountCredits, sweepAll: sweepAll, feeKind: .transfer) else {
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        do {
            try await env.manager.shieldedTransfer(
                walletId: env.walletId,
                // Per-operation Orchard spend authority — see `performWithdraw`.
                resolver: MnemonicResolver(),
                account: 0,
                recipientRaw43: recipientRaw43,
                amount: submittedAmount)
        } catch {
            handleSpendError(error, manager: env.manager)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: shielded→shielded send completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// External send: DIP-17 Platform credits → a third-party Platform
    /// bech32m address, via `PlatformSendExecutor` (credit transfer, inputs
    /// auto-selected largest-first). Stages: `.signing → .broadcasting →
    /// .success` — a single opaque transition, no proof and no asset lock.
    func performPlatformSend(destination: String, amountCredits: UInt64) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: platform→platform send amount=\(amountCredits) credits")

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .broadcasting

        do {
            try await PlatformSendExecutor.shared.transfer(
                destination: destination,
                amount: amountCredits)
        } catch {
            handlePlatformSpendError(error)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: platform→platform send completed")
        phase = .success
        schedulePlatformResync()
    }

    /// An unknown result that left this attempt's asset lock recorded. The
    /// unknown part may be the lock's own broadcast, before any shield was
    /// sent, so waiting for sync does not always finish the transfer. Resuming
    /// that outpoint pays the recipient the caller passes and cannot pay
    /// twice: consensus consumes a lock once. False once Platform reported
    /// the lock consumed.
    var canResumeUnconfirmedAssetLock: Bool {
        phase == .submittedUnconfirmed && lastAssetLockOutPoint != nil
            && lastAssetLockContext != nil && lastResumeReport == nil
    }

    /// Retry the existing lock after fresh authorization. Retain its outpoint
    /// even when the PIN is cancelled, so the next tap cannot fund a second lock.
    /// Also continues an unconfirmed attempt whose lock is still recorded
    /// (`canResumeUnconfirmedAssetLock`).
    func retryLastAssetLock(recipientRaw43: Data? = nil) async {
        let continuesUnconfirmed = canResumeUnconfirmedAssetLock
        let retryable: Bool
        if case .failed = phase { retryable = true } else { retryable = continuesUnconfirmed }
        guard retryable, let outpoint = lastAssetLockOutPoint,
              let context = lastAssetLockContext else { return }
        do {
            _ = try CoreShieldedDrainService().manager(for: context)
        } catch {
            // The earlier result is still unknown; a refused resume must not
            // turn it into a failure the sheet answers with a fresh payment.
            if !continuesUnconfirmed { handleFailure(error) }
            return
        }
        reset()
        lastAssetLockOutPoint = outpoint
        lastAssetLockContext = context
        await resumeAssetLock(
            outPointTxidWire: outpoint.txidWire,
            outPointVout: outpoint.vout,
            recipientRaw43: recipientRaw43,
            expectedDrainContext: context,
            retryUnverifiedConsumption: true)
        // A resume that stopped or failed says nothing new about the earlier
        // submission: keep the unknown-result state and its recorded lock, so
        // closing the sheet still ends the send flow.
        if continuesUnconfirmed, case .failed = phase {
            lastAssetLockOutPoint = outpoint
            lastAssetLockContext = context
            phase = .submittedUnconfirmed
        }
    }

    /// Reset to `.idle` so the user can retry from a `.failed` state.
    /// Keeps no in-flight observers — the FFI calls themselves are
    /// uncancellable, so this just resets UI state. Does nothing while an
    /// attempt is in flight: leaving the in-flight phases releases the
    /// attempt's `ShieldedAssetLocksInFlight` claim, and the SDK may still be
    /// consuming that lock.
    func reset() {
        guard !phase.isInFlight else {
            assertionFailure("reset() while a transfer is in flight")
            Self.logger.warning("🛡️ SHIELD-TX :: reset() ignored while a transfer is in flight")
            return
        }
        stopAssetLockPolling()
        lastAssetLockOutPoint = nil
        lastAssetLockContext = nil
        lastFailure = nil
        lastResumeReport = nil
        phase = .idle
    }

    // MARK: - Internal

    struct BasicEnvironment {
        let manager: PlatformWalletManager
        let walletId: Data
        let network: Network
        let modelContainer: ModelContainer
    }

    private struct Environment {
        let manager: PlatformWalletManager
        let walletId: Data
        let network: Network
        let modelContainer: ModelContainer
        let shieldedRecipient: Data
    }

    /// Host readiness shared by every route. The Core↔Platform legs stop
    /// here; the shielded legs also require the bound Orchard address
    /// (`resolveEnvironment`).
    private func resolveBasicEnvironment() throws -> BasicEnvironment {
        try hostEnvironment()
    }

    private static func sdkHostEnvironment() throws -> BasicEnvironment {
        guard let manager = SwiftDashSDKHost.shared.manager else {
            throw CoordinatorError.noManager
        }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw CoordinatorError.noWallet
        }
        guard let network = SwiftDashSDKHost.shared.runningNetwork else {
            throw CoordinatorError.noNetwork
        }
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            throw CoordinatorError.noModelContainer
        }
        return BasicEnvironment(
            manager: manager,
            walletId: wallet.walletId,
            network: network,
            modelContainer: modelContainer)
    }

    private func resolveEnvironment() throws -> Environment {
        let basic = try resolveBasicEnvironment()
        let recipient: Data?
        do {
            recipient = try basic.manager.shieldedDefaultAddress(walletId: basic.walletId, account: 0)
        } catch {
            throw CoordinatorError.transferFailed(error)
        }
        guard let recipient, recipient.count == 43 else {
            throw CoordinatorError.noShieldedAddress
        }
        return Environment(
            manager: basic.manager,
            walletId: basic.walletId,
            network: basic.network,
            modelContainer: basic.modelContainer,
            shieldedRecipient: recipient)
    }

    /// Whether a pinned transfer may still run: `binding` (when set) is both
    /// the environment resolved for it and the host's active wallet now.
    private func isStillBound(
        _ binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding?, env: Environment
    ) -> Bool {
        guard let binding else { return true }
        return binding == SwiftDashSDKTransactionSender.CoinJoinWalletBinding(walletId: env.walletId, network: env.network)
            && binding == SwiftDashSDKTransactionSender.CoinJoinWalletBinding.current()
    }

    /// Synchronous single-flight gate. Returns `false` when a transfer is
    /// already in progress (or finished and not yet `reset()`), so a fast
    /// double-tap on Confirm can't queue a second transfer. Because the
    /// coordinator is `@MainActor`, the `phase == .idle` check and the
    /// `.signing` write run with no suspension point between them — the
    /// first caller wins atomically and the second sees `.signing` + bails.
    private func beginTransfer() -> Bool {
        guard phase == .idle else {
            // Logged so a tap that starts nothing is visible in the export.
            Self.logger.info("🛡️ SHIELD-TX :: begin refused phase=\(String(describing: self.phase), privacy: .public)")
            return false
        }
        lastFailure = nil
        lastResumeReport = nil
        phase = .signing
        return true
    }

    /// `beginTransfer()` for a resume of the lock at (`txidWire`, `vout`): it
    /// also fails the resume when another coordinator is still consuming that
    /// lock, and claims the lock for this attempt. Each entry point (the Home
    /// recovery sheet, the tx detail sheet's retry, a confirm sheet's "Try
    /// again") holds its own coordinator, so the phase gate alone cannot see an
    /// attempt that is already running, such as a transfer waiting minutes for
    /// its ChainLock. A fresh transfer's new lock is claimed from the moment
    /// the SDK builds it, before its row exists, so this also covers it.
    /// `onRefusal` receives the error of a refusal by the registry, before
    /// the failure is shown.
    private func beginTransfer(
        consuming txidWire: Data,
        vout: UInt32,
        drainOperation: UUID?,
        onRefusal: (CoordinatorError) -> Void
    ) -> Bool {
        // A running or finished attempt keeps its claim; the phase gate
        // refuses (and logs) this tap.
        guard phase == .idle else { return beginTransfer() }
        let outPoint = ShieldedAssetLocksInFlight.OutPoint(txidWire: txidWire, vout: vout)
        switch ShieldedAssetLocksInFlight.shared.admitResume(outPoint, drainOperation: drainOperation) {
        case .walletReloading:
            Self.logger.info("🛡️ SHIELD-TX :: resume refused vout=\(vout): a removal is reloading the wallet")
            // The caller's `reset()` cleared "Try again"'s outpoint; a refused
            // resume keeps it, so the next tap resumes this lock instead of
            // building a new one.
            lastAssetLockOutPoint = outPoint
            onRefusal(.walletReloading)
            handleFailure(CoordinatorError.walletReloading)
            return false
        case .claimedElsewhere:
            Self.logger.info("🛡️ SHIELD-TX :: resume refused vout=\(vout): the lock is still being consumed by another attempt")
            lastAssetLockOutPoint = outPoint
            onRefusal(.assetLockInFlight)
            handleFailure(CoordinatorError.assetLockInFlight)
            return false
        case .admitted:
            break
        }
        // Idle was checked above with no suspension since, so this admits.
        _ = beginTransfer()
        inFlightOutPoint = outPoint
        return true
    }

    /// Ends a Max drain's claim. A completed drain's lock row can still read
    /// as unfinished after the call returns (the SDK can write its final
    /// status afterwards, or the last refresh was superseded), and the claim
    /// is all that keeps the recovery surfaces from offering to finish it. So
    /// the claim of a completed drain is held until `ShieldedTxLookup` shows
    /// the drain's row (found by its operation id, so a result without an
    /// outpoint is covered too) finished (`AssetLockStatus.isComplete`), or
    /// `drainSettleTimeout` passes; nothing is refreshed from here. A row
    /// missing from the snapshot counts as pending. Any other drain releases
    /// at once. The settler watches `lookup`.
    private static func releaseDrainClaim(_ operation: UUID, completed: Bool, lookup: ShieldedTxLookup = .shared) {
        guard completed else {
            ShieldedAssetLocksInFlight.shared.releaseDrain(operation)
            return
        }
        DrainClaimSettler(operation: operation, timeout: drainSettleTimeout, lookup: lookup).start()
    }

    private static let drainSettleTimeout: TimeInterval = 30

    /// The outcome line of a resume the registry refused. A lock another
    /// attempt is consuming is not a failure of this lock; a wallet reload is
    /// a refusal, as the other refusals before the resume call are.
    private static func logGateRefusal(
        _ refusal: CoordinatorError,
        event: String,
        txidWire: Data,
        vout: UInt32,
        fundingTypeRaw: Int,
        statusBeforeRaw: Int?
    ) {
        if case .assetLockInFlight = refusal {
            AssetLockRetryLog.logOutcome(
                "outcome=skipped reason=in-flight", prefix: AssetLockRetryLog.shieldPrefix, event: event,
                txidWire: txidWire, vout: vout, fundingTypeRaw: fundingTypeRaw, statusBeforeRaw: statusBeforeRaw)
        } else {
            AssetLockRetryLog.logRefusal(
                refusal, prefix: AssetLockRetryLog.shieldPrefix, event: event,
                txidWire: txidWire, vout: vout, fundingTypeRaw: fundingTypeRaw, statusBeforeRaw: statusBeforeRaw)
        }
    }

    private func releaseInFlightOutPoint() {
        guard let inFlightOutPoint else { return }
        ShieldedAssetLocksInFlight.shared.release(inFlightOutPoint)
        self.inFlightOutPoint = nil
    }

    private func markInFlightLockConsumed(in lookup: ShieldedTxLookup = .shared) {
        guard let inFlightOutPoint else {
            Self.logger.warning("🛡️ SHIELD-TX :: finished without a known asset lock to mark consumed")
            return
        }
        lookup.markConsumed(txidWire: inFlightOutPoint.txidWire)
    }

    /// PIN/biometric gate. `phase` is already `.signing` (set synchronously
    /// by `beginTransfer()`); this just awaits user authorization and maps
    /// the cancel/fail outcomes onto coordinator errors.
    private func authorize() async throws {
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            throw CoordinatorError.authCancelled
        } catch {
            throw CoordinatorError.authFailed
        }
    }

    private func handleFailure(_ error: Error) {
        // The SDK's recipient-mismatch payload names both Orchard addresses;
        // its failure record keeps the case name without them.
        let logged = Self.isRecipientMismatch(error)
            ? AssetLockFailureRecord.describe(error).logDescription
            : String(describing: error)
        Self.logger.error("🛡️ SHIELD-TX :: failure \(logged, privacy: .public)")
        lastFailure = error
        phase = .failed(Self.failureMessage(for: error))
    }

    /// Whether `error` refused a resume's recipient: the app's own check or
    /// the SDK's error 61, bare or inside `transferFailed`.
    static func isRecipientMismatch(_ error: Error) -> Bool {
        switch AssetLockInputLimit.innermost(error) {
        case PlatformWalletError.assetLockRecipientMismatch, CoordinatorError.resumeRecipientMismatch:
            return true
        default:
            return false
        }
    }

    /// The text a `.failed` phase shows for `error`. The SDK's own text for a
    /// recipient mismatch names both Orchard addresses, so the app's message
    /// replaces it wherever it surfaces.
    static func failureMessage(for error: Error) -> String {
        if AssetLockInputLimit.isTooManyInputs(error) {
            return AssetLockInputLimit.message
        }
        if isRecipientMismatch(error) {
            return CoordinatorError.resumeRecipientMismatch.localizedDescription
        }
        if let local = error as? LocalizedError, let description = local.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    /// Map a shielded-spend FFI error to the right terminal phase. The SDK
    /// throws `PlatformWalletError.shieldedSpendUnconfirmed` when the broadcast
    /// was accepted by relay but its result couldn't be confirmed — the host
    /// must NOT re-submit (a retry risks a double-spend / wasted fee). Surface
    /// that as the distinct, non-retryable `.submittedUnconfirmed` and kick a
    /// shielded sync so the effect lands; everything else is a normal failure.
    private func handleSpendError(_ error: Error, manager: PlatformWalletManager) {
        if case PlatformWalletError.shieldedSpendUnconfirmed = error {
            Self.logger.info("🛡️ SHIELD-TX :: broadcast unconfirmed — awaiting sync, retry suppressed")
            phase = .submittedUnconfirmed
            scheduleShieldedResync(manager: manager)
        } else {
            handlePlatformSpendError(error)
        }
    }

    /// An ambiguous broadcast cannot prove the dispatch did not execute.
    /// Keep the submitted state so this sheet never offers a fresh payment.
    private func handlePlatformSpendError(_ error: Error) {
        switch error {
        case SDKError.stateTransitionResultUnconfirmed, PlatformWalletError.transactionBroadcastUnconfirmed,
             PlatformWalletError.shieldedSpendUnconfirmed:
            phase = .submittedUnconfirmed
            schedulePlatformResync()
            if let manager = SwiftDashSDKHost.shared.manager {
                scheduleShieldedResync(manager: manager)
            }
        default:
            handleFailure(CoordinatorError.transferFailed(error))
        }
    }

    /// Fire-and-forget shielded readback refresh after a successful transfer.
    /// Detached from the transfer flow so a slow/blocked sync can't hold the
    /// sheet on a non-dismissible phase after the transfer already landed.
    /// Captures only `manager` (a long-lived singleton) — no retain on the
    /// coordinator past the sheet's lifetime.
    private func scheduleShieldedResync(manager: PlatformWalletManager) {
        PlatformAddressSyncCoordinator.shared
            .refreshShieldedBalanceAfterSpend(using: manager)
    }

    /// Kick the Platform-address (BLAST) sync after a transfer that changes the
    /// DIP-17 Platform balance — `performShield` debits it, `performUnshield`
    /// credits it. `scheduleShieldedResync` only refreshes the shielded side, so
    /// without this the "Platform Payment" balance stays stale until the next
    /// periodic BLAST pass. A few spaced kicks cover the brief indexing lag
    /// before the credit is visible past the BLAST watermark (`syncNow()` no-ops
    /// while a pass is already running, so a single immediate call can miss it).
    /// `performPlatformSend` relies on the same kick after a Platform send.
    private func schedulePlatformResync() {
        Task {
            var previousDelaySeconds: UInt64 = 0
            for delaySeconds in [UInt64(0), 4, 12] {
                let intervalSeconds = delaySeconds - previousDelaySeconds
                if intervalSeconds > 0 {
                    try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                }
                await PlatformAddressSyncCoordinator.shared.syncNow()
                previousDelaySeconds = delaySeconds
            }
        }
    }

    // MARK: - Asset-lock polling

    /// Mirror `DWIdentityRegistrationCoordinator.startAssetLockPolling` —
    /// 0.5 s cadence, lifetime-bounded by the in-flight transfer. Reads the
    /// row of the lock `capture` holds; until the SDK reports the built lock,
    /// and while its row is not persisted yet, a tick does nothing.
    private func startAssetLockPolling(modelContainer: ModelContainer, capture: NewAssetLockCapture) {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.assetLockPollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.pollAssetLockStatus(modelContainer: modelContainer, capture: capture)
            }
        }
    }

    private func stopAssetLockPolling() {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = nil
    }

    private func pollAssetLockStatus(modelContainer: ModelContainer, capture: NewAssetLockCapture) {
        // Only meaningful while the asset-lock route is in-flight.
        switch phase {
        case .locking, .proving, .broadcasting:
            break
        default:
            return
        }
        guard let key = capture.withLock({ $0 }) else { return }
        do {
            guard let row = try AssetLockRecoveryService.persistedLock(
                txidWire: key.txidWire, vout: key.vout, in: modelContainer.mainContext)
            else { return }
            advancePhaseForAssetLockStatus(row.statusRaw)
        } catch {
            Self.logger.warning("🛡️ SHIELD-TX :: asset-lock poll failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Map `PersistentAssetLock.statusRaw` to the next phase. Monotonic —
    /// only advances forward (e.g. a late-arriving `Broadcast` after we
    /// already saw `InstantSendLocked` is ignored). The SDK call's return
    /// drives the final `.success` transition, not status 4.
    private func advancePhaseForAssetLockStatus(_ status: Int) {
        switch status {
        case 0, 1: // Built, Broadcast
            // Already at .locking — nothing to do.
            break
        case 2, 3: // InstantSendLocked, ChainLocked
            if phase == .locking {
                phase = .proving
            }
        case 4, 6: // Consumed / DrainCompleted — the ST has landed, FFI is almost back.
            if phase == .locking || phase == .proving {
                phase = .broadcasting
            }
        default:
            break
        }
    }
}

/// The outpoint a fresh-build funding call reports for its new asset lock.
/// Written once on the FFI worker thread, read on the main actor.
typealias NewAssetLockCapture = OSAllocatedUnfairLock<ShieldedAssetLocksInFlight.OutPoint?>

/// Holds a completed Max drain's claim in `ShieldedAssetLocksInFlight` until
/// `ShieldedTxLookup` shows the drain's lock (every entry carrying its
/// operation id) finished — `AssetLockStatus.isComplete` — or the timeout
/// passes; see
/// `ShieldedTransferCoordinator.releaseDrainClaim`. A lock missing from the
/// snapshot counts as pending. Keeps itself alive
/// through its subscription and timer until it releases.
@MainActor
final class DrainClaimSettler {
    private let operation: UUID
    private let timeout: TimeInterval
    private let lookup: ShieldedTxLookup
    private let registry: ShieldedAssetLocksInFlight
    private var subscription: AnyCancellable?
    private var retainedSelf: DrainClaimSettler?

    init(
        operation: UUID,
        timeout: TimeInterval,
        lookup: ShieldedTxLookup = .shared,
        registry: ShieldedAssetLocksInFlight = .shared
    ) {
        self.operation = operation
        self.timeout = timeout
        self.lookup = lookup
        self.registry = registry
    }

    func start() {
        retainedSelf = self
        // Subscribed before the first read, so a change in between is seen.
        subscription = NotificationCenter.default
            .publisher(for: .shieldedTxLookupDidChange, object: lookup)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.releaseIfSettled() }
            }
        releaseIfSettled()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            MainActor.assumeIsolated { self?.release() }
        }
    }

    private func releaseIfSettled() {
        // Every row carrying the drain's id must be finished (consumed, or
        // recorded as a completed drain). RecoveredFromChain is not final for
        // a drain and still offers Retry, so it keeps the claim.
        let rows = lookup.allEntries().filter { $0.info.drainOperation == operation }
        guard !rows.isEmpty,
              rows.allSatisfy({ AssetLockStatus(rawValue: $0.info.statusRaw)?.isComplete == true })
        else { return }
        release()
    }

    private func release() {
        guard retainedSelf != nil else { return }
        subscription?.cancel()
        subscription = nil
        registry.releaseDrain(operation)
        retainedSelf = nil
    }
}

/// The Platform address calls of the Core → Platform route
/// (`ShieldedTransferCoordinator.performFundPlatform`,
/// `resumeFundPlatform`).
@MainActor
protocol CoreToPlatformFunding: AnyObject {
    func fundFromCore(
        recipientAmountDuffs: UInt64, lockValueDuffs: UInt64, onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws
    func fundExternalFromCore(
        destination: String, recipientAmountDuffs: UInt64, lockValueDuffs: UInt64,
        onAssetLockBuilt: AssetLockBuiltHandler?
    ) async throws
    func checkFundFromCoreResumable(outPointTxid: Data, outPointVout: UInt32) throws
    func resumeFundFromCore(outPointTxid: Data, outPointVout: UInt32, recipientAmountDuffs: UInt64) async throws
}

extension PlatformAddressSyncCoordinator: CoreToPlatformFunding {}

/// The PIN/biometric gate a transfer awaits before it moves funds.
protocol TransferAuthorizing {
    @MainActor
    func authorize() async throws
}

extension DWIdentityAuthorizer: TransferAuthorizing {}
