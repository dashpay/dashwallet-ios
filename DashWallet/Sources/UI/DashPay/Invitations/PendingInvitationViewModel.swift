//
//  PendingInvitationViewModel.swift
//  DashWallet
//
//  Drives the Home "accept invitation" card: waits for the chain to sync,
//  checks the stored invitation against the network, and hands definitive
//  verdicts to Home to present — each one ends the invitation.
//

import Combine
import Foundation
import UIKit

@MainActor
final class PendingInvitationViewModel: ObservableObject {

    /// One per app, not one per Home view: every instance validates the same
    /// stored invitation, so several would race each other over the network
    /// and the verdict could land on a Home that is no longer on screen.
    /// (`SyncingActivityMonitor` holds its observers strongly, so a per-view
    /// instance would also never be released.)
    static let shared = PendingInvitationViewModel()

    enum CardState: Equatable {
        /// The chain is still catching up; nothing can be checked yet.
        case syncing
        case verifying
        /// The network could not answer; the user can retry.
        case undetermined
        /// A ChainLock-only invitation still waiting for its ChainLock.
        case awaitingChainLock
        case valid(tier: InvitationTier, amountDuffs: UInt64)
    }

    @Published private(set) var invitation: PendingInvitation?
    @Published private(set) var cardState: CardState = .syncing

    /// A verdict that ended the invitation, for Home to present; the store
    /// is already cleared by the time it arrives. Emitted when it happens,
    /// and also kept in `undeliveredOutcome` until a visible Home has shown
    /// it — the check can finish while the user is on another tab.
    let definitiveOutcomes = PassthroughSubject<InvitationValidation, Never>()
    private(set) var undeliveredOutcome: InvitationValidation?

    /// Android treats a check older than a minute as stale
    /// (`InvitationLinkData.expired`); Create re-checks past that.
    static let validationLifetime: TimeInterval = 60

    private let store: PendingInvitationStore
    /// Whether a scope is both selected and bound to the SDK host.
    private let isActive: @MainActor (InvitationScope) -> Bool
    /// The last verdict and the invitation (scope + link) it is about.
    private var lastVerdict: (validation: InvitationValidation, at: Date, invitation: PendingInvitation)?
    private var validationTask: Task<InvitationValidation?, Never>?
    /// The invitation (scope + link) `validationTask` is checking, and the
    /// check's identity — a finishing check clears only its own state.
    private var validationFor: PendingInvitation?
    private var validationToken: UUID?
    /// One delayed re-check while the wallet is not ready to answer, instead
    /// of spinning on an unchanged invitation.
    private var delayedRetry: Task<Void, Never>?
    static let notReadyRetryDelay: UInt64 = 5_000_000_000
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    init(store: PendingInvitationStore = .shared,
         isActive: @escaping @MainActor (InvitationScope) -> Bool = { InvitationScope.isActiveAndBound($0) }) {
        self.store = store
        self.isActive = isActive
        store.$pending
            .removeDuplicates()
            .sink { [weak self] pending in
                guard let self else { return }
                self.invitation = pending
                if pending != self.lastVerdict?.invitation {
                    self.lastVerdict = nil
                }
                self.refreshCardState()
                self.validateIfPossible()
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        for name in [Notification.Name("DWAppDidUnlockNotification"),
                     UIApplication.didBecomeActiveNotification,
                     SwiftDashSDKWalletState.activeWalletDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.store.reload()
                    self?.validateIfPossible()
                }
            })
        }
        SyncingActivityMonitor.shared.add(observer: self)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Actions

    /// Forget the invitation locally; nothing goes to the network. Opening
    /// the link again brings it back.
    func hide() {
        guard let invitation, isActive(invitation.scope) else { return }
        validationTask?.cancel()
        store.remove(invitation, reason: .hidden)
    }

    func retry() {
        lastVerdict = nil
        validateIfPossible()
    }

    /// Re-checks a stale verdict first, so a voucher spent in the meantime is
    /// caught before the PIN. Calls `proceed` with the invitation and its
    /// tier only when it is still valid.
    func create(proceed: @escaping (PendingInvitation, InvitationTier) -> Void) {
        // The claim spends the voucher from whatever wallet is active, so the
        // invitation must be that wallet's own.
        guard let invitation, isActive(invitation.scope) else { return }
        if let lastVerdict, lastVerdict.invitation == invitation,
           Date().timeIntervalSince(lastVerdict.at) < Self.validationLifetime,
           let tier = lastVerdict.validation.tier {
            proceed(invitation, tier)
            return
        }
        lastVerdict = nil
        Task {
            guard let verdict = await self.runValidation(),
                  let tier = verdict.tier,
                  self.invitation == invitation,
                  self.isActive(invitation.scope) else { return }
            proceed(invitation, tier)
        }
    }

    /// Home showed the outcome; it is no longer waiting for a screen.
    func acknowledgeOutcome(_ outcome: InvitationValidation) {
        if undeliveredOutcome == outcome {
            undeliveredOutcome = nil
        }
    }

    // MARK: - Validation

    private var canValidate: Bool {
        invitation != nil
            && SyncingActivityMonitor.shared.state == .syncDone
            && !WalletLifecycleOverlayPresenter.shared.lockScreenVisible
            && UIApplication.shared.applicationState == .active
    }

    func validateIfPossible() {
        guard canValidate else {
            refreshCardState()
            return
        }
        if let lastVerdict, Date().timeIntervalSince(lastVerdict.at) < Self.validationLifetime {
            return
        }
        Task { _ = await runValidation() }
    }

    @discardableResult
    private func runValidation() async -> InvitationValidation? {
        if let validationTask, validationFor == invitation {
            return await validationTask.value
        }
        // A check still running for an invitation that was hidden, replaced,
        // or belongs to a scope the user left: let it finish (its result is
        // discarded), then check this one.
        if let stale = validationTask {
            _ = await stale.value
        }
        guard let invitation, canValidate else {
            refreshCardState()
            return nil
        }
        if let validationTask, validationFor == invitation {
            return await validationTask.value
        }
        cardState = .verifying
        let token = UUID()
        let task = Task { await InvitationValidator.validate(invitation) }
        validationTask = task
        validationFor = invitation
        validationToken = token
        let verdict = await task.value
        if validationToken == token {
            validationTask = nil
            validationFor = nil
            validationToken = nil
        }

        // The invitation may have been hidden, replaced or left behind by a
        // wallet switch while the check ran; the one now shown gets its own
        // check.
        guard let verdict, self.invitation == invitation else {
            refreshCardState()
            if let current = self.invitation, current != invitation {
                // A replacement is shown now: it gets its own check.
                validateIfPossible()
            } else if self.invitation != nil {
                // Same invitation, but the wallet could not answer yet (not
                // hydrated, or mid-switch). Sync, unlock, foreground and
                // wallet-change events retry too; this is the backstop.
                scheduleDelayedRetry()
            }
            return nil
        }
        lastVerdict = (verdict, Date(), invitation)
        if verdict.isDefinitive {
            if verdict.clearsEverywhere, let uri = invitation.normalizedURI {
                store.removeEverywhere(normalizedURI: uri, reason: .definitiveOutcome)
            } else {
                store.remove(invitation, reason: .definitiveOutcome)
            }
            undeliveredOutcome = verdict
            definitiveOutcomes.send(verdict)
        }
        refreshCardState()
        return verdict
    }

    private func scheduleDelayedRetry() {
        guard delayedRetry == nil else { return }
        delayedRetry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.notReadyRetryDelay)
            guard let self, !Task.isCancelled else { return }
            self.delayedRetry = nil
            self.validateIfPossible()
        }
    }

    private func refreshCardState() {
        guard invitation != nil else { return }
        if validationTask != nil {
            cardState = .verifying
            return
        }
        switch lastVerdict?.validation {
        case .valid(let tier, let amount, _)?:
            cardState = .valid(tier: tier, amountDuffs: amount)
        case .undetermined?:
            cardState = .undetermined
        case .awaitingChainLock?:
            cardState = .awaitingChainLock
        default:
            cardState = SyncingActivityMonitor.shared.state == .syncDone ? .verifying : .syncing
        }
    }
}

extension PendingInvitationViewModel: SyncingActivityMonitorObserver {
    nonisolated func syncingActivityMonitorProgressDidChange(_ progress: Double) {}

    nonisolated func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State,
                                                          state: SyncingActivityMonitor.State) {
        Task { @MainActor [weak self] in
            self?.validateIfPossible()
        }
    }
}
