//
//  SyncGateNote.swift
//  DashWallet
//
//  The note shown while the chain is still syncing.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

/// Inline explanation for a Continue disabled by the chain-sync gate:
/// Core-funded sends stay off until `SyncingActivityMonitor` reports
/// `.syncDone` (a stale UTXO set can't safely fund a spend). Shared by
/// the Send and Internal transfer screens.
struct SyncGateNote: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Text(NSLocalizedString(
                "Your wallet is still syncing. Sending from your Transparent balance will be available once syncing completes.",
                comment: "Core send blocked until chain sync completes"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }
}

#if DEBUG

#Preview {
    SyncGateNote()
        .padding()
        .background(Color.dash.primaryBackground)
}

#endif
