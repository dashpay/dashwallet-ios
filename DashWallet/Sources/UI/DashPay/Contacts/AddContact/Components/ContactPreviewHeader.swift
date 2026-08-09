//
//  ContactPreviewHeader.swift
//  DashWallet
//
//  Identity block of the add-contact sheet: avatar, name, and whatever the
//  contact published about themselves.
//

import SwiftUI
import DashUIKit

struct ContactPreviewHeader: View {
    let title: String
    /// The DPNS username. Rendered as a second line only when the title is
    /// something else — a profile display name or the owner's alias.
    let username: String
    let avatarURL: String?
    let identitySeed: Data
    /// `dashpay.profile.publicMessage`, when the contact published one.
    let publicMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 20) {
                ContactAvatarView(
                    title: title,
                    avatarURL: avatarURL,
                    identitySeed: identitySeed,
                    size: 60
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .dashFont(.subheadMedium)
                        .foregroundStyle(Color.dash.primaryText)

                    if username != title {
                        Text(username)
                            .dashFont(.caption1)
                            .foregroundStyle(Color.dash.tertiaryText)
                    }
                }
            }

            if let publicMessage, !publicMessage.isEmpty {
                Text(publicMessage)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
            }
        }
        .padding(.trailing, 40)
    }
}

#if DEBUG

#Preview("Username only") {

    ContactPreviewHeader(
        title: "briantest63a",
        username: "briantest63a",
        avatarURL: nil,
        identitySeed: Data("briantest63a".utf8),
        publicMessage: nil
    )
    .background(.red.opacity(0.3))
}

#Preview("Display name + message") {

    ContactPreviewHeader(
        title: "Brian",
        username: "briantest63a",
        avatarURL: nil,
        identitySeed: Data("briantest63a".utf8),
        publicMessage: "Building things on Dash Platform. Say hi!"
    )
    .background(.red.opacity(0.3))
}

#endif
