import Combine
import Foundation
import SwiftDashSDK

/// Core → Shielded Max: one selection's status lookup, estimate and recovery
/// decisions, shared by the internal transfer form and the Send screen.
///
/// The owning view model keeps everything that is its own — the amount text,
/// the other routes' Max — and hands this object three things through
/// `Dependencies`: how to word "nothing to move", how to apply an estimate to
/// the amount field, and what to do when the wallet or network changed under
/// an active selection. Nothing here reads a balance, a rate or the screen.
///
/// Order of operations is the contract (`scripts/core_drain_recovery_harness.py`
/// compiles this file against stubs and checks it): the durable marker's UUID
/// is read and retained BEFORE any status call can suspend and clear it, status
/// is read before a quote is requested, a pending operation blocks a new quote,
/// and a resume's result is dropped unless the same selection, context and
/// operation are still current.
@MainActor
final class CoreShieldedDrainMaxController: ObservableObject {

    struct Dependencies {
        /// Why Max found nothing to move when the drain preview reports
        /// insufficient funds — the balance-aware explanation is the owner's.
        let insufficientFundsMessage: () -> String
        /// Apply an estimate (whole duffs) to the amount field; `nil` clears
        /// the field. Called with the owner's "applying Max" guard expected.
        let applyEstimate: (UInt64?) -> Void
        /// The wallet or network changed under an active selection: the owner
        /// drops its whole Max selection (which clears this object too).
        let onContextChanged: () -> Void
        /// Said once a completed operation has been verified for this owner.
        let completionMessage: () -> String
    }

    /// Max is the current intent on this route.
    @Published private(set) var isActive = false
    @Published private(set) var isLoading = false
    @Published private(set) var confirmation: CoreShieldedDrainConfirmation?
    @Published private(set) var isPending = false
    @Published private(set) var isCompleted = false
    /// Why Max could not produce an amount, is still resolving one, or has
    /// an estimate to explain. Estimates are shown separately from errors.
    @Published private(set) var notice: String?
    private(set) var hasOutpoint = false
    private(set) var operation: CoreShieldedDrainOperation?
    private(set) var context: CoreShieldedDrainContext?
    /// The task behind the current refresh, awaited by tests.
    private(set) var task: Task<Void, Never>?
    private var generation = UUID()
    // Selection lifetime survives balance-only refreshes, unlike preview tasks.
    private var selection = UUID()
    // The selection whose resume is still running. Its lock reads as pending
    // until the resume returns, so a refresh meanwhile would offer Resume again.
    private var resumeSelection: UUID?

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    deinit {
        task?.cancel()
    }

    /// Where a pending operation pays. Read from the durable marker, never
    /// from the screen: a resume must pay the recipient chosen when it started.
    var pendingRecipient: CoreShieldedDrainRecipient? {
        isPending ? operation?.recipient : nil
    }

    var completionNotice: String? {
        isCompleted ? dependencies.completionMessage() : nil
    }

    var estimateNotice: String? {
        isActive && confirmation != nil ? notice : nil
    }

    var actionTitle: String? {
        guard isActive, !isLoading else { return nil }
        if isCompleted { return NSLocalizedString("New transfer", comment: "Start a separate transfer") }
        if isPending {
            return hasOutpoint
                ? NSLocalizedString("Resume transfer", comment: "Resume the same asset lock")
                : NSLocalizedString("Check status", comment: "Read-only drain lookup")
        }
        return confirmation == nil
            ? NSLocalizedString("Try again", comment: "Retry drain preview") : nil
    }

    /// Max was tapped on a Core → Shielded route. The owner has already
    /// dropped its previous Max selection.
    func select() {
        isActive = true
        refresh()
    }

    @discardableResult
    func performAction() -> Task<Void, Never>? {
        guard !isLoading else { return nil }
        if isPending, hasOutpoint, let context {
            isLoading = true
            // The shared runner owns execution even if this form goes away.
            let selection = selection
            let operation = operation
            resumeSelection = selection
            return Task { [weak self] in
                let outcome = await InternalTransferRunner.shared.resumeCoreDrain(
                    context: context, operation: operation)
                guard let self else { return }
                if self.resumeSelection == selection { self.resumeSelection = nil }
                // Leaving or reselecting Max reset the form; that selection
                // owns its state now.
                guard self.isActive,
                      selection == self.selection else { return }
                guard self.context == context,
                      self.operation == operation,
                      (try? CoreShieldedDrainService.currentContext()) == context else {
                    // Same selection, but its wallet, network or operation no
                    // longer matches: drop this result, release the gate and
                    // re-derive the form from the current context.
                    self.isLoading = false
                    self.refresh()
                    return
                }
                if outcome?.drainVerdict == .completed {
                    self.showCompletion()
                } else {
                    self.refresh()
                }
            }
        } else {
            if isCompleted {
                selection = UUID()
                isCompleted = false
                operation = nil
            }
            refresh()
            return nil
        }
    }

    private func showCompletion() {
        // Terminal evidence supersedes any still-running balance preview.
        task?.cancel()
        generation = UUID()
        isCompleted = true
        isPending = false
        hasOutpoint = false
        isLoading = false
        confirmation = nil
        notice = nil
    }

    func refresh() {
        // While this selection's resume runs the form stays busy; the resume
        // refreshes itself when it returns.
        guard isActive, !isCompleted,
              resumeSelection != selection else { return }
        task?.cancel()
        let generation = UUID()
        self.generation = generation
        isLoading = true
        confirmation = nil
        notice = NSLocalizedString("Checking available funds and fees…", comment: "Core drain preview")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let context = try CoreShieldedDrainService.currentContext()
                if let previous = self.context, previous != context {
                    self.dependencies.onContextChanged()
                    self.notice = CoreShieldedDrainService.ServiceError.contextChanged.localizedDescription
                    return
                }
                self.context = context
                let service = CoreShieldedDrainService()
                // Retain the UUID before status can clear its marker and
                // suspend. An overlapping balance refresh must query this same
                // operation even when it cancels the first status task.
                if self.operation == nil {
                    self.operation = try service.store.load(context)
                }
                let outcome: WalletDrainOutcome?
                if let operation = self.operation {
                    outcome = try await service.status(for: operation)
                } else {
                    outcome = nil
                }
                guard !Task.isCancelled, generation == self.generation else { return }
                switch outcome?.drainVerdict {
                case .completed:
                    self.showCompletion()
                    return
                case .pending(let hasOutpoint):
                    self.isPending = true
                    self.hasOutpoint = hasOutpoint
                    self.notice = NSLocalizedString(
                        "A previous Max transfer is still pending. Check its status or resume it before starting another. Resume pays the address it was started with.",
                        comment: "Core drain recovery")
                    self.isLoading = false
                    return
                case .notSent:
                    // The SDK never dispatched this id and `status` removed its
                    // marker: forget it, so the next refresh reads whatever
                    // marker a later operation may have written.
                    self.operation = nil
                    self.isPending = false
                    self.hasOutpoint = false
                case nil:
                    self.isPending = false
                    self.hasOutpoint = false
                }
                let manager = try service.manager(for: context)
                let quote = try await manager.shieldedWalletDrainPreview(walletId: context.walletId)
                guard !Task.isCancelled, generation == self.generation else { return }
                _ = try service.manager(for: context)
                self.isLoading = false
                let estimate = Self.estimate(
                    from: quote, insufficientFundsMessage: self.dependencies.insufficientFundsMessage)
                self.notice = estimate.notice
                guard estimate.isConfirmable else { return }
                self.confirmation = CoreShieldedDrainConfirmation(
                    context: context, candidateBalanceDuffs: quote.candidateBalanceDuffs,
                    estimatedRecipientCredits: quote.estimatedRecipientCredits,
                    estimatedL1FeeDuffs: quote.estimatedL1FeeDuffs, poolFeeCredits: quote.poolFeeCredits)
                self.dependencies.applyEstimate(estimate.amountDuffs)
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                self.isLoading = false
                self.notice = error.localizedDescription
            }
        }
    }

    /// Drop the selection. Called from the owner's whole-Max reset, so a
    /// context-changed notice set right after survives it.
    func clear() {
        task?.cancel()
        task = nil
        generation = UUID()
        selection = UUID()
        isActive = false
        isLoading = false
        confirmation = nil
        isPending = false
        isCompleted = false
        operation = nil
        hasOutpoint = false
        context = nil
        notice = nil
    }

    // MARK: - Estimate

    /// What one drain preview says to the user and puts in the amount field.
    struct Estimate: Equatable {
        let notice: String
        /// Whole duffs for the amount field; `nil` clears it.
        let amountDuffs: UInt64?
        /// Whether the preview is carried into a confirmation. Insufficient
        /// funds carries nothing to confirm.
        let isConfirmable: Bool
    }

    nonisolated static func estimate(
        from quote: WalletDrainPreview,
        insufficientFundsMessage: () -> String
    ) -> Estimate {
        let amountDuffs: UInt64?
        if let credits = quote.estimatedRecipientCredits, credits >= 1000 {
            amountDuffs = credits / 1000
        } else {
            amountDuffs = nil
        }
        switch quote.status {
        case .insufficientFunds:
            return Estimate(notice: insufficientFundsMessage(), amountDuffs: nil, isConfirmable: false)
        case .ready:
            return Estimate(
                notice: NSLocalizedString(
                    "Max moves all eligible funds available at confirmation. The displayed amount and fees are estimates.",
                    comment: "Core drain estimate"),
                amountDuffs: amountDuffs, isConfirmable: true)
        case .inputLimitMayBeExceeded:
            return Estimate(
                notice: NSLocalizedString(
                    "This balance is made of too many separate payments to move with Max in one transfer. Enter a smaller amount instead.",
                    comment: "Core drain input limit preview"),
                amountDuffs: amountDuffs, isConfirmable: true)
        }
    }
}
