//
//  ContactItem.swift
//  DashWallet
//
//  Value-type read model for the DashPay contacts subsystem (migration
//  Row #18). Materialized by `SwiftDashSDKContactsService` from the
//  SwiftData rows the SDK's DashPay background sync persists
//  (`PersistentDashpayContactRequest` + `PersistentDashpayContactProfile`)
//  — replaces the DashSync-era `DWDP*` object hierarchy that wrapped
//  `DSFriendRequestEntity` / `DSDashpayUserEntity` Core Data entities.
//

import Foundation

extension String {
    /// DPNS labels render without the implied ".dash" parent domain
    /// (visual only — stored values keep the full name).
    var withoutDashSuffix: String {
        hasSuffix(".dash") ? String(dropLast(5)) : self
    }
}

/// Relationship between the current user's identity and a contact
/// identity, derived from the persisted contact-request rows:
/// a `(owner, contact)` pair with BOTH direction rows is established;
/// a single incoming row is a pending incoming request; a single
/// outgoing row is a pending outgoing request. (Same classification
/// `DSBlockchainIdentity.friendshipStatusForRelationshipWith…` used to
/// answer from Core Data.)
enum ContactRelationship: Equatable {
    /// They sent us a request we haven't accepted yet.
    case incoming
    /// We sent them a request they haven't accepted yet.
    case outgoing
    /// Both direction rows exist — mutual friendship on Platform.
    case established
}

/// One row of the contacts read model: a contact identity plus the
/// display fields joined from the synced DashPay profile cache and
/// the local DPNS-label hint store.
struct ContactItem: Identifiable, Equatable {
    /// 32-byte Platform identity ID of the contact.
    let contactIdentityId: Data

    let relationship: ContactRelationship

    /// DPNS label when known. Sources, in precedence order: the label
    /// captured at add time (username search), or a lazy
    /// `dpnsGetUsername` reverse lookup for incoming senders.
    /// Nil until one of those has run.
    let username: String?

    /// `dashpay.profile.displayName` from the synced contact-profile
    /// cache. Nil when the contact published no profile (or the cache
    /// hasn't synced it yet).
    let profileDisplayName: String?

    /// Owner-private alias set on the established contact (SDK
    /// `EstablishedContact.setAlias`, persisted on the request row).
    /// Highest display precedence when present.
    let alias: String?

    /// Owner-private note (SDK `EstablishedContact.setNote`).
    let note: String?

    /// Owner-private hidden flag (SDK `EstablishedContact.hide`).
    /// Hidden contacts move to the collapsed Hidden section.
    let isHidden: Bool

    /// The SDK gave up on building this contact's DIP-15 payment
    /// channel for a permanent reason (`EstablishedContact
    /// .payment_channel_broken`): the counterparty's encrypted xpub
    /// cannot be decrypted, or their key shape can never satisfy the
    /// ECDH gate.
    ///
    /// Being `.established` is NOT the same as being payable —
    /// friendship is mutual contact requests, while paying needs the
    /// external contact account those requests are the input to. A
    /// broken channel is unrecoverable from this side: the sweep never
    /// retries it, and only a fresh contact request from the CONTACT
    /// clears the flag. Surfacing it is what stops the UI offering a
    /// Pay button that can only ever fail.
    let paymentChannelBroken: Bool

    /// `dashpay.profile.avatarUrl` from the synced contact-profile cache.
    let avatarURL: String?

    /// `dashpay.profile.publicMessage` from the synced contact-profile cache.
    let publicMessage: String?

    /// Creation timestamp of the most recent request row for the pair —
    /// incoming rows carry the sender's document timestamp, so this is
    /// what "requested N days ago" renders from. For established pairs
    /// this is the reciprocation time (when the friendship completed).
    let createdAt: Date

    /// Per-direction row timestamps. For established pairs the newer
    /// of the two tells who reciprocated: incoming newer → they
    /// accepted our request; outgoing newer → we accepted theirs.
    /// Nil when that direction's row doesn't exist (pending states).
    let incomingCreatedAt: Date?
    let outgoingCreatedAt: Date?

    var id: Data { contactIdentityId }

    /// Title for list rows: owner-set alias first, then profile
    /// display name, then DPNS label, then a truncated identity-id
    /// fallback so a just-synced row with no resolved metadata still
    /// renders something stable.
    var displayTitle: String {
        if let alias, !alias.isEmpty {
            return alias
        }
        if let profileDisplayName, !profileDisplayName.isEmpty {
            return profileDisplayName
        }
        if let username, !username.isEmpty {
            return username.withoutDashSuffix
        }
        return String(contactIdentityId.map { String(format: "%02x", $0) }.joined().prefix(8)) + "…"
    }
}
