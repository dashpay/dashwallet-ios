//
//  StorageExplorerUnavailableView.swift
//  DashWallet
//

import SwiftUI

struct StorageExplorerUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Storage Explorer requires the Platform sync runtime.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Start Platform Sync") {
                PlatformAddressSyncCoordinator.startForCurrentNetwork()
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Storage Explorer")
    }
}
