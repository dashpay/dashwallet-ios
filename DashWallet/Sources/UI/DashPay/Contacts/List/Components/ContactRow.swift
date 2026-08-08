//
//  ContactRow.swift
//  DashWallet
//
//  A single established-contact row.
//

import SwiftUI
import DashUIKit

/// One contact row for every section of the list. What trails the name is
/// decided by `item.relationship`, not by the caller: an incoming request
/// gets the accept/ignore pair, an outgoing one the pending badge, and an
/// established contact nothing. Passing that in was how the old split into
/// two row types started.
struct ContactRow: View {
    let item: ContactItem
    /// True while this row's accept or ignore is in flight.
    var isProcessing: Bool = false
    /// Only called for an incoming request; nil elsewhere.
    var onAccept: (() -> Void)? = nil
    var onIgnore: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ContactAvatarView(
                title: item.displayTitle,
                avatarURL: item.avatarURL,
                identitySeed: item.contactIdentityId
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .dashFont(.subheadMedium)
                    .foregroundStyle(Color.dash.primaryText)

                if let helpText = secondaryLine {
                    Text(helpText)
                        .dashFont(.footnote)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
            .padding(.leading, 6)

            Spacer()

            trailing
        }
        .padding(10)
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.relationship {
        case .incoming:
            DashUIKit.DashButton(
                text: NSLocalizedString("Accept", comment: "DashPay Contacts"),
                isLoading: isProcessing,
                size: .extraSmall,
                style: .filledBlue
            ) {
                onAccept?()
            }

            if !isProcessing {
                Button(action: { onIgnore?() }) {
                    XmarkIcon(size: 9, color: Color.dash.primaryText)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(NSLocalizedString("Close", comment: "DashPay Contacts"))
            }
        case .outgoing:
            Text(NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts"))
                .dashFont(.caption1Medium)
                .foregroundStyle(Color.dash.orange)
        case .established:
            EmptyView()
        }
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

#if DEBUG

/// Every section the list renders, in one place — the trailing accessory is
/// the only thing that differs between them.
#Preview {
    ContactsCard {
        VStack(spacing: 0) {
            ContactRow(item: .preview(title: "briantest63a"))
            Divider().padding(.leading, 61)
            ContactRow(
                item: .preview(title: "s22test63b", relationship: .incoming),
                onAccept: {}, onIgnore: {})
            Divider().padding(.leading, 61)
            ContactRow(
                item: .preview(title: "Upsilon2", relationship: .incoming),
                isProcessing: true)
            Divider().padding(.leading, 61)
            ContactRow(item: .preview(title: "Delta", relationship: .outgoing))
        }
    }
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
