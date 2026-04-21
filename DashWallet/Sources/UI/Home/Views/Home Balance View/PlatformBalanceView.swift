//
//  PlatformBalanceView.swift
//  DashWallet
//

import SwiftUI

struct PlatformBalanceView: View {
    @ObservedObject private var coordinator = PlatformAddressSyncCoordinator.shared

    var body: some View {
        if coordinator.isRunning {
            VStack(spacing: 2) {
                Text(NSLocalizedString("Platform", comment: ""))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Text(PlatformCreditsFormatter.dashString(coordinator.platformBalance))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.navigationBarColor)
        }
    }
}
