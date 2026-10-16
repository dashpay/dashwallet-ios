//
//  InvitationValidation.swift
//  DashWallet
//
//  What a pending invitation turned out to be once checked against the
//  network, and which usernames it can pay for.
//
//  The link does not say whether it funds a contested username. The inviter
//  picks the amount — 0.25 DASH for any name, 0.03 DASH for non-contested
//  names only — and the invitee reads it back from the funding asset lock
//  (Android: `RequestUserNameViewModel.isInviteForContestedNames`).
//

import Foundation
import OSLog
import SwiftDashSDK

enum InvitationTier: Equatable {
    /// Funds any username, contested ones included.
    case contested
    /// Funds non-contested usernames only (a digit 2–9, or 20+ characters).
    case nonContested
}

/// What the invitee sees of the inviter, taken from the link.
struct InvitationInviter: Equatable {
    let username: String?
    let displayName: String?
    let avatarURL: String?

    static let unknown = InvitationInviter(username: nil, displayName: nil, avatarURL: nil)

    /// Display name, then username; nil when the link carried neither.
    var bestName: String? {
        [displayName, username]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

enum InvitationValidation: Equatable {
    enum InvalidReason: Equatable {
        case malformed
        case wrongNetwork
        case belowMinimum
    }

    case valid(tier: InvitationTier, amountDuffs: UInt64, inviter: InvitationInviter)
    case invalid(InvalidReason, inviter: InvitationInviter)
    case alreadyClaimed(inviter: InvitationInviter)
    /// The wallet already has a username.
    case alreadyHasIdentity
    /// The wallet has an identity, without a username, other than the one
    /// this invitation would create.
    case alreadyHasOtherIdentity
    case alreadyRequestedUsername
    /// The network could not answer (not propagated yet, transport failure).
    /// Not a verdict: the invitation is kept and checked again.
    case undetermined
    /// A ChainLock-only invitation (the link carries no InstantSend lock)
    /// whose funding transaction is not chain-locked yet. It cannot be
    /// claimed until it is; kept and checked again.
    case awaitingChainLock

    /// A verdict that ends the invitation: shown once, then the invitation is
    /// forgotten.
    var isDefinitive: Bool {
        switch self {
        case .valid, .undetermined, .awaitingChainLock: return false
        case .invalid, .alreadyClaimed, .alreadyHasIdentity, .alreadyHasOtherIdentity, .alreadyRequestedUsername:
            return true
        }
    }

    var tier: InvitationTier? {
        if case .valid(let tier, _, _) = self { return tier }
        return nil
    }

    /// The verdict is a fact about the voucher itself, true in every wallet
    /// and network the link is stored under — so every copy goes. The other
    /// definitive verdicts are about the wallet that was checked (it already
    /// has a username, it has a request in a vote, it is on the other
    /// network) and remove only that wallet's copy.
    var clearsEverywhere: Bool {
        switch self {
        case .alreadyClaimed, .invalid(.malformed, _), .invalid(.belowMinimum, _):
            return true
        case .invalid(.wrongNetwork, _), .alreadyHasIdentity, .alreadyHasOtherIdentity, .alreadyRequestedUsername,
             .valid, .undetermined, .awaitingChainLock:
            return false
        }
    }
}

/// What the wallet knows about its own DashPay identity when a check runs.
struct InvitationWalletState: Equatable {
    /// The identity snapshot is still loading: an absent identity or
    /// username means "not known yet", not "none".
    var isLoading: Bool
    var hasRegisteredUsername: Bool
    var hasPendingUsernameRequest: Bool
    /// This wallet's identity, when it has one without a username.
    var identityId: Data?
}

/// Pure mapping from what the SDK reported to a verdict — no I/O, so it is
/// unit-testable.
enum InvitationValidationPolicy {

    /// Local checks that need no network, in order. nil means "ask the
    /// network".
    ///
    /// An identity WITHOUT a username is not a verdict here: it may be the
    /// one this very invitation created in a claim that landed but reported
    /// failure (a broadcast timeout), and only the network can tell.
    static func localVerdict(
        hasRegisteredUsername: Bool,
        hasPendingUsernameRequest: Bool,
        preview: ManagedPlatformWallet.InvitationPreview?
    ) -> InvitationValidation? {
        localVerdict(
            hasRegisteredUsername: hasRegisteredUsername,
            hasPendingUsernameRequest: hasPendingUsernameRequest,
            previewIsValid: preview?.structurallyValid == true,
            inviter: inviter(from: preview))
    }

    static func localVerdict(
        hasRegisteredUsername: Bool,
        hasPendingUsernameRequest: Bool,
        previewIsValid: Bool,
        inviter: InvitationInviter
    ) -> InvitationValidation? {
        if hasRegisteredUsername { return .alreadyHasIdentity }
        if hasPendingUsernameRequest { return .alreadyRequestedUsername }
        guard previewIsValid else { return .invalid(.malformed, inviter: inviter) }
        return nil
    }

    /// The whole check, with the wallet and the network passed in. The
    /// wallet's state is read again after the status query: while it ran,
    /// the wallet may have learned its own earlier claim's identity (or a
    /// username), and a verdict from the state before would turn that
    /// claim into "already claimed". nil when the wallet cannot answer.
    @MainActor
    static func decide(
        uri: String?,
        previewIsValid: Bool,
        inviter: InvitationInviter,
        walletState: @MainActor () -> InvitationWalletState,
        queryStatus: @MainActor (String) async throws -> ManagedPlatformWallet.InvitationClaimStatus
    ) async -> InvitationValidation? {
        func local(_ state: InvitationWalletState) -> InvitationValidation? {
            localVerdict(
                hasRegisteredUsername: state.hasRegisteredUsername,
                hasPendingUsernameRequest: state.hasPendingUsernameRequest,
                previewIsValid: previewIsValid,
                inviter: inviter)
        }
        let before = walletState()
        guard !before.isLoading else { return nil }
        if let verdict = local(before) { return verdict }
        guard let uri else { return .invalid(.malformed, inviter: .unknown) }

        let result: Result<ManagedPlatformWallet.InvitationClaimStatus, Error>
        do {
            result = .success(try await queryStatus(uri))
        } catch {
            result = .failure(error)
        }

        let after = walletState()
        guard !after.isLoading else { return nil }
        if let verdict = local(after) { return verdict }
        switch result {
        case .success(let status):
            return verdict(
                status: status,
                inviter: inviter,
                minimumDuffs: ManagedPlatformWallet.minInvitationDuffs,
                contestedDuffs: UInt64(DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME),
                localIdentityId: after.identityId)
        case .failure(let error):
            return verdict(error: error, inviter: inviter)
        }
    }

    /// - Parameter localIdentityId: this wallet's identity when it has one
    ///   (without a username — a username is settled locally). The identity
    ///   this invitation created is ours to finish, not "already claimed";
    ///   any other identity means the wallet cannot take an invitation.
    static func verdict(
        status: ManagedPlatformWallet.InvitationClaimStatus,
        inviter: InvitationInviter,
        minimumDuffs: UInt64,
        contestedDuffs: UInt64,
        localIdentityId: Data? = nil
    ) -> InvitationValidation {
        let tier: InvitationTier = status.amountDuffs >= contestedDuffs ? .contested : .nonContested
        if let localIdentityId {
            guard localIdentityId == status.prospectiveIdentityId else { return .alreadyHasOtherIdentity }
            // Our own earlier claim: only the username is left to register.
            return .valid(tier: tier, amountDuffs: status.amountDuffs, inviter: inviter)
        }
        if status.alreadyClaimed { return .alreadyClaimed(inviter: inviter) }
        if status.amountDuffs < minimumDuffs { return .invalid(.belowMinimum, inviter: inviter) }
        if !status.isInstant && !status.isChainLocked { return .awaitingChainLock }
        return .valid(tier: tier, amountDuffs: status.amountDuffs, inviter: inviter)
    }

    /// The SDK's claim-status call draws the definitive/undetermined line:
    /// a malformed link and a link for the other network can never be
    /// claimed; anything else may succeed on a later try.
    static func verdict(error: Error, inviter: InvitationInviter) -> InvitationValidation {
        switch error {
        case PlatformWalletError.invalidParameter:
            return .invalid(.malformed, inviter: inviter)
        case PlatformWalletError.invalidNetwork:
            return .invalid(.wrongNetwork, inviter: inviter)
        default:
            return .undetermined
        }
    }

    static func inviter(from preview: ManagedPlatformWallet.InvitationPreview?) -> InvitationInviter {
        guard let preview else { return .unknown }
        return InvitationInviter(
            username: preview.inviterUsername,
            displayName: preview.inviterDisplayName,
            avatarURL: preview.inviterAvatarURL)
    }
}

/// How a failed invitation claim ends — pure, so it is unit-testable.
enum InvitationClaimFailure: Equatable {
    /// The link can never be claimed by this wallet. Ends this wallet's copy.
    case invalid
    /// The claim failed with a "spent" report — the wallet's typed error,
    /// the node's consensus code, or error text. None is proof that this
    /// voucher was spent: the node's rejection is not proof-verified, and
    /// the typed error can concern another asset lock in the same
    /// registration. The invitation stays; the card's proof-verified status
    /// query is the only thing that removes a spent voucher.
    case reportedUsed
    /// The InstantSend proof went stale before the funding block was
    /// chain-locked; the same invitation claims fine a few minutes later.
    case stillConfirming

    var endsInvitation: Bool { self == .invalid }

    /// `IdentityAssetLockTransactionOutPointAlreadyConsumedError`, as a node
    /// reports it.
    static let outPointAlreadyConsumedCode: UInt32 = 10504

    /// nil for a failure that says nothing about the invitation (network,
    /// PIN, DPNS) — the generic registration wording applies.
    static func classify(_ error: Error) -> InvitationClaimFailure? {
        let underlying = unwrap(error)
        switch underlying {
        case PlatformWalletError.assetLockAlreadyConsumed:
            return .reportedUsed
        case PlatformWalletError.invalidParameter, PlatformWalletError.invalidNetwork:
            return .invalid
        case let error as PlatformWalletError where error.consensusError?.code == outPointAlreadyConsumedCode:
            return .reportedUsed
        default:
            break
        }
        // An error without a typed case or a consensus code: only its text
        // names the cause. "Not yet chain-locked" is decided wallet-side.
        let text = String(describing: underlying).lowercased()
        if text.contains("already consumed") || text.contains("already completely used") {
            return .reportedUsed
        }
        if text.contains("not yet chain-locked") {
            return .stillConfirming
        }
        return nil
    }

    /// The user-facing wording; `sender` is the inviter's name.
    func message(sender: String) -> String {
        switch self {
        case .reportedUsed:
            // Not proven spent (see the case): the Home card's check names
            // the outcome, so this does not.
            return NSLocalizedString(
                "This invitation couldn't be used. Check it on the Home screen.",
                comment: "DashPay Invitations")
        case .invalid:
            return String.localizedStringWithFormat(
                NSLocalizedString("Your invitation from %@ is not valid", comment: ""), sender)
        case .stillConfirming:
            return NSLocalizedString(
                "The invitation is still confirming on the network. Try again in a few minutes.",
                comment: "DashPay Invitations")
        }
    }

    /// The coordinator reports an IdentityCreate failure wrapped in
    /// `CoordinatorError.identityRegistration`.
    private static func unwrap(_ error: Error) -> Error {
        if case DWIdentityRegistrationCoordinator.CoordinatorError.identityRegistration(let inner) = error {
            return inner
        }
        return error
    }
}

/// What the card does while the wallet cannot answer a check yet — pure, so
/// it is unit-testable.
enum InvitationNotReadyPolicy {
    enum Step: Equatable {
        /// Keep Verifying and check again shortly.
        case waitAndRecheck
        /// Stop waiting: show "couldn't verify" with Retry.
        case offerRetry
    }

    /// Checks (about 5 s apart) before the card offers Retry.
    static let attemptsBeforeRetry = 3

    static func next(afterAttempts attempts: Int) -> Step {
        attempts >= attemptsBeforeRetry ? .offerRetry : .waitAndRecheck
    }

    /// Whether a registration-status notification starts a check. A failed
    /// identity-name read posts the same notification as a real change, and
    /// every not-ready check re-arms that read — so while the wallet cannot
    /// answer, the bounded re-checks (or Retry) own the next check, or a
    /// failing read would loop past the budget.
    static func revalidatesOnStatusChange(afterAttempts attempts: Int) -> Bool {
        attempts == 0
    }
}

/// Runs the checks against the live wallet.
@MainActor
enum InvitationValidator {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.invitations")

    /// nil when the wallet is not ready to be asked (not hydrated yet), or
    /// when the active wallet or network is no longer the invitation's — the
    /// checks read the live wallet, so their answer would be about another
    /// scope.
    static func validate(_ invitation: PendingInvitation) async -> InvitationValidation? {
        // Selected AND bound: mid-switch the host still exposes the outgoing
        // wallet, whose identity would answer for this invitation's wallet.
        guard InvitationScope.isActiveAndBound(invitation.scope),
              let wallet = SwiftDashSDKHost.shared.wallet,
              DWCurrentUserIdentityInfo.shared.isCurrentNetworkContextReady else {
            return nil
        }
        guard let verdict = await check(invitation, wallet: wallet) else { return nil }
        return InvitationScope.isActiveAndBound(invitation.scope) ? verdict : nil
    }

    private static func check(_ invitation: PendingInvitation, wallet: ManagedPlatformWallet) async -> InvitationValidation? {
        let uri = invitation.normalizedURI
        let preview = uri.flatMap { try? wallet.parseInvitation(uri: $0) }
        return await InvitationValidationPolicy.decide(
            uri: uri,
            previewIsValid: preview?.structurallyValid == true,
            inviter: InvitationValidationPolicy.inviter(from: preview),
            walletState: { currentWalletState() },
            queryStatus: { uri in
                do {
                    let status = try await wallet.invitationClaimStatus(uri: uri)
                    logger.info(
                        "🎟️ INVITE :: status amount=\(status.amountDuffs, privacy: .public) claimed=\(status.alreadyClaimed, privacy: .public)")
                    return status
                } catch {
                    logger.info("🎟️ INVITE :: status failed: \(String(describing: error), privacy: .public)")
                    throw error
                }
            })
    }

    private static func currentWalletState() -> InvitationWalletState {
        let identity = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
        return InvitationWalletState(
            isLoading: identity.isLoading,
            hasRegisteredUsername: identity.username?.isEmpty == false,
            hasPendingUsernameRequest: DWContestedNameStatusService.shared.pendingLabel != nil
                || identity.pendingContestedName != nil,
            identityId: identity.identityId)
    }
}
