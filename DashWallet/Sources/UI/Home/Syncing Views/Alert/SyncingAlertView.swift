//
//  SyncingAlertView.swift
//  DashWallet
//
//  SwiftUI content for the syncing detail alert: overall percentage up
//  top, then one row per SPV sync phase (headers → filter headers →
//  filters → masternode list) with its own progress bar, so the dialog
//  explains what the overall percentage is actually working on instead
//  of a single "header #x of x" line for an already-finished phase.
//

import Combine
import SwiftDashSDK
import SwiftUI
import DashUIKit

// MARK: - SyncingAlertViewModel

/// Mirrors `SyncModelImpl`'s observer wiring (same monitor, same
/// main-thread callbacks) but also republishes the per-phase snapshot,
/// the connected-peer list, and a stall signal that surfaces the
/// "Sync too slow? Change peers" action.
final class SyncingAlertViewModel: ObservableObject {
    /// No sync progress for this long while `.syncing` → offer the
    /// peer-rotation action. Generous enough that a normal filter-batch
    /// pause doesn't trip it.
    private static let stallThreshold: TimeInterval = 45

    @Published private(set) var state: SyncingActivityMonitor.State
    @Published private(set) var progress: Double
    @Published private(set) var snapshot: SyncStateSnapshot
    @Published private(set) var peers: [PlatformSpvPeerInfo] = []
    /// True after `stallThreshold` seconds without a progress change
    /// while syncing — shows the "Sync too slow?" row.
    @Published private(set) var isStalled = false
    /// Mirrors the coordinator's complete stop → start transaction, including
    /// restarts initiated from the diagnostics screen.
    @Published private(set) var isRotatingPeers = false

    private let monitor = SyncingActivityMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastProgressChange = Date()
    private var stallTimer: AnyCancellable?

    init() {
        state = monitor.state
        progress = monitor.progress
        snapshot = monitor.snapshot
        monitor.add(observer: self)

        SwiftDashSDKSPVCoordinator.shared.$connectedPeers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in
                self?.peers = peers
            }
            .store(in: &cancellables)

        SwiftDashSDKSPVCoordinator.shared.$isRestarting
            .receive(on: RunLoop.main)
            .sink { [weak self] isRestarting in
                self?.isRotatingPeers = isRestarting
            }
            .store(in: &cancellables)

        stallTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.evaluateStall()
            }
    }

    deinit {
        monitor.remove(observer: self)
    }

    /// Registration/claim in flight means an asset-lock may be waiting on
    /// an IS/CL proof over the P2P connection — a restart re-establishes
    /// the subscription but mid-flight is the wrong moment to encourage
    /// one, so the action hides. MainActor: reads the coordinator's
    /// isolated phase; only touched from SwiftUI body / button actions.
    @MainActor
    var canRotatePeers: Bool {
        switch DWIdentityRegistrationCoordinator.shared.phase {
        case .preparingKeys, .inFlight:
            return false
        case .idle, .completed, .failed:
            return true
        }
    }

    @MainActor
    func rotatePeers() {
        guard canRotatePeers else { return }
        isStalled = false
        lastProgressChange = Date()
        SwiftDashSDKWalletRuntime.rotatePeers()
    }

    private func evaluateStall() {
        guard state == .syncing else {
            isStalled = false
            return
        }
        isStalled = Date().timeIntervalSince(lastProgressChange) > Self.stallThreshold
    }
}

// MARK: SyncingActivityMonitorObserver

extension SyncingAlertViewModel: SyncingActivityMonitorObserver {
    func syncingActivityMonitorProgressDidChange(_ progress: Double) {
        if progress != self.progress {
            lastProgressChange = Date()
            isStalled = false
        }
        self.progress = progress
        snapshot = monitor.snapshot
    }

    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State,
                                              state: SyncingActivityMonitor.State) {
        self.state = state
        snapshot = monitor.snapshot
        lastProgressChange = Date()
    }
}

// MARK: - SyncingAlertView

struct SyncingAlertView: View {
    @ObservedObject var viewModel: SyncingAlertViewModel
    var onOk: () -> Void

    @State private var isRotating = false

    private static let heightFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            Image("icon_syncing_large")
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(
                    viewModel.state == .syncing
                        ? .linear(duration: 1.75).repeatForever(autoreverses: false)
                        : .default,
                    value: isRotating)

            Text(title)
                .font(.title3)
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            content
                .padding(.top, 20)

            if !viewModel.peers.isEmpty {
                peersSection
                    .padding(.top, 20)
            }

            if (viewModel.isStalled || viewModel.isRotatingPeers) && viewModel.canRotatePeers {
                stallSection
                    .padding(.top, 16)
            }

            DashButton(
                text: NSLocalizedString("OK", comment: ""),
                size: .small,
                stretch: false
            ) {
                onOk()
            }
            .padding(.top, 28)
        }
        .padding(.horizontal, 24)
        .onAppear { isRotating = viewModel.state == .syncing }
        .onChange(of: viewModel.state) { newState in
            isRotating = newState == .syncing
        }
    }

    private var title: String {
        switch viewModel.state {
        case .syncFailed:
            return NSLocalizedString("Sync Failed", comment: "")
        case .noConnection:
            return NSLocalizedString("Unable to connect", comment: "")
        default:
            return String(format: "%@ %.1f%%",
                          NSLocalizedString("Syncing", comment: ""),
                          min(max(viewModel.progress, 0), 1) * 100.0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .syncing, .syncDone:
            if viewModel.snapshot.phases.isEmpty {
                // No per-phase detail from the SDK yet — single-line
                // fallback from the snapshot's headline numbers.
                Text(String(format: NSLocalizedString("block #%d of %d", comment: ""),
                            viewModel.snapshot.lastSyncBlockHeight,
                            viewModel.snapshot.estimatedBlockHeight))
                    .font(.footnote)
                    .foregroundColor(.dash.secondaryText)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(viewModel.snapshot.phases.enumerated()), id: \.offset) { _, phase in
                        phaseRow(phase)
                    }
                }
            }

        case .syncFailed, .noConnection, .unknown:
            EmptyView()
        }
    }

    private func phaseRow(_ phase: SyncStateSnapshot.Phase) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label(for: phase.kind))
                    .font(.footnote)
                    .foregroundColor(.dash.primaryText)
                Spacer(minLength: 12)
                if phase.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.green)
                } else {
                    Text("\(formattedHeight(phase.current)) / \(formattedHeight(phase.target))")
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.dash.secondaryText)
                }
            }
            // Fully qualified: the app declares its own `ProgressView`
            // type, which shadows SwiftUI's in this scope.
            SwiftUI.ProgressView(value: fraction(of: phase))
                .progressViewStyle(.linear)
                .tint(phase.isComplete ? .green : .dash.blue)
        }
    }

    private var peersSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text(NSLocalizedString("Connected peers", comment: "SPV sync"))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                Text("\(viewModel.peers.count)")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundColor(.dash.secondaryText)
            }
            ForEach(viewModel.peers) { peer in
                HStack {
                    Circle()
                        .fill(color(for: peer.nodeType))
                        .frame(width: 6, height: 6)
                    Text(peer.address)
                        .font(.caption.monospaced())
                        .foregroundColor(.dash.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(label(for: peer.nodeType))
                        .font(.caption)
                        .foregroundColor(.dash.tertiaryText)
                }
            }
        }
    }

    private var stallSection: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Sync too slow?", comment: "SPV sync"))
                .font(.footnote)
                .foregroundColor(.dash.secondaryText)
            Button {
                viewModel.rotatePeers()
            } label: {
                if viewModel.isRotatingPeers {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                } else {
                    Text(NSLocalizedString("Change peers", comment: "SPV sync"))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.dash.blue)
                }
            }
            .disabled(viewModel.isRotatingPeers)
        }
    }

    private func color(for nodeType: PlatformSpvPeerNodeType) -> Color {
        switch nodeType {
        case .evonode: return .purple
        case .masternode: return .dash.blue
        case .normal: return .green
        case .unknown: return .gray
        }
    }

    private func label(for nodeType: PlatformSpvPeerNodeType) -> String {
        switch nodeType {
        case .evonode: return NSLocalizedString("Evonode", comment: "SPV sync peer type")
        case .masternode: return NSLocalizedString("Masternode", comment: "SPV sync peer type")
        case .normal: return NSLocalizedString("Node", comment: "SPV sync peer type")
        case .unknown: return ""
        }
    }

    private func label(for kind: SyncStateSnapshot.Phase.Kind) -> String {
        switch kind {
        case .headers:
            return NSLocalizedString("Headers", comment: "SPV sync phase")
        case .filterHeaders:
            return NSLocalizedString("Filter headers", comment: "SPV sync phase")
        case .filters:
            return NSLocalizedString("Filters", comment: "SPV diagnostics")
        case .masternodes:
            return NSLocalizedString("Masternode list", comment: "SPV sync phase")
        }
    }

    private func fraction(of phase: SyncStateSnapshot.Phase) -> Double {
        guard !phase.isComplete else { return 1.0 }
        guard phase.target > 0 else { return 0.0 }
        return min(1.0, Double(phase.current) / Double(phase.target))
    }

    private func formattedHeight(_ height: UInt32) -> String {
        Self.heightFormatter.string(from: NSNumber(value: height)) ?? String(height)
    }
}
