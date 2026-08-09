//
//  TransactionFilterButton.swift
//  DashWallet
//
//  The control that opens TransactionFilterDialog.
//

import SwiftUI
import DashUIKit

/// Opens ``TransactionFilterDialog``. Shared by the home transaction list and
/// the DashPay contact activity card so the two cannot drift apart — the
/// filter is the same idea in both, and a user who learns it in one place
/// should recognise it in the other.
struct TransactionFilterButton: View {
    let action: () -> Void

    var body: some View {
        DashButton(
            text: NSLocalizedString("Filter", comment: ""),
            trailingIcon: .custom("icon_filter_button"),
            style: .plain,
            size: .small,
            stretch: false,
            action: action
        )
        .overrideForegroundColor(.dash.blue)
    }
}

#if DEBUG

#Preview {
    TransactionFilterButton {}
        .padding()
        .background(Color.dash.primaryBackground)
}

#endif
