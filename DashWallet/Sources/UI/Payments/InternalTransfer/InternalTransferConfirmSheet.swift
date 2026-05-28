//
//  InternalTransferConfirmSheet.swift
//  DashWallet
//

import SwiftUI

/// Confirmation half-sheet shown when the user taps `Continue` on the
/// Internal transfer screen. Pure display — Confirm currently dismisses
/// without invoking any transfer logic (shielding lands later).
struct InternalTransferConfirmSheet: View {

    let dashDuffs: Int64
    let creditsText: String
    let fiatText: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Confirm", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
                .padding(.top, 20)

            DashAmount(
                amount: dashDuffs,
                font: .largeTitle,
                dashSymbolFactor: 0.7,
                showDirection: false)
                .padding(.top, 14)

            secondaryLine
                .padding(.top, 6)

            summaryCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            privacyTipCard
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Spacer(minLength: 12)

            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveButtonText: NSLocalizedString("Confirm", comment: ""),
                positiveButtonAction: onConfirm,
                negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                negativeButtonAction: onCancel)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(Color.primaryBackground)
    }

    // MARK: - Pieces

    private var dragHandle: some View {
        Rectangle()
            .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }

    private var secondaryLine: some View {
        HStack(spacing: 4) {
            Text("~ \(creditsText)")
                .font(.subheadline)
                .foregroundColor(.secondaryText)
            Text("c")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondaryText)
            Text("/ \(fiatText)")
                .font(.subheadline)
                .foregroundColor(.secondaryText)
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                label: NSLocalizedString("From", comment: ""),
                value: NSLocalizedString("Dash Wallet", comment: ""))
            divider
            summaryRow(
                label: NSLocalizedString("To", comment: ""),
                value: NSLocalizedString("Shielded balance", comment: ""))
            divider
            summaryRow(
                label: NSLocalizedString("Network fee", comment: ""),
                value: "~ $X")
            divider
            summaryRow(
                label: NSLocalizedString("Total credits", comment: ""),
                valueView: AnyView(
                    HStack(spacing: 4) {
                        Text("~ \(creditsText)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primaryText)
                        Text("c")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primaryText)
                    }))
        }
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private func summaryRow(label: String, value: String) -> some View {
        summaryRow(
            label: label,
            valueView: AnyView(
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primaryText)))
    }

    private func summaryRow(label: String, valueView: AnyView) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
            Spacer()
            valueView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray300.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Privacy tip

    private var privacyTipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dashBlue)
                    .frame(width: 30, height: 30)
                Image(systemName: "shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Privacy tip", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(NSLocalizedString(
                    "For best privacy, wait at least 2 hours before using these credits.",
                    comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }
}
