//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation

/// One internal transfer, described completely enough to execute without the
/// screen that asked for it.
struct InternalTransferRequest: Equatable {
    enum Kind: Equatable {
        case route(InternalTransferRoute)
        case identityTopUp(IdentityTopUpTransfer)
        case identityWithdrawal(IdentityWithdrawalTransfer)
    }

    let kind: Kind
    let amountDuffsUnsigned: UInt64
    let creditsAmount: UInt64
    /// `.coreToPlatform` only: the L1 asset-lock value — the recipient amount
    /// plus the funding reserve that rides on top of it. Resolved by
    /// `InternalTransferViewModel.coreToPlatformLockValueDuffs` and FROZEN
    /// here at Continue: the coordinator executes this number verbatim and
    /// never recomputes the reserve, so the Total the user confirmed is
    /// exactly the lock that is broadcast. `nil` fails the transfer closed.
    let coreToPlatformLockDuffs: UInt64?
    /// `.platformToCore` only: the preflighted transition fee.
    let withdrawalFeeCredits: UInt64?
    /// `.platformToCore` only: run the AUTO all-addresses withdrawal.
    let isFullPlatformWithdrawal: Bool
    /// Shielded reverse routes only: execute the note-aware Max plan.
    let isFullShieldedSweep: Bool
    /// Frozen with the submitted amount, so a capacity refresh only rewrites
    /// a figure the user derived with Max.
    let platformShieldAmountWasMax: Bool
}

/// Runs an internal transfer and outlives whatever presented it.
///
/// The executors used to be `@StateObject`s on the confirm sheet, which tied a
/// live transfer to that sheet's lifetime: dismissing it deallocated the
/// coordinator and cancelled the task mid-flight. For a Core-funded route that
/// can strand an asset lock that was already committed on chain — the exact
/// case the retry path exists to recover from. Nothing about executing a
/// transfer belongs to a view, so none of it lives in one any more.
///
/// A shared instance rather than an injected one (against the usual
/// preference) because the point is precisely to be reachable after the view
/// that started the work is gone. One transfer at a time: the screen offers no
/// way to start a second while the first is in flight.
@MainActor
final class InternalTransferRunner: ObservableObject {

    static let shared = InternalTransferRunner()

    /// The one lifecycle callers render from, whichever executor is running.
    /// `submittedUnconfirmed` is route-only — no identity transition lands in
    /// that state.
    enum Phase: Equatable {
        case idle
        case inFlight
        case success
        case submittedUnconfirmed
        case failed(String)
    }

    /// A Platform shield whose capacity moved under the submitted amount. Not
    /// a failure to show but an amount to re-derive.
    struct PlatformShieldCapacityChange: Equatable {
        let maxShieldableCredits: UInt64?
        let submittedAmountWasMax: Bool
    }

    /// What `start` settled, for the surface that asked for the transfer.
    enum StartOutcome: Equatable {
        /// Authorized and handed off. The transfer is running.
        case started
        /// Another transfer is still in flight; nothing was started.
        case busy
        /// The user backed out of the PIN prompt, or it failed. Not an error
        /// state — the caller returns to what it was showing.
        case notAuthorized
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var platformShieldCapacityChange: PlatformShieldCapacityChange?
    /// What to tell the user, for whoever is on screen when it happens.
    ///
    /// The confirm sheet closes as soon as the transfer starts, so the
    /// outcome arrives with nothing of the transfer's own left on screen —
    /// this is how it reaches the surface the user actually landed on.
    /// Cleared by that surface once shown.
    @Published var notice: Notice? {
        didSet { noticeRaisedAt = notice == nil ? nil : Date() }
    }

    /// When the current notice was raised.
    ///
    /// The toast lives on `HomeView`, and a notice raised while the user is
    /// elsewhere stays set until something clears it. Without a timestamp the
    /// next appearance of that screen would announce an outcome from an
    /// arbitrary time ago as if it had just happened.
    private(set) var noticeRaisedAt: Date?

    /// The things worth saying, in the order they can happen.
    enum Notice: Equatable {
        case started
        /// A second transfer asked to start while the first is still running.
        /// The runner takes one at a time, and refusing silently would look
        /// like Confirm did nothing.
        case busy
        case succeeded
        /// Accepted by the network but not yet confirmed — a shielded spend
        /// whose receipt has not landed.
        case submitted
        case failed(String)
    }

    private let coordinator = ShieldedTransferCoordinator()
    private let topUpExecutor = IdentityTopUpViewModel()
    private let withdrawExecutor = IdentityWithdrawViewModel()
    private let authorizer = DWIdentityAuthorizer()
    private var cancellables = Set<AnyCancellable>()
    private var request: InternalTransferRequest?
    /// Held across the authorization gate, which is the window `phase` cannot
    /// cover: it is still `.idle` while the PIN prompt is up.
    private var isAwaitingAuthorization = false

    private init() {
        coordinator.$phase
            .sink { [weak self] routePhase in
                self?.apply(routePhase)
            }
            .store(in: &cancellables)
    }

    /// Takes the transfer at the moment the user confirms it, not when the
    /// sheet is built.
    ///
    /// Everything here publishes, and an earlier version armed the runner from
    /// the confirm view model's `init` — which SwiftUI runs inside
    /// `StateObject(wrappedValue:)`, i.e. during a view update. That is the
    /// "Publishing changes from within view updates" warning: three of them,
    /// since `coordinator.reset()` fed the phase sink as well. A tap is not a
    /// view update, so taking the request here removes the whole class of it.
    ///
    /// Authorization is awaited HERE, before anything is handed to an
    /// executor, and that is the whole reason this is `async`: the PIN prompt
    /// has to be answered while the confirm sheet is still up. The executors
    /// each raise the same gate from inside work that outlives that sheet, so
    /// leaving it to them meant the sheet closed first and the user met the
    /// prompt on whatever screen they landed on. `preauthorized` below is what
    /// keeps that inner gate from asking a second time.
    func start(_ request: InternalTransferRequest) async -> StartOutcome {
        guard phase != .inFlight, !isAwaitingAuthorization else {
            notice = .busy
            return .busy
        }

        // Claimed BEFORE the gate, not after. `phase` only becomes `.inFlight`
        // once an executor is running, and the PIN prompt sits in between —
        // three entry points build a transfer screen against this one shared
        // runner, so a second Confirm during that window passed the phase guard
        // and would have started a second transfer behind the first prompt.
        isAwaitingAuthorization = true
        defer { isAwaitingAuthorization = false }

        do {
            try await authorizer.authorize()
        } catch {
            // Both backing out and a failed prompt leave the caller where it
            // was — the prompt itself has already said whatever there was to
            // say, and nothing has been started to report on.
            return .notAuthorized
        }

        // Clear what the previous transfer left, so this one is not read
        // through its outcome.
        self.request = request
        phase = .idle
        platformShieldCapacityChange = nil
        coordinator.reset()

        notice = .started
        run(request)
        return .started
    }

    // No retry here. A Core-funded route that fails after committing its asset
    // lock is recovered by the home screen: the pending transaction row is
    // tappable and opens `ShieldedRecoverySheet`, which resumes that exact
    // outpoint. A second entry point would risk building a second lock.

    // MARK: - Execution

    /// Every executor runs inside `preauthorized`, because `start` has already
    /// held the gate open for this exact transfer. Without it the user would
    /// be asked for the PIN twice: once on the sheet, once again from inside
    /// the coordinator.
    private func run(_ request: InternalTransferRequest) {
        Task {
            await DWIdentityAuthorizer.preauthorized {
                switch request.kind {
                case .route(let route):
                    await runRoute(route, request)
                case .identityTopUp(let topUp):
                    await runTopUp(topUp, request)
                case .identityWithdrawal(let withdrawal):
                    await runWithdrawal(withdrawal, request)
                }
            }
        }
    }

    private func runRoute(_ route: InternalTransferRoute, _ request: InternalTransferRequest) async {
        switch route {
        case .coreToShielded:
            await coordinator.performAssetLock(recipientAmountDuffs: request.amountDuffsUnsigned)
        case .platformToShielded:
            await coordinator.performShield(amountCredits: request.creditsAmount)
        case .shieldedToCore:
            await coordinator.performWithdraw(
                amountCredits: request.creditsAmount,
                sweepAll: request.isFullShieldedSweep)
        case .shieldedToPlatform:
            await coordinator.performUnshield(
                amountCredits: request.creditsAmount,
                sweepAll: request.isFullShieldedSweep)
        case .coreToPlatform:
            // Fee-on-top: the recipient is credited the typed amount and the
            // funding reserve rides on top inside the lock. The frozen lock
            // value goes through as-is — the coordinator fails closed if it is
            // missing or does not exceed the amount.
            await coordinator.performFundPlatform(
                recipientAmountDuffs: request.amountDuffsUnsigned,
                lockValueDuffs: request.coreToPlatformLockDuffs)
        case .platformToCore:
            await coordinator.performPlatformWithdraw(
                amountCredits: request.creditsAmount,
                fullBalance: request.isFullPlatformWithdrawal,
                feeHeadroomCredits: request.withdrawalFeeCredits)
        }
    }

    /// Both identity executors report the same three outcomes, so they reduce
    /// the same way: a result is success, a message is failure, and a bare
    /// nil is neither — the executor declined without anything to say.
    private func runTopUp(_ topUp: IdentityTopUpTransfer, _ request: InternalTransferRequest) async {
        phase = .inFlight
        let newBalance = await topUpExecutor.topUp(
            identityId: topUp.identityId,
            amountDuffs: request.amountDuffsUnsigned,
            source: .init(spending: topUp.source))
        phase = outcome(succeeded: newBalance != nil, message: consume(&topUpExecutor.errorMessage))
        announce(phase)
    }

    private func runWithdrawal(
        _ withdrawal: IdentityWithdrawalTransfer,
        _ request: InternalTransferRequest
    ) async {
        phase = .inFlight
        let succeeded = await withdrawExecutor.withdraw(
            identityId: withdrawal.identityId,
            amountCredits: request.creditsAmount,
            target: withdrawal.target)
        phase = outcome(succeeded: succeeded, message: consume(&withdrawExecutor.errorMessage))
        announce(phase)
    }

    /// Identity transfers reach their terminal phase by returning rather than
    /// through the coordinator's stream, so they say so here. A silent decline
    /// (`.idle`) is not worth a notice.
    private func announce(_ phase: Phase) {
        switch phase {
        case .success: notice = .succeeded
        case .failed(let message): notice = .failed(message)
        case .idle: notice = nil
        case .inFlight, .submittedUnconfirmed: break
        }
    }

    /// A failure with no message is the executor declining without a reason
    /// worth showing — nothing happened, so nothing is reported. The gate is
    /// no longer one of those cases: `start` settles authorization before an
    /// executor is ever reached.
    private func outcome(succeeded: Bool, message: String?) -> Phase {
        if succeeded { return .success }
        guard let message else { return .idle }
        return .failed(message)
    }

    /// Clears the executor's message as it reads it, so a later retry cannot
    /// inherit the previous failure.
    private func consume(_ message: inout String?) -> String? {
        defer { message = nil }
        return message
    }

    // MARK: - Route phase

    private func apply(_ routePhase: ShieldedTransferCoordinator.Phase) {
        // Identity transfers drive `phase` directly; the coordinator is idle
        // then and must not overwrite them.
        guard case .route? = request?.kind else { return }

        switch routePhase {
        case .signing, .locking, .proving, .broadcasting:
            phase = .inFlight
        case .success:
            phase = .success
            notice = .succeeded
        case .submittedUnconfirmed:
            phase = .submittedUnconfirmed
            notice = .submitted
        case .failed(let message):
            phase = .failed(message)
            notice = .failed(message)
            notePlatformShieldCapacityChange()
        default:
            phase = .idle
        }
    }

    /// Reported once — a retry against a stale figure would only fail the same
    /// way.
    private func notePlatformShieldCapacityChange() {
        guard platformShieldCapacityChange == nil,
              let request,
              let error = coordinator.lastFailure as? ShieldedTransferCoordinator.CoordinatorError,
              case .platformShieldCapacityChanged(let maxShieldableCredits) = error
        else { return }

        platformShieldCapacityChange = PlatformShieldCapacityChange(
            maxShieldableCredits: maxShieldableCredits,
            submittedAmountWasMax: request.platformShieldAmountWasMax)
    }
}
