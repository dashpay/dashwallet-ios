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

/// Works around a real conflict between `BottomSheet.selfSizing`'s
/// measurement scheme and an unbounded content list — without touching
/// DashUIKit (a pinned local SPM dependency on a branch awaiting review).
///
/// `selfSizingSheet` measures `BottomSheet`'s content with
/// `.fixedSize(horizontal: false, vertical: true)`, and that modifier stays
/// on the *rendered* tree, not just a throwaway measurement pass — so the
/// content always lays out at its full natural height, and the sheet's own
/// system-provided viewport (capped at `maxHeightFraction` of the window)
/// simply clips whatever doesn't fit. Its own doc comment says the fix is
/// "wrap it in a ScrollView," but that doesn't survive contact with this
/// measurement scheme: a `ScrollView` under a `fixedSize` proposal does not
/// report a useful ideal height back up — DashUIKit's own PR notes call
/// this out as "mis-sizes or collapses."
///
/// The way out: never let a `ScrollView` sit inside the `fixedSize` pass
/// with an *unresolved* size. Measure the content once, unwrapped — the
/// exact path used today, so short content self-sizes identically to
/// before, and a `ScrollView` never enters the tree for it at all. Only once
/// that measurement exceeds this content's height budget does it get
/// rebuilt inside a `ScrollView` pinned to an *exact* `.frame(height:)`
/// (not `maxHeight:` — an exact height reports a fixed, correct ideal size
/// through the outer `fixedSize` pass regardless of the proposal it
/// receives; a `maxHeight` on a `ScrollView` is exactly the
/// "doesn't report a useful size" case above).
///
/// Two honest trade-offs, not hidden ones:
///  - Switching from the plain branch to the scrolling branch is a SwiftUI
///    branch change, so on that one transition any `@StateObject` inside
///    `content` (`ContactActivityCard`'s view model) is torn down and
///    rebuilt once — one extra, now-cheap reload (see the batch-fetch and
///    bounded-query fixes elsewhere in this change), not a recurring cost,
///    and it never happens for content that fits, which is the common case.
///  - The budget below assumes `BottomSheet`'s current fixed chrome (the
///    18pt grabber + `NavigationBar`'s 64pt `minHeight`, both hardcoded in
///    DashUIKit) plus this content's own top/bottom padding. If a future
///    DashUIKit revision changes either constant, this reserve drifts out
///    of sync with it — there's no way to read those values from here
///    without modifying DashUIKit itself.
private struct SelfSizingScrollLimiter<Content: View>: View {
    /// Mirrors `BottomSheet.selfSizingSheet`'s own default `maxHeightFraction`
    /// (`ContactSheet` doesn't override it), so this content's budget targets
    /// the same ceiling the outer sheet is already capping itself at.
    private static var maxHeightFraction: CGFloat { 0.95 }
    /// Grabber (18) + `NavigationBar` `minHeight` (64) — both outside
    /// `content()`, so the outer `fixedSize` pass counts them on top of
    /// whatever this view reports — plus this content's own 20pt top +
    /// 20pt bottom padding (`ContactSheet.body`), plus an 8pt rounding
    /// buffer. Reserving it here keeps (chrome + this content) comfortably
    /// under DashUIKit's own `maxHeightFraction` budget, so its outer clip
    /// never has anything left to trim.
    private static var chromeReserve: CGFloat { 18 + 64 + 20 + 20 + 8 }

    @ViewBuilder let content: () -> Content
    @State private var naturalHeight: CGFloat?

    var body: some View {
        Group {
            if let naturalHeight, naturalHeight > budget {
                ScrollView {
                    measuredContent
                }
                .frame(height: budget)
            } else {
                measuredContent
            }
        }
    }

    /// The actual content, instrumented to report its own natural height —
    /// used in both branches so a shrinking list (the user narrows the
    /// activity filter down to almost nothing) can drop back out of the
    /// scrolling branch, not just grow into it. `ScrollView` always proposes
    /// an unbounded height to its child along the scroll axis, so this
    /// reports the content's true intrinsic height even from inside it.
    private var measuredContent: some View {
        content()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SelfSizingScrollLimiterHeightKey.self,
                        value: proxy.size.height)
                }
            )
            .onPreferenceChange(SelfSizingScrollLimiterHeightKey.self) { naturalHeight = $0 }
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

private struct SelfSizingScrollLimiterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
        case .theyAskedUs: .requestReceived
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
