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
import OSLog
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
    /// Whether the voucher behind `uri` has already funded an identity.
    ///
    /// Structural parsing is local and says nothing about whether the voucher
    /// is still spendable, so a spent invitation used to be discovered only at
    /// the very end of registration, as a raw SDK
    /// "asset lock … already completely used".
    ///
    /// `nil` means undetermined — no wallet, or the lookup failed. Callers
    /// must treat that as "proceed", never as "spent": a network hiccup must
    /// not block a good invitation.
    func isVoucherAlreadyClaimed(uri: String) async -> Bool?
}

@MainActor
final class DWInvitationService: DWInvitationServicing {

    static let shared = DWInvitationService()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.invitations")

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

    /// See the protocol. Platform derives a created identity's id from the
    /// asset-lock outpoint, so the id an invitation *would* produce is knowable
    /// before the claim — and an identity already existing under it is exactly
    /// the "this voucher is spent" signal.
    ///
    /// Two round trips: the SDK refetches the funding transaction to locate the
    /// credit output the voucher controls (it need not be output 0), then we
    /// fetch the identity under the resulting id.
    func isVoucherAlreadyClaimed(uri: String) async -> Bool? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let sdk = SwiftDashSDKHost.shared.sdk
        else {
            return nil
        }
        do {
            let prospectiveId = try await wallet.invitationProspectiveIdentityId(uri: uri)
            let identity = try await sdk.identityGet(identityId: prospectiveId.toBase58String())
            return !identity.isEmpty
        } catch {
            // Undetermined, not "unclaimed". A miss and a transport failure are
            // indistinguishable at this layer, and an unclaimed invitation is
            // *expected* to miss — so the only safe reading is "proceed" and
            // let the claim be the authority.
            Self.logger.info(
                "🎟️ INVITE :: claimed-check inconclusive: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func sendContactRequestToInviter(username: String) async throws {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw ServiceError.noWallet
        }
        // The caller reaches this straight off the "Username registered"
        // alert, so the identity is seconds old. `DWCurrentUserIdentityInfo`
        // serves a cached snapshot that only rebuilds when something
        // invalidates it, and the registration coordinator's own
        // notification has not necessarily round-tripped yet — the contacts
        // service then reads no owner id and fails with "No DashPay identity
        // is registered" for an identity that plainly exists.
        //
        // Rebuild before the read rather than waiting for the cascade.
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        if DWCurrentUserIdentityInfo.shared.identityId == nil {
            // Discovery, not just staleness: adopt what the SDK holds so the
            // app-level pick (main identity) is set too.
            DWCurrentUserIdentityInfo.shared.reconcileRecoveredIdentity()
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
