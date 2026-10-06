//
//  DWIdentityRegistrationCoordinator.swift
//  DashWallet
//
//  App-scoped singleton orchestrator for SwiftDashSDK-backed DashPay
//  identity + DPNS username registration.
//
//  Sequence:
//    1. PIN / biometric gate via DWIdentityAuthorizer.
//    2. Pre-derive identity public keys + persist privates to Keychain
//       (`ManagedPlatformWallet.prePersistIdentityKeysForRegistration`).
//    3. Build asset-lock tx + broadcast + wait for IS/CL + submit
//       IdentityCreate state transition
//       (`registerIdentityWithFunding`).
//    4. Submit DPNS preorder + register state transitions
//       (`registerDpnsName`).
//    5. Mirror success into DWGlobalOptions for the legacy Obj-C
//       identity-read sites.
//
//  Progress is exposed two ways:
//    - `@Published phase` mirrored from `DWIdentityRegistrationController`
//      (idle / preparingKeys / inFlight / completed / failed).
//    - `@Published assetLockStatus` polled from SwiftData every 0.5s
//      while `phase == .inFlight`, sourced from the matching
//      `PersistentAssetLock` row.
//  The `DWRegistrationPhaseAdapter` collapses both onto the existing
//  3-state `DWDPRegistrationState` for the `DWDPRegistrationStatusViewController`
//  UI.
//
//  v1 scope:
//    - Single identity per wallet (`identityIndex` pinned at 0).
//    - Four funding paths:
//      * Core-funded via `registerIdentityWithFunding` (legacy default).
//      * Platform Payment via `registerIdentityFromAddresses` —
//        spends credits already on DIP-17 platform addresses.
//        Skips the Core-chain asset-lock IS/CL wait.
//      * Shielded via `shieldedIdentityCreateFromPool` (Type 20) —
//        spends a fixed exit denomination from the wallet's Orchard
//        pool. Pre-flighted against `ShieldedIdentityFundingReadiness`
//        (funding / maturity / pool-size gates); no asset-lock.
//      * Invitation via `claimInvitation` (DIP-13) — consumes the
//        voucher asset-lock the INVITER built; entered through
//        `startClaimInvitation(username:invitationURI:)` only.
//    - Core-funded registrations survive process interruption:
//      a persisted identity is continued at DPNS, otherwise the
//      original tracked asset lock is resumed by outpoint.
//

import Combine
import CryptoKit
import Foundation
import SwiftData
import SwiftDashSDK

/// Plans Platform-Payment identity funding while preserving the
/// `DeductFromInput(0)` fee source used by SwiftDashSDK.
///
/// The SDK currently has no public identity-from-addresses fee estimator.
/// Keep a conservative reserve on the BTreeMap-smallest selected address,
/// matching the input-order and fee-source rules enforced by the Rust
/// transition builder. Only the actual transition fee is deducted; unused
/// reserve remains in the Platform-Payment address.
enum PlatformPaymentIdentityFundingPolicy {
    static let creditsPerDuff: UInt64 = 1_000

    /// 0.002 DASH of headroom reserved on the fee-source (BTreeMap input 0)
    /// address. The observed identity-from-addresses base fee is ~0.0004 DASH
    /// (`required 41500000` credits), so this keeps a ~5x margin that also
    /// absorbs metered execution cost and additional-input overhead.
    ///
    /// It is deliberately much smaller than a typical Platform-address payment
    /// (~0.01 DASH): the reserve doubles as the *minimum* balance an address
    /// must hold to qualify as the fee source, and any smaller-hash address
    /// below it is dropped from the plan (it cannot be a valid input 0). An
    /// oversized reserve therefore strands funds — e.g. a 0.05 DASH balance
    /// fragmented across 0.03 + 0.01 + 0.01 addresses would be rejected if the
    /// reserve exceeded 0.01. Keeping it at 0.002 lets realistic fragments
    /// remain usable fee sources while still covering the fee.
    ///
    /// TODO(SwiftDashSDK): replace this reserve with the SDK's authoritative
    /// identity-from-addresses fee estimate once one is exposed.
    static let feeHeadroomCredits: UInt64 = 200_000_000

    struct Candidate: Equatable {
        let addressType: UInt8
        let hash: Data
        let balance: UInt64
    }

    enum PlanningError: Error, Equatable {
        case insufficient(required: UInt64, available: UInt64)
    }

    static func requiredAvailableCredits(fundingDuffs: UInt64) -> UInt64 {
        let (fundingCredits, multiplicationOverflow) =
            fundingDuffs.multipliedReportingOverflow(by: creditsPerDuff)
        guard !multiplicationOverflow else { return .max }
        let (required, additionOverflow) =
            fundingCredits.addingReportingOverflow(feeHeadroomCredits)
        return additionOverflow ? .max : required
    }

    static func canFund(
        candidates: [Candidate],
        fundingDuffs: UInt64
    ) -> Bool {
        let (targetCredits, overflow) =
            fundingDuffs.multipliedReportingOverflow(by: creditsPerDuff)
        guard !overflow else { return false }
        return (try? makeInputs(
            candidates: candidates,
            targetCredits: targetCredits)) != nil
    }

    /// Resolve the active wallet's persisted Platform-Payment address rows.
    /// Both UI eligibility and submit-time planning consume this exact
    /// candidate representation so fragmented balances cannot produce
    /// different answers at the two call sites.
    @MainActor
    static func currentCandidates() throws -> [Candidate] {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            return []
        }
        return try candidates(
            walletId: wallet.walletId,
            modelContainer: modelContainer)
    }

    @MainActor
    static func candidates(
        walletId: Data,
        modelContainer: ModelContainer
    ) throws -> [Candidate] {
        let descriptor = FetchDescriptor<PersistentAccount>(
            predicate: #Predicate { account in
                account.accountType == 14
                    && account.wallet.walletId == walletId
            }
        )
        return try modelContainer.mainContext.fetch(descriptor)
            .flatMap { $0.platformAddresses }
            .filter { $0.balance > 0 }
            .map {
                Candidate(
                    addressType: $0.addressType,
                    hash: $0.addressHash,
                    balance: $0.balance)
            }
    }

    @MainActor
    static func canFundCurrentWallet(fundingDuffs: UInt64) -> Bool {
        guard let candidates = try? currentCandidates() else { return false }
        return canFund(
            candidates: candidates,
            fundingDuffs: fundingDuffs)
    }

    /// Saturating credit total of `candidates`.
    private static func totalCredits(of candidates: [Candidate]) -> UInt64 {
        candidates.reduce(UInt64(0)) {
            let (sum, overflow) = $0.addingReportingOverflow($1.balance)
            return overflow ? .max : sum
        }
    }

    /// The candidates `makeInputs` can actually plan from, in
    /// PlatformAddress/BTreeMap order (Rust's derived order compares the
    /// address variant first — P2PKH before P2SH — then the 20-byte hash),
    /// plus their saturating credit total.
    ///
    /// Any selected address before the fee source would become BTreeMap
    /// input 0 itself, so leading addresses that cannot retain the reserve
    /// are skipped and the plan draws exclusively from the viable suffix.
    /// `nil` when no address can be the fee source.
    private static func usableSelection(
        candidates: [Candidate]
    ) -> (usable: [Candidate], availableCredits: UInt64)? {
        let sorted = candidates
            .filter { $0.balance > 0 }
            .sorted { lhs, rhs in
                if lhs.addressType != rhs.addressType {
                    return lhs.addressType < rhs.addressType
                }
                return lhs.hash.lexicographicallyPrecedes(rhs.hash)
            }
        guard let feeSourceIndex = sorted.firstIndex(where: {
            $0.balance > feeHeadroomCredits
        }) else { return nil }
        let usable = Array(sorted[feeSourceIndex...])
        return (usable, totalCredits(of: usable))
    }

    /// Largest funding amount `makeInputs` can plan from `candidates`, in
    /// whole duffs (floored, so the ceiling never overstates what the
    /// credit-denominated planner accepts). Input 0 contributes
    /// `balance − reserve` and every later input its full balance, so the
    /// ceiling is the usable total minus the retained fee headroom. 0 when
    /// no address qualifies as the fee source.
    static func maxFundableDuffs(candidates: [Candidate]) -> UInt64 {
        guard let (_, availableCredits) = usableSelection(candidates: candidates),
              availableCredits > feeHeadroomCredits
        else { return 0 }
        return (availableCredits - feeHeadroomCredits) / creditsPerDuff
    }

    /// Builds inputs from the usable selection above.
    static func makeInputs(
        candidates: [Candidate],
        targetCredits: UInt64
    ) throws -> [ManagedPlatformWallet.IdentityAddressInput] {
        let required = {
            let (sum, overflow) = targetCredits.addingReportingOverflow(feeHeadroomCredits)
            return overflow ? UInt64.max : sum
        }()

        guard let (usable, usableAvailable) = usableSelection(candidates: candidates) else {
            throw PlanningError.insufficient(
                required: required,
                available: totalCredits(of: candidates))
        }
        guard usableAvailable >= required else {
            throw PlanningError.insufficient(
                required: required,
                available: usableAvailable)
        }

        var remaining = targetCredits
        var inputs: [ManagedPlatformWallet.IdentityAddressInput] = []
        for (index, candidate) in usable.enumerated() {
            guard remaining > 0 else { break }
            let maximumContribution = index == 0
                ? candidate.balance - feeHeadroomCredits
                : candidate.balance
            let contribution = min(maximumContribution, remaining)
            guard contribution > 0 else { continue }
            inputs.append(
                ManagedPlatformWallet.IdentityAddressInput(
                    addressType: candidate.addressType,
                    hash: candidate.hash,
                    credits: contribution))
            remaining -= contribution
        }

        guard remaining == 0 else {
            throw PlanningError.insufficient(
                required: required,
                available: usableAvailable)
        }
        return inputs
    }
}

@MainActor
final class DWIdentityRegistrationCoordinator: ObservableObject {

    static let shared = DWIdentityRegistrationCoordinator()

    /// `DWLogger`, not `os.Logger`: a failed registration has to be readable
    /// from the "Share application logs" export, which ships only the
    /// DWLogger files.
    private static let logger = CoordinatorLog()

    /// v1 pins identityIndex to 0; dashwallet only ever has one
    /// DashPay identity per wallet.
    private static let pinnedIdentityIndex: UInt32 = 0

    /// Number of SDK base keys to pre-derive: AUTHENTICATION/MASTER,
    /// AUTHENTICATION/CRITICAL, AUTHENTICATION/HIGH, and
    /// TRANSFER/CRITICAL. The DashPay ENCRYPTION/DECRYPTION pair is
    /// appended separately at ids 4 and 5 below.
    private static let defaultKeyCount: UInt32 = 4

    /// BIP44 account index used for asset-lock funding. dashwallet
    /// uses the default account only.
    private static let defaultAccountIndex: UInt32 = 0

    /// Asset-lock polling interval while `phase == .inFlight`. The
    /// FFI emits at most a handful of status transitions per
    /// registration (Built → Broadcast → IS/CL → Consumed), so a
    /// 0.5s cadence is plenty without burning CPU.
    private static let assetLockPollInterval: TimeInterval = 0.5

    /// Rust rejects Core identity top-ups below this floor. Purchases use
    /// it when funding the explicitly accepted sale price.
    private static let minimumCoreTopUpDuffs: UInt64 = 50_500

    /// Fee headroom an existing identity must hold for each DPNS name
    /// registered in one run, on top of any contest fund: 0.01 DASH.
    ///
    /// One name is two document transitions (preorder + domain), and the
    /// contested flow also publishes the optional verification document from
    /// the same balance. The fees observed on those paths are orders of
    /// magnitude smaller — the consensus shortfall reported for a contested
    /// domain was 100_000 credits beyond the fund, and the costliest
    /// transition the app measures is ~41_500_000 credits
    /// (`PlatformPaymentIdentityFundingPolicy`) — so this leaves a >10x
    /// margin per name. It also absorbs the fee of the top-up transition
    /// itself, which Platform takes from the credits it delivers.
    ///
    /// Deliberately below what a new identity keeps after IdentityCreate
    /// (0.03 / 0.25 DASH minus the create fee): an identity this flow has
    /// just funded must never read as short and trigger a second payment.
    static let registrationFeeHeadroomCreditsPerName: UInt64 = 1_000_000_000

    /// Credits an existing identity needs to register `username` — and the
    /// companion, when one is registered in the same run. The contest fund
    /// is locked by the contested domain document itself (the consensus
    /// check is balance ≥ fund + fee), so it is required up front.
    static func requiredRegistrationCredits(
        username: String,
        temporaryUsername: String?
    ) -> UInt64 {
        requiredRegistrationCredits(
            isContested: DWContestedNameStatusService.isContestedLabel(username),
            nameCount: temporaryUsername == nil ? 1 : 2)
    }

    static func requiredRegistrationCredits(isContested: Bool, nameCount: UInt64) -> UInt64 {
        let fund = isContested ? UsernameMarketplaceService.contestedFundCredits : 0
        return fund + nameCount * registrationFeeHeadroomCreditsPerName
    }

    /// Duffs to move into an identity holding `heldCredits` so it reaches
    /// `requiredCredits`: the shortfall rounded up to whole duffs, floored at
    /// the Rust-side minimum top-up. 0 when nothing is missing.
    static func identityTopUpDuffs(
        requiredCredits: UInt64,
        heldCredits: UInt64
    ) -> UInt64 {
        guard heldCredits < requiredCredits else { return 0 }
        let perDuff = PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        let shortfallDuffs = (requiredCredits - heldCredits + perDuff - 1) / perDuff
        return max(shortfallDuffs, minimumCoreTopUpDuffs)
    }

    // MARK: - Published surface

    /// Current phase, mirrored from the active controller.
    @Published private(set) var phase: DWIdentityRegistrationController.Phase = .idle

    /// Latest `PersistentAssetLock.statusRaw` for the active
    /// registration (0 = Built, 1 = Broadcast, 2 = InstantSendLocked,
    /// 3 = ChainLocked, 4 = Consumed). 0 outside of `.inFlight`.
    @Published private(set) var assetLockStatus: Int = 0

    /// When the most recent failure happened. Consulted by
    /// `DWRegistrationPhaseAdapter.map(...)` so the existing UI's
    /// 3-state error copies are accurate to where the chain broke.
    private(set) var failedAtPhase: DWDPRegistrationState?

    /// Last error description, for surfacing to the registration UI
    /// when phase is `.failed`.
    private(set) var lastErrorMessage: String?

    /// Username being registered. Stashed at submit time so the
    /// `.completed` mirror can write DWGlobalOptions.dashpayUsername.
    private(set) var currentUsername: String?

    /// Wallet the in-flight attempt registers for. Stashed at submit time
    /// because `.completed` arrives after awaited Platform work, during
    /// which a wallet switch can rebind `SwiftDashSDKHost.shared.wallet`.
    private var registrationWalletId: Data?
    private var registrationNetwork: Network?
    /// `registrationNetwork`'s persistence scope, read when the attempt
    /// starts: a devnet's scope follows the configured devnet, which can
    /// change before the attempt completes.
    private var registrationNetworkScope: String?
    private var resumedIdentityId: Data?
    private(set) var isRegisteringUsername = false
    /// An existing identity is being topped up before its name is
    /// registered. Reported as the payment step, ahead of
    /// `isRegisteringUsername`, by `DWRegistrationPhaseAdapter`.
    private(set) var isFundingExistingIdentity = false

    /// Funding source for the in-flight attempt (the value the
    /// coordinator's caller passed into `startCreateUsername(_:fundingSource:)`).
    /// Read by `DWIdentityRegistrationBridge.refreshFromCoordinator`
    /// when mapping phase → UI state so the Platform Payment path
    /// can skip the asset-lock progression rule in
    /// `DWRegistrationPhaseAdapter`. Defaults to `.core` outside of
    /// an active attempt.
    private(set) var currentFundingSource: DWIdentityFundingSource = .core

    /// Non-contested companion label registered alongside a contested
    /// submission in the same flow ("temporary username"), non-nil only
    /// after its `registerDpnsName` succeeded. Read by
    /// `CreateUsernameViewModel.registrationOutcome(for:)` to tell the
    /// form which of the two names actually landed.
    private(set) var registeredTemporaryUsername: String?

    /// Failure description when the companion registration was requested
    /// but failed. Deliberately non-fatal: the contested submission has
    /// already succeeded by the time the companion registers, so the flow
    /// completes and the form reports the partial outcome.
    private(set) var temporaryUsernameError: String?

    // MARK: - Internal state

    private var controller: DWIdentityRegistrationController?

    /// An attempt is running: either the published phase or the controller's
    /// own says so. The registration and purchase entry points, `cancel()`, the
    /// create form and Request details all ask this, so the two are never
    /// consulted apart.
    var isAttemptActive: Bool {
        phase.isActive || controller?.phase.isActive == true
    }
    private var phaseSubscription: AnyCancellable?
    private var assetLockPollingTask: Task<Void, Never>?
    /// Single-flight handle for `checkPendingContestResolution()`.
    private var contestResolutionTask: Task<Void, Never>?
    /// The next in-session check of a pending contest, timed to its deadline.
    private var contestTimerTask: Task<Void, Never>?
    /// Single-flight for the restore-time bookmark recovery.
    private var contestRecoveryTask: Task<Void, Never>?
    /// Network+identity scopes already asked about this launch, so a Home
    /// appear does not turn into a Platform query every time.
    private static var attemptedContestRecoveries: Set<String> = []

    private let authorizer = DWIdentityAuthorizer()

    private init() {}

    /// Value copy of the persisted Core asset lock used to recover a
    /// registration after process death. Keeping only the outpoint and
    /// status avoids carrying a SwiftData model object across SDK awaits.
    private struct RegistrationRecoveryLock {
        let outPointHex: String
        let statusRaw: Int
    }

    // MARK: - Errors

    enum CoordinatorError: LocalizedError {
        case noWallet
        case noNetwork
        case noModelContainer
        case noSDK
        case authCancelled
        case authFailed
        case keyDerivation(Error)
        case identityRegistration(Error)
        case dpnsRegistration(Error)
        case availabilityCheck(Error)
        case purchase(Error)
        case purchaseCompletedInOriginalContext(name: String, identityId: Data)
        case insufficientPlatformCredits(required: UInt64, available: UInt64)
        case insufficientShieldedBalance(requiredCredits: UInt64, availableCredits: UInt64)
        case shieldedBalanceImmature(readyAt: Date)
        case shieldedPoolTooSmall(currentNotes: UInt64)
        case noShieldedFallbackAddress
        case shieldedCreateUnconfirmed
        case missingInvitation
        case alreadyInFlight
        case invalidTemporaryUsername
        case contextChanged
        case usernameUnavailable
        /// Topping up an existing identity before its name failed; wraps the
        /// cause. Kept apart from `.dpnsRegistration` so the failure is
        /// reported at the payment step, where it happened.
        case identityTopUp(Error)
        case identityBalanceUnavailable
        case insufficientCoreBalanceForTopUp(neededDuffs: UInt64, availableDuffs: UInt64)
        case shieldedTopUpUnavailable(neededDuffs: UInt64)
        case topUpExceedsConfirmed(neededDuffs: UInt64, confirmedDuffs: UInt64)
        /// The identity needs a top-up, but no amount was confirmed for it.
        case topUpNotConfirmed(neededDuffs: UInt64)

        var isCompletedPurchase: Bool {
            if case .purchaseCompletedInOriginalContext = self { return true }
            return false
        }

        var isIdentityTopUp: Bool {
            if case .identityTopUp = self { return true }
            return false
        }

        var errorDescription: String? {
            switch self {
            case .noWallet:
                return NSLocalizedString("Wallet is not ready for identity registration", comment: "DashPay")
            case .noNetwork:
                return NSLocalizedString("Network is not configured", comment: "DashPay")
            case .noModelContainer:
                return NSLocalizedString("Storage is not configured", comment: "DashPay")
            case .noSDK:
                return NSLocalizedString("SDK is not initialized", comment: "DashPay")
            case .authCancelled:
                return NSLocalizedString("Authentication cancelled", comment: "DashPay")
            case .authFailed:
                return NSLocalizedString("Authentication failed", comment: "DashPay")
            case .keyDerivation(let underlying):
                return underlying.localizedDescription
            case .identityRegistration(let underlying):
                return underlying.localizedDescription
            case .dpnsRegistration(let underlying):
                return underlying.localizedDescription
            case .purchaseCompletedInOriginalContext(let name, _):
                return String.localizedStringWithFormat(
                    NSLocalizedString("“%@” was purchased successfully. Switch back to the original wallet and network to see it. Do not purchase it again.", comment: "DashPay purchase context changed"), name)
            case .purchase(let underlying):
                // Marketplace-typed failures (price changed, delisted,
                // insufficient credits) get their friendly wording.
                return UsernameMarketplaceService.userFacingMessage(for: underlying)
            case .availabilityCheck(let underlying):
                return underlying.localizedDescription
            case .insufficientPlatformCredits(let required, let available):
                let requiredDuffs =
                    (required + PlatformPaymentIdentityFundingPolicy.creditsPerDuff - 1)
                    / PlatformPaymentIdentityFundingPolicy.creditsPerDuff
                let availableDuffs =
                    available / PlatformPaymentIdentityFundingPolicy.creditsPerDuff
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Platform Payment needs at least %@ DASH available; you have %@ DASH. Add funds to Platform and try again.",
                        comment: "DashPay Platform Payment funding shortfall"),
                    requiredDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol,
                    availableDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)
            case .insufficientShieldedBalance:
                return NSLocalizedString("Not enough shielded balance to register an identity", comment: "DashPay")
            case .shieldedBalanceImmature(let readyAt):
                let time = DateFormatter.localizedString(from: readyAt, dateStyle: .none, timeStyle: .short)
                return String.localizedStringWithFormat(
                    NSLocalizedString("Your shielded balance is still maturing. It will be ready around %@.", comment: "DashPay"),
                    time)
            case .shieldedPoolTooSmall(let currentNotes):
                return String.localizedStringWithFormat(
                    NSLocalizedString("The shared privacy pool is still growing (%ld of %ld deposits). Try again once it reaches the minimum.", comment: "DashPay"),
                    Int(currentNotes), Int(ShieldedIdentityFundingReadiness.minimumPoolNotes))
            case .noShieldedFallbackAddress:
                return NSLocalizedString("No Platform address is available yet for the shielded registration fallback. Try again after the wallet finishes syncing.", comment: "DashPay")
            case .shieldedCreateUnconfirmed:
                return NSLocalizedString("The registration was submitted but its result couldn't be confirmed. Wait a minute for the wallet to sync, then try again — don't resubmit immediately.", comment: "DashPay")
            case .missingInvitation:
                return NSLocalizedString("This invitation link is not valid.", comment: "DashPay Invitations")
            case .alreadyInFlight:
                return NSLocalizedString("Identity registration already in progress", comment: "DashPay")
            case .contextChanged:
                return NSLocalizedString("The active wallet or identity changed. Please try again.", comment: "DashPay registration recovery")
            case .usernameUnavailable:
                return NSLocalizedString("This username is no longer available. Please choose another one.", comment: "DashPay registration recovery")
            case .invalidTemporaryUsername:
                return NSLocalizedString("The temporary username must not itself require voting.", comment: "Usernames")
            case .identityTopUp(let underlying):
                return underlying.localizedDescription
            case .identityBalanceUnavailable:
                return NSLocalizedString("Couldn’t check your identity balance. Check your connection and try again.", comment: "DashPay: existing identity top-up before a username")
            case .insufficientCoreBalanceForTopUp(let neededDuffs, let availableDuffs):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Your identity needs %@ DASH more to register this name, but only %@ DASH can be sent from your wallet. Add funds and try again.",
                        comment: "DashPay: existing identity top-up before a username"),
                    neededDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol,
                    availableDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)
            case .shieldedTopUpUnavailable(let neededDuffs):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Your identity needs %@ DASH more to register this name, and it can’t be added from your Shielded balance here. Use Top Up in My Profile, then try again.",
                        comment: "DashPay: existing identity top-up before a username"),
                    neededDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)
            case .topUpNotConfirmed(let neededDuffs):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Registering this name needs %@ DASH from your wallet to top up your identity, and that amount was not confirmed. Nothing was sent. Try again to confirm it.",
                        comment: "DashPay: existing identity top-up before a username"),
                    neededDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)
            case .topUpExceedsConfirmed(let neededDuffs, let confirmedDuffs):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Registering this name now needs %1$@ DASH from your wallet, more than the %2$@ DASH you confirmed. Nothing was sent. Try again to confirm the new amount.",
                        comment: "DashPay: existing identity top-up before a username"),
                    neededDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol,
                    confirmedDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)
            }
        }
    }

    // MARK: - Public API

    /// Proof-of-identity link for the submission in flight, handed over by
    /// `startCreateUsername` and consumed once the identity exists. Held here
    /// rather than threaded through `finishUsernameRegistration` →
    /// `registerNames`, neither of which has a reason to know about it.
    private var pendingVerificationURL: URL?

    /// Run the full new-user create-username flow:
    /// PIN gate → pre-derive keys → IdentityCreate → DPNS register.
    /// On success, mirrors the username into `DWGlobalOptions` and
    /// returns the 32-byte identifier. On failure, sets
    /// `failedAtPhase` + `lastErrorMessage` and rethrows.
    ///
    /// `fundingSource` selects between Core BIP44 UTXOs
    /// (`registerIdentityWithFunding` → asset-lock + IS/CL + ST) and
    /// DIP-17 Platform Payment addresses
    /// (`registerIdentityFromAddresses` → direct address-funded ST).
    /// Defaults to `.core` for callers that don't care (legacy
    /// Obj-C entry points, retries after a terminal phase).
    ///
    /// `.invitation` is entered through
    /// `startClaimInvitation(username:invitationURI:)`, which supplies
    /// the voucher link; calling this method with `.invitation` and no
    /// `invitationURI` fails with `.missingInvitation`.
    ///
    /// `temporaryUsername` (contested submissions only) is a
    /// NON-contested companion label registered to the same identity
    /// right after the contested submission, inside the same authorized
    /// flow — the user is reachable at it while masternode voting runs,
    /// and keeps it permanently afterwards. Its registration failure is
    /// non-fatal (`temporaryUsernameError`); its success is recorded in
    /// `registeredTemporaryUsername` and it becomes the identity's main
    /// name while the vote runs. The contested label is bookmarked with
    /// `promoteOnWin`, so a win makes it the main name instead (a loss
    /// leaves the companion in place).
    @discardableResult
    func startCreateUsername(
        _ username: String,
        fundingSource: DWIdentityFundingSource = .core,
        invitationURI: String? = nil,
        temporaryUsername: String? = nil,
        /// Proof-of-identity link for a contested submission, published as an
        /// `identityVerify` document once the identity exists — inside this
        /// flow, with the signer it already holds, so it costs no second PIN.
        /// Android publishes the same document from `CreateIdentityService`.
        verificationURL: URL? = nil,
        /// The most an existing identity's top-up may move without a new
        /// confirmation: what the confirmation sheet showed. nil = none shown.
        authorizedTopUpDuffs: UInt64? = nil,
        /// The user picked `fundingSource` for this request, so a retry of it
        /// should reuse it (`recordAcceptedSource`). False for callers that
        /// pass the default.
        remembersFundingSource: Bool = false
    ) async throws -> Identifier {
        Self.logger.info("🪪 IDENT-COORD :: startCreateUsername username=\(username) funding=\(fundingSource.logLabel) temporary=\(temporaryUsername ?? "none")")
        // An overlapping start is rejected before it touches the attempt's
        // state: the proof link belongs to the request already running, and
        // overwriting it would publish another URL under that request's
        // identity, or drop the one it accepted.
        guard !isAttemptActive else {
            throw CoordinatorError.alreadyInFlight
        }
        pendingVerificationURL = verificationURL

        // A companion label only makes sense next to a contested main
        // label, and must itself be non-contested — registering a second
        // contested name here would silently open a second vote the UI
        // never explained. Reject before any money moves.
        if let temporaryUsername {
            guard DWContestedNameStatusService.isContestedLabel(username),
                  !DWContestedNameStatusService.isContestedLabel(temporaryUsername)
            else {
                Self.logger.error("🪪 IDENT-COORD :: invalid temporary username pairing main=\(username) temporary=\(temporaryUsername)")
                throw CoordinatorError.invalidTemporaryUsername
            }
        }

        // Preconditions — resolved once up-front so failures are
        // surfaced before the PIN prompt.
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.error("🪪 IDENT-COORD :: no managed wallet")
            throw CoordinatorError.noWallet
        }
        guard let network = SwiftDashSDKHost.shared.runningNetwork else {
            Self.logger.error("🪪 IDENT-COORD :: no running network")
            throw CoordinatorError.noNetwork
        }
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            Self.logger.error("🪪 IDENT-COORD :: no model container")
            throw CoordinatorError.noModelContainer
        }
        guard DWCurrentUserIdentityInfo.shared.isCurrentNetworkContextReady else {
            throw CoordinatorError.noWallet
        }
        let identitySnapshot = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
        guard !identitySnapshot.isLoading else { throw CoordinatorError.noWallet }
        return try await UsernameRegistrationRecoveryFlow.route(
            identityId: identitySnapshot.identityId,
            resume: { identityId in
                // An invitation voucher funds a NEW identity; it can never top
                // up this one, so that entry registers on the existing credits.
                try await self.resumeUsernameRegistration(
                    identityId: identityId, username: username, temporaryUsername: temporaryUsername,
                    topUpSource: fundingSource == .invitation ? nil : fundingSource,
                    authorizedTopUpDuffs: authorizedTopUpDuffs,
                    remembersFundingSource: remembersFundingSource)
            },
            create: {
                try await self.createIdentityAndUsername(
                    username, fundingSource: fundingSource, invitationURI: invitationURI,
                    temporaryUsername: temporaryUsername, wallet: wallet,
                    network: network, modelContainer: modelContainer,
                    authorizedTopUpDuffs: authorizedTopUpDuffs,
                    remembersFundingSource: remembersFundingSource)
            })
    }

    private func createIdentityAndUsername(
        _ username: String, fundingSource: DWIdentityFundingSource,
        invitationURI: String?, temporaryUsername: String?, wallet: ManagedPlatformWallet,
        network: Network, modelContainer: ModelContainer, authorizedTopUpDuffs: UInt64? = nil,
        remembersFundingSource: Bool = false
    ) async throws -> Identifier {
        let recoveryLock = lookupRegistrationRecoveryLock(
            walletId: wallet.walletId,
            modelContainer: modelContainer)
        if let recoveryLock {
            Self.logger.info("🪪 IDENT-COORD :: recoverable Core registration found status=\(recoveryLock.statusRaw)")
        }

        // Single-flight guard. The FFI calls we're about to make
        // (`registerIdentityWithFunding` / `registerIdentityFromAddresses`
        // / `registerDpnsName`) can't be cancelled — `resetState()`
        // would drop our observers but the underlying network work
        // keeps racing to its terminal. Letting a second submit in
        // would race two asset-lock broadcasts against the same
        // identity index and tear up the DWGlobalOptions mirror on
        // whichever completion fires last. Reject overlapping starts
        // and let the existing attempt finish or fail terminally.
        guard !isAttemptActive else { throw CoordinatorError.alreadyInFlight }

        // Tear down any prior terminal controller / subscription
        // before creating a fresh attempt. Safe even if no prior
        // attempt ran — `resetState()` is idempotent.
        resetState()

        currentUsername = username
        registrationWalletId = wallet.walletId
        registrationNetwork = network
        registrationNetworkScope = network.persistenceScope
        // A persisted identity-registration lock always wins over the
        // newly-selected funding source. The original Core payment has
        // already happened; presenting PP / shielded progress here would
        // be misleading and, more importantly, must never trigger a
        // second funding operation.
        currentFundingSource = recoveryLock == nil ? fundingSource : .core
        failedAtPhase = nil
        lastErrorMessage = nil
        let isContestedSubmission = DWContestedNameStatusService.isContestedLabel(username)
        let requiredIdentityFundingDuffs = isContestedSubmission
            ? DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME
            : DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        Self.logger.info(
            "🪪 IDENT-COORD :: contested=\(isContestedSubmission) identityFundingDuffs=\(requiredIdentityFundingDuffs)")

        let newController = DWIdentityRegistrationController()
        controller = newController
        wireController(newController)
        newController.enterPreparingKeys()
        // Asset-lock polling only applies to the Core-funded path —
        // the Platform Payment path never writes a `PersistentAssetLock`
        // row, and polling would just keep `assetLockStatus` pegged at
        // 0 throughout the FFI call (which would force the adapter
        // backwards to `.processingPayment` on every emit if the
        // funding-source branch in the adapter wasn't honored).
        if currentFundingSource == .core {
            startAssetLockPolling(walletId: wallet.walletId, modelContainer: modelContainer)
        }

        // PIN / biometric gate. Throws on cancel / failure; the
        // controller stays at `.idle` so the UI doesn't show
        // "Processing payment" for a cancellation.
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            resetState()
            throw CoordinatorError.authCancelled
        } catch {
            lastErrorMessage = CoordinatorError.authFailed.localizedDescription
            newController.enterFailed(lastErrorMessage ?? "")
            throw CoordinatorError.authFailed
        }

        do {
            try validateRegistrationContext(walletId: wallet.walletId, network: network)
        } catch {
            newController.enterFailed(error.localizedDescription)
            throw error
        }

        // Step 1: pre-derive identity public keys + persist privates
        // to Keychain. Synchronous on the FFI side; the resolver
        // callback reads the mnemonic via WalletStorage.
        newController.enterPreparingKeys()
        var pubkeys: [ManagedPlatformWallet.IdentityPubkey]
        do {
            pubkeys = try wallet.prePersistIdentityKeysForRegistration(
                identityIndex: Self.pinnedIdentityIndex,
                keyCount: Self.defaultKeyCount,
                network: network)
            let dashPaySpecifications = DWDashPayIdentityKeys.registrationSpecifications(
                firstKeyId: Self.defaultKeyCount)
            pubkeys.append(contentsOf: try DWDashPayIdentityKeys.deriveAndPersist(
                wallet: wallet,
                identityIdString: "",
                identityIndex: Self.pinnedIdentityIndex,
                specifications: dashPaySpecifications,
                network: network))
            Self.logger.info("🪪 IDENT-COORD :: pre-derived \(pubkeys.count) keys including DashPay contact pair")
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: key derivation failed: \(String(describing: error))")
            failedAtPhase = .processingPayment
            lastErrorMessage = error.localizedDescription
            newController.enterFailed(error.localizedDescription)
            throw CoordinatorError.keyDerivation(error)
        }

        // Build the signer used by both IdentityCreate and DPNS
        // register. The signer's lifetime is the whole chain — the
        // FFI captures an unretained pointer to it, so we hold the
        // strong reference here for the duration of the awaits.
        let signer = KeychainSigner(modelContainer: modelContainer)

        // Step 2: IdentityCreate. Funding-source path, crash-resume
        // against the original Core asset lock, OR skipped entirely
        // if a prior attempt at this identity index already landed an
        // identity on Platform —
        // re-running IdentityCreate would fail with a unique-key
        // collision because the DIP-9 derived authentication keys
        // at `pinnedIdentityIndex` are deterministic per wallet and
        // already bound to the prior identity in Platform's unique-
        // key index. The resume path picks up the persisted
        // identityId from SwiftData and falls through to DPNS
        // register so a transient failure between IdentityCreate
        // success and DPNS register can be retried without leaving
        // the user stuck.
        newController.enterInFlight()
        let identityId: Identifier
        let fundedNow: Bool
        do {
            (identityId, fundedNow) = try await createOrRecoverIdentity(
                IdentityCreationContext(wallet: wallet, network: network, modelContainer: modelContainer,
                                        signer: signer, pubkeys: pubkeys, fundingSource: fundingSource,
                                        username: username, invitationURI: invitationURI,
                                        requiredIdentityFundingDuffs: UInt64(requiredIdentityFundingDuffs),
                                        remembersFundingSource: remembersFundingSource),
                recoveryLock: recoveryLock)
            Self.logger.info("🪪 IDENT-COORD :: identity created, id=\(identityId.map { String(format: "%02x", $0) }.joined().prefix(8))…")
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: identity creation failed: \(String(describing: error))")
            throw reportIdentityCreationFailure(error, controller: newController)
        }

        // An identity this run did not fund — reused from an earlier attempt,
        // or recovered from a lock paid for some other request — may hold less
        // than this name needs. A fresh one was funded for exactly this request.
        // An invitation voucher cannot top up, so that path never tries.
        let topUp: IdentityTopUpPlan? = fundedNow || currentFundingSource == .invitation
            ? nil
            // Capped at what the user confirmed, as on the resume path.
            : IdentityTopUpPlan(
                source: currentFundingSource, modelContainer: modelContainer,
                authorizedDuffs: authorizedTopUpDuffs,
                remembersFundingSource: remembersFundingSource && recoveryLock == nil)
        return try await finishUsernameRegistration(
            identityId: identityId, username: username, temporaryUsername: temporaryUsername,
            wallet: wallet, network: network, signer: signer, newController: newController,
            topUp: topUp)
    }

    /// Inputs captured before authorization; helpers never resolve a new wallet.
    private struct IdentityCreationContext {
        let wallet: ManagedPlatformWallet
        let network: Network
        let modelContainer: ModelContainer
        let signer: KeychainSigner
        let pubkeys: [ManagedPlatformWallet.IdentityPubkey]
        let fundingSource: DWIdentityFundingSource
        let username: String
        let invitationURI: String?
        let requiredIdentityFundingDuffs: UInt64
        /// The user picked `fundingSource` (see `recordAcceptedSource`).
        var remembersFundingSource = false
    }

    /// Submit only the selected funding route when no paid lock or identity exists.
    private func createFundedIdentity(_ context: IdentityCreationContext) async throws -> Identifier {
        // Called by each route right before it pays — after its own checks,
        // and never when a paid lock or an earlier identity is reused instead.
        let recordPick = {
            self.recordAcceptedSource(
                context.fundingSource, ifPicked: context.remembersFundingSource,
                label: context.username, walletId: context.wallet.walletId)
        }
        let wallet = context.wallet
        let modelContainer = context.modelContainer
        let signer = context.signer
        let pubkeys = context.pubkeys
        let username = context.username
        let invitationURI = context.invitationURI
        let requiredIdentityFundingDuffs = context.requiredIdentityFundingDuffs
        let identityId: Identifier
        switch context.fundingSource {
        case .core:
            recordPick()
            let result = try await wallet.registerIdentityWithFunding(
                amountDuffs: requiredIdentityFundingDuffs,
                accountIndex: Self.defaultAccountIndex,
                identityIndex: Self.pinnedIdentityIndex,
                identityPubkeys: pubkeys,
                signer: signer)
            identityId = result.0

        case .platformPayment:
            let targetCredits =
                UInt64(requiredIdentityFundingDuffs)
                * PlatformPaymentIdentityFundingPolicy.creditsPerDuff
            let inputs = try buildPlatformPaymentInputs(
                walletId: wallet.walletId,
                modelContainer: modelContainer,
                targetCredits: targetCredits)
            Self.logger.info("🪪 IDENT-COORD :: PP inputs=\(inputs.count) targetCredits=\(targetCredits)")
            recordPick()
            do {
                let created = try await wallet.registerIdentityFromAddresses(
                    inputs: inputs,
                    output: nil,
                    identityIndex: Self.pinnedIdentityIndex,
                    identityPubkeys: pubkeys,
                    identitySigner: signer,
                    addressSigner: signer)
                identityId = created.identityId
            } catch {
                guard Self.isPlatformAddressInsufficientFunds(error) else {
                    throw error
                }
                throw CoordinatorError.insufficientPlatformCredits(
                    required: PlatformPaymentIdentityFundingPolicy
                        .requiredAvailableCredits(
                            fundingDuffs: UInt64(requiredIdentityFundingDuffs)),
                    available: SwiftDashSDKWalletState.shared
                        .platformPaymentCredits)
            }

        case .shielded:
            identityId = try await createIdentityFromShieldedPool(
                username: username,
                walletId: wallet.walletId,
                modelContainer: modelContainer,
                pubkeys: pubkeys,
                signer: signer,
                beforeSpend: recordPick)

        case .invitation:
            // DIP-13 claim: register the invitee's identity funded
            // by the voucher embedded in the link. The SDK refetches
            // the funding tx and rebuilds the IS/CL proof itself;
            // key prep above is identical to every other source.
            guard let invitationURI else {
                throw CoordinatorError.missingInvitation
            }
            let managed = try await wallet.claimInvitation(
                uri: invitationURI,
                identityIndex: Self.pinnedIdentityIndex,
                identityPubkeys: pubkeys,
                signer: signer,
                nowUnix: UInt32(Date().timeIntervalSince1970))
            identityId = try managed.getId()
        }
        return identityId
    }

    /// Reuse a persisted identity or paid Core lock before considering new funding.
    /// `fundedNow` is true only when this call created and funded the identity
    /// for the current request.
    private func createOrRecoverIdentity(
        _ context: IdentityCreationContext, recoveryLock: RegistrationRecoveryLock?
    ) async throws -> (identityId: Identifier, fundedNow: Bool) {
        let wallet = context.wallet
        let modelContainer = context.modelContainer
        let signer = context.signer
        let pubkeys = context.pubkeys
        let identityId: Identifier
        if let existingId = lookupExistingIdentityId(
            walletId: wallet.walletId,
            modelContainer: modelContainer)
        {
            Self.logger.info("🪪 IDENT-COORD :: recovery — local identity exists at index \(Self.pinnedIdentityIndex), skipping IdentityCreate")
            identityId = existingId
            reconcileConsumedRecoveryLock(
                recoveryLock,
                identityId: existingId,
                walletId: wallet.walletId,
                modelContainer: modelContainer)
        } else if let recoveryLock {
            // The app may have died after Platform accepted
            // IdentityCreate but before the identity persister callback
            // reached SwiftData. Probe the deterministic DIP-9 slot
            // first; blindly resubmitting in that state produces the
            // unique-key collision from BUG-2.
            if let platformIdentityId = try await wallet.loadIdentity(
                atIndex: Self.pinnedIdentityIndex)
            {
                Self.logger.info("🪪 IDENT-COORD :: recovery — Platform identity found at index \(Self.pinnedIdentityIndex), skipping IdentityCreate")
                identityId = platformIdentityId
                reconcileConsumedRecoveryLock(
                    recoveryLock,
                    identityId: platformIdentityId,
                    walletId: wallet.walletId,
                    modelContainer: modelContainer)
            } else {
                guard let outPoint = Self.parseOutPointHex(recoveryLock.outPointHex) else {
                    throw NSError(
                        domain: "DWIdentityRegistrationCoordinator",
                        code: -2,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString(
                                "The pending registration payment could not be restored.",
                                comment: "DashPay registration recovery")
                        ])
                }
                Self.logger.info("🪪 IDENT-COORD :: recovery — resuming original asset lock vout=\(outPoint.vout)")
                let result = try await wallet.resumeIdentityWithAssetLock(
                    outPointTxid: outPoint.txidWire,
                    outPointVout: outPoint.vout,
                    identityIndex: Self.pinnedIdentityIndex,
                    identityPubkeys: pubkeys,
                    signer: signer)
                identityId = result.0
            }
        } else {
            return (try await createFundedIdentity(context), true)
        }
        return (identityId, false)
    }

    /// Preserve payment/creation failure phases independently of funding dispatch.
    private func reportIdentityCreationFailure(
        _ error: Error, controller: DWIdentityRegistrationController
    ) -> Error {
        if let coordError = error as? CoordinatorError {
            if case .shieldedCreateUnconfirmed = coordError {
                failedAtPhase = .creatingID
            } else {
                failedAtPhase = .processingPayment
            }
            lastErrorMessage = coordError.localizedDescription
            controller.enterFailed(coordError.localizedDescription)
            return coordError
        }
        switch currentFundingSource {
        case .core:
            failedAtPhase = assetLockStatus < 2 ? .processingPayment : .creatingID
        case .platformPayment, .shielded, .invitation:
            failedAtPhase = .creatingID
        }
        lastErrorMessage = error.localizedDescription
        controller.enterFailed(error.localizedDescription)
        return CoordinatorError.identityRegistration(error)
    }

    /// Registration for an identity that already exists. No IdentityCreate;
    /// when `topUpSource` is set and the identity holds less than the name
    /// needs, the shortfall is topped up from that source first (see
    /// `fundExistingIdentityIfNeeded`). nil registers on the existing credits.
    @discardableResult
    func resumeUsernameRegistration(
        identityId: Identifier,
        username: String,
        temporaryUsername: String? = nil,
        topUpSource: DWIdentityFundingSource? = nil,
        authorizedTopUpDuffs: UInt64? = nil,
        remembersFundingSource: Bool = false
    ) async throws -> Identifier {
        guard !isAttemptActive else {
            throw CoordinatorError.alreadyInFlight
        }
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              let container = SwiftDashSDKHost.shared.modelContainer,
              DWCurrentUserIdentityInfo.shared.isCurrentNetworkContextReady else {
            throw CoordinatorError.noWallet
        }
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        guard DWCurrentUserIdentityInfo.shared.identityId == identityId else {
            throw CoordinatorError.contextChanged
        }
        if let temporaryUsername {
            guard DWContestedNameStatusService.isContestedLabel(username),
                  !DWContestedNameStatusService.isContestedLabel(temporaryUsername) else {
                throw CoordinatorError.invalidTemporaryUsername
            }
        }
        resetState()
        currentUsername = username
        registrationWalletId = wallet.walletId
        registrationNetwork = network
        registrationNetworkScope = network.persistenceScope
        resumedIdentityId = identityId
        isRegisteringUsername = true
        // What the row reports if the top-up runs: the payment step is judged
        // by the source, as for a new identity.
        currentFundingSource = topUpSource ?? .core
        let newController = DWIdentityRegistrationController()
        controller = newController
        wireController(newController)
        newController.enterPreparingKeys() // reserves the slot while authentication is open
        defer { DWCurrentUserIdentityInfo.shared.refreshFromSDK() }
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            resetState()
            throw CoordinatorError.authCancelled
        } catch {
            lastErrorMessage = CoordinatorError.authFailed.localizedDescription
            newController.enterFailed(lastErrorMessage ?? "")
            throw CoordinatorError.authFailed
        }
        do {
            try validateRegistrationContext(walletId: wallet.walletId, network: network)
            // Restore signing material after seed recovery. Use this identity's
            // recorded derivation index, never assume the selected identity is 0.
            guard let index = try wallet.managedIdentity(identityId: identityId).getIdentityIndex() else {
                throw CoordinatorError.contextChanged
            }
            try wallet.prePersistIdentityKeysForRegistration(
                identityIndex: index, keyCount: Self.defaultKeyCount, network: network)
        } catch {
            lastErrorMessage = error.localizedDescription
            newController.enterFailed(error.localizedDescription)
            throw CoordinatorError.keyDerivation(error)
        }
        return try await finishUsernameRegistration(
            identityId: identityId, username: username, temporaryUsername: temporaryUsername,
            wallet: wallet, network: network, signer: KeychainSigner(modelContainer: container),
            newController: newController,
            topUp: topUpSource.map {
                IdentityTopUpPlan(
                    source: $0, modelContainer: container, authorizedDuffs: authorizedTopUpDuffs,
                    remembersFundingSource: remembersFundingSource)
            })
    }

    /// Whether the wallet+network scope the UsernamePrefs registration records
    /// key off is still this registration's. Narrower than
    /// `validateRegistrationContext`: a record only needs the scope, not an
    /// identity snapshot that may be mid-refresh.
    private func isRecordScopeCurrent(walletId: Data, network: Network) -> Bool {
        WalletEnvironment.network == network
            && (WalletEnvironment.activeWalletIdHex as String?) == walletId.hexEncodedString()
    }

    private func validateRegistrationContext(walletId: Data, network: Network) throws {
        guard SwiftDashSDKHost.shared.wallet?.walletId == walletId,
              SwiftDashSDKHost.shared.runningNetwork == network,
              isRecordScopeCurrent(walletId: walletId, network: network) else {
            throw CoordinatorError.contextChanged
        }
        if let resumedIdentityId {
            let snapshot = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
            guard !snapshot.isLoading, snapshot.identityId == resumedIdentityId else {
                throw CoordinatorError.contextChanged
            }
        }
    }

    func registrationNameState(
        _ username: String, identityId: Identifier, wallet: ManagedPlatformWallet
    ) async throws -> UsernameRegistrationRecoveryFlow.NameState {
        // A contested domain is not proof of ownership. Check the live vote first.
        if DWContestedNameStatusService.isContestedLabel(username),
           let vote = try await wallet.fetchContestVoteState(identityId: identityId, label: username) {
            switch vote.winner {
            case .none:
                if vote.contenders.contains(where: { $0.identityId == identityId }) { return .voting }
            case .wonByIdentity(let winner):
                guard winner == identityId else { throw CoordinatorError.usernameUnavailable }
                return .owned
            case .locked:
                throw CoordinatorError.usernameUnavailable
            }
        }
        if let owner = try await wallet.resolveDpnsName(username) {
            guard owner == identityId else { throw CoordinatorError.usernameUnavailable }
            return .owned
        }
        if DWContestedNameStatusService.isContestedLabel(username) {
            // The identity-scoped vote lookup can return nil for a resolved
            // contest or for another contender. A locked/closed poll still
            // prevents registration even though no identity owns the name.
            switch await UsernameMarketplaceService().contestPrecheck(label: username) {
            case .locked:
                throw CoordinatorError.usernameUnavailable
            case .activeContest(_, let endsAt):
                if let endsAt,
                   UsernameMarketplaceService.contenderJoinDeadline(voteEnd: endsAt) <= Date() {
                    throw CoordinatorError.usernameUnavailable
                }
            case .unknown:
                throw CoordinatorError.availabilityCheck(NSError(
                    domain: "DWIdentityRegistrationCoordinator", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                        "Could not check username availability. Please try again.", comment: "DashPay registration recovery")]))
            case .fresh:
                break
            }
        }
        return .available
    }

    /// How an existing identity is topped up before its name is registered:
    /// the source the user chose, and the store its Platform inputs are read
    /// from.
    private struct IdentityTopUpPlan {
        let source: DWIdentityFundingSource
        let modelContainer: ModelContainer
        /// The top-up the user confirmed; nil when no amount was shown.
        var authorizedDuffs: UInt64? = nil
        /// The user picked `source` (see `recordAcceptedSource`).
        var remembersFundingSource = false
    }

    private func finishUsernameRegistration(
        identityId: Identifier, username: String, temporaryUsername: String?,
        wallet: ManagedPlatformWallet, network: Network, signer: KeychainSigner,
        newController: DWIdentityRegistrationController,
        authorize: () async throws -> Void = {},
        topUp: IdentityTopUpPlan? = nil
    ) async throws -> Identifier {
        defer { DWCurrentUserIdentityInfo.shared.refreshFromSDK() }
        do {
            return try await registerNames(
                identityId: identityId, username: username, temporaryUsername: temporaryUsername,
                wallet: wallet, network: network, signer: signer, newController: newController,
                authorize: authorize, topUp: topUp)
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            throw DWIdentityAuthorizer.AuthError.cancelled
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: username step failed: \(String(describing: error))")
            isFundingExistingIdentity = false
            let isTopUpFailure = (error as? CoordinatorError)?.isIdentityTopUp == true
            failedAtPhase = isTopUpFailure ? .processingPayment : .registrationUsername
            lastErrorMessage = error.localizedDescription
            newController.enterFailed(error.localizedDescription)
            throw error
        }
    }

    /// Tops up an existing identity so it can pay for the names about to be
    /// registered — Android's `CreateIdentityService` does the same with a
    /// fresh asset lock when the username costs more than the identity holds.
    ///
    /// The balance is read live from Platform, never from the persisted row:
    /// the row can lag, and after an app kill between a landed top-up and the
    /// registration it is the live figure that shows the identity is already
    /// funded, so a retry does not pay a second time. If the read fails the
    /// attempt stops rather than guess.
    ///
    /// Sources: Core builds a new asset lock (`topUpIdentityWithFunding`),
    /// Platform spends DIP-17 address credits (`topUpFromAddresses`, inputs
    /// planned by `PlatformPaymentIdentityFundingPolicy`). Shielded has no
    /// top-up route in this flow — the SDK's pool top-up is not wired into
    /// the app — so it fails here, before anything is broadcast.
    private func fundExistingIdentityIfNeeded(
        identityId: Identifier, username: String, temporaryUsername: String?,
        plan: IdentityTopUpPlan, wallet: ManagedPlatformWallet, network: Network,
        signer: KeychainSigner, newController: DWIdentityRegistrationController
    ) async throws {
        let requiredCredits = Self.requiredRegistrationCredits(
            username: username, temporaryUsername: temporaryUsername)
        let heldCredits: UInt64
        do {
            heldCredits = try await wallet.refreshIdentityBalance(identityId: identityId)
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: identity balance read failed: \(String(describing: error))")
            throw CoordinatorError.identityTopUp(CoordinatorError.identityBalanceUnavailable)
        }
        let topUpDuffs = Self.identityTopUpDuffs(requiredCredits: requiredCredits, heldCredits: heldCredits)
        Self.logger.info("🪪 IDENT-COORD :: existing identity requiredCredits=\(requiredCredits) heldCredits=\(heldCredits) topUpDuffs=\(topUpDuffs) authorized=\(plan.authorizedDuffs.map(String.init) ?? "none") source=\(plan.source.logLabel)")
        guard topUpDuffs > 0 else { return }
        // No confirmed amount authorizes no top-up, not an unlimited one.
        guard let authorized = plan.authorizedDuffs else {
            throw CoordinatorError.identityTopUp(CoordinatorError.topUpNotConfirmed(neededDuffs: topUpDuffs))
        }
        // The confirmation showed a top-up from the persisted balance; the
        // live one can be higher. Never move more than the user confirmed —
        // stop before any spend and let them confirm the new amount.
        if authorized == 0 {
            // Nothing was shown because nothing looked needed; say that rather
            // than "more than the 0 DASH you confirmed".
            throw CoordinatorError.identityTopUp(CoordinatorError.topUpNotConfirmed(neededDuffs: topUpDuffs))
        }
        if topUpDuffs > authorized {
            throw CoordinatorError.identityTopUp(
                CoordinatorError.topUpExceedsConfirmed(neededDuffs: topUpDuffs, confirmedDuffs: authorized))
        }

        // Re-emitting `.inFlight` is what makes the bridge re-read the step:
        // the flag alone publishes nothing.
        isFundingExistingIdentity = true
        newController.enterInFlight()
        do {
            try validateRegistrationContext(walletId: wallet.walletId, network: network)
            switch plan.source {
            case .core:
                let spendableDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
                guard spendableDuffs >= topUpDuffs else {
                    throw CoordinatorError.insufficientCoreBalanceForTopUp(
                        neededDuffs: topUpDuffs, availableDuffs: spendableDuffs)
                }
                recordAcceptedSource(
                    plan.source, ifPicked: plan.remembersFundingSource, label: username, walletId: wallet.walletId)
                _ = try await wallet.topUpIdentityWithFunding(
                    identityId: identityId,
                    amountDuffs: topUpDuffs,
                    accountIndex: Self.defaultAccountIndex)
            case .platformPayment:
                let inputs = try buildPlatformPaymentInputs(
                    walletId: wallet.walletId,
                    modelContainer: plan.modelContainer,
                    targetCredits: topUpDuffs * PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
                recordAcceptedSource(
                    plan.source, ifPicked: plan.remembersFundingSource, label: username, walletId: wallet.walletId)
                _ = try await wallet.topUpFromAddresses(
                    identityId: identityId,
                    inputs: inputs,
                    addressSigner: signer)
                SwiftDashSDKWalletState.shared.refreshPlatformPaymentCredits()
            case .shielded:
                throw CoordinatorError.shieldedTopUpUnavailable(neededDuffs: topUpDuffs)
            case .invitation:
                // Callers never plan a voucher top-up; register on what is held.
                break
            }
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: existing identity top-up failed: \(String(describing: error))")
            throw CoordinatorError.identityTopUp(error)
        }
        Self.logger.info("🪪 IDENT-COORD :: existing identity topped up by \(topUpDuffs) duffs")
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        isFundingExistingIdentity = false
        newController.enterInFlight()
    }

    /// Drops the step-2.9 bookmark for a submission that never reached the
    /// network. Safe to call when none was written.
    private func withdrawPrematureBookmark(
        _ username: String, isContested: Bool, network: Network, wallet: ManagedPlatformWallet
    ) {
        guard isContested else { return }
        DWContestedNameStatusService.shared.clearPending(
            label: username, for: network, walletId: wallet.walletId)
    }

    private func registerNames(
        identityId: Identifier, username: String, temporaryUsername: String?,
        wallet: ManagedPlatformWallet, network: Network, signer: KeychainSigner,
        newController: DWIdentityRegistrationController,
        authorize: () async throws -> Void,
        topUp: IdentityTopUpPlan?
    ) async throws -> Identifier {
        try validateRegistrationContext(walletId: wallet.walletId, network: network)
        isRegisteringUsername = true
        assetLockPollingTask?.cancel()
        let registrationContainer = SwiftDashSDKHost.shared.modelContainer
        let draftScope = UsernameRegistrationDraftStore.Scope(
            network: network.persistenceScope, walletId: wallet.walletId, identityId: identityId)
        try UsernameRegistrationDraftStore().save(
            .init(username: username, temporaryUsername: temporaryUsername), for: draftScope)
        let isContestedSubmission = DWContestedNameStatusService.isContestedLabel(username)
        var nameState = UsernameRegistrationRecoveryFlow.NameState.available
        // Step 2.9: bookmark a contested submission BEFORE the document exists.
        //
        // `registerDpnsName` below creates the DPNS domain document for a
        // contested label too — voting only decides who keeps it — while the
        // bookmark that marks it as "not ours yet" used to be written at step
        // 3.5. Everything that filters in-flight contested labels reads that
        // bookmark, so for the whole submission the app treated the name as
        // owned: More offered a Profile row for it, and the request-status
        // screen (whose entry guards on `pendingLabel`) could not be opened at
        // all, which made the row's ⓘ a dead control.
        //
        // Written from the local predicate — no network needed to know a label
        // is contested — and withdrawn again if the registration throws, or if
        // step 3.5 finds the name was already ours.
        //
        // Provisional until step 3.5 confirms it: an app killed before the DPNS
        // write returns never reaches either path, and a marker from an earlier
        // launch must not read as a submitted request (see
        // `reconcileProvisionalSubmission`).
        if isContestedSubmission {
            DWContestedNameStatusService.shared.recordSubmission(
                label: username, network: network, identityId: identityId, walletId: wallet.walletId,
                promoteOnWin: true, provisional: true)
        }

        // Step 3: reconcile first; an RPC failure never implies availability.
        do {
            nameState = try await UsernameRegistrationRecoveryFlow.run(
                authorize: authorize,
                validateContext: {
                    try self.validateRegistrationContext(walletId: wallet.walletId, network: network)
                },
                lookup: {
                    newController.enterInFlight()
                    return try await self.registrationNameState(
                        username, identityId: identityId, wallet: wallet)
                },
                register: {
                    // Only once the lookup says the name is still to be
                    // registered: a retry of a submission that already landed
                    // must not pay for it again.
                    if let topUp {
                        try await self.fundExistingIdentityIfNeeded(
                            identityId: identityId, username: username,
                            temporaryUsername: temporaryUsername, plan: topUp,
                            wallet: wallet, network: network, signer: signer,
                            newController: newController)
                    }
                    _ = try await wallet.registerDpnsName(
                        identityId: identityId, name: username, signer: signer)
                })
            Self.logger.info("🪪 IDENT-COORD :: DPNS name registered: \(username)")
            // A request for another name is now on Platform: an earlier one's
            // missing instant name is no longer what to report. Settled here,
            // after authorization and the write, so a cancelled or refused
            // attempt — on any entry point, the invitation claim included —
            // leaves it in place; a retry of that same name keeps it too.
            if isRecordScopeCurrent(walletId: wallet.walletId, network: network) {
                UsernamePrefs.shared.clearFailedCompanion(unlessUsername: username)
            }
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            withdrawPrematureBookmark(
                username, isContested: isContestedSubmission, network: network, wallet: wallet)
            throw DWIdentityAuthorizer.AuthError.cancelled
        } catch let error as CoordinatorError where error.isIdentityTopUp {
            // Nothing reached DPNS; keep the typed error so the failure is
            // reported at the payment step.
            withdrawPrematureBookmark(
                username, isContested: isContestedSubmission, network: network, wallet: wallet)
            throw error
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: DPNS registration failed: \(String(describing: error))")
            // Nothing was submitted, so nothing is out for a vote — leaving the
            // step-2.9 bookmark would report a contest that does not exist.
            withdrawPrematureBookmark(
                username, isContested: isContestedSubmission, network: network, wallet: wallet)
            throw CoordinatorError.dpnsRegistration(error)
        }

        if !isContestedSubmission || nameState == .owned {
            DWCurrentUserIdentityInfo.persistConfirmedUsername(
                username, identityId: identityId, walletId: wallet.walletId, container: registrationContainer)
        }

        // Step 3.5: branch on contested-name status. The SDK uses the
        // same `registerDpnsName` call for contested and uncontested
        // labels, but the on-chain effect differs: a contested name
        // is "preregistered" pending masternode voting (~90 min
        // testnet, ~2 weeks mainnet). The label is NOT actually
        // claimed until the vote resolves. We:
        //   1. Bookmark the submission via DWContestedNameStatusService
        //      so the CreateUsername form can detect the in-flight
        //      submission on relaunch and swap to the status screen.
        //   2. Refresh the SDK's contested-names cache so a
        //      subsequent `getContestedDpnsNames()` read sees the
        //      label (otherwise we'd race against the next idle
        //      sync).
        //   3. Skip the DWGlobalOptions mirror writes in
        //      `handlePhaseChange` — they run when
        //      `checkPendingContestResolution()` detects the win and
        //      calls `DWContestedNameStatusService.finalizeWon(username:)`.
        Self.logger.info("🪪 IDENT-COORD :: contested=\(isContestedSubmission) label=\(username)")
        if isContestedSubmission && nameState != .owned {
            // Persist a conservative network-scoped deadline together with
            // the label BEFORE the first vote-state read. Platform can
            // legitimately return nil until the contest is indexed; without
            // this fallback a relaunch after resolution would have no safe
            // point from which to query canonical ownership. Also confirms the
            // provisional step-2.9 marker: the request is in.
            DWContestedNameStatusService.shared.recordSubmission(
                label: username,
                network: network, identityId: identityId, walletId: wallet.walletId,
                promoteOnWin: true)
            do {
                _ = try await wallet.syncContestedDpnsNames(identityId: identityId)
                Self.logger.info("🪪 IDENT-COORD :: contested-names cache synced")
            } catch {
                Self.logger.warning("🪪 IDENT-COORD :: syncContestedDpnsNames failed: \(String(describing: error))")
            }
            do {
                if let voteState = try await wallet.fetchContestVoteState(
                    identityId: identityId,
                    label: username) {
                    DWContestedNameStatusService.shared
                        .recordVotingEndTime(voteState.endTime, label: username, network: network, walletId: wallet.walletId)
                }
            } catch {
                Self.logger.warning("🪪 IDENT-COORD :: initial contest vote-state fetch failed: \(String(describing: error))")
            }
        }

        // Step 3.6: companion (temporary) username. The contested label
        // above is only preregistered — it belongs to nobody until the
        // vote resolves — so the user asked for a second, non-contested
        // name to be reachable at in the meantime. Same identity, same
        // signer, no additional PIN prompt. Failure is deliberately
        // non-fatal: the contested submission (the primary intent, and
        // the user's locked funds) already succeeded, so the flow
        // completes and the form reports the partial outcome from
        // `temporaryUsernameError`.
        if let temporaryUsername, isContestedSubmission {
            do {
                _ = try await UsernameRegistrationRecoveryFlow.run(
                    authorize: {},
                    validateContext: {
                        try self.validateRegistrationContext(walletId: wallet.walletId, network: network)
                    },
                    lookup: {
                        try await self.registrationNameState(
                            temporaryUsername, identityId: identityId, wallet: wallet)
                    },
                    register: {
                        _ = try await wallet.registerDpnsName(
                            identityId: identityId, name: temporaryUsername, signer: signer)
                    })
                DWCurrentUserIdentityInfo.persistConfirmedUsername(
                    temporaryUsername, identityId: identityId, walletId: wallet.walletId, container: registrationContainer)
                registeredTemporaryUsername = temporaryUsername
                if isRecordScopeCurrent(walletId: wallet.walletId, network: network) {
                    // This request now has its instant name, whichever one
                    // failed before.
                    UsernamePrefs.shared.clearFailedCompanion(forContestedLabel: username)
                }
                Self.logger.info("🪪 IDENT-COORD :: temporary DPNS name registered: \(temporaryUsername)")
                // Push the new label into the identity read model right
                // away (same post-registration refresh the marketplace's
                // `register(label:)` does) so profile/username surfaces
                // don't wait for the next Home-appear sync.
                DWCurrentUserIdentityInfo.shared.refreshFromSDK()
            } catch {
                temporaryUsernameError = error.localizedDescription
                Self.logger.error("🪪 IDENT-COORD :: temporary DPNS registration failed: \(String(describing: error))")
                // Kept past this attempt: the form has usually handed off to
                // the status row by now, so Request details is where the user
                // learns the instant name is missing and can try it again.
                // Written only while the registration's wallet and network are
                // still the active ones, which is the scope the record uses.
                if isRecordScopeCurrent(walletId: wallet.walletId, network: network) {
                    UsernamePrefs.shared.failedCompanion = .init(
                        username: temporaryUsername,
                        contestedLabel: username,
                        // Raw, worded when shown: the wording follows the
                        // app's language at display time.
                        reason: error.localizedDescription)
                } else {
                    Self.logger.warning("🪪 IDENT-COORD :: failed instant username not recorded — the active wallet or network changed")
                }
            }
        }

        // Step 3.7: the proof-of-identity link, when the user gave one before
        // submitting. Published here for the same reason the companion name is:
        // the identity exists, the signer is authorized, and masternode owners
        // can only weigh the link while the vote is open. Non-fatal — the
        // request is already in, and the link can be added later from
        // "Request details".
        if let verificationURL = pendingVerificationURL, isContestedSubmission {
            pendingVerificationURL = nil
            do {
                // The awaits above (registration, contested-name sync, vote
                // state) leave room for a wallet or network switch; a document
                // written after one would land for the wrong context. Skipped,
                // not retried: the link can still be added from "Request
                // details".
                try validateRegistrationContext(walletId: wallet.walletId, network: network)
                try await IdentityVerifyService.shared.publish(
                    url: verificationURL,
                    forLabel: username,
                    identityId: identityId,
                    wallet: wallet,
                    network: network,
                    signer: signer)
            } catch CoordinatorError.contextChanged {
                Self.logger.info("🪪 IDENT-COORD :: identity-verify publish skipped: registration context changed")
            } catch {
                Self.logger.error("🪪 IDENT-COORD :: identity-verify publish failed: \(String(describing: error))")
            }
        }

        // Refresh confirmed ownership in the SDK cache and persistence, including
        // reconciliation which skipped broadcasting an already-owned name.
        if !isContestedSubmission || nameState == .owned || registeredTemporaryUsername != nil {
            _ = try? await wallet.syncDpnsNames(identityId: identityId)
        }

        // Step 4: mark complete + mirror to DWGlobalOptions. The
        // controller transition triggers the phaseSubscription
        // sink which posts the notification + writes
        // DWGlobalOptions (skipped for contested submissions —
        // see handlePhaseChange).
        if nameState == .owned {
            DWContestedNameStatusService.shared.clearPending(label: username, for: network, walletId: wallet.walletId)
        }
        if temporaryUsernameError == nil {
            UsernameRegistrationDraftStore().clear(for: draftScope)
        }
        do {
            try validateRegistrationContext(walletId: wallet.walletId, network: network)
        } catch {
            // Preserve the successful result and original scoped bookkeeping;
            // never mirror it into a newly selected wallet or report failure.
            resetState()
            completedRegistrationContextMessage = NSLocalizedString(
                "The name request succeeded for the original identity. Switch back to the original wallet and network to see its status.",
                comment: "DashPay registration context changed")
            Self.logger.info("DPNS completed in original context; current UI reconciliation deferred")
            return identityId
        }
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        newController.enterCompleted(identityId: identityId)
        Self.logger.info("🪪 IDENT-COORD :: registration complete")

        // Completion bookkeeping and the success return must not depend on this
        // optional network read. Keep the captured wallet/network guards inside
        // the refresh so a later context switch cannot publish into another wallet.
        Task { @MainActor in
            await DWCurrentUserIdentityInfo.shared.refreshBalanceFromNetwork(
                identityId: identityId, wallet: wallet, network: network)
        }
        return identityId
    }

    /// DIP-13 invitation claim: register this wallet's identity funded
    /// by the invitation voucher, then register `username` via DPNS.
    /// Same PIN gate / key prep / phase reporting / resume semantics as
    /// `startCreateUsername` — a claim that lands IdentityCreate but
    /// fails DPNS retries past the (already consumed) voucher via the
    /// persisted-identity resume path.
    ///
    /// `invitationURI` must be the normalized `dashpay://invite` /
    /// applink URI (see `DWInvitationLinkNormalizer`); structural
    /// validation should have happened in the redeem UI, but claim-time
    /// SDK errors (malformed link, already-claimed voucher, wrong
    /// network) surface here as `.identityRegistration`.
    @discardableResult
    func startClaimInvitation(
        username: String,
        invitationURI: String,
        temporaryUsername: String? = nil,
        verificationURL: URL? = nil
    ) async throws -> Identifier {
        try await startCreateUsername(
            username,
            fundingSource: .invitation,
            invitationURI: invitationURI,
            temporaryUsername: temporaryUsername,
            verificationURL: verificationURL)
    }

    /// Direct purchase of a marketplace-listed name from the
    /// create-username flow: ensure this wallet's identity exists and
    /// holds enough credits — creating it Core-funded, or topping it up
    /// from the wallet balance — then buy at exactly `priceCredits`.
    ///
    /// Core funding only: the form offers this purchase against the
    /// wallet balance, and the marketplace's own buy sheet remains the
    /// path for already-funded identities
    /// (`UsernameMarketplaceService.purchase`). Same PIN gate /
    /// single-flight / phase reporting as `startCreateUsername`; the
    /// `.completed` transition performs the DWGlobalOptions mirror
    /// writes (a purchase never writes a contested bookmark, so the
    /// deferral branch in `handlePhaseChange` cannot trigger).
    @discardableResult
    func startPurchaseUsername(name: String, priceCredits: UInt64) async throws -> Identifier {
        Self.logger.info("🪪 IDENT-COORD :: startPurchaseUsername name=\(name) priceCredits=\(priceCredits)")

        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw CoordinatorError.noWallet
        }
        guard let network = SwiftDashSDKHost.shared.runningNetwork else {
            throw CoordinatorError.noNetwork
        }
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            throw CoordinatorError.noModelContainer
        }

        let identitySnapshot = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
        guard !identitySnapshot.isLoading else { throw CoordinatorError.noWallet }
        let selectedIdentityId = identitySnapshot.identityId

        // Single-flight — same rationale as `startCreateUsername`: the
        // funding FFI calls race to their terminal even if we stop
        // observing, and two funding attempts must never overlap.
        guard !isAttemptActive else {
            Self.logger.warning("🪪 IDENT-COORD :: rejecting concurrent purchase; phase=\(String(describing: phase))")
            throw CoordinatorError.alreadyInFlight
        }
        resetState()
        currentUsername = name
        registrationWalletId = wallet.walletId
        registrationNetwork = network
        registrationNetworkScope = network.persistenceScope
        currentFundingSource = .core

        let newController = DWIdentityRegistrationController()
        controller = newController
        wireController(newController)
        newController.enterPreparingKeys()
        // Both funding branches below (IdentityCreate, top-up) move value
        // through a Core asset lock, so the polling applies as in the
        // Core-funded registration path.
        startAssetLockPolling(walletId: wallet.walletId, modelContainer: modelContainer)

        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            resetState()
            throw CoordinatorError.authCancelled
        } catch {
            lastErrorMessage = CoordinatorError.authFailed.localizedDescription
            newController.enterFailed(lastErrorMessage ?? "")
            throw CoordinatorError.authFailed
        }

        do {
            try validatePurchaseContext(walletId: wallet.walletId, network: network, identityId: selectedIdentityId)
        } catch {
            newController.enterFailed(error.localizedDescription)
            throw error
        }

        // Credits the buyer identity must hold: the sale price plus the
        // same 0.03-DASH headroom a fresh registration funds itself with,
        // covering the purchase transition fee (and Core-side asset-lock
        // conversion losses).
        let headroomDuffs = DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        let requiredCredits = priceCredits + headroomDuffs * 1_000
        let signer = KeychainSigner(modelContainer: modelContainer)

        let identityId: Identifier
        do {
            if let existingId = selectedIdentityId {
                identityId = existingId
                newController.enterInFlight()
                // Top up only the shortfall. The persisted balance can lag
                // the chain; the headroom absorbs small drift, and the SDK
                // still pre-flights the real balance inside the purchase.
                let heldCredits = UsernameMarketplaceService.identityBalanceCredits(
                    identityId: existingId,
                    container: modelContainer)
                if heldCredits < requiredCredits {
                    // Rust rejects Core top-ups below `minimumCoreTopUpDuffs`,
                    // and a near-covered identity can shortfall under it.
                    let shortfallDuffs = max(
                        (requiredCredits - heldCredits + 999) / 1_000,
                        Self.minimumCoreTopUpDuffs)
                    Self.logger.info("🪪 IDENT-COORD :: purchase top-up shortfallDuffs=\(shortfallDuffs)")
                    _ = try await wallet.topUpIdentityWithFunding(
                        identityId: existingId,
                        amountDuffs: shortfallDuffs,
                        accountIndex: Self.defaultAccountIndex)
                }
            } else {
                // Fresh identity, funded with the full purchase amount.
                // Key prep is identical to the registration path.
                newController.enterPreparingKeys()
                var pubkeys = try wallet.prePersistIdentityKeysForRegistration(
                    identityIndex: Self.pinnedIdentityIndex,
                    keyCount: Self.defaultKeyCount,
                    network: network)
                pubkeys.append(contentsOf: try DWDashPayIdentityKeys.deriveAndPersist(
                    wallet: wallet,
                    identityIdString: "",
                    identityIndex: Self.pinnedIdentityIndex,
                    specifications: DWDashPayIdentityKeys.registrationSpecifications(
                        firstKeyId: Self.defaultKeyCount),
                    network: network))
                newController.enterInFlight()
                let fundingDuffs = (requiredCredits + 999) / 1_000
                let result = try await wallet.registerIdentityWithFunding(
                    amountDuffs: fundingDuffs,
                    accountIndex: Self.defaultAccountIndex,
                    identityIndex: Self.pinnedIdentityIndex,
                    identityPubkeys: pubkeys,
                    signer: signer)
                identityId = result.0
            }
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: purchase funding failed: \(String(describing: error))")
            failedAtPhase = assetLockStatus < 2 ? .processingPayment : .creatingID
            lastErrorMessage = error.localizedDescription
            newController.enterFailed(error.localizedDescription)
            throw CoordinatorError.identityRegistration(error)
        }

        // The purchase itself — exact-price: the SDK pre-flights the
        // listing and the buyer's balance, and consensus rejects any
        // seller-side price change (typed `.priceChanged`). The trade
        // index keys on the normalized label.
        do {
            try validatePurchaseContext(walletId: wallet.walletId, network: network, identityId: selectedIdentityId)
            let normalized = (try? SwiftDashSDKHost.shared.sdk?.dpnsNormalizeLabel(name))
                .flatMap { $0 } ?? name.lowercased()
            _ = try await wallet.purchaseDpnsName(
                purchaserIdentityId: identityId,
                name: normalized,
                expectedPriceCredits: priceCredits,
                signer: signer)
            Self.logger.info("🪪 IDENT-COORD :: purchased \(name) for \(priceCredits) credits")
            // Bought now: an earlier lost contest for it no longer hides it.
            // The label as asked for; the store matches DPNS-normalized forms.
            DWContestedNameStatusService.shared.clearRejected(
                label: name, for: network, identityId: identityId, walletId: wallet.walletId)
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: purchase failed: \(String(describing: error))")
            failedAtPhase = .registrationUsername
            let coordError = CoordinatorError.purchase(error)
            lastErrorMessage = coordError.localizedDescription
            newController.enterFailed(lastErrorMessage ?? "")
            throw coordError
        }

        // The name now points at this identity — but a purchase writes
        // marketplace rows, not the `dpns_names` cache every username
        // surface reads. Pull the name into that cache, then adopt the
        // identity through the same reconciliation the seed-recovery path
        // uses: main-identity bookmark, DWGlobalOptions mirrors from SDK
        // truth, contacts refresh, and the canonical registration
        // notification that installs the DashPay tabs. (The bare
        // phase-completion below is NOT enough for an identity that
        // arrived outside the bridge — DWDashPayModel deliberately
        // ignores bridge events without a registration username.)
        do {
            _ = try await wallet.syncDpnsNames(identityId: identityId)
        } catch {
            // The reconcile falls back to persisted rows; the Home-appear
            // syncFromNetwork retries the cache pull.
            Self.logger.warning("🪪 IDENT-COORD :: post-purchase syncDpnsNames failed: \(String(describing: error))")
        }
        let adoptedInCurrentContext = UsernamePurchaseCompletion.reconcileIfCurrent(
            isCurrent: {
                SwiftDashSDKHost.shared.wallet?.walletId == wallet.walletId
                    && SwiftDashSDKHost.shared.runningNetwork == network
                    && WalletEnvironment.network == network
                    && DWCurrentUserIdentityInfo.shared.refreshedSnapshot().identityId == identityId
            },
            reconcile: {
                // Bought from the create-username flow, so it becomes the main
                // name — recorded before the reconcile, which mirrors
                // `usernames.first`.
                DWCurrentUserIdentityInfo.shared.promoteToMainName(
                    name, identityId: identityId, walletId: wallet.walletId, network: network)
                _ = DWCurrentUserIdentityInfo.shared.reconcileRecoveredIdentity()
            })
        guard adoptedInCurrentContext else {
            // The purchase is final. Do not mark it failed/retryable or mutate
            // the new wallet's mirrors through a normal completed transition.
            resetState()
            throw CoordinatorError.purchaseCompletedInOriginalContext(name: name, identityId: identityId)
        }
        // The reconcile adopted the CANONICAL SDK label into the mirrors.
        // Align `currentUsername` with it before the `.completed`
        // transition, whose mirror write would otherwise overwrite the
        // adopted label with the buyer's raw typed form (any casing that
        // normalizes equal can buy the name).
        if let adopted = DWGlobalOptions.sharedInstance().dashpayUsername, !adopted.isEmpty {
            currentUsername = adopted
        }
        newController.enterCompleted(identityId: identityId)
        Self.logger.info("🪪 IDENT-COORD :: purchase complete")
        return identityId
    }

    /// Revalidate the selected identity as well as wallet/network after authorization
    /// and funding, before another operation can spend the captured context's funds.
    private func validatePurchaseContext(walletId: Data, network: Network, identityId: Data?) throws {
        try validateRegistrationContext(walletId: walletId, network: network)
        if let identityId, DWCurrentUserIdentityInfo.shared.refreshedSnapshot().identityId != identityId {
            throw CoordinatorError.contextChanged
        }
    }

    /// Restart the flow after a `.failed` terminal phase. Identical
    /// to `startCreateUsername(_:fundingSource:)` — the prior
    /// controller is discarded and a fresh attempt runs end-to-end.
    /// The Keychain-persisted identity keys from the prior attempt
    /// are overwritten during pre-derive. Invitation attempts retry
    /// through `startClaimInvitation` (the URI is required), not here.
    @discardableResult
    func retry(
        _ username: String,
        fundingSource: DWIdentityFundingSource = .core,
        temporaryUsername: String? = nil,
        authorizedTopUpDuffs: UInt64? = nil,
        remembersFundingSource: Bool = false
    ) async throws -> Identifier {
        Self.logger.info("🪪 IDENT-COORD :: retry username=\(username) funding=\(fundingSource.logLabel)")
        return try await startCreateUsername(
            username,
            fundingSource: fundingSource,
            temporaryUsername: temporaryUsername,
            authorizedTopUpDuffs: authorizedTopUpDuffs,
            remembersFundingSource: remembersFundingSource)
    }

    /// Clear terminal state. An active FFI operation cannot be cancelled, so
    /// retain its single-flight guard until it actually completes.
    func cancel() {
        Self.logger.info("🪪 IDENT-COORD :: cancel")
        guard !isAttemptActive else { return }
        resetState()
    }

    /// Forward DPNS availability checks to the SDK. Used by
    /// `DWCheckExistenceUsernameValidationRule` (legacy form) and
    /// `CreateUsernameViewModel.checkIfBlocked` (SwiftUI form) to replace
    /// `DSIdentitiesManager.searchIdentityByDashpayUsername:`.
    func dpnsCheckAvailability(_ name: String) async throws -> Bool {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            throw CoordinatorError.noSDK
        }
        do {
            return try await sdk.dpnsCheckAvailability(name: name)
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: dpns availability check failed: \(String(describing: error))")
            throw CoordinatorError.availabilityCheck(error)
        }
    }

    func registrationRecovery() -> UsernameRegistrationRecovery {
        guard DWCurrentUserIdentityInfo.shared.isCurrentNetworkContextReady,
              let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer else { return .none }
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        let snapshot = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
        guard !snapshot.isLoading else { return .none }
        if snapshot.hasIdentity { return snapshot.registrationRecovery }
        return lookupRegistrationRecoveryLock(walletId: wallet.walletId, modelContainer: container) == nil
            ? .none : .pendingCoreAssetLock
    }

    func pendingUsernameDraft() -> UsernameRegistrationDraftStore.Draft? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              let id = registrationRecovery().identityId else { return nil }
        return UsernameRegistrationDraftStore().draft(for: .init(
            network: network.persistenceScope, walletId: wallet.walletId, identityId: id))
    }

    // MARK: - Contested-name resolution

    /// Fire-and-forget reconciliation of the pending contested-DPNS
    /// submission (recorded by `recordSubmission` at submit time) against
    /// Platform's resolved state. Triggered from Home appear / app
    /// foreground; O(1) no-op when nothing is pending. Never throws — a
    /// failed check logs and retries on the next trigger.
    ///
    /// Outcomes: `ContestVoteState.winner` is us →
    /// `finalizeWon(username:)` performs the DWGlobalOptions mirror writes
    /// deferred by `handlePhaseChange`; another winner / locked / a contest
    /// that disappeared after its recorded deadline → clear the bookmark;
    /// still voting or not indexed yet → nothing. `getDpnsNames()` alone is
    /// never proof of a win because preregistration writes that document
    /// before voting begins.
    ///
    /// Appear/foreground alone left a vote that ended while the app stayed
    /// open reading "Voting" until the user happened to switch screens, so
    /// every pass also schedules the next one against the earliest deadline
    /// (`scheduleNextContestCheck`).
    func checkPendingContestResolution() {
        let service = DWContestedNameStatusService.shared
        guard !service.pendingLabels.isEmpty || !service.provisionalLabels.isEmpty else {
            // Nothing bookmarked. On a wallet restored mid-vote that is not
            // "nothing to do" — the bookmark lives in UserDefaults, scoped per
            // wallet + network, so a restore starts with none while the request
            // is still out for a vote. Ask Platform instead of offering the
            // user a second registration for a name they may already win.
            recoverPendingContestsIfNeeded()
            return
        }
        guard contestResolutionTask == nil else { return } // single-flight
        switch phase {
        case .preparingKeys, .inFlight:
            return // don't reconcile mid-registration
        case .idle, .completed, .failed:
            break
        }
        contestResolutionTask = Task { [weak self] in
            await self?.runPendingContestResolution()
            self?.contestResolutionTask = nil
            self?.scheduleNextContestCheck()
        }
    }

    /// Re-check a pending contest shortly after its deadline, and keep
    /// re-checking every minute past it: Platform settles the poll at the
    /// first block after the end, and the vote state can lag that. Before
    /// the deadline the wait is capped, so a stale or fallback deadline
    /// cannot put the check to sleep for the whole mainnet window.
    /// A suspended app does not run the timer; foregrounding triggers a
    /// check of its own, which reschedules.
    private func scheduleNextContestCheck() {
        contestTimerTask?.cancel()
        contestTimerTask = nil
        guard let network = WalletEnvironment.network else { return }
        let service = DWContestedNameStatusService.shared
        let labels = service.pendingLabels(for: network)
        guard !labels.isEmpty else { return }

        let now = Date()
        let nextDeadline = labels
            .compactMap { service.pendingVotingEndTime(label: $0, for: network) }
            .filter { $0 > now }
            .min()
        let delay: TimeInterval
        if let nextDeadline {
            delay = min(nextDeadline.timeIntervalSince(now) + 20, 30 * 60)
        } else {
            delay = 60
        }
        contestTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.checkPendingContestResolution()
        }
    }

    /// Rebuilds contested bookmarks for an identity whose local record is
    /// gone — a restore from seed, or a reinstall.
    ///
    /// Platform is the authority: our identity is a contender in an unresolved
    /// contest, or it is not. Read through `activeContests` (async, off the
    /// main thread) rather than the per-identity query, which is a synchronous
    /// main-actor FFI call and would freeze Home on every appear.
    ///
    /// Runs once per launch per wallet + network, and only for an identity
    /// with no username of its own — the state where the app would otherwise
    /// invite a second, paid registration.
    private func recoverPendingContestsIfNeeded() {
        guard contestRecoveryTask == nil else { return }
        switch phase {
        case .preparingKeys, .inFlight:
            return
        case .idle, .completed, .failed:
            break
        }
        guard let network = WalletEnvironment.network else { return }
        guard let identityId = DWCurrentUserIdentityInfo.shared.identityId else { return }
        // The wallet this identity belongs to, pinned now: the recovered
        // bookmarks are written after a network round trip, and an omitted
        // wallet scope resolves to whichever wallet is active by then.
        guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
              (WalletEnvironment.activeWalletIdHex as String?) == walletId.hexEncodedString()
        else { return }
        // Deliberately NOT gated on "this wallet owns no username": the flow
        // this recovery exists for — a contested request with an instant
        // companion registered beside it — leaves the wallet owning a name
        // while its contested one is still out for a vote. The caller already
        // establishes the only condition that matters: no bookmark is held.

        let scope = "\(network.rawValue):\(ScriptAddressCodec.base58Encode(identityId))"
        guard Self.attemptedContestRecoveries.insert(scope).inserted else { return }

        contestRecoveryTask = Task { [weak self] in
            await self?.runPendingContestRecovery(identityId: identityId, walletId: walletId, network: network)
            self?.contestRecoveryTask = nil
        }
    }

    private func runPendingContestRecovery(identityId: Data, walletId: Data, network: Network) async {
        let myIdentity = ScriptAddressCodec.base58Encode(identityId)
        let contests: [DPNSContest]
        do {
            contests = try await ContestedNamesService().activeContests()
        } catch {
            // Transient: the scope stays marked for this launch, and the next
            // one retries. Recovery must not turn into a per-appear query.
            Self.logger.info("🪪 IDENT-COORD :: contest recovery — list failed: \(String(describing: error))")
            return
        }

        let mine = contests.filter { contest in
            contest.contenders.contains { $0.identityId == myIdentity }
        }
        guard !mine.isEmpty else { return }

        let service = DWContestedNameStatusService.shared
        for contest in mine {
            // The spelling this identity actually requested, when the FFI could
            // decode it — the normalized form is what Platform indexes, not
            // what the user typed.
            let label = contest.contenders
                .first { $0.identityId == myIdentity }?
                .displayLabel
                // Our own contender document did not decode. When the whole
                // contest requested a single spelling, that spelling is also
                // ours — no guessing involved. With two or more, keep the
                // normalized form rather than adopt someone else's name.
                ?? (contest.requestedLabels.count == 1 ? contest.requestedLabels[0] : nil)
                ?? contest.normalizedLabel
            service.recordSubmission(label: label, network: network, identityId: identityId, walletId: walletId)
            if let endTime = contest.endTime {
                service.recordVotingEndTime(endTime, label: label, network: network, walletId: walletId)
            }
            Self.logger.info("🪪 IDENT-COORD :: contest recovery — restored bookmark for \(label)")
        }

        // The bookmarks are the originating wallet's either way; the UI is
        // told only if that wallet is still the one on screen.
        guard WalletEnvironment.network == network,
              (WalletEnvironment.activeWalletIdHex as String?) == walletId.hexEncodedString(),
              DWCurrentUserIdentityInfo.shared.identityId == identityId
        else {
            Self.logger.info("🪪 IDENT-COORD :: contest recovery — context changed during the query; bookmarks kept for their wallet, UI not refreshed")
            return
        }

        // Every voting surface reads the bookmark on this notification.
        NotificationCenter.default.post(name: .DWDashPayRegistrationStatusUpdated, object: nil)
        // The restored bookmarks need the same monitoring a fresh submission
        // gets: resolution now, then the deadline timer.
        checkPendingContestResolution()
    }

    /// The three ways a contest ends for us. `lostVote` and `blocked` are
    /// kept apart all the way to the row: a blocked name belongs to nobody
    /// and never will, a lost one simply belongs to someone else.
    private enum ContestOutcome { case won, lostVote, blocked }

    private func runPendingContestResolution() async {
        guard let expectedNetwork = WalletEnvironment.network else { return }


        // Bounded wait for host hydration — the Home-appear trigger can
        // fire before SwiftDashSDKWalletRuntime finishes starting. Give up
        // quietly; the next trigger retries.
        var attempts = 0
        while SwiftDashSDKHost.shared.wallet == nil || SwiftDashSDKHost.shared.modelContainer == nil {
            attempts += 1
            if attempts > 30 {
                Self.logger.info("🪪 IDENT-COORD :: contest check — host never hydrated, retry on next trigger")
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        guard SwiftDashSDKHost.shared.runningNetwork == expectedNetwork,
              let wallet = SwiftDashSDKHost.shared.wallet,
              SwiftDashSDKHost.shared.modelContainer != nil else { return }

        // nil can be the cold-launch SwiftData inverse-edge miss (see
        // DWCurrentUserIdentityInfo's wallet-side lookup rationale) —
        // transient, so never clear the bookmark on it.
        guard let identityId = DWCurrentUserIdentityInfo.shared.refreshedSnapshot().identityId
        else {
            Self.logger.info("🪪 IDENT-COORD :: contest check — no identity row yet, retry on next trigger")
            return
        }

        if let container = SwiftDashSDKHost.shared.modelContainer {
            do {
                try await DWCurrentUserIdentityInfo.shared.rehydrateLegacyContests(
                    wallet: wallet, network: expectedNetwork, container: container)
            } catch {
                Self.logger.warning("Legacy contest ownership is still unknown: \(error.localizedDescription)")
            }
        }
        // A marker an earlier launch left before its DPNS write is settled
        // first: confirmed markers join the resolution below, the rest drop.
        for label in DWContestedNameStatusService.shared.provisionalLabels(
            for: expectedNetwork, identityId: identityId, walletId: wallet.walletId) {
            await reconcileProvisionalSubmission(
                label: label, wallet: wallet, identityId: identityId, expectedNetwork: expectedNetwork)
        }

        // Confirmed submissions only: an outcome (won / lost / blocked) is
        // never inferred for a request that may not have been sent.
        let labels = DWContestedNameStatusService.shared.pendingLabels(
            for: expectedNetwork, identityId: identityId, walletId: wallet.walletId, confirmedOnly: true)

        // Every in-flight contest resolves independently — a per-label
        // failure only skips that label for this pass.
        for label in labels {
            await resolvePendingContest(
                label: label,
                wallet: wallet,
                identityId: identityId,
                expectedNetwork: expectedNetwork)
        }
    }

    private func resolvePendingContest(
        label: String,
        wallet: ManagedPlatformWallet,
        identityId: Data,
        expectedNetwork: Network
    ) async {
        let outcome: ContestOutcome
        do {
            if let state = try await wallet.fetchContestVoteState(identityId: identityId, label: label) {
                DWContestedNameStatusService.shared
                    .recordVotingEndTime(state.endTime, label: label, network: expectedNetwork, walletId: wallet.walletId)
                switch state.winner {
                case .none:
                    return // still voting
                case .wonByIdentity(let winner):
                    outcome = (winner == identityId) ? .won : .lostVote
                case .locked:
                    outcome = .blocked
                }
            } else {
                // No vote state: contest pruned, or it never existed for
                // this identity. Re-sync the contested cache; if the label
                // dropped out (and it isn't in getDpnsNames — checked
                // above), the contest resolved against us.
                _ = try await wallet.syncContestedDpnsNames(identityId: identityId)
                let contested = try wallet.managedIdentity(identityId: identityId).getContestedDpnsNames()
                if contested.contains(where: {
                    DWContestedNameStatusService.labelsMatch($0, label)
                }) {
                    return // transient inconsistency — retry next trigger
                }
                // A missing vote state immediately after registration means
                // "not indexed yet", not "won". Only resolve the canonical
                // name owner after an authoritative deadline was observed and
                // has passed. The local getDpnsNames cache is intentionally
                // not consulted: preregistration puts the label there before
                // voting and therefore cannot prove ownership.
                guard let votingEnd = DWContestedNameStatusService.shared
                    .pendingVotingEndTime(label: label, for: expectedNetwork, walletId: wallet.walletId),
                      Date() >= votingEnd else {
                    return
                }
                // A name nobody owns after the deadline was locked; one
                // owned by another identity was voted away from us.
                let resolvedOwner = try await wallet.resolveDpnsName(label)
                if resolvedOwner == identityId {
                    outcome = .won
                } else if resolvedOwner == nil {
                    // Past the deadline, off the contested list and owned by
                    // nobody: the only ending that leaves a name unclaimed is
                    // a lock. A lookup that merely failed throws instead.
                    outcome = .blocked
                } else {
                    outcome = .lostVote
                }
            }
        } catch {
            Self.logger.warning("🪪 IDENT-COORD :: contest check for \(label) failed (retry on next trigger): \(String(describing: error))")
            return
        }

        if outcome == .won {
            // Pull the won name into the DPNS cache before finalizing, so the
            // persister can store it and a `promoteOnWin` promotion lands now
            // rather than on a later refresh. Best effort: the promotion
            // waits for the name either way.
            _ = try? await wallet.syncDpnsNames(identityId: identityId)
        }

        // Freshness guard: the bookmark may have been cleared or the
        // network switched while our awaits were in flight. Same MainActor
        // stretch as the mutation below, so it's atomic against
        // recordSubmission.
        guard WalletEnvironment.network == expectedNetwork,
              SwiftDashSDKHost.shared.runningNetwork == expectedNetwork,
              SwiftDashSDKHost.shared.wallet?.walletId == wallet.walletId,
              (WalletEnvironment.activeWalletIdHex as String?) == wallet.walletId.hexEncodedString(),
              DWCurrentUserIdentityInfo.shared.identityId == identityId,
              DWContestedNameStatusService.shared.pendingLabels(
                  for: expectedNetwork, identityId: identityId, walletId: wallet.walletId, confirmedOnly: true)
                  .contains(where: { DWContestedNameStatusService.labelsMatch($0, label) })
        else {
            Self.logger.info("🪪 IDENT-COORD :: contest check for \(label) became stale after network/submission change")
            return
        }
        switch outcome {
        case .won:
            Self.logger.info("🪪 IDENT-COORD :: contest WON for \(label) — finalizing")
            UsernamePrefs.shared.clearFailedCompanion(forContestedLabel: label)
            DWContestedNameStatusService.shared.finalizeWon(
                username: label,
                network: expectedNetwork,
                identityId: identityId,
                walletId: wallet.walletId)
        case .lostVote, .blocked:
            let reason = (outcome == .blocked) ? "blocked by the network" : "won by another identity"
            Self.logger.info("🪪 IDENT-COORD :: contest for \(label) \(reason) — clearing its bookmark; a new registration attempt is viable")
            // Kept out of the identity's names before the bookmark that hid it
            // goes: the SDK still lists the label as the identity's.
            DWContestedNameStatusService.shared.recordRejected(
                label: label, network: expectedNetwork, identityId: identityId, walletId: wallet.walletId)
            DWContestedNameStatusService.shared.clearPending(label: label, for: expectedNetwork)
            // Remember the outcome. Clearing the bookmark alone sent the row
            // straight back to "Join DashPay — request your username", so a
            // user who lost a two-week vote was never told: the request simply
            // vanished. The record drives the row's "Rejected — <name>" state
            // and its Try again, and is cleared when they act on it.
            UsernamePrefs.shared.lostContestUsername = label
            UsernamePrefs.shared.lostContestWasBlocked = (outcome == .blocked)
            // The vote is over; a missing instant name for it is no longer
            // what the user needs to hear about.
            UsernamePrefs.shared.clearFailedCompanion(forContestedLabel: label)
            // Same announcement `finalizeWon` makes. Without it the rejection
            // sat in UserDefaults until something else happened to refresh the
            // row — the tile only appeared after leaving the screen and coming
            // back.
            NotificationCenter.default.post(
                name: .DWDashPayRegistrationStatusUpdated,
                object: nil)
        }
    }

    /// Settles a pre-submission marker left by an earlier launch — the app
    /// ended between the step-2.9 marker and the DPNS write's result, so it is
    /// unknown whether the request was sent. Platform answers with the same
    /// lookup a registration retry makes:
    ///   - our identity contends in the vote → confirm; the normal resolution
    ///     takes it from there;
    ///   - the name is ours → finalize it as a win;
    ///   - still available, or taken / locked without us → drop the marker so
    ///     the row falls back to the interrupted registration and its retry.
    ///     Never reported as Rejected or Blocked: we may never have asked.
    ///   - lookup failed → keep the marker; the next trigger retries.
    private func reconcileProvisionalSubmission(
        label: String,
        wallet: ManagedPlatformWallet,
        identityId: Data,
        expectedNetwork: Network
    ) async {
        let state: UsernameRegistrationRecoveryFlow.NameState?
        do {
            state = try await registrationNameState(label, identityId: identityId, wallet: wallet)
        } catch CoordinatorError.usernameUnavailable {
            state = nil
        } catch {
            Self.logger.warning("🪪 IDENT-COORD :: provisional \(label) lookup failed (retry on next trigger): \(String(describing: error))")
            return
        }
        if state == .owned {
            _ = try? await wallet.syncDpnsNames(identityId: identityId)
        }

        // Same freshness guard as `resolvePendingContest`, and the marker must
        // still be the earlier launch's: a retry started meanwhile owns it.
        let service = DWContestedNameStatusService.shared
        guard WalletEnvironment.network == expectedNetwork,
              SwiftDashSDKHost.shared.runningNetwork == expectedNetwork,
              SwiftDashSDKHost.shared.wallet?.walletId == wallet.walletId,
              (WalletEnvironment.activeWalletIdHex as String?) == wallet.walletId.hexEncodedString(),
              DWCurrentUserIdentityInfo.shared.identityId == identityId,
              service.provisionalLabels(for: expectedNetwork, identityId: identityId, walletId: wallet.walletId)
                  .contains(where: { DWContestedNameStatusService.labelsMatch($0, label) })
        else { return }

        switch state {
        case .voting:
            Self.logger.info("🪪 IDENT-COORD :: provisional \(label) is in the vote — confirmed")
            service.recordSubmission(
                label: label, network: expectedNetwork, identityId: identityId, walletId: wallet.walletId)
        case .owned:
            Self.logger.info("🪪 IDENT-COORD :: provisional \(label) is already ours — finalizing")
            service.finalizeWon(
                username: label, network: expectedNetwork, identityId: identityId, walletId: wallet.walletId)
            return // finalizeWon announces the change itself
        case .available, nil:
            Self.logger.info("🪪 IDENT-COORD :: provisional \(label) was never submitted — marker dropped")
            service.clearPending(label: label, for: expectedNetwork, walletId: wallet.walletId)
        }
        NotificationCenter.default.post(name: .DWDashPayRegistrationStatusUpdated, object: nil)
    }

    // MARK: - Internal helpers

    private func wireController(_ controller: DWIdentityRegistrationController) {
        phaseSubscription = controller.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] newPhase in
                self?.handlePhaseChange(newPhase)
            }
    }

    /// Remembers the source the user picked for a request (`picked`), for a
    /// retry of it to reuse (`UsernamePrefs.acceptedFundingSourceRaw`).
    /// Called by each paying route right before its FFI call, after its own
    /// checks: a new identity's Core, Platform or Shielded funding, and an
    /// existing identity's Core or Platform top-up. A request stopped before
    /// that leaves no record; one that fails after it keeps it. An invitation
    /// pays from the voucher, not from a balance the user picks.
    private func recordAcceptedSource(
        _ source: DWIdentityFundingSource, ifPicked picked: Bool, label: String, walletId: Data
    ) {
        guard picked, source != .invitation else { return }
        guard let networkScope = registrationNetworkScope else {
            Self.logger.error("🪪 IDENT-COORD :: accepted source not recorded: no network scope for this attempt")
            return
        }
        UsernamePrefs.recordAcceptedFundingSourceRaw(
            source.rawValue, forLabel: label, walletId: walletId, networkScope: networkScope)
    }

    private func handlePhaseChange(_ newPhase: DWIdentityRegistrationController.Phase) {
        phase = newPhase

        // Mirror to DWGlobalOptions on terminal success so existing
        // Obj-C consumers (87 sites referencing
        // DSBlockchainIdentity.currentDashpayUsername) keep working
        // until row #17 migrates them individually.
        //
        // Contested submissions defer these writes — the username
        // isn't actually claimed until masternode voting resolves
        // (~90 min testnet, ~2 weeks mainnet). The pending-submission
        // bookmark is the signal: `DWContestedNameStatusService.shared.pendingLabel`
        // matches `currentUsername` iff Step 3.5 wrote it just now.
        // `checkPendingContestResolution()` (Home appear/foreground)
        // calls `DWContestedNameStatusService.finalizeWon(username:)`
        // to perform them when the vote resolves in our favor.
        if case .completed(let completedIdentityId) = newPhase, let username = currentUsername,
           let walletId = registrationWalletId, let network = registrationNetwork,
           registrationWalletId == SwiftDashSDKHost.shared.wallet?.walletId,
           registrationNetwork == SwiftDashSDKHost.shared.runningNetwork,
           registrationNetwork == WalletEnvironment.network,
           registrationWalletId?.hexEncodedString() == (WalletEnvironment.activeWalletIdHex as String?) {
            // A name registered through this flow becomes the identity's main
            // name, even when the identity already owns others: it is the
            // name the user just asked to be known by.
            let isContestedSubmission = DWContestedNameStatusService.shared.isPendingLabel(username)
            if isContestedSubmission {
                if let temporaryUsername = registeredTemporaryUsername {
                    // The companion name registered in Step 3.6 is live
                    // immediately, so it is the main name while the
                    // contested label stays deferred. The contested bookmark
                    // carries `promoteOnWin`: `finalizeWon` makes the
                    // contested name main if the vote is won; a lost vote
                    // leaves the companion in place.
                    Self.logger.info("🪪 IDENT-COORD :: completed (contested) — temporary username \(temporaryUsername) becomes main")
                    DWCurrentUserIdentityInfo.shared.promoteToMainName(
                        temporaryUsername, identityId: completedIdentityId, walletId: walletId, network: network)
                } else {
                    Self.logger.info("🪪 IDENT-COORD :: completed (contested) — deferring DWGlobalOptions mirror writes")
                }
            } else {
                DWCurrentUserIdentityInfo.shared.promoteToMainName(
                    username, identityId: completedIdentityId, walletId: walletId, network: network)
            }
        }
        // The request went through; a later one for this label is a new
        // request with a fresh choice of source. Keyed by the wallet that
        // made it, which a switch may have made inactive meanwhile.
        if case .completed = newPhase, let username = currentUsername,
           let walletId = registrationWalletId, let networkScope = registrationNetworkScope {
            UsernamePrefs.clearAcceptedFundingSource(forLabel: username, walletId: walletId, networkScope: networkScope)
        }

        // The registering wallet now owns an identity: drop its
        // generated-on-device marker so the next runtime start runs the
        // full pre-SPV bring-up (hygiene — the budget gate also checks local
        // rows). Independent of the username mirror above, and keyed by the
        // wallet this attempt started for, not the host's current wallet,
        // which a switch may have rebound meanwhile.
        if case .completed = newPhase, let walletId = registrationWalletId {
            GeneratedWalletIdentityMarker.clear(walletId: walletId)
        }

        // Stop asset-lock polling on terminal phases — no further
        // statusRaw transitions will arrive.
        switch newPhase {
        case .completed, .failed:
            assetLockPollingTask?.cancel()
            assetLockPollingTask = nil
            // The contest check refuses to run mid-registration, and the form
            // hands off on `.inFlight`, so a More appearance during the attempt
            // armed nothing. Start it once a request has completed — on the
            // next turn, once this phase is published; it keeps its own
            // single-flight and context guards. Not after a failure: a
            // timed-out DPNS write may still land, and judging its marker now
            // could drop a request that is about to be indexed.
            // Only after a contested request: a plain name or a purchase has
            // nothing to resolve, and the check would otherwise fall through
            // to a Platform-wide contest recovery query.
            if case .completed = newPhase, let username = currentUsername,
               DWContestedNameStatusService.isContestedLabel(username) {
                Task { @MainActor [weak self] in self?.checkPendingContestResolution() }
            }
        default:
            break
        }

        // The bridge observes this @Published surface and posts the
        // Obj-C notification; the coordinator stays Combine-only so
        // there's a single owner of NotificationCenter side-effects.
    }

    private func startAssetLockPolling(walletId: Data, modelContainer: ModelContainer) {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.assetLockPollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.pollAssetLockStatus(walletId: walletId, modelContainer: modelContainer)
            }
        }
    }

    private func pollAssetLockStatus(walletId: Data, modelContainer: ModelContainer) async {
        // Only poll while the registration is in-flight; outside of
        // that, the published value should sit at 0 / last terminal.
        guard case .inFlight = phase else { return }

        let context = modelContainer.mainContext
        let pinnedIndex = Int32(Self.pinnedIdentityIndex)
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId && row.identityIndexRaw == pinnedIndex
            }
        )
        descriptor.fetchLimit = 1
        do {
            let rows = try context.fetch(descriptor)
            guard let row = rows.first else { return }
            if assetLockStatus != row.statusRaw {
                assetLockStatus = row.statusRaw
                Self.logger.debug("🪪 IDENT-COORD :: assetLockStatus → \(row.statusRaw)")
            }
        } catch {
            Self.logger.warning("🪪 IDENT-COORD :: asset-lock poll failed: \(String(describing: error))")
        }
    }

    private(set) var completedRegistrationContextMessage: String?

    private func resetState() {
        completedRegistrationContextMessage = nil
        phaseSubscription?.cancel()
        phaseSubscription = nil
        assetLockPollingTask?.cancel()
        assetLockPollingTask = nil
        controller?.resetToIdle()
        controller = nil
        phase = .idle
        assetLockStatus = 0
        failedAtPhase = nil
        lastErrorMessage = nil
        currentUsername = nil
        registrationWalletId = nil
        registrationNetwork = nil
        registrationNetworkScope = nil
        resumedIdentityId = nil
        isRegisteringUsername = false
        isFundingExistingIdentity = false
        currentFundingSource = .core
        registeredTemporaryUsername = nil
        temporaryUsernameError = nil
    }

    /// Look up the persisted identity at `pinnedIdentityIndex` for
    /// the given wallet. Returns the 32-byte identifier if found, or
    /// `nil` if no prior attempt completed IdentityCreate.
    ///
    /// Used by `startCreateUsername` to skip the IdentityCreate step
    /// when a previous attempt landed the identity but failed before
    /// DPNS register completed. Re-running IdentityCreate in that
    /// state would always fail with a unique-key collision (the
    /// DIP-9 derived authentication keys are deterministic per
    /// identity index), so detection + resume is the only way to
    /// recover without bumping the index.
    private func lookupExistingIdentityId(
        walletId: Data,
        modelContainer: ModelContainer
    ) -> Identifier? {
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.identities
            .first(where: { $0.identityIndex == Self.pinnedIdentityIndex })?.identityId
    }

    /// Whether this wallet holds an identity top-up asset lock that was paid
    /// on Core and is waiting to reach Platform: Broadcast, InstantSend- or
    /// ChainLocked (1…3), for `identityId` (any identity when unknown). Built (0) never left the
    /// device, and RecoveredFromChain (5) is what a restore rebuilds every old,
    /// long consumed lock as. The form only warns on this — a lock stuck in
    /// 1…3 cannot always be finished, so it must not block for good; the
    /// tx-detail action resumes these (`AssetLockRecoveryService`).
    static func hasUnfinishedIdentityTopUp(
        walletId: Data, identityId: Data?, modelContainer: ModelContainer
    ) -> Bool {
        let context = modelContainer.mainContext
        // The lock records the topped-up identity's own HD index; an unbound
        // top-up (type 2) is tied to none, so it counts for any identity.
        var identityIndex: Int32?
        if let identityId {
            let identityDescriptor = FetchDescriptor<PersistentIdentity>(
                predicate: #Predicate { $0.identityId == identityId })
            identityIndex = (try? context.fetch(identityDescriptor))?.first.map { Int32(bitPattern: $0.identityIndex) }
        }
        let descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId && (row.fundingTypeRaw == 1 || row.fundingTypeRaw == 2)
                    && row.statusRaw >= 1 && row.statusRaw <= 3
            })
        guard let rows = try? context.fetch(descriptor) else { return false }
        return rows.contains { row in
            row.fundingTypeRaw == 2 || identityIndex == nil || row.identityIndexRaw == identityIndex
        }
    }

    /// Oldest unfinished IdentityRegistration lock for the pinned slot.
    /// Choosing the original payment is deliberate: a wallet already
    /// affected by BUG-2 may contain two rows, and retrying the newer one
    /// would leave the first payment stranded yet again.
    private func lookupRegistrationRecoveryLock(
        walletId: Data,
        modelContainer: ModelContainer
    ) -> RegistrationRecoveryLock? {
        let context = modelContainer.mainContext
        let pinnedIndex = Int32(bitPattern: Self.pinnedIdentityIndex)
        let descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId
                    && row.identityIndexRaw == pinnedIndex
                    && row.fundingTypeRaw == 0
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        // Unfinished = anything but the Consumed (4) tombstone. That
        // includes 5 (RecoveredFromChain): a registration lock at 5 with
        // no identity is a genuinely incomplete registration — a stranded
        // broadcast whose block chain-locked after an app kill, or a
        // restored wallet whose registration never finished — and the SDK
        // resume path explicitly supports consuming it (Platform rejects
        // an already-spent outpoint with a typed error). Restored wallets
        // whose registration DID complete never resume from this lock:
        // `hasPendingRegistrationRecovery` checks the identity row first,
        // and the start flow probes the local row and then the Platform
        // slot (reconciling this lock to Consumed) before any resume.
        guard let rows = try? context.fetch(descriptor),
              let row = rows.first(where: { $0.statusRaw != 4 })
        else {
            return nil
        }
        return RegistrationRecoveryLock(
            outPointHex: row.outPointHex,
            statusRaw: row.statusRaw)
    }

    /// If Platform already contains the identity derived from this
    /// outpoint, reconcile the stale local lock row to Consumed. This is
    /// the process-death window where Platform accepted IdentityCreate
    /// but the SDK did not get to flush its final cleanup callback.
    private func reconcileConsumedRecoveryLock(
        _ recoveryLock: RegistrationRecoveryLock?,
        identityId: Identifier,
        walletId: Data,
        modelContainer: ModelContainer
    ) {
        guard let recoveryLock,
              let outPoint = Self.parseOutPointHex(recoveryLock.outPointHex),
              Self.identityIdentifier(
                txidWire: outPoint.txidWire,
                vout: outPoint.vout) == identityId
        else {
            return
        }

        let context = modelContainer.mainContext
        let outPointHex = recoveryLock.outPointHex
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId && row.outPointHex == outPointHex
            })
        descriptor.fetchLimit = 1
        guard let row = try? context.fetch(descriptor).first else { return }
        row.statusRaw = 4
        row.updatedAt = Date()
        do {
            try context.save()
            assetLockStatus = 4
            Self.logger.info("🪪 IDENT-COORD :: recovery — reconciled accepted asset lock to Consumed")
        } catch {
            // Identity + DPNS recovery can still complete. Leaving the row
            // pending is recoverable and safer than turning this local
            // bookkeeping failure into another registration failure.
            Self.logger.warning("🪪 IDENT-COORD :: recovery — failed to reconcile asset lock: \(String(describing: error))")
        }
    }

    /// Decode SwiftData's display-order `<txid>:<vout>` representation
    /// back to the raw wire-order outpoint expected by the SDK.
    nonisolated static func parseOutPointHex(
        _ value: String
    ) -> (txidWire: Data, vout: UInt32)? {
        let parts = value.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 64,
              let vout = UInt32(parts[1])
        else {
            return nil
        }

        var displayTxid = Data(capacity: 32)
        var index = parts[0].startIndex
        for _ in 0..<32 {
            let end = parts[0].index(index, offsetBy: 2)
            guard let byte = UInt8(parts[0][index..<end], radix: 16) else {
                return nil
            }
            displayTxid.append(byte)
            index = end
        }
        return (Data(displayTxid.reversed()), vout)
    }

    /// DIP-27 identity id for an asset-lock outpoint:
    /// double-SHA256(txid_wire || vout_little_endian).
    nonisolated static func identityIdentifier(
        txidWire: Data,
        vout: UInt32
    ) -> Identifier? {
        guard txidWire.count == 32 else { return nil }
        var outPoint = txidWire
        var littleEndianVout = vout.littleEndian
        withUnsafeBytes(of: &littleEndianVout) {
            outPoint.append(contentsOf: $0)
        }
        let first = Data(SHA256.hash(data: outPoint))
        return Data(SHA256.hash(data: first))
    }

    /// The Platform Wallet FFI currently folds DPP consensus errors into a
    /// message-bearing `PlatformWalletError`, so this is the narrowest
    /// recoverable classification available to the app. Keep both the DPP
    /// type name and its stable user-facing text for compatibility across
    /// SDK revisions.
    nonisolated static func isPlatformAddressInsufficientFunds(
        _ error: Error
    ) -> Bool {
        let message = error.localizedDescription
        return message.localizedCaseInsensitiveContains(
            "AddressesNotEnoughFundsError")
            || message.localizedCaseInsensitiveContains(
                "Insufficient combined address balances")
    }

    /// Select DIP-17 Platform Payment inputs while leaving fee headroom
    /// on the address that becomes the SDK's `DeductFromInput(0)` source.
    private func buildPlatformPaymentInputs(
        walletId: Data,
        modelContainer: ModelContainer,
        targetCredits: UInt64
    ) throws -> [ManagedPlatformWallet.IdentityAddressInput] {
        let candidates: [PlatformPaymentIdentityFundingPolicy.Candidate]
        do {
            candidates = try PlatformPaymentIdentityFundingPolicy.candidates(
                walletId: walletId,
                modelContainer: modelContainer)
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: PP account fetch failed: \(String(describing: error))")
            throw CoordinatorError.identityRegistration(error)
        }
        do {
            return try PlatformPaymentIdentityFundingPolicy.makeInputs(
                candidates: candidates,
                targetCredits: targetCredits)
        } catch let error as PlatformPaymentIdentityFundingPolicy.PlanningError {
            guard case .insufficient(let required, let available) = error else {
                throw CoordinatorError.identityRegistration(error)
            }
            throw CoordinatorError.insufficientPlatformCredits(
                required: required,
                available: available)
        }
    }

    /// Shielded (Type-20) funding path: spend a fixed exit denomination
    /// from the wallet's Orchard pool into a brand-new identity via
    /// `shieldedIdentityCreateFromPool`.
    ///
    /// Pre-flighted against `ShieldedIdentityFundingReadiness` so the
    /// three gates (funding, maturity, pool size) fail with typed,
    /// user-explainable errors BEFORE the ~30 s Halo 2 proof starts.
    /// Drive re-enforces the pool minimum server-side, so an unknown
    /// pool count doesn't block here — the FFI error is the backstop.
    ///
    /// The denomination is the smallest current consensus exit covering
    /// the name's cost: 0.1 DASH standard, 0.25 DASH for contested names.
    /// The metered fee is
    /// taken FROM the denomination, so the new identity starts at
    /// denomination − fee and no extra headroom is required.
    ///
    /// `ShieldedIdentityCreateUnconfirmedError` (broadcast accepted but
    /// result unconfirmed) maps to `.shieldedCreateUnconfirmed` — NOT
    /// retryable immediately; if the create actually landed, the SDK's
    /// pending-spend redrive persists the identity row on a later sync
    /// and the next attempt resumes past IdentityCreate via
    /// `lookupExistingIdentityId`.
    private func createIdentityFromShieldedPool(
        username: String,
        walletId: Data,
        modelContainer: ModelContainer,
        pubkeys: [ManagedPlatformWallet.IdentityPubkey],
        signer: KeychainSigner,
        /// Runs once the pre-flight passed, right before the pool is spent.
        beforeSpend: () -> Void = {}
    ) async throws -> Identifier {
        guard let manager = SwiftDashSDKHost.shared.manager else {
            throw CoordinatorError.noSDK
        }

        let contested = DWContestedNameStatusService.isContestedLabel(username)
        let denomination = ShieldedIdentityFundingReadiness.requiredCredits(forContestedName: contested)

        guard let readiness = ShieldedIdentityFundingReadiness.shared
            .evaluate(requiredCredits: denomination) else {
            throw CoordinatorError.noWallet
        }
        switch readiness.state {
        case .needsFunding:
            throw CoordinatorError.insufficientShieldedBalance(
                requiredCredits: denomination,
                availableCredits: readiness.unspentCredits)
        case .maturing(let readyAt):
            throw CoordinatorError.shieldedBalanceImmature(readyAt: readyAt)
        case .poolTooSmall(let current):
            throw CoordinatorError.shieldedPoolTooSmall(currentNotes: current)
        case .ready:
            break
        }

        // REQUIRED Type-20 fallback: if identity creation fails a
        // stateful check, the spend still finalizes and the value lands
        // at this address (bound into the transition sighash). Same
        // encoding the address-funded inputs use: 1-byte variant tag +
        // 20-byte hash.
        guard let fallbackAddressBytes = shieldedFallbackAddressBytes(
            walletId: walletId,
            modelContainer: modelContainer) else {
            throw CoordinatorError.noShieldedFallbackAddress
        }

        Self.logger.info("🪪 IDENT-COORD :: shielded create denomination=\(denomination) contested=\(contested)")
        beforeSpend()
        do {
            let identityId = try await manager.shieldedIdentityCreateFromPool(
                walletId: walletId,
                // Per-operation Orchard spend authority (seedless
                // shielded bind) — same pattern as the app's other
                // shielded spends in `ShieldedTransferCoordinator`.
                resolver: MnemonicResolver(),
                account: 0,
                identityIndex: Self.pinnedIdentityIndex,
                identityPubkeys: pubkeys,
                denomination: denomination,
                sendToAddressOnCreationFailure: fallbackAddressBytes,
                identitySigner: signer)
            PlatformAddressSyncCoordinator.shared
                .refreshShieldedBalanceAfterSpend(using: manager)
            return identityId
        } catch let unconfirmed as ShieldedIdentityCreateUnconfirmedError {
            Self.logger.warning("🪪 IDENT-COORD :: shielded create unconfirmed id=\(unconfirmed.identityId.map { String(format: "%02x", $0) }.joined().prefix(8))…")
            PlatformAddressSyncCoordinator.shared
                .refreshShieldedBalanceAfterSpend(using: manager)
            throw CoordinatorError.shieldedCreateUnconfirmed
        }
    }

    /// Lowest-indexed Platform Payment address as raw 21-byte
    /// `PlatformAddress` storage bytes (`[addressType] + addressHash`)
    /// for the Type-20 creation-failure fallback. Deterministic — the
    /// same wallet always produces the same fallback. nil when no
    /// Platform address row exists yet (pre-first-platform-sync).
    private func shieldedFallbackAddressBytes(
        walletId: Data,
        modelContainer: ModelContainer
    ) -> Data? {
        let accountDescriptor = FetchDescriptor<PersistentAccount>(
            predicate: #Predicate { account in
                account.accountType == 14
                    && account.wallet.walletId == walletId
            }
        )
        guard let accounts = try? modelContainer.mainContext.fetch(accountDescriptor) else {
            return nil
        }
        guard let row = accounts
            .flatMap({ $0.platformAddresses })
            .min(by: { $0.addressIndex < $1.addressIndex }) else {
            return nil
        }
        return Data([row.addressType]) + row.addressHash
    }
}

/// `os.Logger`-shaped front for `DWLogger`. DWLogger records every line at
/// info, so the level travels as a text tag instead.
private struct CoordinatorLog {
    func debug(_ message: String) { DWLogger.log(message) }
    func info(_ message: String) { DWLogger.log(message) }
    func warning(_ message: String) { DWLogger.log("WARNING " + message) }
    func error(_ message: String) { DWLogger.log("ERROR " + message) }
}
