//
//  LastSyncLabel.swift
//  DashWallet
//
//  The "Last sync: …" line shared by the Sync Info screens (Platform,
//  Shielded, DashPay). It exists so the three screens cannot drift: the
//  relative timestamp needs a refresh schedule to stay honest, and that is
//  easy to get subtly wrong in one copy out of three.
//
//  `Date.formatted(.relative:)` resolves the offset once, at render time, so
//  a plain Text holds its initial value for as long as the screen stays open
//  — and these are screens people leave open to watch a sync run. TimelineView
//  re-renders it on a schedule instead.
//

import DashUIKit
import SwiftUI

struct LastSyncLabel: View {
    let date: Date

    /// Short on purpose: `.relative` renders seconds, so a coarse schedule
    /// would leave "3 seconds ago" on screen well after it stopped being true.
    private static let refreshInterval: TimeInterval = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { _ in
            Text(String.localizedStringWithFormat(
                NSLocalizedString(
                    "Last sync: %@",
                    comment: "Sync diagnostics - %@ is a relative time such as 2 hours ago"),
                date.formatted(.relative(presentation: .numeric))))
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.dash.primaryText)
    }
}
