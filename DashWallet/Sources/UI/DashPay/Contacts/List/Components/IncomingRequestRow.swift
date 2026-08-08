//
//  IncomingRequestRow.swift
//  DashWallet
//
//  An incoming contact-request row with its Accept / Ignore pair.
//

import SwiftUI
import DashUIKit

struct IncomingRequestRow: View {
    let item: ContactItem
    let isProcessing: Bool
    let onAccept: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ContactAvatarView(
                title: item.displayTitle,
                avatarURL: item.avatarURL,
                identitySeed: item.contactIdentityId)
                .padding(.leading, 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                if let username = item.username?.withoutDashSuffix, !username.isEmpty, username != item.displayTitle {
                    Text(username)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isProcessing {
                // Android shows an hourglass + golden "Accepting".
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12))
                    Text(NSLocalizedString("Accepting", comment: "DashPay Contacts"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.dashGolden)
                .padding(.trailing, 12)
            } else {
                AcceptPillButton(action: onAccept)
                IgnoreCircleButton(action: onIgnore)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 70)
    }
}

#if DEBUG

/// Both states, because the in-flight one swaps the accept/ignore pair for
/// a progress label and is otherwise only reachable mid-network-call.
#Preview {
    ContactsCard {
        VStack(spacing: 0) {
            IncomingRequestRow(
                item: .preview(title: "briantest63a", relationship: .incoming),
                isProcessing: false,
                onAccept: {}, onIgnore: {})
            Divider().padding(.leading, 61)
            IncomingRequestRow(
                item: .preview(title: "s22test63b", relationship: .incoming),
                isProcessing: true,
                onAccept: {}, onIgnore: {})
        }
    }
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
