//
//  ContactAvatarView.swift
//  DashWallet
//
//  Avatar + shared visual components for the SDK contacts screens
//  (migration Row #18), styled after the Android dash-wallet DashPay
//  design (wallet/res/layout/dashpay_contact_row.xml and friends).
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

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
                .foregroundColor(Color.dash.whiteText)
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
                .foregroundColor(.dash.blue)
                .frame(minWidth: 64)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.dash.blue.opacity(0.1)))
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
                .foregroundColor(.dash.secondaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.dash.gray300Alpha10))
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
    var focus: FocusState<Bool>.Binding? = nil

    @FocusState private var internalFocus: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.dash.tertiaryText)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused(focus ?? $internalFocus)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.dash.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground)
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

// MARK: - Identity ID

/// The contact's Platform identity id, in the centred style the contact sheets
/// already use for the lines under the name.
///
/// A username is a DPNS label — it can be contested, transferred, or released
/// and taken by somebody else — so it does not identify a person on its own.
/// The identity id does, which is why it belongs next to the name rather than
/// only inside the QR payload.
///
/// Shown in full base58: that is how identities read on Platform explorers, in
/// the wallet's own identity list and in the `dashpay://user` link, and a
/// reader who needs it at all usually needs to paste the whole value.
struct ContactIdentityIdView: View {
    let identityId: Data
    /// Called once the value is on the pasteboard, for a host that shows its
    /// own confirmation. Without one the button acknowledges the copy itself.
    var onCopy: (() -> Void)? = nil

    @State private var didCopy = false

    private var base58: String { identityId.toBase58String() }

    var body: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("Identity ID", comment: "DashPay Contacts"))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(base58)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(.dash.tertiaryText)
            }
        }
        .padding(.horizontal, 32)
        .contentShape(Rectangle())
        .onTapGesture { copyToPasteboard() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func copyToPasteboard() {
        UIPasteboard.general.string = base58
        if let onCopy {
            onCopy()
            return
        }
        withAnimation { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { didCopy = false }
        }
    }
}
