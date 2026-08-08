//
//  ContactAvatarView.swift
//  DashWallet
//
//  Circular contact avatar with a monogram fallback.
//

import SwiftUI
import DashUIKit

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
