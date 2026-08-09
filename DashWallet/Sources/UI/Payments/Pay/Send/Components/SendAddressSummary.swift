//
//  SendAddressSummary.swift
//  DashWallet
//
//  Where the money is going, as read-only context on the steps after the
//  address has been decided.
//

import SwiftUI
import DashUIKit

/// Destination context for the source and amount steps.
///
/// Not a field: by this point the address is settled, and the boxed control
/// with a pencil this replaced offered an edit the step could not make —
/// tapping it only went back, which the navigation bar's own back button
/// already does. So it reads as a heading, the way the merchant header does
/// on the gift-card screens.
struct SendAddressSummary: View {
    @ObservedObject var viewModel: SendViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Middle-truncated, not tail: the last characters are what
            // distinguishes two addresses of the same form, so a plain
            // ellipsis at the end hides exactly what is worth checking.
            Text(String(
                format: NSLocalizedString("to %@", comment: "Send screen — the destination address"),
                truncateMiddle(viewModel.trimmedAddress, visible: 10)))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Color.dash.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let destination = viewModel.destination {
                destinationBadge(destination)
            }
        }
        .padding(.horizontal, 20)
    }
}

#if DEBUG

/// One per destination kind — the badge is what differs.
#Preview("Destination context") {
    VStack(alignment: .leading, spacing: 16) {
        SendAddressSummary(viewModel: .preview(
            address: "yQzt83pPGeXQpVn4rL8mKdWvBcTfGhJkMnPaPuNstuWJK",
            destination: .core))

        SendAddressSummary(viewModel: .preview(
            address: "8xKq2mVn4pLrTyWvBcDfGhJkMnPqRsTuVwXyZaBcDeFg",
            destination: .platform))

        SendAddressSummary(viewModel: .preview(
            address: "dashs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            destination: .shielded(raw43: Data(repeating: 0x2a, count: 43))))
    }
    .padding(.vertical)
    .background(Color.dash.primaryBackground)
}

#endif
