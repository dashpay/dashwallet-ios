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
    /// Non-nil presents the post-save "rescan now?" prompt carrying the
    /// height that was just written.
    @State private var savedBirthHeightPendingRescan: UInt32?

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
                    heightsCard
                    perPhaseCard
                    rescanFiltersCard
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
        .background(Color.primaryBackground)
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
                "Re-checks the compact block filters from the chosen height for this wallet's transactions, re-downloading and re-matching them. This rediscovers any missed transactions but can take a while. Full rescan re-checks every filter since genesis and can take a long time on mainnet.",
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
                "The wallet's creation height — the floor for filter scans and \"From wallet creation\" rescans. Set 0 for an imported wallet whose history may predate this device.",
                comment: "SPV diagnostics"))
        }
        .alert(
            NSLocalizedString("Birth height updated", comment: "SPV diagnostics"),
            isPresented: Binding(
                get: { savedBirthHeightPendingRescan != nil },
                set: { if !$0 { savedBirthHeightPendingRescan = nil } }
            ),
            presenting: savedBirthHeightPendingRescan
        ) { height in
            Button(NSLocalizedString("Rescan now", comment: "SPV diagnostics")) {
                savedBirthHeightPendingRescan = nil
                performRescan(fromHeight: height)
            }
            Button(NSLocalizedString("Later", comment: ""), role: .cancel) {
                savedBirthHeightPendingRescan = nil
            }
        } message: { _ in
            Text(NSLocalizedString(
                "The saved height becomes the scan floor from the next launch. Rescan filters from it now to pick up any missed history immediately.",
                comment: "SPV diagnostics"))
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
                    .foregroundColor(.primaryText)
                Spacer()
                Text(walletBirthHeight.map { "\($0)" } ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .monospacedDigit()
                Button(action: {
                    birthHeightEntryText = walletBirthHeight.map { "\($0)" } ?? ""
                    showBirthHeightEntry = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dashBlue)
                }
                .disabled(walletBirthHeight == nil)
            }
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var connectedPeersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Connected Peers")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Spacer()
                Text("\(coordinator.connectedPeers.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .monospacedDigit()
            }
            .padding(.bottom, 4)

            if coordinator.connectedPeers.isEmpty {
                Text("No peers connected")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                ForEach(coordinator.connectedPeers) { peer in
                    HStack {
                        Text(peer.address)
                            .font(.system(size: 13))
                            .foregroundColor(.primaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer()
                        peerBadge(peer.nodeType)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondaryBackground)
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
                title: "Masternodes",
                state: coordinator.syncProgress.masternodes?.state,
                percentage: nil,
                current: coordinator.syncProgress.masternodes?.currentHeight,
                target: coordinator.syncProgress.masternodes?.targetHeight
            )
        }
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var rescanFiltersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Filters", comment: "SPV diagnostics"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryText)

            Text(NSLocalizedString(
                "Rewind this wallet's filter scan to re-download and re-match compact block filters, rediscovering any missed transactions.",
                comment: "SPV diagnostics"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                rescanResultMessage = nil
                showRescanChoices = true
            }) {
                Text(NSLocalizedString("Rescan Filters", comment: "SPV diagnostics"))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray300.opacity(0.3))
                    .foregroundColor(rescanEnabled ? .primaryText : .secondary)
                    .cornerRadius(8)
            }
            .disabled(!rescanEnabled)

            if !rescanEnabled {
                Text(NSLocalizedString(
                    "Available only while SPV is running with a wallet bound.",
                    comment: "SPV diagnostics"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
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
                SwiftDashSDKWalletRuntime.stop()
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

    /// Validate the birth-height text field and write it onto the
    /// bound wallet's `PersistentWallet` row. The row is the durable
    /// source: the SDK's `loadWallets` restore sends `birthHeight`
    /// back to Rust at every launch, so the edit becomes the wallet's
    /// scan floor from the next start. The LIVE session's floor is
    /// unchanged (Rust read it at configure) — the post-save prompt
    /// offers an immediate filter rescan from the new height, which
    /// reads the row and therefore honors the edit right away.
    func saveEnteredBirthHeight() {
        let trimmed = birthHeightEntryText.trimmingCharacters(in: .whitespaces)
        guard let height = UInt32(trimmed) else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "Enter a valid block height.", comment: "SPV diagnostics")
            return
        }
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer else {
            rescanResultIsError = true
            rescanResultMessage = NSLocalizedString(
                "Available only while SPV is running with a wallet bound.",
                comment: "SPV diagnostics")
            return
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
            return
        }
        let previous = row.birthHeight
        guard height != previous else { return }
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
        savedBirthHeightPendingRescan = height
    }
}
