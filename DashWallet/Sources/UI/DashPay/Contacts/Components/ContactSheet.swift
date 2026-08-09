//
//  ContactSheet.swift
//  DashWallet
//
//  One sheet for a person, whatever our relationship with them is: a search
//  hit we could ask, a request waiting on us, or an established contact.
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

/// Honest limitation: the SDK exposes no on-chain profile fetch for an
/// arbitrary identity (`getDashPayProfile` / `getContactProfile` read the local
/// cache only), so for a true stranger this shows the DPNS username and a
/// placeholder avatar, not a fetched bio. Real profile fields appear once the
/// identity is one of our contacts or requesters. Nothing is fabricated when
/// the data is absent.
struct ContactSheet: View {

    /// What we can do about this person. Everything the sheet renders follows
    /// from this — the cards are not chosen by the caller, so the same state
    /// cannot be drawn two ways from two screens.
    enum Relationship {
        /// Nothing between us yet; we can send a request.
        case stranger
        /// We asked and are waiting.
        case requestSent
        /// They asked us.
        case requestReceived
        /// Mutual. Payments are possible.
        case established
        /// Our own identity.
        case isSelf
        /// Pre-DashPay identity: no keys to receive a contact request.
        case cannotReceiveRequests
    }

    /// The person, flattened out of whichever model the caller had. Keeping
    /// this neutral is what lets one sheet serve the contacts list and the
    /// network search — a `DpnsSearchResult` cannot be built from a
    /// `ContactItem`, nor the other way round.
    struct Identity {
        let title: String
        let username: String
        let avatarURL: String?
        let identitySeed: Data
        let publicMessage: String?
    }

    let identity: Identity
    let relationship: Relationship
    /// A request for this person is in flight.
    var isSending: Bool = false

    var onPay: (() -> Void)? = nil
    var onSendRequest: (() -> Void)? = nil
    var onAccept: (() -> Void)? = nil
    var onIgnore: (() -> Void)? = nil
    /// Opens one of the activity list's payments. Nil leaves those rows
    /// inert — the host decides whether it can show a transaction from here.
    var onSelectTransaction: ((Transaction) -> Void)? = nil
    /// The contact record, when this person is one. `Identity` is deliberately
    /// neutral so a search hit and a contact can share this sheet, but the
    /// owner-private settings are written against a real contact — so that
    /// card needs the record itself, not the flattened view of it.
    var contact: ContactItem? = nil

    @Environment(\.dismiss) private var dismiss

    /// Self-sizing: the sheet snaps to whatever this state needs, and the
    /// states differ a lot — a stranger has one button, an incoming request
    /// has two plus an explanation.
    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            showBackButton: .constant(false),
            background: .dash.primaryBackground
        ) {
            // See `SelfSizingScrollLimiter` below for why this can't just be
            // `ScrollView { VStack { ... } }`.
            SelfSizingScrollLimiter {
                VStack(alignment: .leading, spacing: 20) {
                    profileCard

                    if relationship == .requestReceived {
                        incomingRequestCard
                    }

                    // Alias, note and hiding are written as a `contactInfo`
                    // document against an established pair, so they have no
                    // meaning until the request has been accepted.
                    if relationship == .established, let contact {
                        ContactSettingsCard(contact: contact)
                    }

                    // Anyone we have a request with, either way: payments need a
                    // mutual contact, but the request itself is already history
                    // worth showing while it is still pending. A stranger, our
                    // own identity and a keyless identity have no record at all.
                    if relationship == .established
                        || relationship == .requestSent
                        || relationship == .requestReceived {
                        ContactActivityCard(
                            contactIdentityId: identity.identitySeed,
                            onSelect: onSelectTransaction)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
        // Close once the request the user submitted has landed. Dismissing on
        // tap instead would hide the progress the button is there to show.
        .onChange(of: isSending) { wasSending, nowSending in
            if wasSending && !nowSending { dismiss() }
        }
    }

    // MARK: - Who they are, and the one thing we can do about it

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            ContactPreviewHeader(
                title: identity.title,
                username: identity.username,
                avatarURL: identity.avatarURL,
                identitySeed: identity.identitySeed,
                publicMessage: identity.publicMessage
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Paying needs a mutual contact — DashPay derives the payment
            // address from the contact's xpub, which only an accepted request
            // hands over.
            if relationship == .established, let onPay {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Send", comment: "DashPay Contacts"),
//                    leadingIcon: .custom("icon_dash_currency"),
                    leadingIcon: .custom("menu-dash-logo-square", bundle: .dashUIKit),
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: onPay)
            }

            // Kept on screen after it is spent: the button turning into a
            // disabled "Request sent" is what tells the user the request is
            // already out — removing it would read as "nothing happened".
            if relationship == .stranger || relationship == .requestSent {
                DashUIKit.DashButton(
                    text: relationship == .requestSent
                        ? NSLocalizedString("Request sent", comment: "DashPay Contacts")
                        : NSLocalizedString("Send request", comment: "DashPay Contacts"),
                    isEnabled: relationship == .stranger,
                    isLoading: isSending,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: { onSendRequest?() })
            }

            if let note = statusNote {
                Text(note)
                    .dashFont(.caption1)
                    .foregroundStyle(Color.dash.secondaryText)
                    .padding(.trailing, 40)
            }
        }
        .padding(20)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
    }

    /// The line under the action. Absent for an established contact — there
    /// the button speaks for itself.
    private var statusNote: String? {
        switch relationship {
        case .stranger:
            String(
                format: NSLocalizedString("Once %@ accepts your request you can pay directly to the username", comment: "DashPay Contacts"),
                identity.username)
        case .requestSent:
            String(
                format: NSLocalizedString("Once %@ accepts your request you can pay directly to the username", comment: "DashPay Contacts"),
                identity.username)
        case .cannotReceiveRequests:
            NSLocalizedString("This user hasn't set up the keys needed to receive contact requests yet.", comment: "DashPay Contacts")
        case .isSelf:
            NSLocalizedString("This is your own identity.", comment: "DashPay Contacts")
        case .requestReceived, .established:
            nil
        }
    }

    // MARK: - They asked us

    private var incomingRequestCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(
                    format: NSLocalizedString("%@ has sent you contact request", comment: "DashPay Contacts"),
                    identity.username))
                    .dashFont(.subheadMedium)
                    .foregroundStyle(Color.dash.primaryText)

                Text(String(
                    format: NSLocalizedString("If you don't want %@ to be in your contact list you can tap the \"Ignore\" button. They will not be notified about your decision.", comment: "DashPay Contacts"),
                    identity.username))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
            }

            HStack(spacing: 20) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Ignore", comment: "DashPay Contacts"),
                    isEnabled: !isSending,
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: { onIgnore?() })

                DashUIKit.DashButton(
                    text: NSLocalizedString("Accept", comment: "DashPay Contacts"),
                    isLoading: isSending,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: { onAccept?() })
            }
        }
        .padding(20)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
    }
}

// MARK: - Self-sizing overflow

/// Keeps `BottomSheet.selfSizing` honest when the content can be long,
/// without touching DashUIKit (a pinned local SPM dependency on a branch
/// awaiting review).
///
/// `selfSizingSheet` measures its content under
/// `.fixedSize(horizontal: false, vertical: true)`, and that modifier stays on
/// the rendered tree — so content always lays out at its full natural height
/// and the sheet, capped at `maxHeightFraction` of the window, simply clips
/// it. A plain `ScrollView` doesn't help: under a `fixedSize` proposal it
/// reports no useful ideal height, which is the "mis-sizes or collapses" case
/// DashUIKit's own doc warns about.
///
/// What does work is giving the `ScrollView` an *exact* height — an exact
/// frame reports a stable ideal size through the outer measurement pass
/// whatever proposal it receives. So: measure the content once unwrapped,
/// then render it inside a `ScrollView` pinned to `min(natural, budget)`.
/// Content that fits gets a scroll view exactly its own height, which looks
/// and behaves like no scroll view at all — scrolling is disabled outright so
/// it can't even rubber-band.
///
/// The branch flips once, on first measurement, and never again — it is not
/// keyed on the threshold, so a list that grows past the budget (or shrinks
/// back under it) only changes the frame height, never the view identity.
/// That matters: a branch change would tear down and rebuild any
/// `@StateObject` inside, and `ContactActivityCard` owns one.
private struct SelfSizingScrollLimiter<Content: View>: View {
    /// Mirrors `BottomSheet.selfSizingSheet`'s own default `maxHeightFraction`
    /// (`ContactSheet` doesn't override it), so this targets the same ceiling
    /// the outer sheet caps itself at.
    private static var maxHeightFraction: CGFloat { 0.95 }
    /// `BottomSheet`'s fixed chrome, which sits outside `content()` and so is
    /// added on top of whatever height this view reports: an 18pt grabber and
    /// a `NavigationBar` with a 64pt `minHeight`. Both are hardcoded in
    /// DashUIKit and can't be read from here, so if a future revision changes
    /// them this reserve drifts with them. The extra 12pt is slack — being a
    /// little short costs a few unused points, being a little long costs the
    /// grabber and close button sliding off the top of the screen.
    private static var chromeReserve: CGFloat { 18 + 64 + 12 }

    @ViewBuilder let content: () -> Content
    @State private var naturalHeight: CGFloat?

    var body: some View {
        if let naturalHeight {
            ScrollView {
                measuredContent
            }
            .frame(height: min(naturalHeight, budget))
            .scrollDisabled(naturalHeight <= budget)
        } else {
            measuredContent
        }
    }

    /// `onGeometryChange` rather than a preference key: it reports the
    /// laid-out height directly and survives the outer `fixedSize` pass, where
    /// preference propagation through two nested measurement systems is easy
    /// to lose. It keeps reporting from inside the scroll view too — a
    /// `ScrollView` proposes unbounded height along its axis, so the value
    /// stays the content's true intrinsic height and tracks a list that grows
    /// or shrinks.
    private var measuredContent: some View {
        content()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard height > 0 else { return }
                naturalHeight = height
            }
    }

    private var budget: CGFloat {
        let windowHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.bounds.height
            ?? UIScreen.main.bounds.height
        return windowHeight * Self.maxHeightFraction - Self.chromeReserve
    }
}

// MARK: - From a contact we already have

extension ContactSheet {
    init(
        contact: ContactItem,
        isSending: Bool = false,
        onPay: (() -> Void)? = nil,
        onAccept: (() -> Void)? = nil,
        onIgnore: (() -> Void)? = nil,
        onSelectTransaction: ((Transaction) -> Void)? = nil
    ) {
        self.identity = Identity(
            title: contact.displayTitle,
            username: contact.username?.withoutDashSuffix ?? contact.displayTitle,
            avatarURL: contact.avatarURL,
            identitySeed: contact.contactIdentityId,
            publicMessage: contact.publicMessage)
        self.relationship = switch contact.relationship {
        case .incoming: .requestReceived
        case .outgoing: .requestSent
        case .established: .established
        }
        self.isSending = isSending
        self.onPay = onPay
        self.onAccept = onAccept
        self.onIgnore = onIgnore
        self.onSelectTransaction = onSelectTransaction
        self.contact = contact
    }
}

// MARK: - From a network search hit

extension ContactSheet {
    init(
        result: DpnsSearchResult,
        collision: AddContactViewModel.Collision,
        /// Present when this identity is already known to us, which is the
        /// only way to get an avatar or a public message for it.
        contact: ContactItem?,
        isSending: Bool = false,
        onPay: (() -> Void)? = nil,
        onSendRequest: (() -> Void)? = nil,
        onAccept: (() -> Void)? = nil,
        onIgnore: (() -> Void)? = nil,
        onSelectTransaction: ((Transaction) -> Void)? = nil
    ) {
        let username = result.fullName.withoutDashSuffix
        self.identity = Identity(
            title: contact?.displayTitle ?? username,
            username: username,
            avatarURL: contact?.avatarURL,
            identitySeed: result.identityId,
            publicMessage: contact?.publicMessage)
        self.relationship = switch collision {
        case .none: .stranger
        case .alreadyRequested: .requestSent
        // Muting hid their request from us; it is still live on Platform,
        // so the sheet offers the same answer it would for a fresh one.
        case .theyAskedUs, .ignoredSender: .requestReceived
        case .established: .established
        case .isSelf: .isSelf
        case .missingDashPayKeys: .cannotReceiveRequests
        }
        self.isSending = isSending
        self.onPay = onPay
        self.onSendRequest = onSendRequest
        self.onAccept = onAccept
        self.onIgnore = onIgnore
        self.onSelectTransaction = onSelectTransaction
        self.contact = contact
    }
}

#if DEBUG

/// Presented through `.sheet` rather than rendered flat, so the canvas shows
/// the real thing: the bottom sheet over the screen it is raised from, at the
/// height its content actually needs.
private struct ContactSheetHost: View {
    let relationship: ContactSheet.Relationship
    var identity = ContactSheet.Identity(
        title: "briantest63a",
        username: "briantest63a",
        avatarURL: nil,
        identitySeed: Data("briantest63a".utf8),
        publicMessage: nil)
    var isSending = false
    @State private var isPresented = true

    var body: some View {
        Color.dash.primaryBackground
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                ContactSheet(
                    identity: identity,
                    relationship: relationship,
                    isSending: isSending,
                    onPay: {}, onSendRequest: {}, onAccept: {}, onIgnore: {})
            }
    }
}

#Preview("Stranger") { ContactSheetHost(relationship: .stranger) }

#Preview("Stranger — sending") { ContactSheetHost(relationship: .stranger, isSending: true) }

#Preview("Request sent") { ContactSheetHost(relationship: .requestSent) }

#Preview("Request received") { ContactSheetHost(relationship: .requestReceived) }

#Preview("Request received — accepting") {
    ContactSheetHost(relationship: .requestReceived, isSending: true)
}

#Preview("Established") { ContactSheetHost(relationship: .established) }

#Preview("Cannot receive requests") { ContactSheetHost(relationship: .cannotReceiveRequests) }

#Preview("This is you") { ContactSheetHost(relationship: .isSelf) }

/// The tallest state: a display name over the username, plus a published
/// message — the sheet has to grow for it.
#Preview("Established — full profile") {
    ContactSheetHost(
        relationship: .established,
        identity: ContactSheet.Identity(
            title: "Brian",
            username: "briantest63a",
            avatarURL: nil,
            identitySeed: Data("briantest63a".utf8),
            publicMessage: "Building things on Dash Platform. Ping me about contested names, invitations, or anything DashPay."))
}

#endif
