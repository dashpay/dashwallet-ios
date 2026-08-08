//
//  PayContactSheet.swift
//  DashWallet
//
//  Amount entry and send flow for paying a DashPay contact.
//

import SwiftUI
import DashUIKit

struct PayContactSheet: View {
    @StateObject private var viewModel: PayContactViewModel
    @Environment(\.dismiss) private var dismiss

    /// Default `nil` rather than a fresh view model: default arguments are
    /// evaluated off the main actor and `PayContactViewModel` is
    /// `@MainActor`. `StateObject`'s autoclosure defers construction to view
    /// installation. Previews pass one in.
    init(contact: ContactItem, viewModel: PayContactViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PayContactViewModel(contact: contact))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let txid = viewModel.sentTxid {
                    success(txid: txid)
                } else {
                    form
                }
            }
            .padding(24)
            .navigationTitle(String(
                format: NSLocalizedString("Pay %@", comment: "DashPay Contacts"),
                viewModel.contact.displayTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString(viewModel.sentTxid == nil ? "Cancel" : "Done", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(.dash.blue)
                }
            }
            .alert(
                NSLocalizedString("Error", comment: ""),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } })
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        // The sheet carries its own keypad now, so it needs the room the
        // system keyboard used to occupy.
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var form: some View {
        // The shared amount surface every other send screen uses, over the
        // app's own keypad. A raw `TextField` + `.decimalPad` accepted whatever
        // the system keyboard allowed — a bare separator, a locale comma, more
        // precision than DASH has — and left validation to the parser, so the
        // typed text and the amount actually sent could disagree.
        EnterAmountView(
            primaryAmount: viewModel.amountText.isEmpty ? "0" : viewModel.amountText,
            secondaryAmount: viewModel.fiatAmountText,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(App.fiatCurrency),
            isPrimarySelected: true,
            isCurrencySelectorHidden: true,
            onMax: { viewModel.fillWithMax() }
        )
        .padding(.top, 12)

        Text(String(
            format: NSLocalizedString("Available: %@ DASH", comment: "DashPay Contacts"),
            PayContactViewModel.dashString(duffs: viewModel.maxSendable)))
            .font(.system(size: 13))
            .foregroundColor(.dash.secondaryText)

        Text(NSLocalizedString("A network fee will be added on top of the amount.", comment: "DashPay Contacts"))
            .font(.system(size: 12))
            .foregroundColor(.dash.tertiaryText)

        NumericKeyboardView(
            value: $viewModel.amountText,
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Pay", comment: "DashPay Contacts"),
            actionEnabled: viewModel.parsedDuffs != nil,
            inProgress: viewModel.isSending,
            actionHandler: { viewModel.pay() }
        )
        .padding(.top, 8)
    }

    private func success(txid: Data) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Color.dash.green)
            Text(NSLocalizedString("Payment Sent", comment: "DashPay Contacts"))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.dash.primaryText)
            Text(String(
                format: NSLocalizedString("%@ DASH sent to %@", comment: "DashPay Contacts"),
                viewModel.sentAmountDuffs.map { PayContactViewModel.dashString(duffs: $0) } ?? viewModel.amountText,
                viewModel.contact.displayTitle))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            if let fee = viewModel.sentFeeDuffs {
                Text(String(
                    format: NSLocalizedString("Network fee: %@ DASH", comment: "DashPay Contacts"),
                    PayContactViewModel.dashString(duffs: fee)))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.tertiaryText)
            }
        }
        .padding(.top, 24)
    }
}

#if DEBUG

/// No wallet state behind these, so `maxSendable` is 0 and the amount never
/// parses — the entry preview shows the disabled-Pay state. The confirmation
/// is seeded directly instead of being reached through a send.
#Preview("Amount entry") {
    PayContactSheet(
        contact: .preview(title: "briantest63a"),
        viewModel: .preview(contact: .preview(title: "briantest63a")))
}

#Preview("Sent") {
    PayContactSheet(
        contact: .preview(title: "s22test63b"),
        viewModel: .preview(
            contact: .preview(title: "s22test63b"),
            sent: (txid: Data(repeating: 0xAB, count: 32), amount: 1_500_000, fee: 226)))
}

#endif
