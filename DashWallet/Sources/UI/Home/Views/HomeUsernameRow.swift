//
//  HomeUsernameRow.swift
//  DashWallet
//
//  Persistent Home entry point for a registered DashPay username (SB-11).
//  The nav-bar avatar (HomeViewController) is scroll-gated — hidden at the
//  top of the feed and revealed only past `kTopBarShowThreshold`, so on a
//  short feed it can be unreachable. This row sits inside the balance
//  header, which is always on screen at the top of Home, and reuses the
//  same tap target (`profileAction()` → `SDKIdentityProfileSheet`) so there
//  is a single source of truth for "open my profile".
//

import SwiftUI
import DashUIKit

#if DASHPAY
struct HomeUsernameRow: View {
    let username: String
    let avatarURL: String?
    let identitySeed: Data
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ContactAvatarView(title: username, avatarURL: avatarURL, identitySeed: identitySeed, size: 36)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("My profile, %@", comment: "Home — persistent username row accessibility label"), username)))
    }
}

#if DEBUG

// Previewed on the balance header's color, where the row actually sits, so
// the white text/chevron contrast is exercised. The no-avatar case is the
// common one (registered username, `hasProfile=false` → letter placeholder).
#Preview("No avatar (placeholder)") {
    HomeUsernameRow(
        username: "Epsilon2",
        avatarURL: nil,
        identitySeed: Data([0x0e, 0x8f, 0xdf, 0x06]),
        onTap: {})
        .padding(24)
        .background(Color.navigationBarColor)
}

#Preview("Long username (truncation)") {
    HomeUsernameRow(
        username: "a-very-long-dashpay-username",
        avatarURL: nil,
        identitySeed: Data([0x89, 0xfd, 0x6d, 0xdb]),
        onTap: {})
        .frame(width: 200)
        .padding(24)
        .background(Color.navigationBarColor)
}

#endif
#endif
