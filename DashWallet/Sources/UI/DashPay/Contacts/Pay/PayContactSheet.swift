//
//  PayContactSheet.swift
//  DashWallet
//
//  Amount entry and send flow for paying a DashPay contact.
//

import SwiftUI
import DashUIKit

struct PayContactSheet: View {
    let contact: ContactItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var walletState = SwiftDashSDKWalletState.shared
    @State private var amountText = ""
    @State private var isSending = false
    @State private var sentTxid: Data? = nil
    /// Exact network fee (duffs) of the broadcast transaction.
    @State private var sentFeeDuffs: UInt64? = nil
    /// Duffs actually broadcast, captured at send time.
    ///
    /// The confirmation must state what was paid, not what was typed. Echoing
    /// `amountText` back made any gap between the two — a locale separator, a
    /// stray character, precision the parser drops — render as a truthful-looking
    /// "sent" line for an amount that never left the wallet.
    @State private var sentAmountDuffs: UInt64?
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let txid = sentTxid {
                    success(txid: txid)
                } else {
                    form
                }
            }
            .padding(24)
            .navigationTitle(String(
                format: NSLocalizedString("Pay %@", comment: "DashPay Contacts"),
                contact.displayTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString(sentTxid == nil ? "Cancel" : "Done", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(.dash.blue)
                }
            }
            .alert(
                NSLocalizedString("Error", comment: ""),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } })
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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
            primaryAmount: amountText.isEmpty ? "0" : amountText,
            secondaryAmount: fiatAmountText,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(App.fiatCurrency),
            isPrimarySelected: true,
            isCurrencySelectorHidden: true,
            onMax: { amountText = Self.dashString(duffs: maxSendable) }
        )
        .padding(.top, 12)

        Text(String(
            format: NSLocalizedString("Available: %@ DASH", comment: "DashPay Contacts"),
            Self.dashString(duffs: maxSendable)))
            .font(.system(size: 13))
            .foregroundColor(.dash.secondaryText)

        Text(NSLocalizedString("A network fee will be added on top of the amount.", comment: "DashPay Contacts"))
            .font(.system(size: 12))
            .foregroundColor(.dash.tertiaryText)

        NumericKeyboardView(
            value: $amountText,
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Pay", comment: "DashPay Contacts"),
            actionEnabled: parsedDuffs != nil,
            inProgress: isSending,
            actionHandler: { pay() }
        )
        .padding(.top, 8)
    }

    /// Fiat equivalent of what is typed, for the secondary line. Empty while
    /// the amount is unparseable or rates have not arrived.
    private var fiatAmountText: String {
        guard let duffs = parsedDuffs else { return "" }
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    private func success(txid: Data) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.dashGreen)
            Text(NSLocalizedString("Payment Sent", comment: "DashPay Contacts"))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.dash.primaryText)
            Text(String(
                format: NSLocalizedString("%@ DASH sent to %@", comment: "DashPay Contacts"),
                sentAmountDuffs.map { Self.dashString(duffs: $0) } ?? amountText,
                contact.displayTitle))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            if let fee = sentFeeDuffs {
                Text(String(
                    format: NSLocalizedString("Network fee: %@ DASH", comment: "DashPay Contacts"),
                    Self.dashString(duffs: fee)))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.tertiaryText)
            }
        }
        .padding(.top, 24)
    }

    // MARK: Amounts

    private var maxSendable: UInt64 {
        walletState.feeAwareMaxSendable()
    }

    /// Entered DASH amount in duffs, or nil when unparseable, zero,
    /// or above the sendable cap. The cap check runs in `Decimal`
    /// space BEFORE the `UInt64` conversion — `NSDecimalNumber`'s
    /// `uint64Value` wraps modulo 2^64, so an overflowing input
    /// (e.g. 2^64 + 1 duffs) would otherwise alias to a tiny value
    /// that passes the range check and sends the wrong amount.
    private var parsedDuffs: UInt64? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let dash = Decimal(string: normalized), dash > 0 else { return nil }
        let duffsDecimal = dash * Decimal(100_000_000)
        guard duffsDecimal <= Decimal(maxSendable) else { return nil }
        let duffs = NSDecimalNumber(decimal: duffsDecimal).uint64Value
        guard duffs > 0 else { return nil }
        return duffs
    }

    private static func dashString(duffs: UInt64) -> String {
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return "\(dash)"
    }

    // MARK: Pay

    private func pay() {
        guard let duffs = parsedDuffs, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let (txid, feeDuffs) = try await WalletSendService.shared.sendToContact(
                    contactIdentityId: contact.contactIdentityId,
                    amount: duffs)
                sentTxid = txid
                sentFeeDuffs = feeDuffs
                sentAmountDuffs = duffs
                // Project the freshly recorded Sent entry to SwiftData
                // right away — the entry lives only in Rust memory
                // until a projection runs, and an app kill before one
                // would lose it permanently (the SDK cannot re-derive
                // sent history; learned the hard way 2026-07-08).
                SwiftDashSDKContactsService.shared.refreshPaymentsProjection()
            } catch {
                let nsError = error as NSError
                if !WalletSendService.isAuthenticationCancelledError(nsError) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
