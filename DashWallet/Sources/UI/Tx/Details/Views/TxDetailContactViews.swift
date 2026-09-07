//
//  TxDetailContactViews.swift
//  DashWallet
//
//  Contact-aware pieces of the transaction-details screen, for
//  transactions that are recorded DashPay payments. Mirrors the Android
//  dash-wallet transaction result design (`transaction_result_content.xml`
//  + `TransactionResultViewBinder`): the counterparty's avatar carries the
//  direction icon as a corner badge, and the counterparty row stands in
//  for the raw address the payment went to.
//

import SwiftUI
import DashUIKit

// MARK: - TxDetailContactAvatar

/// Header avatar: the contact's picture with the transaction's direction
/// icon badged into the bottom-trailing corner (Android `check_icon` +
/// `secondary_icon`).
struct TxDetailContactAvatar: View {
    let contact: TxDetailModel.ContactParty
    let directionIcon: UIImage
    var size: CGFloat = 50

    /// Same badge-to-icon ratio (14/30) and ring as `DashUIKit
    /// .TransactionView`, so the header badge and the home row's badge read
    /// as the same token at their different sizes.
    private var badgeSize: CGFloat { size * 14 / 30 }

    var body: some View {
        ContactAvatarView(
            title: contact.name,
            avatarURL: contact.avatarURL,
            identitySeed: contact.identityId,
            size: size
        )
        .overlay(alignment: .bottomTrailing) {
            Image(uiImage: directionIcon)
                .resizable()
                .scaledToFit()
                .frame(width: badgeSize, height: badgeSize)
                .padding(2)
                .background(Circle().fill(Color(uiColor: .dw_secondaryBackground())))
                .offset(x: 3, y: 3)
        }
    }
}

// MARK: - TxDetailContactRow

/// The "Sent to / Received from <contact>" row. Replaces the counterparty
/// address group — an address says nothing a contact payment's own record
/// doesn't say better — and opens the contact's profile on tap.
///
/// Name only, no avatar: the header already carries the contact's picture,
/// and a second copy of it here competes with the plain right-aligned values
/// the rest of the section uses.
struct TxDetailContactRow: View {
    let title: String
    let contact: TxDetailModel.ContactParty

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.dash.footnoteMedium)
                .foregroundColor(.dash.secondaryText)
                .lineLimit(1)
                // The row label is short and fixed; a long contact name is
                // what gives way when the row runs out of width.
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                Text(contact.name)
                    .font(.dash.footnote)
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let secondaryName = contact.secondaryName {
                    Text(secondaryName)
                        .font(.dash.caption1)
                        .foregroundColor(.dash.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.dash.tertiaryText)
        }
        .padding(.vertical, 4)
    }
}
