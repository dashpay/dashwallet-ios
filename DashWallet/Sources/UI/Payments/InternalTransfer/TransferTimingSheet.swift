//
//  TransferTimingSheet.swift
//  DashWallet
//

import SwiftUI

struct TransferTimingSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primaryText)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
                }
            }

            Text(NSLocalizedString("Transfers take different times", comment: ""))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 18) {
                timingRow(
                    iconSystemName: "bolt.fill",
                    iconColor: .orange,
                    title: NSLocalizedString("From Dash Wallet to Shielded balance", comment: ""),
                    subtitle: NSLocalizedString("The transfer is instant", comment: ""))

                timingRow(
                    iconSystemName: "clock.fill",
                    iconColor: .blue,
                    title: NSLocalizedString("From Shielded balance to Dash Wallet", comment: ""),
                    subtitle: NSLocalizedString("The transfer could take up to 10 minutes", comment: ""))
            }

            Spacer(minLength: 8)

            DashButton(
                text: NSLocalizedString("I got it", comment: ""),
                style: .filledBlue,
                size: .large,
                action: {
                    onConfirm()
                })
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .background(Color.primaryBackground)
    }

    private func timingRow(
        iconSystemName: String,
        iconColor: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
