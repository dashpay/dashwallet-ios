//
//  SendStepChrome.swift
//  DashWallet
//
//  The card the address field collapses into once a destination decodes.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

// MARK: - Shared step chrome

/// Back-chevron + "Send" title, shared by the source and amount steps.
struct SendAddressSummary: View {
    @ObservedObject var viewModel: SendViewModel
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(NSLocalizedString("Address", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let destination = viewModel.destination {
                        destinationBadge(destination)
                    }
                }
                HStack(spacing: 8) {
                    Text(truncateMiddle(viewModel.trimmedAddress, visible: 10))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

#if DEBUG

/// The card the address field collapses into once a destination decodes —
/// one preview per destination kind, since the badge is what differs.
#Preview("Address summary") {
    VStack(spacing: 12) {
        SendAddressSummary(
            viewModel: .preview(
                address: "yV1D1ivvSUyKPJnbFmzSTVh1MyZ3JbeVkY",
                destination: .core),
            onEdit: {})

        SendAddressSummary(
            viewModel: .preview(
                address: "dash:8xKq2mVn4pLrTyWvBcDfGhJkMnPqRsTuVwXyZ",
                destination: .platform),
            onEdit: {})

        SendAddressSummary(
            viewModel: .preview(
                address: "dashs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                destination: .shielded(raw43: Data(repeating: 0x2a, count: 43))),
            onEdit: {})
    }
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif

