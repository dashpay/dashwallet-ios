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

import OSLog
import SwiftData
import SwiftUI
import DashUIKit
import UIKit
import SwiftDashSDK

struct SwiftDashSDKSPVStatusScreen: View {
    private let vc: UINavigationController

    @ObservedObject private var coordinator = SwiftDashSDKSPVCoordinator.shared

    // MARK: - Rescan Filters UI state
    //
    // This screen predates the SwiftUI-first ViewModel rule and is a
    // developer diagnostic (see the file header), so the rescan flow's
    // small amount of state lives here rather than in a new ViewModel.
    // The FFI call itself is isolated in the `@MainActor` extension at
    // the bottom of the file, keeping the view struct free of direct
    // SDK calls.

    /// Presents the height-choice confirmation dialog.
    @State private var showRescanChoices = false
    /// Presents the "From height…" numeric-entry alert.
    @State private var showHeightEntry = false
    /// Bound to the "From height…" text field. Validated to a `UInt32`
    /// before use; a non-numeric / empty value is rejected rather than
    /// defaulted to a height.
    @State private var heightEntryText = ""
    /// Result banner text after a rescan attempt. Success and failure
    /// are distinguished by `rescanResultIsError` for colouring.
    @State private var rescanResultMessage: String?
    @State private var rescanResultIsError = false

    /// Presents the birth-height edit alert (numeric entry, mirrors the
    /// "From height…" rescan alert).
    @State private var showBirthHeightEntry = false
    /// Bound to the birth-height text field; validated to a `UInt32`
    /// before use, never defaulted.
    @State private var birthHeightEntryText = ""
    /// Non-nil presents the clear-and-resync confirmation carrying the
    /// entered height. Nothing is written until the user confirms; on
    /// confirm the row is updated and the next-launch chain resync armed.
    /// Entered heights at or below the current one land here — "equal"
    /// included, because a store anchored above the (already-correct)
    /// birth height can only be repaired by the resync, and re-saving
    /// the current height is the only way to express that in this UI.
    @State private var pendingResyncConfirmHeight: UInt32?

    /// Presents the drop-unconfirmed confirmation dialog.
    @State private var showDropUnconfirmedConfirm = false
    /// True while the bulk drop + runtime reload + rescan runs; disables
    /// the button and shows its progress spinner.
    @State private var isDroppingUnconfirmed = false
    /// Result banner under the drop button; coloured via `dropResultIsError`.
    @State private var dropResultMessage: String?
    @State private var dropResultIsError = false

    // MARK: - Pending transfers UI state

    /// Locks awaiting a recovery resume, re-read when the card appears and
    /// after a pass so the count reflects what actually remains.
    @State private var pendingRecoveries: [AssetLockRecoveryService.PendingRecovery] = []
    @State private var isRecoveringPending = false
    /// "3 of 23" progress while the pass runs.
    @State private var recoveryProgress: (done: Int, total: Int)?
    @State private var recoveryResultMessage: String?
    @State private var recoveryResultIsError = false

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
                Text("Core Sync Status")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.dash.primaryText)
                Spacer()
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stateBadgeCard
                    progressCard
                    heightsCard
                    perPhaseCard
                    rescanFiltersCard
                    dropUnconfirmedCard
                    pendingTransfersCard
                    connectedPeersCard
                    if let lastError = coordinator.lastError {
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
        .confirmationDialog(
            NSLocalizedString("Rescan Filters", comment: "SPV diagnostics"),
            isPresented: $showRescanChoices,
            titleVisibility: .visible
        ) {
            if let birthHeight = walletBirthHeight {
                Button(NSLocalizedString("From wallet creation", comment: "SPV diagnostics")) {
                    performRescan(fromHeight: birthHeight)
                }
            }
            Button(NSLocalizedString("From height…", comment: "SPV diagnostics")) {
                heightEntryText = ""
                showHeightEntry = true
            }
            Button(
                NSLocalizedString("Full rescan (from 0) — slow", comment: "SPV diagnostics"),
                role: .destructive
            ) {
                performRescan(fromHeight: 0)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "Re-checks the compact block filters from the chosen height for this wallet's transactions, re-downloading and re-matching them. Rescans are floored at the wallet's creation height and at the locally stored chain data — to recover history below that, lower the wallet birth height instead.",
                comment: "SPV diagnostics"))
        }
        .alert(
            NSLocalizedString("Rescan from height", comment: "SPV diagnostics"),
            isPresented: $showHeightEntry
        ) {
            TextField(
                NSLocalizedString("Block height", comment: "SPV diagnostics"),
                text: $heightEntryText)
                .keyboardType(.numberPad)
            Button(NSLocalizedString("Rescan", comment: "SPV diagnostics")) {
                startRescanFromEnteredHeight()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "Enter the core block height to re-check filters from.",
                comment: "SPV diagnostics"))
        }
        .alert(
            NSLocalizedString("Edit birth height", comment: "SPV diagnostics"),
            isPresented: $showBirthHeightEntry
        ) {
            TextField(
                NSLocalizedString("Block height", comment: "SPV diagnostics"),
                text: $birthHeightEntryText)
                .keyboardType(.numberPad)
            Button(NSLocalizedString("Save", comment: "")) {
                saveEnteredBirthHeight()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "The wallet's creation height — the floor for filter scans and \"From wallet creation\" rescans. Set it at or below the wallet's first funding; imports default to 200000 on mainnet and 0 on testnet. Saving a height at or below the current one clears this network's chain data at the next launch and rescans from it.",
                comment: "SPV diagnostics"))
        }
        .confirmationDialog(
            NSLocalizedString("Drop unconfirmed transactions?", comment: "SPV diagnostics"),
            isPresented: $showDropUnconfirmedConfirm,
            titleVisibility: .visible
        ) {
            Button(
                NSLocalizedString("Drop & rescan", comment: "SPV diagnostics"),
                role: .destructive
            ) {
                dropUnconfirmedAndRescan()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "Deletes this wallet's unconfirmed transactions from this device only and frees the coins they tried to spend. The filter rescan restores any of them that is actually on the blockchain. Nothing is sent to the network.",
                comment: "SPV diagnostics"))
        }
        .alert(
            NSLocalizedString("Clear chain data and resync?", comment: "SPV diagnostics"),
            isPresented: Binding(
                get: { pendingResyncConfirmHeight != nil },
                set: { if !$0 { pendingResyncConfirmHeight = nil } }
            ),
            presenting: pendingResyncConfirmHeight
        ) { height in
            Button(
                NSLocalizedString("Clear & resync", comment: "SPV diagnostics"),
                role: .destructive
            ) {
                pendingResyncConfirmHeight = nil
                armBirthHeightResync(height: height)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                pendingResyncConfirmHeight = nil
            }
        } message: { height in
            Text(String(
                format: NSLocalizedString(
                    "Confirming saves birth height %u and clears this network's chain data at the next app launch, re-downloading it and rescanning filters from that height. Fully close and relaunch the app to start; the in-app Restart button does not apply this reset.",
                    comment: "SPV diagnostics"),
                height))
        }
    }

    // MARK: - Cards

    private var stateBadgeCard: some View {
        HStack {
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Text(stateLabel)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.dash.primaryText)
            Spacer()
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aggregate Progress")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                Text(percentageText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
            }
            // Custom bar — local UIKit `ProgressView` shadows SwiftUI's,
            // so we draw our own to avoid the name collision.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.dash.gray300.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.dash.blue)
                        .frame(width: max(0, geo.size.width * clampedProgress))
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var heightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(title: "Tip height", value: "\(coordinator.tipHeight)")
            row(title: "Best peer height", value: "\(coordinator.bestPeerHeight)")
            // Birth height (the wallet's filter-scan floor) with an
            // edit affordance — the escape hatch for wallets stamped
            // with a wrong creation height (e.g. imports made before
            // the import-birth-height fix): set 0 and rescan to
            // recover pre-import history.
            HStack {
                Text(NSLocalizedString("Wallet birth height", comment: "SPV diagnostics"))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                Text(walletBirthHeight.map { "\($0)" } ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .monospacedDigit()
                Button(action: {
                    birthHeightEntryText = walletBirthHeight.map { "\($0)" } ?? ""
                    showBirthHeightEntry = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dash.blue)
                }
                .disabled(walletBirthHeight == nil)
            }
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var connectedPeersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Connected Peers")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                Text("\(coordinator.connectedPeers.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .monospacedDigit()
            }
            .padding(.bottom, 4)

            if coordinator.connectedPeers.isEmpty {
                Text("No peers connected")
                    .font(.system(size: 13))
                    .foregroundColor(Color.dash.secondaryText)
            } else {
                ForEach(coordinator.connectedPeers) { peer in
                    HStack {
                        Text(peer.address)
                            .font(.system(size: 13))
                            .foregroundColor(.dash.primaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer()
                        peerBadge(peer.nodeType)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private func peerBadge(_ nodeType: PlatformSpvPeerNodeType) -> some View {
        Text(peerBadgeLabel(nodeType))
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(peerBadgeColor(nodeType).opacity(0.15))
            .foregroundColor(peerBadgeColor(nodeType))
            .cornerRadius(6)
    }

    private func peerBadgeLabel(_ nodeType: PlatformSpvPeerNodeType) -> String {
        switch nodeType {
        case .evonode:    return "Evonode"
        case .masternode: return "Masternode"
        case .normal:     return "Node"
        case .unknown:    return "Unclassified"
        }
    }

    private func peerBadgeColor(_ nodeType: PlatformSpvPeerNodeType) -> Color {
        switch nodeType {
        case .evonode:    return .purple
        case .masternode: return .blue
        case .normal:     return .gray
        case .unknown:    return .orange
        }
    }

    private var perPhaseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Phase Progress")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.primaryText)
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
                title: "Masternodes",
                state: coordinator.syncProgress.masternodes?.state,
                percentage: nil,
                current: coordinator.syncProgress.masternodes?.currentHeight,
                target: coordinator.syncProgress.masternodes?.targetHeight
            )
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var rescanFiltersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Filters", comment: "SPV diagnostics"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.primaryText)

            Text(NSLocalizedString(
                "Rewind this wallet's filter scan to re-download and re-match compact block filters, rediscovering any missed transactions.",
                comment: "SPV diagnostics"))
                .font(.system(size: 12))
                .foregroundColor(Color.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                rescanResultMessage = nil
                showRescanChoices = true
            }) {
                Text(NSLocalizedString("Rescan Filters", comment: "SPV diagnostics"))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.dash.gray300.opacity(0.3))
                    .foregroundColor(rescanEnabled ? .dash.primaryText : .secondary)
                    .cornerRadius(8)
            }
            .disabled(!rescanEnabled)

            if !rescanEnabled {
                Text(NSLocalizedString(
                    "Available only while SPV is running with a wallet bound.",
                    comment: "SPV diagnostics"))
                    .font(.system(size: 12))
                    .foregroundColor(Color.dash.secondaryText)
            }

            if let message = rescanResultMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(rescanResultIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    /// Bulk "finish what the restore left open".
    ///
    /// A restore rebuilds every shielded funding lock from chain as
    /// `RecoveredFromChain` — completion unknown — so a wallet with a long
    /// shielded history comes back with dozens of transfers each offering its
    /// own retry. Tapping through them one at a time is not a flow, and it is
    /// the only way to learn which ones still hold recoverable value. This runs
    /// the same resume over all of them behind a single authentication.
    @ViewBuilder
    private var pendingTransfersCard: some View {
        if !pendingRecoveries.isEmpty || isRecoveringPending || recoveryResultMessage != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Unfinished Transfers", comment: "SPV diagnostics"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)

                Text(NSLocalizedString(
                    "Restoring a wallet loses the local record of whether each balance transfer finished on Platform, so they come back marked unknown. This asks the network about every one of them at once, finishing the transfers that are still open and marking the rest as already spent. It never builds a new transaction, so it cannot spend anything twice.",
                    comment: "SPV diagnostics"))
                    .font(.system(size: 12))
                    .foregroundColor(Color.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                row(
                    title: NSLocalizedString("Awaiting completion", comment: "SPV diagnostics"),
                    value: "\(pendingRecoveries.count)")

                Button(action: { runPendingRecovery() }) {
                    HStack(spacing: 8) {
                        if isRecoveringPending {
                            SwiftUI.ProgressView()
                                .controlSize(.small)
                        }
                        Text(recoveryButtonTitle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.dash.gray300.opacity(0.3))
                    .foregroundColor(pendingRecoveries.isEmpty || isRecoveringPending ? .secondary : .dash.primaryText)
                    .cornerRadius(8)
                }
                .disabled(pendingRecoveries.isEmpty || isRecoveringPending)

                if let recoveryResultMessage {
                    Text(recoveryResultMessage)
                        .font(.system(size: 12))
                        .foregroundColor(recoveryResultIsError ? .red : Color.dash.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(12)
            .onAppear { refreshPendingRecoveries() }
        } else {
            Color.clear.frame(height: 0).onAppear { refreshPendingRecoveries() }
        }
    }

    private var recoveryButtonTitle: String {
        if let recoveryProgress, isRecoveringPending {
            return String(
                format: NSLocalizedString("Finishing %1$d of %2$d…", comment: "SPV diagnostics"),
                recoveryProgress.done, recoveryProgress.total)
        }
        return isRecoveringPending
            ? NSLocalizedString("Finishing…", comment: "SPV diagnostics")
            : NSLocalizedString("Finish Transfers", comment: "SPV diagnostics")
    }

    private var dropUnconfirmedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Unconfirmed Transactions", comment: "SPV diagnostics"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.primaryText)

            Text(NSLocalizedString(
                "Drop this wallet's transactions still waiting for the network (never locked or mined) from this device, make the coins they tried to spend available again, and rescan recent filters. A dropped transaction that is actually on the blockchain comes back on its own during the rescan. Nothing is sent to the network.",
                comment: "SPV diagnostics"))
                .font(.system(size: 12))
                .foregroundColor(Color.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            row(
                title: NSLocalizedString("Unconfirmed now", comment: "SPV diagnostics"),
                value: "\(UnconfirmedTransactionRemover.unconfirmedCount())")

            Button(action: {
                dropResultMessage = nil
                showDropUnconfirmedConfirm = true
            }) {
                HStack(spacing: 8) {
                    if isDroppingUnconfirmed {
                        SwiftUI.ProgressView()
                            .controlSize(.small)
                    }
                    Text(isDroppingUnconfirmed
                        ? NSLocalizedString("Dropping…", comment: "SPV diagnostics")
                        : NSLocalizedString("Drop Unconfirmed & Rescan", comment: "SPV diagnostics"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.dash.gray300.opacity(0.3))
                .foregroundColor(rescanEnabled && !isDroppingUnconfirmed ? .red : .secondary)
                .cornerRadius(8)
            }
            .disabled(!rescanEnabled || isDroppingUnconfirmed)

            if !rescanEnabled {
                Text(NSLocalizedString(
                    "Available only while SPV is running with a wallet bound.",
                    comment: "SPV diagnostics"))
                    .font(.system(size: 12))
                    .foregroundColor(Color.dash.secondaryText)
            }

            if let message = dropResultMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(dropResultIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                SwiftDashSDKWalletRuntime.stopCoreSPV()
            }) {
                Text("Stop")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.dash.gray300.opacity(0.3))
                    .foregroundColor(.dash.primaryText)
                    .cornerRadius(8)
            }
            .disabled(coreLifecycleBusy)
            Button(action: {
                SwiftDashSDKWalletRuntime.restartCoreSPV()
            }) {
                HStack(spacing: 8) {
                    if coordinator.isRestarting {
                        SwiftUI.ProgressView()
                            .controlSize(.small)
                    }
                    Text(coordinator.isRestarting ? "Restarting…" : "Restart")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.dash.gray300.opacity(0.3))
                .foregroundColor(.dash.primaryText)
                .cornerRadius(8)
            }
            .disabled(coreLifecycleBusy)
        }
    }

    private var coreLifecycleBusy: Bool {
        coordinator.isRestarting || coordinator.isApplyingChainResync
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

    private func phaseRow(title: String, state: SPVSyncState?, percentage: Double?, current: UInt32?, target: UInt32?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.dash.primaryText)
            Spacer()
            Text(phaseDetail(state: state, percentage: percentage, current: current, target: target))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.dash.secondaryText)
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

// MARK: - Rescan Filters actions

/// Everything that touches the SDK / SwiftData for the Rescan Filters
/// flow lives here, off the view's declarative body. `@MainActor`
/// because it reads `SwiftDashSDKHost.shared` (a `@MainActor` singleton)
/// and drives the FFI on the main actor as required by
/// `spvRescanFilters`.
@MainActor
extension SwiftDashSDKSPVStatusScreen {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.spv-status")

    /// True when SPV is running AND a wallet is bound — the two
    /// conditions `spvRescanFilters` needs for an immediate rescan.
    var rescanEnabled: Bool {
        guard !coordinator.isRestarting, !coordinator.isApplyingChainResync else {
            return false
        }
        guard SwiftDashSDKHost.shared.wallet != nil,
              let manager = SwiftDashSDKHost.shared.manager else {
            return false
        }
        return (try? manager.isSpvRunning()) == true
    }

    /// The bound wallet's persisted birth height (block height at
    /// creation) from its `PersistentWallet` row, or `nil` when no
    /// wallet is bound / the row can't be read. This is the honest
    /// wallet-creation height — distinct from `syncedHeight`, which is
    /// the current high-water, not the birth height. When `nil` the
    /// "From wallet creation" choice is omitted rather than defaulted.
    var walletBirthHeight: UInt32? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer else {
            return nil
        }
        let walletId = wallet.walletId
        var descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId })
        descriptor.fetchLimit = 1
        guard let row = (try? container.mainContext.fetch(descriptor))?.first else {
            return nil
        }
        return row.birthHeight
    }

    /// Validate the "From height…" text field to a `UInt32` and start
    /// the rescan. A non-numeric or empty entry is rejected with an
    /// error banner rather than defaulted to `0`.
    func refreshPendingRecoveries() {
        pendingRecoveries = AssetLockRecoveryService.pendingRecoveries()
    }

    func runPendingRecovery() {
        guard !isRecoveringPending else { return }
        let pending = pendingRecoveries
        guard !pending.isEmpty else { return }

        isRecoveringPending = true
        recoveryResultMessage = nil
        recoveryProgress = (0, pending.count)

        Task { @MainActor in
            let outcome = await AssetLockRecoveryService().recoverAll(pending) { done, total in
                recoveryProgress = (done, total)
            }
            isRecoveringPending = false
            recoveryProgress = nil
            refreshPendingRecoveries()

            if outcome.cancelled, outcome.attempted == 0 {
                recoveryResultIsError = false
                recoveryResultMessage = NSLocalizedString("Cancelled.", comment: "SPV diagnostics")
                return
            }

            // Report each bucket separately: "finished" and "was already spent"
            // are different facts about the user's money, and only the first is
            // a completion this pass witnessed.
            var parts: [String] = []
            if outcome.completed > 0 {
                parts.append(String(
                    format: NSLocalizedString("%d finished", comment: "SPV diagnostics"),
                    outcome.completed))
            }
            if outcome.alreadySpent > 0 {
                parts.append(String(
                    format: NSLocalizedString("%d already spent", comment: "SPV diagnostics"),
                    outcome.alreadySpent))
            }
            if outcome.failed > 0 {
                parts.append(String(
                    format: NSLocalizedString("%d could not be reached", comment: "SPV diagnostics"),
                    outcome.failed))
            }
            if outcome.cancelled {
                parts.append(NSLocalizedString("stopped early", comment: "SPV diagnostics"))
            }
            if outcome.stoppedAfterRepeatedFailures {
                parts.append(NSLocalizedString("stopped after repeated failures", comment: "SPV diagnostics"))
            }
            recoveryResultIsError = outcome.failed > 0
            var summary = parts.isEmpty
                ? NSLocalizedString("Nothing to finish.", comment: "SPV diagnostics")
                : parts.joined(separator: ", ")
            // A count of failures with no reason is undiagnosable; carry the
            // first one's text so the screen says what actually went wrong.
            if let reason = outcome.firstFailureMessage {
                summary += "\n\(reason)"
            }
            recoveryResultMessage = summary
        }
    }

    func startRescanFromEnteredHeight() {
        let trimmed = heightEntryText.trimmingCharacters(in: .whitespaces)
        guard let height = UInt32(trimmed) else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "Enter a valid block height.", comment: "SPV diagnostics")
            return
        }
        performRescan(fromHeight: height)
    }

    /// Rewind the running filter scan to `fromHeight` via the SDK FFI.
    /// The call only lowers a synced-height checkpoint (synchronous /
    /// cheap); the running filter sync re-downloads and re-matches on
    /// its next tick, so the Filters row on this screen drops and
    /// re-climbs — that visible movement is the confirmation. On a
    /// throw the error is surfaced; success is never claimed if the
    /// call failed.
    func performRescan(fromHeight: UInt32) {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let manager = SwiftDashSDKHost.shared.manager else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "Available only while SPV is running with a wallet bound.",
                comment: "SPV diagnostics")
            return
        }
        do {
            try manager.spvRescanFilters(walletId: wallet.walletId, fromHeight: fromHeight)
            rescanResultIsError = false
            rescanResultMessage = String(
                format: NSLocalizedString(
                    "Rescan started from height %u — watch the Filters row.",
                    comment: "SPV diagnostics"),
                fromHeight)
            Self.logger.info("🛰️ SPV-STATUS :: rescan filters armed from height \(fromHeight, privacy: .public)")
        } catch {
            rescanResultIsError = true
            rescanResultMessage = error.localizedDescription
            Self.logger.error("🛰️ SPV-STATUS :: rescan filters failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Run the bulk unconfirmed-transaction drop + rescan. The await
    /// spans the persistence surgery, the runtime reload, and the rescan
    /// arm, so the button's spinner honestly covers the whole operation.
    func dropUnconfirmedAndRescan() {
        guard !isDroppingUnconfirmed else { return }
        isDroppingUnconfirmed = true
        Task { @MainActor in
            do {
                let outcome = try await UnconfirmedTransactionRemover().dropAllUnconfirmedAndRescan()
                if outcome.dropped == 0 {
                    dropResultIsError = false
                    dropResultMessage = NSLocalizedString(
                        "No unconfirmed transactions to drop.",
                        comment: "SPV diagnostics")
                } else if outcome.rescanArmed {
                    dropResultIsError = false
                    dropResultMessage = String(
                        format: NSLocalizedString(
                            "Dropped %d unconfirmed transaction(s) — rescanning filters, watch the Filters row.",
                            comment: "SPV diagnostics"),
                        outcome.dropped)
                } else {
                    // The drop finished but the recovery rescan didn't
                    // arm — flag it instead of claiming the safety net ran.
                    dropResultIsError = true
                    dropResultMessage = String(
                        format: NSLocalizedString(
                            "Dropped %d unconfirmed transaction(s), but the filter rescan couldn't start — run Rescan Filters above.",
                            comment: "SPV diagnostics"),
                        outcome.dropped)
                }
                Self.logger.info("🛰️ SPV-STATUS :: bulk unconfirmed drop finished — \(outcome.dropped, privacy: .public) tx(s), rescanArmed=\(outcome.rescanArmed, privacy: .public)")
            } catch {
                dropResultIsError = true
                dropResultMessage = error.localizedDescription
                Self.logger.error("🛰️ SPV-STATUS :: bulk unconfirmed drop failed: \(String(describing: error), privacy: .public)")
            }
            isDroppingUnconfirmed = false
        }
    }

    /// Validate the birth-height text field and route it. The row is the
    /// durable source the SDK's `loadWallets` restore feeds back to Rust at
    /// every launch; the LIVE session can never honor an edit (the Rust
    /// wallet's birth height has no update FFI, and dash-spv never
    /// re-anchors an existing header store, so heights below the store's
    /// first stored block stay unreachable until the store is rebuilt).
    ///
    /// - Raising the height persists immediately — it needs no chain
    ///   rebuild — and disarms any pending resync marker it supersedes.
    /// - A height at or below the current one means "make this floor
    ///   real", which requires the next-launch chain resync; nothing is
    ///   written until the user confirms via `armBirthHeightResync`.
    ///   Equal heights are included: a store anchored above an
    ///   already-correct birth height (e.g. created before the birth
    ///   height was fixed) is repaired the same way, and re-saving the
    ///   current height is how this UI expresses that.
    func saveEnteredBirthHeight() {
        let trimmed = birthHeightEntryText.trimmingCharacters(in: .whitespaces)
        guard let height = UInt32(trimmed) else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "Enter a valid block height.", comment: "SPV diagnostics")
            return
        }
        guard let (row, walletId, network) = boundWalletRow() else { return }
        if height <= row.birthHeight {
            pendingResyncConfirmHeight = height
            return
        }
        saveRaisedBirthHeight(height, row: row, walletId: walletId, network: network)
    }

    /// Fetch the bound wallet's `PersistentWallet` row plus the identifiers
    /// the birth-height flows need. Emits the error banner and returns nil
    /// when no wallet is bound, the row is missing, or it carries no
    /// network.
    private func boundWalletRow() -> (PersistentWallet, walletId: Data, network: Network)? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "Available only while SPV is running with a wallet bound.",
                comment: "SPV diagnostics")
            return nil
        }
        let walletId = wallet.walletId
        var descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId })
        descriptor.fetchLimit = 1
        guard let row = (try? container.mainContext.fetch(descriptor))?.first else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "No persisted wallet row found for the bound wallet.",
                comment: "SPV diagnostics")
            return nil
        }
        guard let network = row.network else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "The persisted wallet row has no network — cannot arm a resync.",
                comment: "SPV diagnostics")
            return nil
        }
        return (row, walletId, network)
    }

    /// Persist a raised birth height (no chain rebuild needed) and disarm
    /// any pending resync marker the raise supersedes.
    private func saveRaisedBirthHeight(
        _ height: UInt32, row: PersistentWallet, walletId: Data, network: Network
    ) {
        guard let container = SwiftDashSDKHost.shared.modelContainer else { return }
        let previous = row.birthHeight
        row.birthHeight = height
        do {
            try container.mainContext.save()
        } catch {
            row.birthHeight = previous
            rescanResultIsError = true
            rescanResultMessage = error.localizedDescription
            Self.logger.error("🛰️ SPV-STATUS :: birth-height save failed: \(String(describing: error), privacy: .public)")
            return
        }
        Self.logger.info("🛰️ SPV-STATUS :: birth height \(previous, privacy: .public) → \(height, privacy: .public)")
        SPVChainResyncMarker.disarm(walletId: walletId, network: network)
        rescanResultIsError = false
        rescanResultMessage = NSLocalizedString(
            "Birth height saved — the raised scan floor applies from the next launch.",
            comment: "SPV diagnostics")
    }

    /// Confirmed clear-and-resync: write the birth height, rewind the row's
    /// `syncedHeight` so the restored wallet's filter scan starts at the new
    /// floor, and arm `SPVChainResyncMarker` — the SPV coordinator applies
    /// it on the next launch by deleting the chain store before `startSpv`.
    func armBirthHeightResync(height: UInt32) {
        guard let (row, walletId, network) = boundWalletRow(),
              let container = SwiftDashSDKHost.shared.modelContainer else { return }
        let previousBirth = row.birthHeight
        let previousSynced = row.syncedHeight
        row.birthHeight = height
        if row.syncedHeight > height {
            row.syncedHeight = height
        }
        do {
            try container.mainContext.save()
        } catch {
            row.birthHeight = previousBirth
            row.syncedHeight = previousSynced
            rescanResultIsError = true
            rescanResultMessage = error.localizedDescription
            Self.logger.error("🛰️ SPV-STATUS :: birth-height resync save failed: \(String(describing: error), privacy: .public)")
            return
        }
        SPVChainResyncMarker.arm(walletId: walletId, fromHeight: height, network: network)
        Self.logger.info("🛰️ SPV-STATUS :: birth height \(previousBirth, privacy: .public) → \(height, privacy: .public), chain resync armed")
        rescanResultIsError = false
        rescanResultMessage = String(
            format: NSLocalizedString(
                "Resync armed from height %u. Fully close the app, then launch it again to start. The in-app Restart button does not apply this reset.",
                comment: "SPV diagnostics"),
            height)
    }
}
