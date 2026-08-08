//
//  Color+Contacts.swift
//  DashWallet
//
//  Colour tokens shared by the DashPay contacts screens.
//

import SwiftUI

// MARK: - Design tokens (Android parity)

extension Color {
    /// Android `dash_golden` #F5A623 — pending-request state text.
    static var dashGolden: Color { Color(red: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255) }
    /// Android `system_green` #3CB878 — Accept (positive) actions.
    static var dashGreen: Color { Color(red: 0x3C / 255, green: 0xB8 / 255, blue: 0x78 / 255) }
}

// MARK: - Avatar

/// Contact avatar: profile `avatarUrl` when present, otherwise the
/// Android `UserAvatarPlaceholderDrawable` placeholder — first letter
/// in white on a deterministic HSV color derived from that letter:
/// digits 0–9 → indices 0–9, A–Z → 10–35; hue = index/36 × 360°,
/// saturation 30%, value 60%. Byte-for-byte the Android algorithm so
/// the same user renders the same color on both platforms.
