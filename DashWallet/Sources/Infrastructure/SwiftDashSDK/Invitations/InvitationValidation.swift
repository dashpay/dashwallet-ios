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
    case alreadyHasIdentity
    case alreadyRequestedUsername
    /// The network could not answer (not propagated yet, transport failure).
    /// Not a verdict: the invitation is kept and checked again.
    case undetermined

    /// A verdict that ends the invitation: shown once, then the invitation is
    /// forgotten.
    var isDefinitive: Bool {
        switch self {
        case .valid, .undetermined: return false
        case .invalid, .alreadyClaimed, .alreadyHasIdentity, .alreadyRequestedUsername: return true
        }
    }

    var tier: InvitationTier? {
        if case .valid(let tier, _, _) = self { return tier }
        return nil
    }
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
        if hasRegisteredUsername { return .alreadyHasIdentity }
        if hasPendingUsernameRequest { return .alreadyRequestedUsername }
        guard let preview, preview.structurallyValid else {
            return .invalid(.malformed, inviter: inviter(from: preview))
        }
        return nil
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
            guard localIdentityId == status.prospectiveIdentityId else { return .alreadyHasIdentity }
            // Our own earlier claim: only the username is left to register.
            return .valid(tier: tier, amountDuffs: status.amountDuffs, inviter: inviter)
        }
        if status.alreadyClaimed { return .alreadyClaimed(inviter: inviter) }
        if status.amountDuffs < minimumDuffs { return .invalid(.belowMinimum, inviter: inviter) }
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
    /// Someone else's claim spent the voucher. Ends the invitation.
    case alreadyUsed
    /// The link can never be claimed by this wallet. Ends the invitation.
    case invalid
    /// The InstantSend proof went stale before the funding block was
    /// chain-locked; the same invitation claims fine a few minutes later.
    case stillConfirming

    var endsInvitation: Bool { self != .stillConfirming }

    /// nil for a failure that says nothing about the invitation (network,
    /// PIN, DPNS) — the generic registration wording applies.
    static func classify(_ error: Error) -> InvitationClaimFailure? {
        let underlying = unwrap(error)
        switch underlying {
        case PlatformWalletError.assetLockAlreadyConsumed:
            return .alreadyUsed
        case PlatformWalletError.invalidParameter, PlatformWalletError.invalidNetwork:
            return .invalid
        default:
            break
        }
        // Platform's consensus rejections reach the claim as a generic SDK
        // error; only their text names the cause.
        let text = String(describing: underlying).lowercased()
        if text.contains("already consumed") || text.contains("already completely used") {
            return .alreadyUsed
        }
        if text.contains("not yet chain-locked") {
            return .stillConfirming
        }
        return nil
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

/// Runs the checks against the live wallet.
@MainActor
enum InvitationValidator {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.invitations")

    /// nil when the wallet is not ready to be asked (not hydrated yet).
    static func validate(_ invitation: PendingInvitation) async -> InvitationValidation? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              DWCurrentUserIdentityInfo.shared.isCurrentNetworkContextReady else {
            return nil
        }
        let uri = invitation.normalizedURI
        let preview = uri.flatMap { try? wallet.parseInvitation(uri: $0) }
        let hasPendingRequest = DWContestedNameStatusService.shared.pendingLabel != nil
            || DWCurrentUserIdentityInfo.shared.refreshedSnapshot().pendingContestedName != nil
        let identityInfo = DWCurrentUserIdentityInfo.shared
        if let local = InvitationValidationPolicy.localVerdict(
            hasRegisteredUsername: identityInfo.username?.isEmpty == false,
            hasPendingUsernameRequest: hasPendingRequest,
            preview: preview) {
            return local
        }
        guard let uri else { return .invalid(.malformed, inviter: .unknown) }
        let inviter = InvitationValidationPolicy.inviter(from: preview)
        let verdict: InvitationValidation
        do {
            let status = try await wallet.invitationClaimStatus(uri: uri)
            verdict = InvitationValidationPolicy.verdict(
                status: status,
                inviter: inviter,
                minimumDuffs: ManagedPlatformWallet.minInvitationDuffs,
                contestedDuffs: UInt64(DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME),
                localIdentityId: identityInfo.identityId)
            logger.info(
                "🎟️ INVITE :: status amount=\(status.amountDuffs, privacy: .public) claimed=\(status.alreadyClaimed, privacy: .public)")
        } catch {
            verdict = InvitationValidationPolicy.verdict(error: error, inviter: inviter)
            logger.info(
                "🎟️ INVITE :: status failed (\(String(describing: verdict), privacy: .public)): \(String(describing: error), privacy: .public)")
        }
        return verdict
    }
}
