//
//  ContactsCard.swift
//  DashWallet
//
//  White rounded card that groups contact rows on the gray background.
//

import SwiftUI
import DashUIKit

struct ContactsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
    }
}

#if DEBUG

// No `avatarURL` here — the placeholder path is the deterministic,
// offline-renderable one; the letter and its HSV color both derive from
// `title`, so each initial gets its own hue.
#Preview("Placeholder initials") {
    HStack(spacing: 12) {
        ForEach(["Epsilon2", "Delta", "b-user", "Zoe", "7", "мій"], id: \.self) { title in
            ContactAvatarView(title: title, avatarURL: nil, identitySeed: Data())
        }
    }
    .padding()
}

#Preview("Sizes") {
    HStack(alignment: .center, spacing: 12) {
        ForEach([24.0, 36.0, 48.0, 64.0], id: \.self) { size in
            ContactAvatarView(title: "Epsilon2", avatarURL: nil, identitySeed: Data(), size: size)
        }
    }
    .padding()
}

#Preview("Empty title (fallback)") {
    ContactAvatarView(title: "", avatarURL: nil, identitySeed: Data(), size: 48)
        .padding()
}

#endif
