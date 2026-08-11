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
    private let prefs = UsernamePrefs.shared
    /// Stateless facade, instantiated per view model by design (see its
    /// type doc). Used here for `contestPrecheck` — the one vote-state
    /// query that distinguishes a locked name from one mid-vote.
    private let marketplaceService = UsernameMarketplaceService()
    private let illegalChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").inverted
    private var submittedRegistrationUsername: String?
    private var didNotifyRegistrationStarted = false
    private var onRegistrationStarted: (@MainActor () -> Void)?
    /// In-flight DPNS availability check. Cancelled and replaced when
    /// the typed label changes, so only the newest input hits the network.
    private var availabilityCheckTask: Task<Void, Never>?
    /// The trimmed label the current availability-check state belongs to,
    /// whether still in flight or already answered. Revalidations for the
    /// SAME label — balance and readiness publishes fire constantly while
    /// syncing — reuse the existing answer instead of hitting DAPI again.
    /// Cleared on screen appear (`refreshRegistrationRecoveryState`) so
    /// every visit re-verifies once.
    private var availabilityCheckLabel: String?
    /// One-shot revalidation alarm for a `.maturing` shielded snapshot.
    /// The shared readiness service arms its own flip timer only for
    /// the STANDARD denomination; a contested name's (0.25 DASH) ready
    /// moment can be later, so the form re-validates itself at the
    /// snapshot's own `readyAt`. Re-armed on every validation.
    private var shieldedMaturityRevalidationTask: Task<Void, Never>?
    /// One-shot re-check at the active contest's next boundary — the
    /// join-window close, then the vote end. The per-label answer cache
    /// deliberately keeps the verdict stable while the user sits on the
    /// screen; these two moments are exactly when it goes stale, so the
    /// form re-queries then instead of letting a submit fail at broadcast.
    private var contestBoundaryRevalidationTask: Task<Void, Never>?
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

    /// The typed label lost an earlier contest to a masternode LOCK, so nobody
    /// can register it. It still reports as available (no owner holds the
    /// domain document), which is why this needs its own flag: the rule row
    /// would otherwise say "Username taken", and the user would keep retrying
    /// a name that can only fail at broadcast.
    @Published private(set) var isLockedContestedName: Bool = false

    /// Contender count when the typed name is already in an ACTIVE masternode
    /// vote started by someone else. Like a LOCK, a mid-vote label still reads
    /// as available (no domain document exists until the vote resolves), but
    /// submitting it joins the running vote as a contender instead of starting
    /// a fresh one — the warning callout and the Continue confirmation switch
    /// their copy on this. nil when no such contest is known (fresh name, our
    /// own request, or the best-effort query failed).
    @Published private(set) var activeContestContenders: Int?

    /// Deadline of that active vote, when the current-contests listing
    /// reports one. Lets the warning callout say WHEN the vote ends —
    /// and switch to "has ended, finalizing" wording once the deadline
    /// passes — instead of an unverifiable "in progress" claim.
    @Published private(set) var activeContestEndsAt: Date?

    /// Sale price (CREDITS, exactly as listed — the purchase call must
    /// echo the listed price verbatim or the SDK refuses it as changed)
    /// when the typed name is TAKEN but its owner has listed it in the
    /// Username Marketplace. Turns the dead-end "Username taken" into a
    /// pointer to the listing — or a direct buy, below. nil when the
    /// name is not for sale or the best-effort lookup failed.
    @Published private(set) var takenNameSalePriceCredits: UInt64?

    /// App policy ceiling for buying a listed name straight from this
    /// form: at 10 DASH or more the purchase belongs in the Username
    /// Marketplace, where the full listing context (trade history,
    /// owner, fiat price) is visible before committing that much.
    static let directPurchaseMaxDuffs: UInt64 = 10 * 100_000_000

    /// The typed name's listing can be bought right here: priced under
    /// the direct-purchase ceiling, with a wallet balance that covers
    /// the price plus the identity fee headroom. Not offered in
    /// invitation mode (the voucher funds a registration, not a trade)
    /// or while a registration recovery is pending.
    var canPurchaseListedNameDirectly: Bool {
        guard let credits = takenNameSalePriceCredits,
              !isInvitationMode,
              !hasPendingRegistrationRecovery else { return false }
        let priceDuffs = credits / 1_000
        guard priceDuffs < Self.directPurchaseMaxDuffs else { return false }
        return coreSpendableDuffs >= priceDuffs + DWDP_MIN_BALANCE_TO_CREATE_USERNAME
    }

    /// Listed at or above the direct-purchase ceiling — the form points
    /// at the marketplace instead of offering the buy.
    var listedNameExceedsDirectPurchaseLimit: Bool {
        guard let credits = takenNameSalePriceCredits else { return false }
        return credits / 1_000 >= Self.directPurchaseMaxDuffs
    }

    /// The active vote's deadline has passed — the poll is being
    /// finalized on-chain. "Join as a contender" would be a stale claim
    /// at that point, so the callout switches to "ended" wording.
    var activeContestHasEnded: Bool {
        guard let endsAt = activeContestEndsAt else { return false }
        return endsAt <= Date()
    }

    /// The vote is still running but its contender-join window
    /// (`contenderJoinDeadline` — poll end − 45 min testnet / − 1 week
    /// mainnet) has closed: the name can no longer be requested until
    /// the vote resolves. Always true once the vote itself has ended.
    /// Consulted at render time AND as the last-moment gate behind the
    /// contested confirmation's "Submit anyway".
    var activeContestJoinClosed: Bool {
        guard let endsAt = activeContestEndsAt else { return false }
        return UsernameMarketplaceService.contenderJoinDeadline(voteEnd: endsAt) <= Date()
    }

    /// Whether the orange contested callout applies to the current
    /// answer. A plainly TAKEN name (someone owns its document) will
    /// never go to a vote — "requires a masternode vote" next to
    /// "Username taken" (or a for-sale listing) would contradict it.
    /// Locked and mid-vote answers keep the callout: it carries their
    /// detail.
    var showContestedWarning: Bool {
        guard isContestedCandidate else { return false }
        if uiState.usernameBlockedRule == .invalidCritical {
            return isLockedContestedName || activeContestContenders != nil
        }
        return true
    }

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
    /// names need the 0.25 DASH exit denomination instead of 0.1).
    /// Recomputed by `validateUsername` and on every readiness publish.
    /// nil while the SDK host has no hydrated wallet.
    @Published private(set) var shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot? = nil
    /// Formatted unspent shielded balance in DASH, for the picker label.
    @Published private(set) var shieldedBalance: String = ""

    /// A prior Core-funded attempt has already created an identity or
    /// persisted an unfinished asset lock. The form must not require a
    /// second balance or offer another funding source in this state.
    @Published private(set) var hasPendingRegistrationRecovery = false

    /// Fee-aware spendable Core balance (duffs) — the real ceiling for funding
    /// a registration: an ordinary L1 spend draws on confirmed UTXOs only and
    /// still needs room for the miner fee, so the displayed total overstates it.
    ///
    /// Cached, not recomputed per validation: the underlying reserve estimate
    /// walks the account's whole UTXO set over the FFI on the main actor, and
    /// validation runs on every (throttled) keystroke. Refreshed from the
    /// balance publisher instead, which is when the number can actually change.
    private var coreSpendableDuffs: UInt64 = 0

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

    func refreshRegistrationRecoveryState() {
        // Screen (re)appear — drop the cached DPNS answer so a stale
        // verdict from an earlier visit (name taken meanwhile, a vote
        // started or resolved) can't carry over into this one.
        availabilityCheckLabel = nil
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
                // The current label changes the required amount
                // (0.03 standard / 0.25 contested), so refresh the
                // source-picker eligibility in the same event.
                self?.checkBalance()
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
        case submittedForVoting
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
        // The cached ceiling tracks the balance publisher, which is enough for
        // per-keystroke validation. Submission spends real UTXOs, so re-derive
        // it once here from the live set: one FFI walk on an explicit user
        // action costs nothing, and it closes the window where the fee reserve
        // moved with the UTXO count while the balance stayed put. Deliberately
        // without re-running `validateUsername` — that would restart the DPNS
        // check and put the spinner back up mid-submission.
        coreSpendableDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()

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
                return registrationOutcome(for: submittedUsername)
            } catch DWIdentityRegistrationCoordinator.CoordinatorError.authCancelled {
                return .cancelled
            } catch {
                return .failure(
                    Self.registrationFailureMessage(error, username: submittedUsername))
            }
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<UsernameRegistrationOutcome, Never>) in
            DWIdentityRegistrationBridge.shared.startCreateUsername(submittedUsername) { [weak self] _, error in
                Task { @MainActor in
                    self?.submittedRegistrationUsername = nil
                    self?.didNotifyRegistrationStarted = false
                    self?.onRegistrationStarted = nil

                    guard let error else {
                        continuation.resume(
                            returning: self?.registrationOutcome(for: submittedUsername)
                                ?? .success)
                        return
                    }
                    // PIN / biometric cancel surfaces as the canonical Cocoa
                    // user-cancel — a silent no-op, not an error popup.
                    if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError {
                        continuation.resume(returning: .cancelled)
                    } else {
                        continuation.resume(
                            returning: .failure(
                                Self.registrationFailureMessage(error, username: submittedUsername)))
                    }
                }
            }
        }
    }

    /// Buy `name` (the taken, listed label captured by the caller at
    /// confirmation time — the text field stays editable during the
    /// flow) at the exact price captured by the availability check.
    /// Routes through
    /// `DWIdentityRegistrationCoordinator.startPurchaseUsername`, which
    /// creates or tops up this wallet's identity from the Core balance
    /// and buys at exactly the captured credits — a seller-side price
    /// change is refused by consensus and surfaces as a typed failure,
    /// as does a price/name mismatch from a mid-flight edit.
    func purchaseListedUsername(name: String) async -> UsernameRegistrationOutcome {
        guard let credits = takenNameSalePriceCredits else {
            // The gate (`canPurchaseListedNameDirectly`) shouldn't let a
            // priceless state reach here; answer with the marketplace's
            // canonical wording rather than crashing.
            return .failure(NSLocalizedString("This username is not for sale.", comment: "Username marketplace"))
        }
        do {
            _ = try await DWIdentityRegistrationCoordinator.shared.startPurchaseUsername(
                name: name,
                priceCredits: credits)
            return .success
        } catch DWIdentityRegistrationCoordinator.CoordinatorError.authCancelled {
            return .cancelled
        } catch {
            DWLogger.log("CreateUsername: purchase failed for '\(name)': \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    /// Human wording for a failed registration. Platform surfaces its refusals
    /// as a Rust debug dump of the whole state transition — hundreds of
    /// characters of `ContestedDocumentResourceVotePoll { … }` that fill the
    /// alert and tell the user nothing. Recognised causes get a sentence; an
    /// unrecognised one is passed through unchanged rather than swallowed, and
    /// the raw text always reaches the log.
    private static func registrationFailureMessage(
        _ error: Error,
        username: String
    ) -> String {
        let raw = error.localizedDescription
        DWLogger.log("CreateUsername: registration failed for '\(username)': \(raw)")

        // The vote poll ended in a LOCK: masternodes decided nobody gets the
        // name. Re-submitting can only fail the same way.
        if raw.contains("vote_poll_status: Locked") || raw.contains("is currently already locked") {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "“%@” was locked by a masternode vote, so it cannot be registered by anyone. Please choose a different username.",
                    comment: "Usernames"),
                username)
        }
        return raw
    }

    private func registrationOutcome(for username: String) -> UsernameRegistrationOutcome {
        guard let pending = DWContestedNameStatusService.shared.pendingLabel,
              DWContestedNameStatusService.labelsMatch(pending, username) else {
            return .success
        }
        return .submittedForVoting
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
    
    private func validateUsername(username: String) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // Re-check on every normal form revalidation (typing, Core/PP
        // balance refresh, shielded readiness). This catches the
        // cold-launch window where the screen appears just before the
        // SDK host finishes restoring the persisted asset-lock rows.
        hasPendingRegistrationRecovery =
            DWIdentityRegistrationCoordinator.shared.hasPendingRegistrationRecovery()

        // Balance/readiness publishes re-run this method constantly while
        // syncing, but they only move the cost rules — the DPNS answer for
        // an unchanged label stays good for the whole screen visit. Only a
        // label change invalidates the check state; same-label runs reuse
        // it below.
        let labelChanged = username != availabilityCheckLabel
        if labelChanged {
            // Kill any in-flight availability check — its result belongs to
            // an input the user has already changed (including changed-to-empty).
            availabilityCheckTask?.cancel()
            contestBoundaryRevalidationTask?.cancel()
            contestBoundaryRevalidationTask = nil
            availabilityCheckLabel = nil
            isLockedContestedName = false
            activeContestContenders = nil
            activeContestEndsAt = nil
            takenNameSalePriceCredits = nil
        }

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
        let coreBalance = coreSpendableDuffs
        let hasEnoughCore = coreBalance >= requiredCost
        let hasEnoughPlatform = PlatformPaymentIdentityFundingPolicy
            .canFundCurrentWallet(
                fundingDuffs: UInt64(requiredCost))
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
        let recoveryFunded = hasPendingRegistrationRecovery && !voucherFunded
        let hasEnoughBalance = recoveryFunded || voucherFunded || hasEnoughCore || hasEnoughPlatform || hasReadyShieldedFunding
        let canContinue = lengthValid && !hasIllegalCharacters && !startsOrEndsWithHyphen && hasEnoughBalance

        // The cost rule is an OR across four funding sources, so a green rule
        // on a wallet the user knows is short reads as a bug with no way to
        // tell WHICH source claimed it can pay. Record the verdicts and the
        // numbers behind them — this lands in the exported diagnostic log.
        if hasEnoughBalance {
            DWLogger.log(
                "CreateUsername: cost rule satisfied for '\(username)' "
                    + "(contested=\(isContested), required=\(requiredCost) duffs) — "
                    + "core=\(hasEnoughCore) [spendable \(coreBalance) duffs], "
                    + "platform=\(hasEnoughPlatform), "
                    + "shielded=\(hasReadyShieldedFunding), "
                    + "recovery=\(recoveryFunded), voucher=\(voucherFunded)")
        }

        // Same label as the existing check state → carry its rule forward
        // (a settled verdict stays settled; an in-flight `.loading` keeps
        // its task) instead of resetting to `.loading` and re-querying.
        // `.error` is deliberately NOT reused — it retries on the next
        // revalidation, as before. `.hidden` means the check never ran for
        // this label (cost rule was failing), so it must run now.
        let priorRule = uiState.usernameBlockedRule
        let reusePriorCheck = canContinue && !labelChanged
            && priorRule != .error && priorRule != .hidden

        uiState = CreateUsernameUIState(
            lengthRule: lengthValid ? .valid : .invalid,
            allowedCharactersRule: hasIllegalCharacters || startsOrEndsWithHyphen ? .invalid : .valid,
            costRule: voucherFunded || recoveryFunded ? .hidden : (hasEnoughBalance ? .valid : .invalid),
            usernameBlockedRule: canContinue ? (reusePriorCheck ? priorRule : .loading) : .hidden,
            requiredDash: requiredCost,
            canContinue: reusePriorCheck && priorRule == .valid
        )

        if canContinue && !reusePriorCheck {
            availabilityCheckLabel = username
            availabilityCheckTask = Task {
                await checkIfBlocked(username: username)
            }
        }
    }

    /// Debounced real DPNS availability check (same coordinator call the
    /// legacy `DWCheckExistenceUsernameValidationRule` path uses), plus a
    /// vote-state precheck for contested candidates. Maps: available with
    /// no known contest → `.valid`; available but mid-vote by others →
    /// `.valid` while the join window is open (submitting joins the vote
    /// as a contender), `.invalidCritical` once it closed; available but
    /// locked by a past vote → `.invalidCritical`; taken →
    /// `.invalidCritical`; our OWN pending contested submission →
    /// `.warning` ("in voting"); RPC failure → `.error` (re-runs on the
    /// next keystroke or balance publish). A taken name additionally gets
    /// a best-effort marketplace lookup — `takenNameSalePriceCredits` when
    /// its owner listed it for sale. `canContinue` is true only for
    /// `.valid` — the submit-time `registerDpnsName` failure remains the
    /// second line of defense.
    private func checkIfBlocked(username: String) async {
        // Debounce: sleep throws on cancellation (the user kept typing).
        do { try await Task.sleep(nanoseconds: Self.availabilityDebounceNanos) }
        catch { return }
        guard !Task.isCancelled else { return }

        let result: UsernameValidationRuleResult
        var locked = false
        var activeContenders: Int?
        var activeContestEnd: Date?
        var salePriceCredits: UInt64?
        do {
            // Two independent questions about the same label, so ask both at
            // once. Chaining them put a second DAPI round trip behind the
            // first, and "Validating username…" sat there for the sum of the
            // two — painful whenever Platform is slow. The vote-state
            // precheck is scoped to contested candidates: only they can sit
            // in a vote poll (resolved to a LOCK, or still being voted on).
            async let availability = DWIdentityRegistrationCoordinator.shared
                .dpnsCheckAvailability(username)
            async let precheck: UsernameMarketplaceService.ContestPrecheck = isContestedCandidate
                ? marketplaceService.contestPrecheck(label: username)
                : .fresh

            let available = try await availability
            if available {
                // "Available" only means no identity owns the domain document.
                // A contested label can still be spoken for: a vote that ended
                // in a LOCK refuses every new submission at broadcast, and a
                // still-running vote means a request joins it as a contender
                // rather than claiming a free name.
                switch await precheck {
                case .locked:
                    locked = true
                    result = .invalidCritical
                case let .activeContest(contenders, endsAt):
                    DWLogger.log(
                        "CreateUsername: '\(username)' is in an active vote "
                            + "(\(contenders) contenders, ends \(endsAt.map { "\($0)" } ?? "unknown"))")
                    // Our own running vote shows as "in voting", not as a
                    // joinable contest. The submission bookmark answers first;
                    // the SDK's local contested-names cache backs it up when
                    // the bookmark is gone (same two sources as the
                    // marketplace row's `hasRequestedContest`).
                    var isOwnRequest = false
                    if let pending = DWContestedNameStatusService.shared.pendingLabel,
                       DWContestedNameStatusService.labelsMatch(pending, username) {
                        isOwnRequest = true
                    } else {
                        isOwnRequest = await marketplaceService.myContestedNames()
                            .contains { DWContestedNameStatusService.labelsMatch($0, username) }
                    }
                    if isOwnRequest {
                        result = .warning
                    } else {
                        activeContenders = contenders
                        activeContestEnd = endsAt
                        // Contenders may only join for the first part of the
                        // poll (`contenderJoinDeadline`); past that a
                        // submission can only fail at broadcast, so Continue
                        // is blocked instead of promising a join the network
                        // will refuse. An unknown deadline stays submittable —
                        // the submit-time transition remains the authority.
                        if let endsAt,
                           UsernameMarketplaceService.contenderJoinDeadline(voteEnd: endsAt) <= Date() {
                            result = .invalidCritical
                        } else {
                            result = .valid
                        }
                    }
                case .fresh, .unknown:
                    // .unknown = the precheck query failed. It must not block
                    // a name that is very likely fine — the submit-time
                    // transition stays the authority (mirrors the old
                    // locked-check's failed-query behavior).
                    result = .valid
                }
            } else if let pending = DWContestedNameStatusService.shared.pendingLabel,
                      pending.caseInsensitiveCompare(username) == .orderedSame {
                // Our own contested submission — reads as taken on-chain
                // while masternode voting is still deciding the owner.
                result = .warning
            } else {
                // Taken — but the owner may have listed it in the Username
                // Marketplace. Best-effort: a failed lookup just leaves the
                // plain "taken" wording.
                if let sale = try? await marketplaceService.nameState(username),
                   sale.isForSale {
                    salePriceCredits = sale.priceCredits
                }
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

        isLockedContestedName = locked
        activeContestContenders = activeContenders
        activeContestEndsAt = activeContestEnd
        takenNameSalePriceCredits = salePriceCredits
        uiState.usernameBlockedRule = result
        uiState.canContinue = (result == .valid)
        armContestBoundaryRevalidation()
    }

    /// Schedule the one-shot re-check at the active contest's next
    /// boundary: the join-window close while joining is still open,
    /// otherwise the vote end. No-op when the current answer has no
    /// active contest or its deadline is unknown.
    private func armContestBoundaryRevalidation() {
        contestBoundaryRevalidationTask?.cancel()
        contestBoundaryRevalidationTask = nil
        guard activeContestContenders != nil, let endsAt = activeContestEndsAt else { return }
        let joinDeadline = UsernameMarketplaceService.contenderJoinDeadline(voteEnd: endsAt)
        let boundary = joinDeadline > Date() ? joinDeadline : endsAt
        let delay = boundary.timeIntervalSinceNow
        guard delay > 0 else { return }
        contestBoundaryRevalidationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((delay + 1) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Drop the per-label cache first — the boundary is exactly
            // what invalidates it.
            self.availabilityCheckLabel = nil
            self.validateUsername(username: self.username)
        }
    }
    
    private func observeBalance() {
        // Trigger a fresh Platform-credit tally on viewmodel init —
        // the wallet-state's auto-refresh only fires on Core-balance
        // updates, so without this the picker would miss any PP
        // credits that landed before the view opened (e.g. a
        // long-standing wallet with PP credits but no recent Core tx).
        SwiftDashSDKWalletState.shared.refreshPlatformPaymentCredits()
        coreSpendableDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
        checkBalance()
        // Source from SwiftDashSDKWalletState. After M6 retired DashSync's
        // SPV, DSWalletBalanceDidChange no longer fires. Function #5 follow-up.
        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // The only moment the spendable ceiling can move. Recomputing
                // it here keeps the FFI UTXO walk off the typing path.
                self.coreSpendableDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
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
        let balance = coreSpendableDuffs
        let platformDuffs = SwiftDashSDKWalletState.shared.platformPaymentCreditsAsDuffs
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiredDuffs = trimmedUsername.isEmpty
            ? DWDP_MIN_BALANCE_TO_CREATE_USERNAME
            : (DWContestedNameStatusService.isContestedLabel(trimmedUsername)
                ? DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME
                : DWDP_MIN_BALANCE_TO_CREATE_USERNAME)
        self.balance = balance.dashAmount.formattedDashAmountWithoutCurrencySymbol
        self.platformPaymentBalance = platformDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol
        // Credits → duffs (÷1000) for display; the readiness snapshot
        // keeps the canonical credit-denominated values.
        let shieldedDuffs = (shieldedReadiness?.unspentCredits ?? 0) / 1_000
        self.shieldedBalance = shieldedDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol
        // These flags drive the actual funding-source picker. They must
        // follow the current name's cost, otherwise a Core/Platform
        // balance that covers 0.03 DASH but not a contested name's
        // 0.25 DASH is still offered and fails only inside the SDK.
        hasMinimumRequiredCoreBalance = balance >= requiredDuffs
        hasMinimumRequiredPlatformBalance = PlatformPaymentIdentityFundingPolicy
            .canFundCurrentWallet(
                fundingDuffs: UInt64(requiredDuffs))
        // `hasMinimumRequiredBalance` stays as the legacy OR view —
        // any pre-PR-5 consumer (banner gate, etc.) keeps seeing
        // "user has enough to register" without caring about source.
        hasMinimumRequiredBalance = hasMinimumRequiredCoreBalance || hasMinimumRequiredPlatformBalance
        hasRecommendedBalance = balance >= DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME
            || PlatformPaymentIdentityFundingPolicy.canFundCurrentWallet(
                fundingDuffs: UInt64(DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME))
    }
}
