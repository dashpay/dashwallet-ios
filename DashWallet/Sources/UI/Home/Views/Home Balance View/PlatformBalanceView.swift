//
//  PlatformBalanceView.swift
//  DashWallet
//

import SwiftUI

struct PlatformBalanceView: View {
    @ObservedObject private var coordinator = PlatformAddressSyncCoordinator.shared

    var body: some View {
        if coordinator.isRunning {
            HStack(spacing: 0) {
                balanceColumn(
                    title: NSLocalizedString("Platform", comment: ""),
                    credits: coordinator.platformBalance)
                balanceColumn(
                    title: NSLocalizedString("Shielded", comment: ""),
                    credits: coordinator.shieldedBalance)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.navigationBarColor)
        }
    }

    /// One centered balance column (title over a DASH amount). Both the
    /// platform and shielded balances are denominated in Platform credits
    /// (1e11 per DASH), so they share `PlatformCreditsFormatter.dashString`.
    private func balanceColumn(title: String, credits: UInt64) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Text(PlatformCreditsFormatter.dashString(credits))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
