//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import SwiftDashSDK

struct CreateUsernameUIState {
    var lengthRule: UsernameValidationRuleResult
    var allowedCharactersRule: UsernameValidationRuleResult
    var costRule: UsernameValidationRuleResult
    var usernameBlockedRule: UsernameValidationRuleResult
    var requiredDash: UInt64
    var canContinue: Bool
    
    init(lengthRule: UsernameValidationRuleResult, allowedCharactersRule: UsernameValidationRuleResult, costRule: UsernameValidationRuleResult, usernameBlockedRule: UsernameValidationRuleResult, requiredDash: UInt64, canContinue: Bool) {
        self.lengthRule = lengthRule
        self.allowedCharactersRule = allowedCharactersRule
        self.costRule = costRule
        self.usernameBlockedRule = usernameBlockedRule
        self.requiredDash = requiredDash
        self.canContinue = canContinue
    }
    
    init() {
        self.lengthRule = .empty
        self.allowedCharactersRule = .empty
        self.costRule = .hidden
        self.usernameBlockedRule = .hidden
        self.requiredDash = DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        self.canContinue = false
    }
}

@MainActor
class CreateUsernameViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let dao: UsernameRequestsDAO = UsernameRequestsDAOImpl.shared
    private let prefs = UsernamePrefs.shared
    private let illegalChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").inverted
    private var submittedRegistrationUsername: String?
    private var didNotifyRegistrationStarted = false
    private var onRegistrationStarted: (@MainActor () -> Void)?
    /// In-flight DPNS availability check. Cancelled and replaced on
    /// every revalidation so only the newest input hits the network.
    private var availabilityCheckTask: Task<Void, Never>?
    /// One-shot revalidation alarm for a `.maturing` shielded snapshot.
    /// The shared readiness service arms its own flip timer only for
    /// the STANDARD denomination; a contested name's (0.3 DASH) ready
    /// moment can be later, so the form re-validates itself at the
    /// snapshot's own `readyAt`. Re-armed on every validation.
    private var shieldedMaturityRevalidationTask: Task<Void, Never>?
    /// Mirrors the legacy `VALIDATION_DEBOUNCE_DELAY`
    /// (DWCheckExistenceUsernameValidationRule.m).
    private static let availabilityDebounceNanos: UInt64 = 400_000_000
    static let shared = CreateUsernameViewModel()
    
    var shouldRequestPayment: Bool {
        get { !prefs.alreadyPaid }
        set { prefs.alreadyPaid = !newValue }
    }
    
    @Published var uiState = CreateUsernameUIState()
    @Published var username: String = ""
    @Published private(set) var currentUsernameRequest: UsernameRequest? = nil
    @Published private(set) var hasMinimumRequiredBalance = false
    @Published private(set) var hasRecommendedBalance = false
    @Published private(set) var balance: String = ""

    /// `true` when the trimmed input is a contested-eligible DPNS
    /// label (≤19 chars + only `[a-zA-Z0-9-]`) AND otherwise passes
    /// the local validators (length + chars + hyphen-placement).
    /// Drives the orange warning box and the Continue-button
    /// confirmation alert in `CreateUsernameView`. Computed
    /// client-side via the SDK's deterministic FFI helper
    /// `dash_sdk_dpns_is_contested_username` — no network call.
    @Published private(set) var isContestedCandidate: Bool = false

    /// Per-funding-source eligibility flags. `hasMinimumRequiredBalance`
    /// (above) is kept as the legacy OR-of-both flag for any existing
    /// consumer; the new picker UI reads these to decide whether to
    /// show both options or auto-pin to the single viable source.
    @Published private(set) var hasMinimumRequiredCoreBalance = false
    @Published private(set) var hasMinimumRequiredPlatformBalance = false
    /// Formatted Platform Payment balance (in DASH, derived from the
    /// duff-equivalent of `SwiftDashSDKWalletState.platformPaymentCredits`).
    @Published private(set) var platformPaymentBalance: String = ""

    /// Shielded-funding readiness for the CURRENT typed name (contested
    /// names need the 0.3 DASH exit denomination instead of 0.1).
    /// Recomputed by `validateUsername` and on every readiness publish.
    /// nil while the SDK host has no hydrated wallet.
    @Published private(set) var shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot? = nil
    /// Formatted unspent shielded balance in DASH, for the picker label.
    @Published private(set) var shieldedBalance: String = ""

    /// Shielded funding is offerable right now: funded + matured + pool
    /// minimum cleared (or pool count unknown — Drive enforces the real
    /// rule at submit).
    var hasReadyShieldedFunding: Bool {
        shieldedReadiness?.state == .ready
    }

    /// Non-nil puts the form in invitation-claim mode (DIP-13): the
    /// registration is funded by the voucher in this normalized link,
    /// so the balance-based cost rule and the funding-source picker do
    /// not apply, and submit routes through
    /// `DWIdentityRegistrationCoordinator.startClaimInvitation`.
    @Published private(set) var invitationURI: String? = nil
    /// The inviter's DPNS username (`du`) when the invitation carries
    /// one — drives the post-claim "send a contact request?" offer.
    @Published private(set) var invitationInviterUsername: String? = nil

    var isInvitationMode: Bool { invitationURI != nil }

    /// Enter invitation-claim mode with a normalized invitation URI
    /// (see `DWInvitationLinkNormalizer`). Re-runs validation so the
    /// cost rule reflects the voucher funding.
    func configureInvitationMode(uri: String) {
        invitationURI = uri
        invitationInviterUsername = DWInvitationService.shared.preview(for: uri)?.inviterUsername
        validateUsername(username: username)
    }
    
    var minimumRequiredBalance: String {
        return DWDP_MIN_BALANCE_TO_CREATE_USERNAME.dashAmount.formattedDashAmountWithoutCurrencySymbol
    }
    
    var recommendedBalance: String {
        return DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME.dashAmount.formattedDashAmountWithoutCurrencySymbol
    }
    
    var minimumRequiredBalanceFiat: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: DWDP_MIN_BALANCE_TO_CREATE_USERNAME.dashAmount, to: App.fiatCurrency) {
            fiat = NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing…", comment: "Balance")
        }

        return fiat
    }
    
    init() {
        $username
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.validateUsername(username: text)
            }
            .store(in: &cancellableBag)

        DWIdentityRegistrationCoordinator.shared.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handleRegistrationPhase(phase)
            }
            .store(in: &cancellableBag)
        
        observeBalance()
    }
    
    /// Terminal outcome of a username-registration attempt, surfaced to
    /// the SwiftUI form so it can keep the screen up through the PIN +
    /// registration and then show the right native alert.
    enum UsernameRegistrationOutcome {
        case success
        case cancelled
        case failure(String)
    }

    /// Kick off SwiftDashSDK identity + DPNS registration and suspend
    /// until the terminal phase. Routes straight to
    /// `DWIdentityRegistrationBridge` (instead of
    /// `DWDashPayModel.createUsername:`) so the awaiting
    /// caller gets a one-shot success / cancel / failure signal to drive
    /// the on-screen popup. The model's `bridgeRegistrationStateChanged:`
    /// observer still mirrors progress to the home banner + writes the
    /// `DWGlobalOptions` success mirror, because it listens on the
    /// bridge's `stateChangedNotification`, not on this call path.
    ///
    /// The funding source is read from
    /// `DWIdentityRegistrationBridge.shared.preferredFundingSource`,
    /// written by `CreateUsernameView` immediately before this call.
    func submitUsernameRequest(onRegistrationStarted: @escaping @MainActor () -> Void = {}) async -> UsernameRegistrationOutcome {
        let submittedUsername = username
        submittedRegistrationUsername = submittedUsername
        didNotifyRegistrationStarted = false
        self.onRegistrationStarted = onRegistrationStarted

        // Invitation-claim mode: same coordinator, but the voucher in
        // the link funds the IdentityCreate, so the call carries the
        // URI and is awaited directly (no Obj-C bridge completion to
        // adapt). Phase-driven `onRegistrationStarted` still fires via
        // `handleRegistrationPhase` — the coordinator publishes the
        // same phases for every funding source.
        if let invitationURI {
            defer {
                submittedRegistrationUsername = nil
                didNotifyRegistrationStarted = false
                self.onRegistrationStarted = nil
            }
            do {
                _ = try await DWIdentityRegistrationCoordinator.shared.startClaimInvitation(
                    username: submittedUsername,
                    invitationURI: invitationURI)
                return .success
            } catch DWIdentityRegistrationCoordinator.CoordinatorError.authCancelled {
                return .cancelled
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<UsernameRegistrationOutcome, Never>) in
            DWIdentityRegistrationBridge.shared.startCreateUsername(submittedUsername) { [weak self] _, error in
                Task { @MainActor in
                    self?.submittedRegistrationUsername = nil
                    self?.didNotifyRegistrationStarted = false
                    self?.onRegistrationStarted = nil

                    guard let error else {
                        continuation.resume(returning: .success)
                        return
                    }
                    // PIN / biometric cancel surfaces as the canonical Cocoa
                    // user-cancel — a silent no-op, not an error popup.
                    if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError {
                        continuation.resume(returning: .cancelled)
                    } else {
                        continuation.resume(returning: .failure(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func handleRegistrationPhase(_ phase: DWIdentityRegistrationController.Phase) {
        guard
            let submittedRegistrationUsername,
            DWIdentityRegistrationCoordinator.shared.currentUsername == submittedRegistrationUsername
        else {
            return
        }

        switch phase {
        case .preparingKeys, .inFlight:
            guard !didNotifyRegistrationStarted else { return }
            didNotifyRegistrationStarted = true
            onRegistrationStarted?()
        case .idle, .completed, .failed:
            break
        }
    }
    
    func fetchUsernameRequestData() {
        if let id = prefs.requestedUsernameId {
            Task {
                currentUsernameRequest = await dao.get(byRequestId: id)
                username = currentUsernameRequest?.username ?? ""
            }
        }
    }
    
    func cancelRequest() {
        if let requestId = prefs.requestedUsernameId {
            Task {
                currentUsernameRequest = nil
                username = ""
                await dao.delete(by: requestId)
                prefs.requestedUsernameId = nil
            }
        }
    }
    
    private func validateUsername(username: String) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)

        // Kill any in-flight availability check — its result belongs to
        // an input the user has already changed (including changed-to-empty).
        availabilityCheckTask?.cancel()

        guard !username.isEmpty else {
            uiState = CreateUsernameUIState()
            isContestedCandidate = false
            // Keep the shielded picker option + balance label live
            // before the user types — evaluated against the standard
            // (uncontested) denomination.
            shieldedReadiness = ShieldedIdentityFundingReadiness.shared
                .evaluate(requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits)
            return
        }

        let lengthValid = username.count >= DW_MIN_USERNAME_LENGTH && username.count <= DW_MAX_USERNAME_LENGTH
        let hasIllegalCharacters = username.rangeOfCharacter(from: illegalChars) != nil
        let startsOrEndsWithHyphen = username.first == "-" || username.last == "-"
        // The FFI helper returns 1 for labels ≤19 chars consisting
        // only of `[a-zA-Z0-9-]` (the masternode-vote threshold from
        // the DPNS contract). We still gate the published flag on
        // the other local validators so the warning doesn't flash
        // for unsubmittable names like "ab" (2 chars — contested-
        // eligible by FFI but length-invalid for the user anyway).
        let isContested = DWContestedNameStatusService.isContestedLabel(username)
        let contestedCandidate = isContested && lengthValid && !hasIllegalCharacters && !startsOrEndsWithHyphen
        isContestedCandidate = contestedCandidate
        let requiredCost = isContested ? DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME : DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        // Any funding source can satisfy the cost rule. Core spends
        // BIP44 UTXOs via `registerIdentityWithFunding`; Platform
        // Payment spends DIP-17 credits via
        // `registerIdentityFromAddresses`; Shielded spends a fixed
        // exit denomination via `shieldedIdentityCreateFromPool` and
        // is viable only when its readiness gates (funding, maturity,
        // pool) all pass. The picker in `CreateUsernameView` lets the
        // user choose among the viable sources; the form is unblocked
        // as soon as any one is.
        let coreBalance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        let platformBalance = SwiftDashSDKWalletState.shared.platformPaymentCreditsAsDuffs
        let hasEnoughCore = coreBalance >= requiredCost
        let hasEnoughPlatform = platformBalance >= requiredCost
        let shieldedRequired = ShieldedIdentityFundingReadiness.requiredCredits(forContestedName: isContested)
        shieldedReadiness = ShieldedIdentityFundingReadiness.shared.evaluate(requiredCredits: shieldedRequired)
        armShieldedMaturityRevalidation()
        // Invitation-claim mode: the voucher pays the registration, so
        // no local balance is required and the cost rule stays hidden.
        // Whether the voucher actually covers the cost is only known at
        // claim time (the amount is not in the link) — the coordinator
        // surfaces an insufficient-voucher failure through the normal
        // error alert.
        let voucherFunded = isInvitationMode
        let hasEnoughBalance = voucherFunded || hasEnoughCore || hasEnoughPlatform || hasReadyShieldedFunding
        let canContinue = lengthValid && !hasIllegalCharacters && !startsOrEndsWithHyphen && hasEnoughBalance

        uiState = CreateUsernameUIState(
            lengthRule: lengthValid ? .valid : .invalid,
            allowedCharactersRule: hasIllegalCharacters || startsOrEndsWithHyphen ? .invalid : .valid,
            costRule: voucherFunded ? .hidden : (hasEnoughBalance ? .valid : .invalid),
            usernameBlockedRule: canContinue ? .loading : .hidden,
            requiredDash: requiredCost,
            canContinue: false
        )

        if canContinue {
            availabilityCheckTask = Task {
                await checkIfBlocked(username: username)
            }
        }
    }

    /// Debounced real DPNS availability check (same coordinator call the
    /// legacy `DWCheckExistenceUsernameValidationRule` path uses). Maps:
    /// available → `.valid`; taken → `.invalidCritical` — including names
    /// in an ACTIVE contest, because `registerDpnsName` creates the domain
    /// document immediately and voting only decides who keeps it (matches
    /// the legacy rule's behavior); our OWN pending contested submission →
    /// `.warning` ("in voting"); RPC failure → `.error` (re-runs on the
    /// next keystroke or balance publish). `canContinue` is true only for
    /// `.valid` — the submit-time `registerDpnsName` failure remains the
    /// second line of defense.
    private func checkIfBlocked(username: String) async {
        // Debounce: sleep throws on cancellation (the user kept typing).
        do { try await Task.sleep(nanoseconds: Self.availabilityDebounceNanos) }
        catch { return }
        guard !Task.isCancelled else { return }

        let result: UsernameValidationRuleResult
        do {
            let available = try await DWIdentityRegistrationCoordinator.shared.dpnsCheckAvailability(username)
            if available {
                result = .valid
            } else if let pending = DWContestedNameStatusService.shared.pendingLabel,
                      pending.caseInsensitiveCompare(username) == .orderedSame {
                // Our own contested submission — reads as taken on-chain
                // while masternode voting is still deciding the owner.
                result = .warning
            } else {
                result = .invalidCritical
            }
        } catch {
            result = .error
        }

        // Drop stale results: the input changed while the RPC was in
        // flight. Compare against the trimmed live value — validateUsername
        // trims before calling us.
        guard !Task.isCancelled,
              self.username.trimmingCharacters(in: .whitespacesAndNewlines) == username
        else { return }

        uiState.usernameBlockedRule = result
        uiState.canContinue = (result == .valid)
    }
    
    private func observeBalance() {
        // Trigger a fresh Platform-credit tally on viewmodel init —
        // the wallet-state's auto-refresh only fires on Core-balance
        // updates, so without this the picker would miss any PP
        // credits that landed before the view opened (e.g. a
        // long-standing wallet with PP credits but no recent Core tx).
        SwiftDashSDKWalletState.shared.refreshPlatformPaymentCredits()
        checkBalance()
        // Source from SwiftDashSDKWalletState. After M6 retired DashSync's
        // SPV, DSWalletBalanceDidChange no longer fires. Function #5 follow-up.
        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.validateUsername(username: self.username)
                self.checkBalance()
            }
            .store(in: &cancellableBag)
        // Mirror the Core-balance subscription so a BLAST-driven PP
        // credit refresh re-runs validation + updates the per-source
        // booleans / formatted strings the picker reads.
        SwiftDashSDKWalletState.shared.$platformPaymentCredits
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.validateUsername(username: self.username)
                self.checkBalance()
            }
            .store(in: &cancellableBag)
        // Shielded readiness changes (a note maturing, a shielded sync
        // pass landing new notes, the pool count arriving) re-run the
        // same validation so the picker's shielded option and the
        // inline readiness hint stay live.
        ShieldedIdentityFundingReadiness.shared.$standardSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.validateUsername(username: self.username)
                self.checkBalance()
            }
            .store(in: &cancellableBag)
    }

    /// Schedule a one-shot revalidation at the current snapshot's
    /// `readyAt` (+1 s of slack) so the `.maturing` hint flips to a
    /// selectable Shielded option without further user input.
    private func armShieldedMaturityRevalidation() {
        shieldedMaturityRevalidationTask?.cancel()
        shieldedMaturityRevalidationTask = nil
        guard case .maturing(let readyAt) = shieldedReadiness?.state else { return }
        let delay = readyAt.timeIntervalSinceNow
        guard delay > 0 else { return }
        shieldedMaturityRevalidationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((delay + 1) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.validateUsername(username: self.username)
            self.checkBalance()
        }
    }

    private func checkBalance() {
        let balance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        let platformDuffs = SwiftDashSDKWalletState.shared.platformPaymentCreditsAsDuffs
        self.balance = balance.dashAmount.formattedDashAmountWithoutCurrencySymbol
        self.platformPaymentBalance = platformDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol
        // Credits → duffs (÷1000) for display; the readiness snapshot
        // keeps the canonical credit-denominated values.
        let shieldedDuffs = (shieldedReadiness?.unspentCredits ?? 0) / 1_000
        self.shieldedBalance = shieldedDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol
        hasMinimumRequiredCoreBalance = balance >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        hasMinimumRequiredPlatformBalance = platformDuffs >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        // `hasMinimumRequiredBalance` stays as the legacy OR view —
        // any pre-PR-5 consumer (banner gate, etc.) keeps seeing
        // "user has enough to register" without caring about source.
        hasMinimumRequiredBalance = hasMinimumRequiredCoreBalance || hasMinimumRequiredPlatformBalance
        hasRecommendedBalance = balance >= DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME
            || platformDuffs >= DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME
    }
}
