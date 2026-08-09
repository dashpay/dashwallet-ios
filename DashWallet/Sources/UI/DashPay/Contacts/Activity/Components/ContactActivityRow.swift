//
//  ContactActivityRow.swift
//  DashWallet
//
//  One payment in the contact activity list.
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

/// A DashPay payment, drawn by the same `DashUIKit.TransactionView` the home
/// transaction list uses — same icons, typography, amount rendering and row
/// metrics, so a payment looks the same wherever the user meets it. This type
/// only maps a ``ContactPayment`` onto that component's inputs.
struct ContactActivityRow: View {
    let payment: SwiftDashSDKContactsService.ContactPayment
    /// Opens the transaction. Absent when this payment has no local
    /// transaction to open — `TransactionView` then renders a static row
    /// instead of a button, rather than a control that leads nowhere.
    var onTap: (() -> Void)? = nil

    private var isSent: Bool { payment.direction == .sent }

    var body: some View {
        DashUIKit.TransactionView(
            icon: .custom(isSent ? "tx.item.sent.icon" : "tx.item.received.icon"),
            title: isSent
                ? NSLocalizedString("Sent", comment: "DashPay Contacts")
                : NSLocalizedString("Received", comment: "DashPay Contacts"),
            // Time only: the day is the group heading above, exactly as in
            // the home transaction list.
            subtitle: DWDateFormatter.sharedInstance.timeOnly(from: payment.date),
            details: memo,
            dashAmount: signedDuffs,
            amountSign: .always,
            fiat: payment.fiatString,
            action: onTap)
    }

    /// Duffs as `TransactionView` wants them: signed, outgoing negative.
    /// Clamped because the row's amount is display-only — a value past
    /// `Int64.max` would trap, and no real payment reaches it.
    private var signedDuffs: Int64 {
        let magnitude = Int64(clamping: payment.amountDuffs)
        return isSent ? -magnitude : magnitude
    }

    /// Rendered in the badge next to the time. The counterparty needs no
    /// naming here — this list belongs to one contact — so the badge is free
    /// for the memo, which is the only per-payment detail we hold.
    private var memo: String? {
        guard let memo = payment.memo, !memo.isEmpty else { return nil }
        return memo
    }
}

#if DEBUG

#Preview {
    VStack(spacing: 0) {
        ContactActivityRow(payment: .preview(), onTap: {})
        ContactActivityRow(payment: .preview(
            txid: "a1", amountDuffs: 4_000_000, direction: .received, daysAgo: 3))
        ContactActivityRow(payment: .preview(
            txid: "b2", amountDuffs: 250_000_000, memo: "Lunch", daysAgo: 12))
        // No fiat rate: the amount stands alone.
        ContactActivityRow(payment: .preview(
            txid: "c3", amountDuffs: 100_000, direction: .received, daysAgo: 40, fiatString: nil))
    }
    .padding(20)
    .background(Color.dash.secondaryBackground)
    .clipShape(.rect(cornerRadius: 20))
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
