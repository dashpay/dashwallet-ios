//
//  ShieldedSyncMonitor.swift
//  DashWallet
//
//  App-lifetime observer of the SDK's shielded (Orchard) sync loop, backing
//  the Sync Info → Shielded Sync Info diagnostic screen. Mirrors the
//  since-launch diagnostics of `ShieldedService` in the SwiftExampleApp
//  (pass counters, durations, live per-pass progress) without owning any
//  lifecycle — `PlatformAddressSyncCoordinator` still starts/stops the
//  loop and attaches/detaches this monitor around each manager generation.
//
//  Singleton justification (CLAUDE.md guardrail #4): the counters are
//  "since launch" — they must survive the diagnostic screen being closed
//  and reopened, so they cannot live in a per-screen ViewModel. Splitting
//  them out of `PlatformAddressSyncCoordinator` keeps that coordinator
//  from accumulating published UI counters (the exact anti-pattern the
//  2026-07 arch review flagged).
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
final class ShieldedSyncMonitor: ObservableObject {

    static let shared = ShieldedSyncMonitor()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.shielded-sync-monitor")

    // MARK: - Published state (Shielded Sync Info screen)

    /// Whether a shielded sync pass is currently in flight (mirror of
    /// `PlatformWalletManager.shieldedSyncIsSyncing`; false while detached).
    @Published private(set) var isSyncing = false
    /// Whether the active wallet has a bound shielded sub-wallet. `nil`
    /// while detached or before the first bound-state read — unknown is
    /// modeled as unknown, not defaulted.
    @Published private(set) var isBound: Bool? = nil
    /// Completion time of the last successful pass observed (from the SDK's
    /// persisted watermark on attach, then per-event).
    @Published private(set) var lastSyncTime: Date? = nil
    /// Error message of the last failed pass, cleared by the next success.
    @Published private(set) var lastError: String? = nil

    /// Sync watermark: highest note-commitment index scanned for the active
    /// wallet (max over its per-account `PersistentShieldedSyncState` rows).
    @Published private(set) var notesSynced: UInt64 = 0

    // Since-launch counters (Platform-walking passes only — cooldown-skipped
    // passes carry all-zero payloads and are not counted).
    @Published private(set) var syncCountSinceLaunch = 0
    @Published private(set) var totalScanned: UInt64 = 0
    @Published private(set) var totalNewNotes: UInt64 = 0
    @Published private(set) var totalNewlySpent: UInt64 = 0

    // Pass timing, measured on this side of the FFI between the rising and
    // falling edge of `shieldedSyncIsSyncing`.
    @Published private(set) var lastSyncDuration: TimeInterval? = nil
    @Published private(set) var longestSyncDuration: TimeInterval? = nil
    /// Seconds the in-flight pass has been running; ticks at 1 Hz while
    /// syncing, nil otherwise.
    @Published private(set) var currentSyncElapsed: TimeInterval? = nil

    // Live per-pass progress (mirrors of the manager's per-chunk callbacks;
    // nil between passes).
    @Published private(set) var currentSyncScanned: UInt64? = nil
    @Published private(set) var currentSyncBlockHeight: UInt64? = nil
    @Published private(set) var currentTreeCommitted: UInt64? = nil
    @Published private(set) var currentTreeTotal: UInt64? = nil

    // MARK: - Private state

    private weak var manager: PlatformWalletManager?
    private var walletId: Data?
    private var modelContainer: ModelContainer?

    private var cancellables = Set<AnyCancellable>()
    private var elapsedTimer: Timer?
    private var currentPassStart: Date?

    private init() {}

    // MARK: - Lifecycle (called by PlatformAddressSyncCoordinator)

    func attach(manager: PlatformWalletManager, walletId: Data, modelContainer: ModelContainer?) {
        detach()

        self.manager = manager
        self.walletId = walletId
        self.modelContainer = modelContainer

        refreshBoundState()
        refreshNotesSynced()
        if let unixSeconds = try? manager.lastShieldedSyncUnixSeconds(), unixSeconds > 0 {
            lastSyncTime = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        }

        manager.$shieldedSyncIsSyncing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] syncing in
                self?.handleSyncingEdge(syncing)
            }
            .store(in: &cancellables)

        manager.$lastShieldedSyncEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self, let event else { return }
                self.handleEvent(event)
            }
            .store(in: &cancellables)

        manager.$currentShieldedSyncScanned
            .receive(on: RunLoop.main)
            .assign(to: \.currentSyncScanned, on: self)
            .store(in: &cancellables)
        manager.$currentShieldedSyncBlockHeight
            .receive(on: RunLoop.main)
            .assign(to: \.currentSyncBlockHeight, on: self)
            .store(in: &cancellables)
        manager.$currentShieldedTreeCommitted
            .receive(on: RunLoop.main)
            .assign(to: \.currentTreeCommitted, on: self)
            .store(in: &cancellables)
        manager.$currentShieldedTreeTotal
            .receive(on: RunLoop.main)
            .assign(to: \.currentTreeTotal, on: self)
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
        stopElapsedTimer()
        manager = nil
        walletId = nil
        modelContainer = nil
        isSyncing = false
        isBound = nil
        currentSyncScanned = nil
        currentSyncBlockHeight = nil
        currentTreeCommitted = nil
        currentTreeTotal = nil
        currentSyncElapsed = nil
        currentPassStart = nil
    }

    // MARK: - Actions (Shielded Sync Info screen)

    /// Run one shielded sync pass now. Errors surface via `lastError`.
    func syncNow() async {
        guard let manager else {
            lastError = "Platform sync is not running"
            return
        }
        lastError = nil
        do {
            try await manager.syncShieldedNow()
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("🛡️ SHIELD-MON :: syncShieldedNow threw: \(String(describing: error), privacy: .public)")
        }
    }

    /// Reset the displayed since-launch counters and timings. Purely a
    /// display reset — persisted notes and the sync watermark are untouched.
    func clearDisplayCounters() {
        syncCountSinceLaunch = 0
        totalScanned = 0
        totalNewNotes = 0
        totalNewlySpent = 0
        lastSyncDuration = nil
        longestSyncDuration = nil
        lastError = nil
    }

    // MARK: - Event handling

    private func handleSyncingEdge(_ syncing: Bool) {
        isSyncing = syncing
        if syncing {
            currentPassStart = Date()
            currentSyncElapsed = 0
            startElapsedTimer()
        } else {
            if let start = currentPassStart {
                let duration = Date().timeIntervalSince(start)
                lastSyncDuration = duration
                if duration > (longestSyncDuration ?? 0) {
                    longestSyncDuration = duration
                }
            }
            currentPassStart = nil
            stopElapsedTimer()
        }
    }

    private func handleEvent(_ event: ShieldedSyncEvent) {
        guard let walletId, let result = event.result(for: walletId) else { return }

        if result.skipped {
            isBound = false
            return
        }
        isBound = true

        if result.success {
            lastError = nil
            if event.syncUnixSeconds > 0 {
                lastSyncTime = Date(timeIntervalSince1970: TimeInterval(event.syncUnixSeconds))
            }
            // Cooldown-skipped passes carry all-zero payloads (see
            // `ShieldedWalletSyncResult.cooldownSkip`) — keep the cached
            // counters instead of applying them.
            if !result.cooldownSkip {
                syncCountSinceLaunch += 1
                totalScanned += result.totalScanned
                totalNewNotes += UInt64(result.newNotes)
                totalNewlySpent += UInt64(result.newlySpent)
                refreshNotesSynced()
            }
        } else {
            lastError = result.errorMessage ?? "Shielded sync failed"
        }
    }

    // MARK: - Reads

    private func refreshBoundState() {
        guard let manager, let walletId else {
            isBound = nil
            return
        }
        // `shieldedDefaultAddress` returns nil when the wallet has no bound
        // shielded sub-wallet and throws when the wallet id is unknown to
        // the manager; neither state is "bound".
        isBound = ((try? manager.shieldedDefaultAddress(walletId: walletId)) ?? nil) != nil
    }

    private func refreshNotesSynced() {
        guard let modelContainer, let walletId else {
            notesSynced = 0
            return
        }
        let descriptor = FetchDescriptor<PersistentShieldedSyncState>(
            predicate: #Predicate<PersistentShieldedSyncState> { $0.walletId == walletId })
        do {
            let rows = try modelContainer.mainContext.fetch(descriptor)
            notesSynced = rows.map(\.lastSyncedIndex).max() ?? 0
        } catch {
            Self.logger.warning("🛡️ SHIELD-MON :: sync-state fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.currentPassStart else { return }
                self.currentSyncElapsed = Date().timeIntervalSince(start)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        currentSyncElapsed = nil
    }
}
