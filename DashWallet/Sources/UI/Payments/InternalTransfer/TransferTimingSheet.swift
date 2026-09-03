//
//  TransferTimingSheet.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

struct TransferTimingSheet: View {
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Scrollable: the sheet is presented in a fixed `.medium()` detent and the
            // `BottomSheet` chrome takes part of it, so on a short screen or with a long
            // translation the text no longer fits. Letting it scroll keeps the CTA — the
            // only thing that records the acknowledgement — reachable at any height.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(NSLocalizedString("Transfers take different times", comment: ""))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.dash.primaryText)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashButton(
                text: NSLocalizedString("I got it", comment: ""),
                style: .filledBlue,
                size: .large,
                action: {
                    onConfirm()
                })
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .background(Color.dash.primaryBackground)
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
                    .foregroundColor(.dash.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
