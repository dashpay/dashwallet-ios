//
//  ContactRow.swift
//  DashWallet
//
//  A single established-contact row.
//

import SwiftUI
import DashUIKit

struct ContactRow: View {
    let item: ContactItem
    var showPendingBadge: Bool = false

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
                if let secondary = secondaryLine {
                    Text(secondary)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            if showPendingBadge {
                Text(NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dashGolden)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 70)
    }

    /// Show the username as the second line when the first line is the
    /// profile display name or alias (both known and different).
    private var secondaryLine: String? {
        guard let username = item.username?.withoutDashSuffix,
              !username.isEmpty,
              username != item.displayTitle else { return nil }
        return username
    }
}
