//
//  ShieldedSyncInfoScreen.swift
//  DashWallet
//
//  Sync Info screen for the SDK's shielded (Orchard) sync loop. Mirrors the
//  SwiftExampleApp "Shielded Sync Status" section (`CoreContentView.swift`):
//  sync state (incl. "Not bound"), total shielded balance, notes-synced
//  watermark, live elapsed + dual Downloaded/Checked progress while a pass
//  runs, last/longest pass durations, since-launch Scanned/New/Spent
//  counters, and a manual Sync Now trigger. Counter state lives in the
//  app-lifetime `ShieldedSyncMonitor`; the balance mirror comes from
//  `PlatformAddressSyncCoordinator.shieldedBalance` (credits, 1e11/DASH).
//
//  Unlike the example app, "Clear" resets only the displayed counters —
//  it never wipes persisted notes or the sync watermark (that destructive
//  variant stays example-app-only).
//

import SwiftUI
import DashUIKit
import UIKit

struct ShieldedSyncInfoScreen: View {
    private let vc: UINavigationController

    @ObservedObject private var monitor = ShieldedSyncMonitor.shared
    @ObservedObject private var coordinator = PlatformAddressSyncCoordinator.shared

    init(vc: UINavigationController) {
        self.vc = vc
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            HStack {
                Button(action: {
                    vc.popViewController(animated: true)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color.dash.primaryText)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1)
                        )
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            // Header
            HStack {
                Text("Shielded Sync Info")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.dash.primaryText)
                Spacer()
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stateCard
                    balanceCard
                    if monitor.isSyncing {
                        liveProgressCard
                    } else if monitor.lastSyncDuration != nil {
                        durationsCard
                    }
                    if monitor.syncCountSinceLaunch > 0 {
                        countersCard
                    }
                    if let lastError = monitor.lastError {
                        errorCard(message: lastError)
                    }
                    controlsCard
                    Spacer(minLength: 12)
                }
            }
        }
        .padding(.horizontal, 20)
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Cards

    private var stateCard: some View {
        HStack(spacing: 8) {
            if !coordinator.isRunning {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.orange)
                Text("Platform sync is not running")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.secondaryText)
            } else if monitor.isSyncing {
                SwiftUI.ProgressView().scaleEffect(0.7)
                Text("Syncing…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
            } else if monitor.isBound == false {
                Image(systemName: "shield.slash")
                    .foregroundColor(.orange)
                Text("Not bound")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.secondaryText)
            } else if let lastSync = monitor.lastSyncTime {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Last sync: \(lastSync, style: .relative) ago")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundColor(Color.dash.secondaryText)
                Text("Not synced yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.secondaryText)
            }
            Spacer()
            if let network = coordinator.runningNetwork {
                Text(network.networkName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.dash.secondaryText)
            }
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(
                title: "Total Shielded Balance",
                value: PlatformCreditsFormatter.dashString(coordinator.shieldedBalance))
            row(
                title: "Notes Synced",
                value: formattedCount(monitor.notesSynced))
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var liveProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Pass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                if let elapsed = monitor.currentSyncElapsed {
                    Text(String(format: "%.1f s", elapsed))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.dash.secondaryText)
                        .monospacedDigit()
                }
            }
            if monitor.currentSyncScanned != nil || monitor.currentTreeCommitted != nil {
                dualProgressRow(
                    label: "Downloaded",
                    value: monitor.currentSyncScanned,
                    total: monitor.currentTreeTotal)
                dualProgressRow(
                    label: "Checked",
                    value: monitor.currentTreeCommitted,
                    total: monitor.currentTreeTotal)
            }
            if let height = monitor.currentSyncBlockHeight, height > 0 {
                row(title: "Block Height", value: formattedCount(height))
            }
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var durationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let last = monitor.lastSyncDuration {
                row(title: "Last Sync Duration", value: String(format: "%.2f s", last))
                // Only worth a row when it meaningfully exceeds the last pass.
                if let longest = monitor.longestSyncDuration, longest > last + 0.05 {
                    row(title: "Longest Pass", value: String(format: "%.2f s", longest))
                }
            }
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var countersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Queries Since Launch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                Text("\(monitor.syncCountSinceLaunch) syncs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.dash.secondaryText)
            }
            HStack(spacing: 8) {
                counterBadge(label: "Scanned", count: monitor.totalScanned, color: .blue)
                counterBadge(label: "New", count: monitor.totalNewNotes, color: .purple)
                counterBadge(label: "Spent", count: monitor.totalNewlySpent, color: .orange)
            }
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Error")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }

    private var controlsCard: some View {
        HStack(spacing: 12) {
            Button(action: {
                Task { await monitor.syncNow() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(syncNowDisabled ? Color.dash.gray300.opacity(0.3) : Color.purple.opacity(0.15))
                .foregroundColor(syncNowDisabled ? .secondary : .purple)
                .cornerRadius(8)
            }
            .disabled(syncNowDisabled)

            Button(action: {
                monitor.clearDisplayCounters()
            }) {
                Text("Clear")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.dash.gray300.opacity(0.3))
                    .foregroundColor(.dash.primaryText)
                    .cornerRadius(8)
            }
        }
    }

    private var syncNowDisabled: Bool {
        monitor.isSyncing || !coordinator.isRunning
    }

    // MARK: - Row builders

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.dash.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dash.primaryText)
                .monospacedDigit()
        }
    }

    /// One bar of the Downloaded/Checked pair. Determinate only when the
    /// on-chain total is known (`total > 0`); otherwise a spinner with the
    /// running count — mirrors `ShieldedDualProgressRows` in the example app.
    private func dualProgressRow(label: String, value: UInt64?, total: UInt64?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.dash.primaryText)
                .frame(width: 90, alignment: .leading)
            if let value, let total, total > 0 {
                SwiftUI.ProgressView(value: Double(min(value, total)), total: Double(total))
                    .tint(.purple)
                Text("\(formattedCount(min(value, total))) / \(formattedCount(total))")
                    .font(.system(size: 11))
                    .foregroundColor(Color.dash.secondaryText)
                    .monospacedDigit()
            } else if let value {
                SwiftUI.ProgressView().scaleEffect(0.6)
                Text("\(formattedCount(value)) notes")
                    .font(.system(size: 11))
                    .foregroundColor(Color.dash.secondaryText)
                    .monospacedDigit()
                Spacer()
            } else {
                SwiftUI.ProgressView().scaleEffect(0.6)
                Spacer()
            }
        }
    }

    private func counterBadge(label: String, count: UInt64, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(formattedCount(count))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.dash.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Formatting

    private func formattedCount(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
