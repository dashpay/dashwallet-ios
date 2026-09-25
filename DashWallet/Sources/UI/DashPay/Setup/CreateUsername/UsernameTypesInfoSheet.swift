//
//  UsernameTypesInfoSheet.swift
//  DashWallet
//
//  "What are contested and non-contested usernames?" — opened from the note
//  a non-contested-only invitation puts under the username rules (Android:
//  `UsernameTypesDialog`).
//

import DashUIKit
import SwiftUI

struct UsernameTypesInfoSheet: View {
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("What are contested and non-contested usernames?", comment: "DashPay Invitations"))
                .dashFont(.title3)
                .foregroundColor(.dash.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(NSLocalizedString(
                "There are two types of usernames: contested and non-contested.\n\nNon-contested usernames have at least one number (2-9) or are longer than 20 characters and will be automatically approved.\n\nIf you want to create a contested username which is shorter and without numbers, you need to register with DashPay without an invitation, pay the required fee and wait for approval upon completion of the voting period.",
                comment: "DashPay Invitations"))
                .dashFont(.body)
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            DashUIKit.DashButton(
                text: NSLocalizedString("Close", comment: ""),
                fillsWidth: true,
                size: .large,
                style: .tintedGray,
                action: onClose)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}
