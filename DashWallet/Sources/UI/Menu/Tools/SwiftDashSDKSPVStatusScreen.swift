//
//  SwiftDashSDKSPVStatusScreen.swift
//  DashWallet
//
//  Tools-menu screen that observes SwiftDashSDKSPVCoordinator and displays
//  the parallel-observe SPV stack's live state. Lets us watch the new SPV
//  pipeline catch up to mainnet on a real device alongside DashSync's
//  still-authoritative SPV stack.
//
//  Reachable in every build configuration so it can be tested across
//  Debug / Testnet / TestFlight schemes. The intent is "developer
//  diagnostic during the migration window"; if Phase B keeps it as a
//  permanent diagnostic, no further changes needed. If we want to hide
//  it from production users post-migration, wrap it in a feature flag.
//
//  See SwiftDashSDKSPVCoordinator.swift for the underlying lifecycle and
//  the migration plan for why parallel-observe mode exists.
//

import SwiftUI
import UIKit
import SwiftDashSDK

struct SwiftDashSDKSPVStatusScreen: View {
    private let vc: UINavigationController

    @ObservedObject private var coordinator = SwiftDashSDKSPVCoordinator.shared

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
                Text("SwiftDashSDK SPV Status")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stateBadgeCard
                    progressCard
                    peersCard
                    perPhaseCard
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

    private var stateBadgeCard: some View {
        HStack {
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Text(stateLabel)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primaryText)
            Spacer()
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aggregate Progress")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Spacer()
                Text(percentageText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
            }
            // Custom bar — local UIKit `ProgressView` shadows SwiftUI's,
            // so we draw our own to avoid the name collision.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray300.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: max(0, geo.size.width * clampedProgress))
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var peersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(title: "Connected peers", value: "\(coordinator.connectedPeerCount)")
            row(title: "Tip height", value: "\(coordinator.tipHeight)")
            row(title: "Best peer height", value: "\(coordinator.bestPeerHeight)")
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var perPhaseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Phase Progress")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryText)
                .padding(.bottom, 4)

            phaseRow(
                title: "Headers",
                state: coordinator.syncProgress.headers?.state,
                percentage: coordinator.syncProgress.headers?.percentage,
                current: coordinator.syncProgress.headers?.currentHeight,
                target: coordinator.syncProgress.headers?.targetHeight
            )
            phaseRow(
                title: "Filter Headers",
                state: coordinator.syncProgress.filterHeaders?.state,
                percentage: coordinator.syncProgress.filterHeaders?.percentage,
                current: coordinator.syncProgress.filterHeaders?.currentHeight,
                target: coordinator.syncProgress.filterHeaders?.targetHeight
            )
            phaseRow(
                title: "Filters",
                state: coordinator.syncProgress.filters?.state,
                percentage: coordinator.syncProgress.filters?.percentage,
                current: coordinator.syncProgress.filters?.currentHeight,
                target: coordinator.syncProgress.filters?.targetHeight
            )
            phaseRow(
                title: "Blocks",
                state: coordinator.syncProgress.blocks?.state,
                percentage: nil,
                current: coordinator.syncProgress.blocks?.lastProcessed,
                target: nil
            )
            phaseRow(
                title: "Masternodes",
                state: coordinator.syncProgress.masternodes?.state,
                percentage: nil,
                current: coordinator.syncProgress.masternodes?.currentHeight,
                target: coordinator.syncProgress.masternodes?.targetHeight
            )
            phaseRow(
                title: "ChainLocks",
                state: coordinator.syncProgress.chainLocks?.state,
                percentage: nil,
                current: coordinator.syncProgress.chainLocks?.bestValidatedHeight,
                target: nil
            )
            phaseRow(
                title: "InstantSend",
                state: coordinator.syncProgress.instantSend?.state,
                percentage: nil,
                current: coordinator.syncProgress.instantSend?.valid,
                target: nil
            )
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
                SwiftDashSDKWalletRuntime.stop()
            }) {
                Text("Stop")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray300.opacity(0.3))
                    .foregroundColor(.primaryText)
                    .cornerRadius(8)
            }
            Button(action: {
                SwiftDashSDKWalletRuntime.startIfReady()
            }) {
                Text("Restart")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray300.opacity(0.3))
                    .foregroundColor(.primaryText)
                    .cornerRadius(8)
            }
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

    private func phaseRow(title: String, state: SPVSyncState?, percentage: Double?, current: UInt32?, target: UInt32?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.primaryText)
            Spacer()
            Text(phaseDetail(state: state, percentage: percentage, current: current, target: target))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Formatting

    private var clampedProgress: Double {
        max(0.0, min(1.0, coordinator.progress))
    }

    private var percentageText: String {
        String(format: "%.1f%%", clampedProgress * 100.0)
    }

    private var stateLabel: String {
        switch coordinator.state {
        case .waitForEvents:
            return "Waiting for events"
        case .waitingForConnections:
            return "Waiting for connections"
        case .syncing:
            return "Syncing \(percentageText)"
        case .synced:
            return "Synced"
        case .error:
            return "Error"
        case .idle:
            return "Idle"
        case .unknown:
            return "Unknown"
        }
    }

    private var badgeColor: Color {
        switch coordinator.state {
        case .synced:
            return .green
        case .syncing, .waitForEvents:
            return .blue
        case .waitingForConnections:
            return .orange
        case .error:
            return .red
        case .idle, .unknown:
            return .gray
        }
    }

    private func phaseDetail(state: SPVSyncState?, percentage: Double?, current: UInt32?, target: UInt32?) -> String {
        guard let state else { return "—" }
        var parts: [String] = []
        parts.append(stateAbbreviation(state))
        if let percentage {
            parts.append(String(format: "%.0f%%", percentage * 100.0))
        }
        if let current, let target, target > 0 {
            parts.append("\(current)/\(target)")
        } else if let current {
            parts.append("\(current)")
        }
        return parts.joined(separator: " · ")
    }

    private func stateAbbreviation(_ state: SPVSyncState) -> String {
        switch state {
        case .waitForEvents:    return "wait"
        case .waitingForConnections: return "conn"
        case .syncing:          return "sync"
        case .synced:           return "done"
        case .error:            return "err"
        case .idle:             return "idle"
        case .unknown:          return "?"
        }
    }
}
