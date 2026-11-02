//
//  ShieldedSubmittedUnconfirmedView.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

/// sync.
struct ShieldedSubmittedUnconfirmedView: View {
    var onDone: () -> Void
    /// Where this transfer's status can be checked later, when the surface
    /// that started it has a place for that.
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "paperplane.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .foregroundColor(.dash.blue)
                .padding(.top, 24)

            Text(NSLocalizedString("Submitted — confirming", comment: "InternalTransfer"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            Text(NSLocalizedString(
                "Your transfer may have reached the network, but its result is not confirmed yet. Don't resend it. Wait for the wallet to sync and check its status.",
                comment: "InternalTransfer"))
                .font(.callout)
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: onDone)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }
}

#if DEBUG


@available(iOS 17, *)
#Preview("Submitted — confirming") {
    ShieldedSubmittedUnconfirmedView(onDone: {})
        .background(Color.dash.primaryBackground)
}

#endif

