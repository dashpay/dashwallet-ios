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

// MARK: - Preview

/// Shown on the gray screen background, which is the only place the card's
/// white fill and rounding read correctly.
#Preview {
    ContactsCard {
        VStack(spacing: 0) {
            ForEach(["Alice", "s22test63b", "Upsilon2"], id: \.self) { name in
                HStack(spacing: 12) {
                    ContactAvatarView(title: name, avatarURL: nil, identitySeed: Data(name.utf8))
                    Text(name)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            }
        }
    }
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
