//
//  ContactActivityEventRow.swift
//  DashWallet
//
//  One relationship event — a request sent, received or accepted.
//

import SwiftUI
import DashUIKit

/// The entries that move no money, in the contact activity card and in the
/// notifications feed.
///
/// Laid out to `DashUIKit.TransactionView`'s metrics (30pt icon, 16pt gap,
/// 12/10 padding, the same two type tokens) so it sits flush with the payment
/// rows beside it, but drawn here rather than through that component: it
/// always renders a `DashAmount`, and these entries have no amount — a zero
/// would read as a payment of nothing. If `TransactionView` ever gains an
/// amount-less mode, this should collapse into it.
struct ContactActivityEventRow: View {

    /// Shown in place of the state symbol by feeds that mix people, where
    /// whose event it is matters more than which kind it is.
    struct Avatar {
        let title: String
        let url: String?
        let identitySeed: Data
    }

    let kind: ContactActivityViewModel.RelationshipEvent.Kind
    let date: Date
    let counterparty: String
    var avatar: Avatar? = nil
    /// Newer than the last time the user opened the notifications screen.
    var isUnread = false
    /// Trailing control — the accept/ignore pair, a pending marker. `AnyView`
    /// because the row is stored in arrays of mixed entries; the alternative
    /// is making the whole row generic, which its callers would then spread.
    var accessory: AnyView? = nil

    init(event: ContactActivityViewModel.RelationshipEvent) {
        self.kind = event.kind
        self.date = event.date
        self.counterparty = event.counterparty
    }

    init(
        kind: ContactActivityViewModel.RelationshipEvent.Kind,
        date: Date,
        counterparty: String,
        avatar: Avatar? = nil,
        isUnread: Bool = false,
        accessory: AnyView? = nil
    ) {
        self.kind = kind
        self.date = date
        self.counterparty = counterparty
        self.avatar = avatar
        self.isUnread = isUnread
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 16) {
            leading

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .dashFont(.footnoteMedium)
                    .foregroundStyle(Color.dash.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(DWDateFormatter.sharedInstance.timeOnly(from: date))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
            }

            Spacer(minLength: 8)

            if isUnread {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 8, height: 8)
            }

            accessory
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var leading: some View {
        if let avatar {
            ContactAvatarView(
                title: avatar.title,
                avatarURL: avatar.url,
                identitySeed: avatar.identitySeed)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
        }
    }

    private var title: String {
        switch kind {
        case .requestSent:
            String(
                format: NSLocalizedString("You sent a contact request to %@", comment: "DashPay Contacts"),
                counterparty)
        case .requestReceived:
            String(
                format: NSLocalizedString("%@ sent you a contact request", comment: "DashPay Contacts"),
                counterparty)
        case .weAccepted:
            String(
                format: NSLocalizedString("You accepted the request from %@", comment: "DashPay Contacts"),
                counterparty)
        case .theyAccepted:
            String(
                format: NSLocalizedString("%@ accepted your contact request", comment: "DashPay Contacts"),
                counterparty)
        }
    }

    private var symbol: String {
        switch kind {
        case .requestSent, .requestReceived: "person.crop.circle.badge.plus"
        case .weAccepted, .theyAccepted: "checkmark.circle.fill"
        }
    }

    /// Green once the friendship is complete, blue while it is only a request
    /// — the same reading the contact rows give those two states.
    private var tint: Color {
        switch kind {
        case .requestSent, .requestReceived: Color.dash.blue
        case .weAccepted, .theyAccepted: Color.dash.green
        }
    }
}

#if DEBUG

/// In the activity card: one contact, so the symbol carries the kind.
#Preview("Contact activity") {
    VStack(spacing: 4) {
        ContactActivityEventRow(event: .preview(kind: .requestSent))
        ContactActivityEventRow(event: .preview(kind: .requestReceived, daysAgo: 1))
        ContactActivityEventRow(event: .preview(kind: .weAccepted, daysAgo: 2))
        ContactActivityEventRow(event: .preview(kind: .theyAccepted, daysAgo: 3))
    }
    .modifier(DashUIKit.MenuViewModifier())
    .padding()
    .background(Color.dash.primaryBackground)
}

/// In the notifications feed: many people, so the avatar replaces the symbol
/// and the actionable row carries its buttons.
#Preview("Notifications feed") {
    VStack(spacing: 4) {
        ContactActivityEventRow(
            kind: .requestReceived,
            date: Date(),
            counterparty: "briantest63a",
            avatar: .init(title: "briantest63a", url: nil, identitySeed: Data("briantest63a".utf8)),
            isUnread: true,
            accessory: AnyView(HStack(spacing: 8) {
                AcceptPillButton {}
                IgnoreCircleButton {}
            }))

        ContactActivityEventRow(
            kind: .theyAccepted,
            date: Date(),
            counterparty: "s22test63b",
            avatar: .init(title: "s22test63b", url: nil, identitySeed: Data("s22test63b".utf8)),
            accessory: AnyView(Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(Color.dash.green)))

        ContactActivityEventRow(
            kind: .requestSent,
            date: Date(),
            counterparty: "Upsilon2",
            avatar: .init(title: "Upsilon2", url: nil, identitySeed: Data("Upsilon2".utf8)))
    }
    .modifier(DashUIKit.MenuViewModifier())
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
