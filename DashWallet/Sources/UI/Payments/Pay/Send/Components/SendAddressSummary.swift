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
    /// Show which balance funds the send, and how much is in it. Off on the
    /// source step, where the cards below already say both and the choice is
    /// still open; on for the amount step, where the source is settled and
    /// the number is what the amount is being measured against.
    var showsSource: Bool = false

    /// Mirrors the app-wide flag the home balance uses, so hiding in one
    /// place hides everywhere. `@State` seeded from it, since a plain read
    /// would not re-render on toggle.
    @State private var isBalanceHidden = DWGlobalOptions.sharedInstance().balanceHidden

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("Send", comment: "Send screen"))
                .dashFont(.title1)
                .foregroundStyle(Color.dash.primaryText)

            Text(String(format: NSLocalizedString("to %@", comment: "Send screen"), viewModel.trimmedAddress))
                .dashFont(.subhead)
                .foregroundStyle(Color.dash.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            if let destination = viewModel.destination {
                Text(String(format: NSLocalizedString("to %@", comment: "Send screen"), destinationTitle(destination)))
                    .dashFont(.subhead)
                    .foregroundStyle(Color.dash.primaryText)
            }

            if showsSource {
                Text(String(
                    format: NSLocalizedString("from %@", comment: "Send screen — the balance being spent"),
                    sourceTitle(viewModel.source)))
                    .dashFont(.subhead)
                    .foregroundStyle(Color.dash.primaryText)

                sourceBalanceLine
            }
        }
    }

    private var sourceBalanceLine: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString("Balance:", comment: "Send screen"))
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.secondaryText)

            if isBalanceHidden {
                // Same masking the home balance uses — the width is fixed, so
                // the row doesn't change size when it is revealed.
                Text("••••••••")
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
            } else {
                // Qualified: the app has a `DashAmount` of its own with a
                // different initializer, and an unqualified name picks it.
                DashUIKit.DashAmount(
                    amount: Int64(clamping: viewModel.selectedSourceBalanceDuffs),
                    fontSize: 13,
                    sign: DashAmountSign.none)
                    .foregroundStyle(Color.dash.secondaryText)
            }

            Button {
                isBalanceHidden.toggle()
                DWGlobalOptions.sharedInstance().balanceHidden = isBalanceHidden
            } label: {
                Image(systemName: isBalanceHidden ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dash.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isBalanceHidden
                ? NSLocalizedString("Show balance", comment: "Send screen")
                : NSLocalizedString("Hide balance", comment: "Send screen"))
        }
    }
}

#if DEBUG

/// The source step: destination only — the From cards below carry the choice.
#Preview("Destination only") {
    VStack(alignment: .leading, spacing: 16) {
        SendAddressSummary(viewModel: .preview(
            address: "yQzt83pPGeXQpVn4rL8mKdWvBcTfGhJkMnPaPuNstuWJK",
            destination: .core))

        SendAddressSummary(viewModel: .preview(
            address: "dashs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            destination: .shielded(raw43: Data(repeating: 0x2a, count: 43))))
    }
    .padding()
    .background(Color.dash.primaryBackground)
}

/// The amount step: the source is settled, so it says which balance is being
/// spent and how much is in it. Whether the number is masked follows the
/// app-wide flag, so this preview shows it as the device last left it.
#Preview("With source") {
    VStack(alignment: .leading, spacing: 16) {
        SendAddressSummary(
            viewModel: .preview(
                address: "yQzt83pPGeXQpVn4rL8mKdWvBcTfGhJkMnPaPuNstuWJK",
                destination: .core,
                coreBalanceDuffs: 158_998_000),
            showsSource: true)

        SendAddressSummary(
            viewModel: .preview(
                address: "yQzt83pPGeXQpVn4rL8mKdWvBcTfGhJkMnPaPuNstuWJK",
                destination: .core,
                source: .shielded),
            showsSource: true)
    }
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
