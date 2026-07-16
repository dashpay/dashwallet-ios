//
//  DWInvitationService.swift
//  DashWallet
//
//  App boundary for DashPay invitations on SwiftDashSDK (DIP-13).
//  PR-1 scope is the invitee side: recognizing/previewing invitation
//  links and the post-claim contact request back to the inviter. The
//  inviter side (create, history, claimed-status watcher, reclaim)
//  lands with the invitation-history UI — see INVITATIONS_REBUILD_PLAN.md.
//
//  The claim itself (IdentityCreate funded by the voucher + DPNS
//  register) runs through `DWIdentityRegistrationCoordinator`, which
//  owns the PIN gate, key pre-persist, phase reporting, and resume
//  semantics shared by every funding source.
//
//  Singleton justification (arch guardrail #4): the service is a
//  stateless facade over `SwiftDashSDKHost.shared` (itself the single
//  SDK owner) and `SwiftDashSDKContactsService.shared`; the protocol
//  seam (`DWInvitationServicing`) is the injection point for tests and
//  future callers.
//

import Foundation
import SwiftDashSDK

@MainActor
protocol DWInvitationServicing: AnyObject {
    /// Canonical invitation URI for any accepted transport, or nil.
    func normalize(_ input: String) -> String?
    /// Read-only structural preview of a normalized invitation URI.
    /// nil while the wallet is not hydrated or on a hard parse error;
    /// a malformed-but-recognized link returns a preview with
    /// `structurallyValid == false`.
    func preview(for uri: String) -> ManagedPlatformWallet.InvitationPreview?
    /// True when this wallet already has a DashPay identity — claiming
    /// an invitation registers a NEW identity, so the flow is not
    /// offered to registered users.
    var hasLocalIdentity: Bool { get }
    /// Resolve the inviter's DPNS username and send them a contact
    /// request from the (just-claimed) local identity. PIN-gated by the
    /// contacts service; throws on resolution or send failure.
    func sendContactRequestToInviter(username: String) async throws
}

@MainActor
final class DWInvitationService: DWInvitationServicing {

    static let shared = DWInvitationService()

    enum ServiceError: LocalizedError {
        case noWallet
        case inviterNotFound(String)

        var errorDescription: String? {
            switch self {
            case .noWallet:
                return NSLocalizedString("Wallet is not ready for identity registration", comment: "DashPay")
            case .inviterNotFound(let username):
                return String.localizedStringWithFormat(
                    NSLocalizedString("%@ couldn't be found on the Dash network to send them a contact request.", comment: "DashPay Invitations"),
                    username)
            }
        }
    }

    private init() {}

    func normalize(_ input: String) -> String? {
        DWInvitationLinkNormalizer.normalize(input)
    }

    func preview(for uri: String) -> ManagedPlatformWallet.InvitationPreview? {
        guard let wallet = SwiftDashSDKHost.shared.wallet else { return nil }
        return try? wallet.parseInvitation(uri: uri)
    }

    var hasLocalIdentity: Bool {
        DWCurrentUserIdentityInfo.shared.identityId != nil
    }

    func sendContactRequestToInviter(username: String) async throws {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw ServiceError.noWallet
        }
        // The link carries only the inviter's username (`du`), not their
        // identity id — resolve via DPNS first (mirrors Android's
        // `identityRepository.getUser(invite.user)` and the SDK example's
        // claim sheet).
        guard let inviterId = try await wallet.resolveDpnsName(username) else {
            throw ServiceError.inviterNotFound(username)
        }
        // The contacts service owns the send: PIN gate, lazy DashPay
        // enc/dec key upgrade for the new identity, and the local
        // pending-row bookkeeping the contacts UI reads.
        try await SwiftDashSDKContactsService.shared.sendContactRequest(
            to: inviterId,
            usernameHint: username)
    }
}
