//
//  PlatformSyncStatusScreen.swift
//  DashWallet
//
//  Tools-menu screen observing `PlatformAddressSyncCoordinator`. Mirrors
//  the SwiftExampleApp "Platform Sync Status" section (see
//  `CoreContentView.swift` lines 139-326 in the swift-sdk package).
//  Surfaces BLAST L2 sync state: last sync time, platform balance,
//  active addresses, chain tip / checkpoint / last recent block / block
//  time, cumulative query counts with per-category badges, and manual
//  controls (Sync Now, Clear, Stop).
//
//  Unrelated to the neutered "SwiftDashSDK SPV Status" cell — that one
//  still represents L1 core SPV (currently disabled by the SDK refactor).
//

import SwiftUI
import UIKit

struct PlatformSyncStatusScreen: View {
    private let vc: UINavigationController

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
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1)
                        )
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            // Header
            HStack {
                Text("Platform Sync Status")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stateCard
                    balanceCard
                    heightsCard
                    if coordinator.syncCountSinceLaunch > 0 {
                        queriesCard
                    }
                    addressesCard
                    if let lastError = coordinator.lastError {
                        errorCard(message: lastError)
                    }
                    controlsCard
                    Spacer(minLength: 12)
                }
            }
        }
        .padding(.horizontal, 20)
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Cards

    private var stateCard: some View {
        HStack(spacing: 8) {
            if coordinator.isSyncing {
                SwiftUI.ProgressView().scaleEffect(0.7)
                Text("Syncing…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
            } else if let lastSync = coordinator.lastSyncTime {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Last sync: \(lastSync, style: .relative) ago")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundColor(.secondary)
                Text(coordinator.isRunning ? "Not synced yet" : "Idle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let network = coordinator.runningNetwork {
                Text(network.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(
                title: "Platform Balance",
                value: PlatformCreditsFormatter.dashString(coordinator.platformBalance))
            row(
                title: "Active Addresses",
                value: "\(coordinator.activeAddressCount)")
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var addressesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Platform Addresses (\(coordinator.derivedAddresses.count))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Spacer()
            }
            if coordinator.derivedAddresses.isEmpty {
                Text("No addresses derived yet")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(coordinator.derivedAddresses) { addr in
                    addressRow(addr)
                    if addr.id != coordinator.derivedAddresses.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private func addressRow(_ addr: DerivedPlatformAddress) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(addr.address)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primaryText)
                HStack(spacing: 6) {
                    Text("#\(addr.accountIndex)/\(addr.addressIndex)")
                    if addr.isUsed { Text("• used") }
                    if addr.balance > 0 {
                        Text("• \(PlatformCreditsFormatter.dashString(addr.balance))")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { UIPasteboard.general.string = addr.address }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var heightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coordinator.chainTipHeight > 0 {
                row(title: "Chain Tip Height", value: formattedHeight(coordinator.chainTipHeight))
            }
            if coordinator.checkpointHeight > 0 {
                row(title: "Sync Checkpoint", value: formattedHeight(coordinator.checkpointHeight))
            }
            if coordinator.lastKnownRecentBlock > 0 {
                row(title: "Last Recent Block", value: formattedHeight(coordinator.lastKnownRecentBlock))
            } else {
                row(title: "Last Recent Block", value: "None found")
            }
            if let blockTime = coordinator.lastSyncBlockTime {
                HStack {
                    Text("Block Time")
                        .font(.system(size: 13))
                        .foregroundColor(.primaryText)
                    Spacer()
                    Text(blockTime, style: .date)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(blockTime, style: .time)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var queriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Queries Since Launch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Spacer()
                Text("\(coordinator.syncCountSinceLaunch) syncs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                queryBadge(label: "Trunk", count: coordinator.totalTrunkQueries, detail: nil, color: .blue)
                queryBadge(label: "Branch", count: coordinator.totalBranchQueries, detail: nil, color: .indigo)
                queryBadge(label: "Compacted", count: coordinator.totalCompactedQueries, detail: coordinator.totalCompactedEntries, color: .orange)
                queryBadge(label: "Recent", count: coordinator.totalRecentQueries, detail: coordinator.totalRecentEntries, color: .green)
            }
        }
        .padding(16)
        .background(Color.secondaryBackground)
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
                Task { await coordinator.syncNow() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(coordinator.isSyncing ? Color.gray300.opacity(0.3) : Color.blue.opacity(0.15))
                .foregroundColor(coordinator.isSyncing ? .secondary : .blue)
                .cornerRadius(8)
            }
            .disabled(coordinator.isSyncing)

            Button(action: {
                coordinator.clearDisplay()
            }) {
                Text("Clear")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray300.opacity(0.3))
                    .foregroundColor(.primaryText)
                    .cornerRadius(8)
            }

            Button(action: {
                PlatformAddressSyncCoordinator.stop()
            }) {
                Text("Stop")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(coordinator.isRunning ? Color.red.opacity(0.15) : Color.gray300.opacity(0.3))
                    .foregroundColor(coordinator.isRunning ? .red : .secondary)
                    .cornerRadius(8)
            }
            .disabled(!coordinator.isRunning)
        }
    }

    // MARK: - Row builders

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primaryText)
                .monospacedDigit()
        }
    }

    private func queryBadge(label: String, count: UInt32, detail: UInt32?, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            if let detail {
                Text("\(detail)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Formatting

    private func formattedHeight(_ h: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: h)) ?? "\(h)"
    }

}
