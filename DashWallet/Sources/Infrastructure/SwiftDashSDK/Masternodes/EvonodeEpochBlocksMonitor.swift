//
//  EvonodeEpochBlocksMonitor.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import SwiftDashSDK
import UIKit

// MARK: - EvonodeEpochBlocksMonitor

/// The one refresh policy for "blocks my evonodes proposed this epoch",
/// shared by every screen that shows it (home card, masternode list).
///
/// Why a shared instance (see the singleton guardrail): one range scan of
/// the epoch's proposers serves every consumer — two screens polling
/// independently would double the network work for the same answer. The
/// fetch itself is behind the `EvonodeEpochBlocksProviding` seam and the
/// owned-evonode source is injectable, so tests can build their own.
///
/// Behaviour:
/// - at most ONE scan in flight; a forced refresh requested while one runs
///   is queued and starts when the slot frees (never dropped);
/// - routine triggers (appear / foreground) are throttled to
///   `refreshInterval` after a success and `retryInterval` after a failure;
/// - a wallet / network switch cancels the running scan (the service stops
///   paging), drops the stale value immediately, and queues a forced scan;
///   the superseded scan's result is discarded by generation.
/// - triggers wired here: sync reaching done, app foreground, active-wallet
///   and network change. Screens only call `refresh()` on appear.
@MainActor
final class EvonodeEpochBlocksMonitor: ObservableObject {
    static let shared = EvonodeEpochBlocksMonitor()

    /// Latest tallies, or `nil` when the wallet has no active evonodes or
    /// nothing has been fetched yet.
    @Published private(set) var blocks: EvonodeEpochBlocks?

    /// Bumped on every context-changing trigger the monitor reacts to (sync
    /// reaching done, active-wallet / network switch). Screens that show
    /// the masternode list observe it to reload the list itself — the
    /// aggregation changes on exactly those events.
    @Published private(set) var contextVersion: UInt64 = 0

    /// Per-node proposal activity folded from every successful tally
    /// (persisted per network) — what "hasn't proposed in 2 days" is judged
    /// from, since Platform only reports per-epoch totals.
    @Published private(set) var activity: EvonodeProposalActivity

    /// Don't re-scan more often than this on routine triggers after a
    /// successful fetch…
    static let refreshInterval: TimeInterval = 5 * 60
    /// …but retry sooner after a failure (Platform unreachable at launch).
    static let retryInterval: TimeInterval = 30

    private let provider: EvonodeEpochBlocksProviding
    private let ownedEvonodes: @MainActor () -> Set<Data>
    private let syncModel: SyncModelImpl
    private var cancellables = Set<AnyCancellable>()

    private var task: Task<Void, Never>?
    /// Identity of the latest requested scan; a superseded scan's outcome
    /// (success or failure) must not touch published state.
    private var generation: UInt64 = 0
    private var lastAttempt: Date?
    private var lastFetchFailed = false
    private var pendingForced = false

    init(
        provider: EvonodeEpochBlocksProviding = EvonodeEpochBlocksService(),
        ownedEvonodes: @escaping @MainActor () -> Set<Data> = EvonodeEpochBlocksMonitor.activeEvonodeProTxHashes,
        syncModel: SyncModelImpl = SyncModelImpl()
    ) {
        self.provider = provider
        self.ownedEvonodes = ownedEvonodes
        self.syncModel = syncModel
        self.activity = Self.activityStore().load()
        observeTriggers()
    }

    /// Activity is kept per network: the same wallet runs different
    /// masternodes on testnet and mainnet.
    private static func activityStore() -> EvonodeProposalActivityStore {
        // `networkName` keeps the existing "mainnet"/"testnet" store keys
        // and gives devnet its own instead of colliding with mainnet's.
        EvonodeProposalActivityStore(network: WalletEnvironment.network?.networkName ?? "mainnet")
    }

    /// The wallet's evonodes still on the network (not retired), by stored
    /// proTxHash — the Rust aggregation; local, no network.
    static func activeEvonodeProTxHashes() -> Set<Data> {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else { return [] }
        let stillListed: (PlatformMasternode) -> Bool = {
            $0.isEvonode && MasternodeStatus(rawValue: $0.status) != .retired
        }
        // Wallet evonodes plus the user's tracked ones — the epoch-blocks
        // range scan is privacy-preserving either way (it never names the
        // nodes), so tracked evonodes ride the same tally.
        return Set(manager.masternodes(for: walletId).filter(stillListed).map(\.proTxHash))
            .union(manager.trackedMasternodes().filter(stillListed).map(\.proTxHash))
    }

    // MARK: Triggers

    private func observeTriggers() {
        syncModel.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard state == .syncDone else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.contextVersion &+= 1
                    self.refresh(force: true)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reset() }
            }
            .store(in: &cancellables)
    }

    // MARK: Refresh

    /// Fetch (or re-fetch) the tallies. Routine calls honour the throttle;
    /// `force` bypasses it. While a scan is running, a forced request is
    /// queued behind it; a routine one is dropped (the running scan answers).
    func refresh(force: Bool = false) {
        if task != nil {
            if force { pendingForced = true }
            return
        }
        let minInterval = lastFetchFailed ? Self.retryInterval : Self.refreshInterval
        if !force, let last = lastAttempt, Date().timeIntervalSince(last) < minInterval {
            return
        }
        let owned = ownedEvonodes()
        guard !owned.isEmpty else {
            if blocks != nil {
                DWLogger.log("EvonodeEpochBlocksMonitor: no active evonodes in the wallet aggregation — clearing")
            }
            blocks = nil
            return
        }
        start(owned: owned, force: force)
    }

    /// Wallet / network switch: the current value and any running scan are
    /// for the old context. Drop the value now (hides the card), let the
    /// running scan stop paging, and queue a forced scan behind it.
    func reset() {
        generation &+= 1
        contextVersion &+= 1
        blocks = nil
        activity = Self.activityStore().load()
        lastAttempt = nil
        lastFetchFailed = false
        if let task {
            task.cancel()
            pendingForced = true
        } else {
            refresh(force: true)
        }
    }

    private func start(owned: Set<Data>, force: Bool) {
        lastAttempt = Date()
        generation &+= 1
        let generation = self.generation
        let provider = self.provider
        DWLogger.log("EvonodeEpochBlocksMonitor: fetching for \(owned.count) evonode(s), force=\(force)")
        task = Task { [weak self] in
            do {
                let blocks = try await provider.fetch(ownedProTxHashes: owned)
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.blocks = blocks
                self.lastFetchFailed = false
                var activity = self.activity
                activity.record(blocks)
                self.activity = activity
                Self.activityStore().save(activity)
                DWLogger.log("EvonodeEpochBlocksMonitor: \(blocks.totalBlocks) block(s) this epoch (epoch \(blocks.epochIndex.map(String.init) ?? "?"))")
            } catch {
                // A superseded / cancelled scan says nothing about the current
                // context — only a live one marks the retry state.
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.lastFetchFailed = true
                DWLogger.log("EvonodeEpochBlocksMonitor: fetch failed: \(error)")
            }
            self?.finish()
        }
    }

    /// The running scan ended (any outcome). Free the slot, then run the
    /// forced refresh that was queued behind it, if any.
    private func finish() {
        task = nil
        if pendingForced {
            pendingForced = false
            refresh(force: true)
        }
    }
}
