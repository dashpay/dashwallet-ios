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
    private var lastVerdict: (validation: InvitationValidation, at: Date, link: String)?
    private var validationTask: Task<InvitationValidation?, Never>?
    /// The link `validationTask` is checking, and the check's identity — a
    /// finishing check clears only its own state, never a newer one's.
    private var validationLink: String?
    private var validationToken: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    init(store: PendingInvitationStore = .shared) {
        self.store = store
        store.$pending
            .removeDuplicates()
            .sink { [weak self] pending in
                guard let self else { return }
                self.invitation = pending
                if pending?.rawLink != self.lastVerdict?.link {
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
        validationTask?.cancel()
        store.clear(reason: .hidden)
    }

    func retry() {
        lastVerdict = nil
        validateIfPossible()
    }

    /// Re-checks a stale verdict first, so a voucher spent in the meantime is
    /// caught before the PIN. Calls `proceed` with the invitation and its
    /// tier only when it is still valid.
    func create(proceed: @escaping (PendingInvitation, InvitationTier) -> Void) {
        guard let invitation else { return }
        if let lastVerdict, lastVerdict.link == invitation.rawLink,
           Date().timeIntervalSince(lastVerdict.at) < Self.validationLifetime,
           let tier = lastVerdict.validation.tier {
            proceed(invitation, tier)
            return
        }
        lastVerdict = nil
        Task {
            guard let verdict = await self.runValidation(),
                  let tier = verdict.tier,
                  let current = self.invitation, current.rawLink == invitation.rawLink else { return }
            proceed(current, tier)
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
        if let validationTask, validationLink == invitation?.rawLink {
            return await validationTask.value
        }
        // A check still running for an invitation that was hidden or
        // replaced: let it finish (its result is discarded), then check this
        // one.
        if let stale = validationTask {
            _ = await stale.value
        }
        guard let invitation, canValidate else {
            refreshCardState()
            return nil
        }
        if let validationTask, validationLink == invitation.rawLink {
            return await validationTask.value
        }
        cardState = .verifying
        let token = UUID()
        let task = Task { await InvitationValidator.validate(invitation) }
        validationTask = task
        validationLink = invitation.rawLink
        validationToken = token
        let verdict = await task.value
        if validationToken == token {
            validationTask = nil
            validationLink = nil
            validationToken = nil
        }

        // The invitation may have been hidden or replaced while the check ran;
        // a replacement gets its own check.
        guard let verdict, self.invitation?.rawLink == invitation.rawLink else {
            refreshCardState()
            if self.invitation != nil, self.invitation?.rawLink != invitation.rawLink {
                validateIfPossible()
            }
            return nil
        }
        lastVerdict = (verdict, Date(), invitation.rawLink)
        if verdict.isDefinitive {
            if let uri = invitation.normalizedURI {
                store.clear(normalizedURI: uri, reason: .definitiveOutcome)
            } else {
                store.clear(reason: .definitiveOutcome)
            }
            undeliveredOutcome = verdict
            definitiveOutcomes.send(verdict)
        }
        refreshCardState()
        return verdict
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
