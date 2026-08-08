//
//  IgnoreCircleButton.swift
//  DashWallet
//
//  Round Ignore action paired with `AcceptPillButton`.
//

import SwiftUI
import DashUIKit

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
