//
//  ShieldedSubmittedUnconfirmedView.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

/// sync.
struct ShieldedSubmittedUnconfirmedView: View {
    var onDone: () -> Void

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
                "Your transfer was broadcast and is confirming on the network. Don't resend it — it will appear once the network confirms it.",
                comment: "InternalTransfer"))
                .font(.callout)
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

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

