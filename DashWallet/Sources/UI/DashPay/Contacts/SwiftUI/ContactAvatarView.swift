//
//  ContactAvatarView.swift
//  DashWallet
//
//  Avatar + shared visual components for the SDK contacts screens
//  (migration Row #18), styled after the Android dash-wallet DashPay
//  design (wallet/res/layout/dashpay_contact_row.xml and friends).
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
struct ContactAvatarView: View {
    let title: String
    let avatarURL: String?
    let identitySeed: Data
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(backgroundColor)
            Text(initial)
                .font(.system(size: size * 0.5, weight: .regular))
                .foregroundColor(.white)
        }
    }

    private var initial: String {
        guard let first = title.first else { return "?" }
        return String(first).uppercased()
    }

    private var backgroundColor: Color {
        guard let scalar = title.uppercased().unicodeScalars.first else {
            return Color(hue: 0, saturation: 0.3, brightness: 0.6)
        }
        let v = scalar.value
        let index: Double
        switch v {
        case 48...57:  // '0'–'9' → 0–9
            index = Double(v - 48)
        case 65...90:  // 'A'–'Z' → 10–35
            index = Double(v - 55)
        default:
            index = Double(v % 36)
        }
        return Color(hue: index / 36.0, saturation: 0.3, brightness: 0.6)
    }
}

// MARK: - Shared controls (Android button styles)

/// Android `Button.Primary.ExtraSmall.Blue`: 30pt tall pill, 8pt
/// radius, 10%-alpha Dash-Blue fill, Dash-Blue label.
struct AcceptPillButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(NSLocalizedString("Accept", comment: "DashPay Contacts"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dashBlue)
                .frame(minWidth: 64)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.dashBlue.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Android `Button.Primary.Small.Round` with `ic_ignore_x`: a plain
/// 30pt round ✕.
struct IgnoreCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.gray300Alpha10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("Ignore", comment: "DashPay Contacts"))
    }
}

/// Android `round_corners_white_bg` search field: white, 8pt radius,
/// magnifier leading, 45pt tall (list variant).
struct ContactsSearchField: View {
    let placeholder: String
    @Binding var text: String
    var height: CGFloat = 45

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.tertiaryText)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondaryBackground)
                .shadow(color: .shadow, radius: 4, y: 1))
    }
}

/// Android white card container (8pt radius) used for row groups.
struct ContactsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondaryBackground))
    }
}
