//
//  AcceptPillButton.swift
//  DashWallet
//
//  Pill-shaped Accept action used on incoming contact requests.
//

import SwiftUI
import DashUIKit

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

#if DEBUG

// MARK: - Preview

#Preview {
    AcceptPillButton(action: {})
        .padding()
}

#endif
