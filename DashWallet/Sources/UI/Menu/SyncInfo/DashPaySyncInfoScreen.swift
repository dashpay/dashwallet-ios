//
//  DashPaySyncInfoScreen.swift
//  DashWallet
//
//  Sync Info screen for the SDK's DashPay background sync (contact
//  requests, own + contact profiles, DashPay payment reconciliation).
//  Mirrors the SwiftExampleApp "DashPay Sync Status" section
//  (`CoreContentView.swift`): sync state with last-sync time, a
//  Recurring/Stopped loop badge, and a manual Sync Now trigger via
//  `PlatformWalletManager.dashPaySyncNow()`.
//
//  The whole file is DASHPAY-gated: the sync loop itself only starts under
//  the dashpay scheme (see `PlatformAddressSyncCoordinator.performStart`).
//

#if DASHPAY

import Combine
import OSLog
import SwiftDashSDK
import SwiftUI
import DashUIKit
import UIKit

// MARK: - ViewModel

@MainActor
final class DashPaySyncInfoViewModel: ObservableObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.dashpay-sync-info")

    /// Whether a DashPay sync pass is currently in flight (mirror of
    /// `PlatformWalletManager.dashPaySyncIsSyncing`).
    @Published private(set) var isSyncing = false
    /// Whether the recurring background loop is running. `nil` while the
    /// manager is unavailable — unknown is shown as unknown.
    @Published private(set) var isLoopRunning: Bool? = nil
    /// Completion time of the last DashPay sync pass (SDK watermark;
    /// global per manager — the sweep is wallet-driven).
    @Published private(set) var lastSync: Date? = nil
    /// Wallet counts from the last manual Sync Now pass, nil until one runs.
    /// The all-zero "no pass ran" sentinel (a pass was already in flight)
    /// is not stored.
    @Published private(set) var lastManualSummary: DashPaySyncSummary? = nil
    @Published private(set) var lastError: String? = nil

    /// False when BLAST (and with it the DashPay loop) isn't running.
    var isManagerAvailable: Bool {
        PlatformAddressSyncCoordinator.shared.platformWalletManager != nil
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        subscribeIfPossible()
    }

    /// Called from the view's `.onAppear`; also re-subscribes if the
    /// manager generation changed while the screen was off-stack.
    func refresh() {
        subscribeIfPossible()
        refreshLoopState()
        refreshLastSync()
    }

    func syncNow() async {
        guard let manager = PlatformAddressSyncCoordinator.shared.platformWalletManager else {
            lastError = "Platform sync is not running"
            return
        }
        lastError = nil
        do {
            let summary = try await manager.dashPaySyncNow()
            // All-zero summary = "no pass ran" sentinel (one was already in
            // flight and this call attached to it).
            if summary != DashPaySyncSummary(success: 0, errors: 0, syncUnixSeconds: 0) {
                lastManualSummary = summary
            }
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("👥 DASHPAY-SYNC-INFO :: dashPaySyncNow threw: \(String(describing: error), privacy: .public)")
        }
        refreshLoopState()
        refreshLastSync()
    }

    private func subscribeIfPossible() {
        cancellables.removeAll()
        guard let manager = PlatformAddressSyncCoordinator.shared.platformWalletManager else {
            isSyncing = false
            isLoopRunning = nil
            return
        }
        manager.$dashPaySyncIsSyncing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] syncing in
                guard let self else { return }
                let wasSyncing = self.isSyncing
                self.isSyncing = syncing
                // Falling edge: a background-loop pass finished — pick up
                // its watermark (mirrors the example app's `.onChange`).
                if wasSyncing && !syncing {
                    self.refreshLastSync()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshLoopState() {
        guard let manager = PlatformAddressSyncCoordinator.shared.platformWalletManager else {
            isLoopRunning = nil
            return
        }
        isLoopRunning = (try? manager.isDashPaySyncRunning()) ?? nil
    }

    private func refreshLastSync() {
        guard let manager = PlatformAddressSyncCoordinator.shared.platformWalletManager,
              let unixSeconds = try? manager.dashPayLastSyncUnixSeconds(),
              unixSeconds > 0
        else { return }
        lastSync = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
    }
}

// MARK: - Screen

struct DashPaySyncInfoScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel = DashPaySyncInfoViewModel()

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
                Text("DashPay Sync Info")
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
                    if let summary = viewModel.lastManualSummary {
                        summaryCard(summary)
                    }
                    if let lastError = viewModel.lastError {
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
        .onAppear {
            viewModel.refresh()
        }
    }

    // MARK: - Cards

    private var stateCard: some View {
        HStack(spacing: 8) {
            if !viewModel.isManagerAvailable {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.orange)
                Text("Platform sync is not running")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.secondaryText)
            } else if viewModel.isSyncing {
                SwiftUI.ProgressView().scaleEffect(0.7)
                Text("Syncing…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
            } else if let lastSync = viewModel.lastSync {
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
            if let running = viewModel.isLoopRunning {
                Text(running ? "Recurring" : "Stopped")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(running ? .secondary : .orange)
            }
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private func summaryCard(_ summary: DashPaySyncSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last Manual Pass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Spacer()
            }
            row(title: "Wallets Synced", value: "\(summary.success)")
            row(title: "Wallets Failed", value: "\(summary.errors)")
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
        Button(action: {
            Task { await viewModel.syncNow() }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("Sync Now")
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(syncNowDisabled ? Color.dash.gray300.opacity(0.3) : Color.dash.blue.opacity(0.15))
            .foregroundColor(syncNowDisabled ? .secondary : .blue)
            .cornerRadius(8)
        }
        .disabled(syncNowDisabled)
    }

    private var syncNowDisabled: Bool {
        viewModel.isSyncing || !viewModel.isManagerAvailable
    }

    // MARK: - Row builder

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
}

#endif
