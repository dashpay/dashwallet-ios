//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import Foundation
import Combine
import SwiftData
import SwiftDashSDK

private let kBaseBalanceHeaderHeight: CGFloat = 100
private let kTimeskewTolerance: TimeInterval = 3600 // 1 hour
private let maxShortcutsCount = 4

/// One selectable category in the home screen's transaction filter. The
/// filter is multi-select (checkboxes): a transaction shows when it belongs
/// to ANY selected category, and a selection covering every offered category
/// means "All" — which also shows transactions that fit no category (internal
/// transfers, CoinJoin mixing groups).
enum TransactionFilterCategory: CaseIterable {
    case sent
    case received
    case rewards
    case masternode
    case giftCard
    case shieldedSent
    case shieldedReceived
}

class HomeViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "HomeViewModel", qos: .userInitiated)
    private var timeSkewDialogShown: Bool = false
    /// Session guard so the proactive CoinJoin-sweep popup shows at most once
    /// per launch (re-evaluated each launch while a leftover balance exists).
    private var coinJoinSweepDialogShown: Bool = false

    static let shared: HomeViewModel = {
        return HomeViewModel(transactionSource: SwiftDashSDKWalletSource())
    }()

    private let transactionSource: TransactionSource
    private var txByHash: [String: TransactionListDataItem] = [:]
    private var crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
    private var coinJoinTxSets: [String: CoinJoinMixingTxSet] = [:] // Grouped by date
    private var coinJoinWithdrawalSet = CoinJoinWithdrawalTxSet() // Single combined "CoinJoin Withdrawals" group (app's sweep tx)
    private var metadataProviders: [MetadataProvider] = []
    #if DEBUG
    var isPreviewMode: Bool = false
    #endif

    /// Tracks whether a full reload is currently in progress to prevent race conditions
    /// with incremental updates (Fix #3)
    private var isReloading: Bool = false

    /// Tracks whether initial data load has completed (Fix #2)
    private var hasCompletedInitialLoad: Bool = false

    /// Debounce timer for sync state changes to prevent excessive reloads (Fix #4)
    private var syncStateDebounceWorkItem: DispatchWorkItem?
    private let syncStateDebounceInterval: TimeInterval = 0.5

    /// Funnel for every "wallet content changed, reload the tx list" trigger.
    /// Throttled in `observeWallet()` so the save/balance notification storm
    /// during sync coalesces into at most one full reload per interval.
    private let txReloadRequests = PassthroughSubject<Void, Never>()

    /// Converts the SDK's current-value balance publisher into actual balance
    /// changes. The initial snapshot is already covered by the eager Home load,
    /// while `removeDuplicates()` prevents the coordinator's repeated 1 Hz
    /// snapshots from requesting redundant transaction-list reloads.
    static func distinctBalanceChanges<P: Publisher>(
        from publisher: P
    ) -> AnyPublisher<Void, Never> where P.Output == WalletBalance?, P.Failure == Never {
        publisher
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    @Published private(set) var txItems: [TransactionGroup] = []

    /// Whether the first full transaction load has finished, published on the
    /// main thread for the home feed.
    ///
    /// Distinct from the worker-queue `hasCompletedInitialLoad`, which guards
    /// reload/incremental-update sequencing off the main thread. This one
    /// exists so the view can tell "still loading" from "genuinely empty" —
    /// `txItems` is empty in both cases, and rendering the empty-state copy
    /// during the initial load tells the user they have no transactions
    /// before that is known.
    @Published private(set) var hasLoadedInitialTxItems: Bool = false
    @Published var shortcutItems: [ShortcutAction] = []
    @Published var showTimeSkewAlertDialog: Bool = false
    @Published var showCoinJoinSweepDialog: Bool = false
    /// Post-sync destination-choice sheet (`CoinJoinMoveFundsSheet`) —
    /// presented instead of `showCoinJoinSweepDialog` when the CoinJoin
    /// balance is large enough to offer the Shielded destination.
    @Published var showCoinJoinMoveFundsSheet: Bool = false
    @Published private(set) var timeSkew: TimeInterval = 0
    @Published private(set) var showJoinDashpay: Bool = false
    /// Selected filter categories (multi-select checkboxes). Defaults to every
    /// category — i.e. "All". Never empty: the dialog blocks unchecking the
    /// last box.
    @Published var selectedFilters: Set<TransactionFilterCategory> = Set(TransactionFilterCategory.allCases) {
        didSet {
            reloadTxDataSource()
        }
    }

    /// True when the wallet has ever received a masternode/mining reward
    /// (any coinbase tx in history). Gates the "Rewards" filter row; computed
    /// on each full reload.
    @Published private(set) var hasRewardsHistory: Bool = false

    /// True when the wallet has ever had a masternode special transaction
    /// (proRegTx / update / revocation). Gates the "Masternode" filter row;
    /// computed on each full reload.
    @Published private(set) var hasMasternodeHistory: Bool = false

    @Published private(set) var headerHeight: CGFloat = kBaseBalanceHeaderHeight // TDOO: move back to HomeView when fully transitioned to SwiftUI
    @Published private(set) var showReclassifyTransaction: Transaction? = nil
    @Published var shouldShowShortcutBanner: Bool = false
    @Published var giftCardTxId: Data? = nil
    
#if DASHPAY
    var joinDashPayState: JoinDashPayState = .callToAction
#endif
    
    private lazy var syncModel = SyncModelImpl()
    
    private var reclassifyTransactionsActivatedAt: Date {
        get { DWGlobalOptions.sharedInstance().dateReclassifyYourTransactionsFlowActivated ?? Date() }
    }
    
    private var shouldDisplayReclassifyTransaction: Bool {
        get { DWGlobalOptions.sharedInstance().shouldDisplayReclassifyYourTransactionsFlow }
        set(value) {
            DWGlobalOptions.sharedInstance().shouldDisplayReclassifyYourTransactionsFlow = value
            
            if (!value) {
                showReclassifyTransaction = nil
            }
        }
    }
    
    init(transactionSource: TransactionSource) {
        self.transactionSource = transactionSource
        syncModel.networkStatusDidChange = { status in
            self.recalculateHeight()
        }

        self.setupMetadataProviders()
        self.onSyncStateChanged()
        self.recalculateHeight()

        // First load right away — `onSyncStateChanged()` above only schedules
        // one behind its 0.5s debounce, which reads as a visibly empty list
        // at startup before the rows pop in. There's no notification storm to
        // coalesce yet, and the fetch runs on `queue`, so this is safe to
        // start immediately.
        self.reloadTxsAndShortcuts()

        self.observeCoinJoinSweep()
        self.observeWallet()
        self.observeNetworkChange()
        #if DASHPAY
        self.observeDashPay()
        #endif
    }

    #if DEBUG
    /// Lightweight init used only by SwiftUI previews.
    /// Skips wallet/sync/coinjoin wiring that depends on the Dash core runtime.
    private init(previewShortcuts: [ShortcutAction]) {
        self.transactionSource = HomeViewModelPreviewTransactionSource()
        self.isPreviewMode = true
        self.shortcutItems = previewShortcuts
    }

    static func makeForPreview(shortcuts: [ShortcutAction]) -> HomeViewModel {
        HomeViewModel(previewShortcuts: shortcuts)
    }
    #endif

    /// Observes network changes (testnet <-> mainnet) to clear cached transaction data
    private func observeNetworkChange() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearCachedData()
#if DASHPAY
                // The selected network changes before its SDK runtime is
                // ready. Keep the banner hidden during that transition; the
                // post-ready wallet-context notification re-evaluates it.
                self?.showJoinDashpay = false
#endif
            }
            .store(in: &cancellableBag)

        // A runtime wallet switch rebinds the host to a different wallet on the
        // SAME network. The cached tx items belong to the old wallet, so treat
        // it exactly like a network switch: drop the caches and reload the new
        // wallet's tx list (SwiftDashSDKWalletSource reads the host's now-active
        // wallet). The balance-driven reloads don't cover this — the balance
        // notifications the switch posts can carry the same total, and their
        // observers don't clear the stale per-hash cache.
        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearCachedData()
#if DASHPAY
                // The runtime posts this only after the destination
                // network's wallet + SwiftData container are bound. Defer
                // one main-queue turn so DWCurrentUserIdentityInfo's
                // notification observer invalidates its old-network snapshot
                // before the banner asks for the destination username.
                DispatchQueue.main.async { [weak self] in
                    self?.checkJoinDashPay()
                }
#endif
            }
            .store(in: &cancellableBag)
    }

    /// Clears all cached transaction data when switching networks
    private func clearCachedData() {
        DWLogger.log("HomeViewModel: Network changed, clearing cached transaction data")

        // Dispatch to self.queue to ensure thread-safe access to txByHash, crowdNodeTxSet, coinJoinTxSets
        // These properties are also accessed/modified in reloadTxDataSource() on self.queue
        self.queue.async { [weak self] in
            guard let self = self else { return }

            // Clear cached data structures on the same queue they're accessed
            self.txByHash.removeAll()
            self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            self.coinJoinTxSets.removeAll()

            // Reset load tracking flags so the new network's data loads correctly
            self.hasCompletedInitialLoad = false
            self.isReloading = false

            // Update UI-bound properties on main thread. The new network's
            // history is loading from scratch, so the feed goes back to its
            // loading state rather than claiming the wallet is empty.
            DispatchQueue.main.async {
                self.txItems = []
                self.hasLoadedInitialTxItems = false
            }

            // Reload fresh data from the new network's wallet
            // reloadTxsAndShortcuts() will dispatch back to queue internally
            DispatchQueue.main.async {
                self.reloadTxsAndShortcuts()
            }
        }
    }
    
    @MainActor
    func checkTimeSkew(force: Bool = false) {
        Task {
            let (isTimeSkewed, timeSkew) = await getDeviceTimeSkew(force: force)
            self.timeSkew = timeSkew
            
            if isTimeSkewed && (!timeSkewDialogShown || force) {
                timeSkewDialogShown = true
                showTimeSkewAlertDialog = true
            }
        }
    }
    
    private func observeWallet() {
        // All reload triggers below funnel into this one throttled pipeline.
        // During sync the persister saves a SwiftData batch several times per
        // second (with a balance notification usually alongside), and each
        // full reload is expensive — unthrottled, the storm kept the reload
        // queue permanently busy and the list janky. `throttle` (not
        // `debounce`) so a continuous save storm still repaints once per
        // interval instead of starving until it ends; `latest: true`
        // guarantees a trailing reload that picks up the final batch. A lone
        // event (e.g. a received tx while idle) passes through immediately.
        txReloadRequests
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.reloadTxsAndShortcuts()
            }
            .store(in: &cancellableBag)

        // Each trigger hops to the main queue before `send()` — the
        // notifications post from arbitrary threads (persister save thread,
        // balance updates) and PassthroughSubject requires serialized sends.
        // (DispatchQueue.main, not RunLoop.main: the latter is default-mode
        // only and stalls delivery during scroll tracking.)
        NotificationCenter.default.publisher(for: Notification.Name.fiatCurrencyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.txReloadRequests.send()
            }
            .store(in: &cancellableBag)

        // Reload when SwiftData saves — Rust's persister callback writes
        // PersistentTransaction rows on every Core SPV / BLAST batch, and
        // SwiftData posts NSManagedObjectContextDidSave under the hood. The
        // legacy SwiftDashSDKWalletState.$transactions bridge is dead (its
        // input callback was removed in the SDK refactor), so we read
        // directly from SwiftData via SwiftDashSDKWalletSource and use this
        // notification as the reload trigger.
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.txReloadRequests.send()
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: .swiftDashSDKTransactionProjectionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    ShieldedTxLookup.shared.refresh()
                    self?.txReloadRequests.send()
                }
            }
            .store(in: &cancellableBag)

        // The platform-address recorder inserts into the app's SQLite —
        // invisible to the SwiftData save trigger above — so it posts its
        // own signal when a received row lands.
        NotificationCenter.default.publisher(for: .platformAddressActivityRecorded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.txReloadRequests.send()
            }
            .store(in: &cancellableBag)

        // Balance changes can precede or arrive without a SwiftData save (for
        // example seed/clear transitions), so retain an independent trigger.
        // Equal snapshots are filtered and the initial current-value emission
        // is skipped because init already starts an eager full reload.
        Self.distinctBalanceChanges(from: SwiftDashSDKWalletState.shared.$balance)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.txReloadRequests.send()
            }
            .store(in: &cancellableBag)
        
        syncModel.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                if state == .syncing {
                    // Reload once per transition into .syncing — replaces the
                    // legacy sync-will-start notification observer.
                    DWLogger.log("HomeViewModel: Sync started, reloading transactions")
                    self.reloadTxsAndShortcuts()
                }
                self.onSyncStateChanged()
                self.maybeShowCoinJoinSweepDialog()
            }
            .store(in: &cancellableBag)
    }
    
    // This is expensive and should not be called often
    private func reloadTxDataSource() {
        // Read main-actor state BEFORE handing off, never from inside the
        // worker pass. A `DispatchQueue.main.sync` from the queue is a barrier
        // whose cost is main-thread *availability*, not work: at launch the
        // main thread is busy with tab-bar layout, avatar state and CrowdNode
        // restore, so a reload that hops mid-pass inherits all of it. Hopping
        // once up front, asynchronously, keeps the pass free-running.
        let dispatch = { @MainActor [weak self] in
            guard let self else { return }
            // Pair each request with the filter selection that was live when
            // it was made. Reading it inside the pass instead would let a pass
            // triggered by one change render a selection the user made after
            // it started.
            let selectedFilters = self.selectedFilters
            let startedAt = Date()
            self.queue.async { [weak self] in
                self?.performReload(selectedFilters: selectedFilters, startedAt: startedAt)
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { dispatch() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { dispatch() } }
        }
    }

    private func performReload(selectedFilters: Set<TransactionFilterCategory>, startedAt: Date) {
        // Fix #3: Set reload flag to prevent race conditions with incremental updates
        self.isReloading = true
        DWLogger.log("HomeViewModel: Starting full transaction reload")

        let transactions = transactionSource.allTransactions
        // Reconcile restored Shielded → Core destinations before Core rows
        // are filtered/classified. The activity projection can recover a
        // destination tag that was absent from the local withdrawal store.
        let shieldedItems = SwiftDashSDKWalletSource.fetchShieldedActivity(
            coreTransactions: transactions)
        self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
        self.coinJoinTxSets = [:]
        self.coinJoinWithdrawalSet = CoinJoinWithdrawalTxSet()

        // Gate the "Rewards" / "Masternode" filter rows; computed from the
        // unfiltered history so they don't flap with the current selection.
        let hasRewards = transactions.contains { $0.isCoinbaseTransaction }
        let hasMasternodes = transactions.contains { $0.isMasternodeTransaction }

        // Snapshot each provider's metadata once per reload —
        // `availableMetadata` copies the whole dictionary through the
        // provider's serial queue, so reading it per-transaction costs
        // O(n) queue hops + dictionary copies per reload.
        let metadataSnapshots = self.metadataProviders.map { $0.availableMetadata }
        let giftCardTxIds = Set(GiftCardMetadataProvider.shared.availableMetadata.keys)

        var items: [TransactionListDataItem] = transactions.compactMap { wrappedTx -> TransactionListDataItem? in
            Tx.shared.updateRateIfNeeded(for: wrappedTx)

            if !self.passesFilter(transaction: wrappedTx, selected: selectedFilters, hasRewards: hasRewards, hasMasternodes: hasMasternodes, giftCardTxIds: giftCardTxIds) {
                return nil
            }

            // TODO(crowdnode-home-grouping): the "CrowdNode · Account" group
            // needs decode-based ObservedTransaction matching (the SDK
            // snapshot here doesn't carry transactionData); ports separately.
            // Until then CrowdNode txs render as individual rows — the
            // current behavior (the old DS-backed grouping branch was dead
            // long before the .ds source case was deleted).
            if wrappedTx.isCoinJoinMixing {
                // CoinJoin mixing tx — group it into the per-day
                // "Mixing Transactions" set.
                let date = DWDateFormatter.sharedInstance.dateOnly(from: wrappedTx.date)
                let coinJoinTxSet = self.coinJoinTxSets[date] ?? CoinJoinMixingTxSet()
                self.coinJoinTxSets[date] = coinJoinTxSet

                if coinJoinTxSet.tryInclude(wrappedTx) {
                    return nil
                }
            } else if wrappedTx.isCoinJoinWithdrawal {
                // App-tagged CoinJoin offload (sweep) tx → the single
                // combined "CoinJoin Withdrawals" group.
                if self.coinJoinWithdrawalSet.tryInclude(wrappedTx) {
                    return nil
                }
            }

            return .tx(wrappedTx, self.resolveMetadata(for: wrappedTx.txHashData, in: metadataSnapshots))
        }

        // Interleave the shielded operations (private receives/sends,
        // Platform↔Shielded moves, shielded identity fundings) — the
        // Core rows above only cover operations with an L1 leg. The
        // day-grouping sort below merges the two timelines.
        for shielded in shieldedItems {
            guard self.passesShieldedFilter(
                item: shielded,
                selected: selectedFilters,
                hasRewards: hasRewards,
                hasMasternodes: hasMasternodes)
            else { continue }
            items.append(.shieldedActivity(shielded))
        }

        // Observed incoming Platform-address payments (app-recorded —
        // the SDK persists no per-payment platform history; see
        // PlatformAddressActivityStore.swift). Received-only by
        // construction, so they ride the .received filter category.
        let platformItems = SwiftDashSDKWalletSource.fetchPlatformActivity()
        for platform in platformItems {
            guard self.passesCategoryFilter(
                categories: [.received],
                selected: selectedFilters,
                hasRewards: hasRewards,
                hasMasternodes: hasMasternodes)
            else { continue }
            items.append(.platformActivity(platform))
        }

        self.txByHash.removeAll()
        items.forEach { item in
            self.txByHash[item.id] = item
        }

        if !crowdNodeTxSet.transactionMap.isEmpty {
            let item: TransactionListDataItem = .crowdnode(crowdNodeTxSet)
            items.append(item)
            self.txByHash[FullCrowdNodeSignUpTxSet.id] = item
        }

        for (_, coinJoinTxSet) in self.coinJoinTxSets {
            if !coinJoinTxSet.transactionMap.isEmpty {
                let item: TransactionListDataItem = .coinjoin(coinJoinTxSet)
                items.append(item)
                self.txByHash[coinJoinTxSet.id] = item
            }
        }

        if !self.coinJoinWithdrawalSet.transactionMap.isEmpty {
            let item: TransactionListDataItem = .coinjoinWithdrawal(self.coinJoinWithdrawalSet)
            items.append(item)
            self.txByHash[self.coinJoinWithdrawalSet.id] = item
        }

        let groupedItems = Dictionary(
            grouping: items.sorted(by: { $0.date > $1.date }),
            by: { DWDateFormatter.sharedInstance.dateOnly(from: $0.date) }
        )

        let array = groupedItems.map { key, items in
            TransactionGroup(id: key, date: items.first!.date, items: items)
        }.sorted { $0.date > $1.date }

        // Fix #2 & #3: Mark initial load complete and clear reload flag
        self.hasCompletedInitialLoad = true
        self.isReloading = false

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        DWLogger.log("HomeViewModel: Full reload complete in \(elapsedMs)ms, \(array.count) groups, \(self.txByHash.count) transactions cached")

        DispatchQueue.main.async {
            self.txItems = array
            self.hasLoadedInitialTxItems = true
            if self.hasRewardsHistory != hasRewards {
                self.hasRewardsHistory = hasRewards
            }
            if self.hasMasternodeHistory != hasMasternodes {
                self.hasMasternodeHistory = hasMasternodes
            }
        }
    }
    
    private func onTransactionStatusChanged(tx: Transaction) {
        self.queue.async { [weak self] in
            guard let self = self else { return }

            // Fix #3: Skip incremental updates while a full reload is in progress
            // to prevent race conditions that could cause missing transactions
            if self.isReloading {
                DWLogger.log("HomeViewModel: Skipping incremental update during full reload for tx: \(tx.txHashHexString)")
                return
            }

            // Fix #2: If initial load hasn't completed yet, the cache is empty and
            // incremental updates won't work correctly. Trigger a full reload instead.
            if !self.hasCompletedInitialLoad {
                DWLogger.log("HomeViewModel: Initial load not complete, triggering full reload for tx: \(tx.txHashHexString)")
                DispatchQueue.main.async {
                    self.reloadTxsAndShortcuts()
                }
                return
            }

            let selectedFilters = DispatchQueue.main.sync { self.selectedFilters }
            let historyFlags = DispatchQueue.main.sync { (self.hasRewardsHistory, self.hasMasternodeHistory) }

            // A coinbase / masternode tx arriving incrementally unlocks its
            // filter row without waiting for the next full reload.
            if tx.isCoinbaseTransaction && !historyFlags.0 {
                DispatchQueue.main.async {
                    self.hasRewardsHistory = true
                }
            }
            if tx.isMasternodeTransaction && !historyFlags.1 {
                DispatchQueue.main.async {
                    self.hasMasternodeHistory = true
                }
            }

            if !self.passesFilter(transaction: tx, selected: selectedFilters, hasRewards: historyFlags.0, hasMasternodes: historyFlags.1) {
                return
            }

            Tx.shared.updateRateIfNeeded(for: tx)
            let txHashHex = tx.txHashHexString
            let itemId = txHashHex
            let txItem: TransactionListDataItem = .tx(tx, resolveMetadata(for: tx.txHashData))
            let newDateKey = DWDateFormatter.sharedInstance.dateOnly(from: tx.date)

            // TODO(crowdnode-home-grouping): the CrowdNode absorb-into-group
            // branch that lived here was dead (it was fed by DashSync's
            // DSTransactionManagerTransactionStatusDidChange, which no longer
            // fires post-M6) and was removed with the CrowdNode tracking port.
            // Today this path is fed by the metadata-provider refresh below
            // (gift-card / custom-icon updates re-rendering an existing row).

            if let existingItem = self.txByHash[itemId] {
                // Updating existing item
                self.txByHash[itemId] = txItem

                // Fix: Find the OLD date group where this transaction currently lives
                // Transaction dates can change when going from unconfirmed to confirmed
                var oldGroupIndex: Int? = nil
                var oldItemIndex: Int? = nil
                var oldDateKey: String? = nil

                let currentGroups = DispatchQueue.main.sync { self.txItems }
                for (gIdx, group) in currentGroups.enumerated() {
                    if let iIdx = group.items.firstIndex(where: { $0.id == itemId }) {
                        oldGroupIndex = gIdx
                        oldItemIndex = iIdx
                        oldDateKey = group.id
                        break
                    }
                }

                var isChanged = true
                if case let .tx(existingTx, oldMetadata) = existingItem, case let .tx(newTx, metadata) = txItem {
                    isChanged = newTx.state != existingTx.state || oldMetadata != metadata
                }

                // Fix: Handle transaction moving between date groups (e.g., unconfirmed -> confirmed)
                if let oldDateKey = oldDateKey, oldDateKey != newDateKey {
                    DWLogger.log("HomeViewModel: Transaction \(itemId) date changed from \(oldDateKey) to \(newDateKey)")

                    // Remove from old group
                    if let oldGIdx = oldGroupIndex, let oldIIdx = oldItemIndex {
                        DispatchQueue.main.async {
                            // Validate both group index and item index bounds before removal
                            // txItems may have changed between when indices were captured and now
                            guard oldGIdx >= 0,
                                  oldGIdx < self.txItems.count,
                                  oldIIdx >= 0,
                                  oldIIdx < self.txItems[oldGIdx].items.count else {
                                DWLogger.log("HomeViewModel: Skipping removal - indices out of bounds (groupIdx: \(oldGIdx), itemIdx: \(oldIIdx))")
                                return
                            }

                            self.txItems[oldGIdx].items.remove(at: oldIIdx)

                            // Remove empty groups (re-check bounds after item removal)
                            if oldGIdx < self.txItems.count && self.txItems[oldGIdx].items.isEmpty {
                                self.txItems.remove(at: oldGIdx)
                            }

                            // Add to new group (similar to new item logic)
                            if let newGroupIndex = self.txItems.firstIndex(where: { $0.id == newDateKey }) {
                                self.txItems[newGroupIndex].items.append(txItem)
                                self.txItems[newGroupIndex].items.sort { $0.date > $1.date }
                            } else {
                                let newGroup = TransactionGroup(id: newDateKey, date: txItem.date, items: [txItem])
                                let insertIndex = self.txItems.firstIndex(where: { $0.date < txItem.date })
                                if let index = insertIndex {
                                    self.txItems.insert(newGroup, at: index)
                                } else {
                                    self.txItems.append(newGroup)
                                }
                            }
                        }
                    }
                } else if isChanged {
                    // Same date group, just update in place
                    if let groupIndex = oldGroupIndex, let itemIndex = oldItemIndex {
                        DispatchQueue.main.async {
                            guard groupIndex < self.txItems.count,
                                  itemIndex < self.txItems[groupIndex].items.count else { return }
                            var updatedGroup = self.txItems[groupIndex]
                            var updatedItems = updatedGroup.items
                            updatedItems[itemIndex] = txItem
                            updatedGroup.items = updatedItems
                            self.txItems[groupIndex] = updatedGroup
                        }
                    }
                }
            } else {
                // New item
                self.txByHash[itemId] = txItem
                let shouldShowReclassify = self.shouldDisplayReclassifyTransaction && tx.date > reclassifyTransactionsActivatedAt

                // Re-check the current data source inside the main-queue hop;
                // a full reload may replace all groups between these queues.
                DispatchQueue.main.async {
                    if let currentGroupIndex = self.txItems.firstIndex(where: { $0.id == newDateKey }) {
                        self.txItems[currentGroupIndex].items.append(txItem)
                        self.txItems[currentGroupIndex].items.sort { $0.date > $1.date }
                    } else {
                        let newGroup = TransactionGroup(id: newDateKey, date: txItem.date, items: [txItem])
                        let insertIndex = self.txItems.firstIndex(where: { $0.date < txItem.date })
                        if let index = insertIndex {
                            self.txItems.insert(newGroup, at: index)
                        } else {
                            self.txItems.append(newGroup)
                        }
                    }
                    self.showReclassifyTransaction = shouldShowReclassify ? tx : nil
                }
            }
        }
    }
    
    func reclassifyTransactionShown(isShown: Bool) {
        if isShown {
            shouldDisplayReclassifyTransaction = false
        }
    }
    
    
    private func recalculateHeight() {
        var height = kBaseBalanceHeaderHeight
        let hasNetwork = syncModel.networkStatus == .online

        if !hasNetwork {
            height += 85
        }

        if shouldShowShortcutBanner {
            // Banner height + the gap between the bar and the banner (added via setCustomSpacing
            // in HomeHeaderView). Without the gap term the fixed header height is too short and
            // the .fill stack shrinks the bar, shifting its card upward.
            height += 70 + HomeHeaderView.shortcutBarBannerSpacing
        }

        self.headerHeight = height
    }
    
    private func getDeviceTimeSkew(force: Bool) async -> (Bool, TimeInterval) {
        do {
            let timeSkew = try await TimeUtils.getTimeSkew(force: force)
            let maxAllowedTimeSkew = kTimeskewTolerance
            return (abs(timeSkew) > maxAllowedTimeSkew, timeSkew)
        } catch {
            // Ignore errors
            return (false, 0)
        }
    }
}

extension HomeViewModel {
    private func onSyncStateChanged() {
        // Fix #4: Debounce sync state changes to prevent excessive reloads.
        // During active sync, state can change rapidly which would cause
        // multiple expensive full reloads in quick succession.
        syncStateDebounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            DWLogger.log("HomeViewModel: Sync state changed (debounced), requesting reload")
            // Through the shared funnel, not straight to the reload: this
            // debounce only coalesces sync-state changes among themselves, so
            // calling directly raced the throttled save/balance triggers and
            // each fired its own full pass.
            self.txReloadRequests.send()
            #if DASHPAY
            self.checkJoinDashPay()
            #endif
        }

        syncStateDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + syncStateDebounceInterval, execute: workItem)
    }
    
    func reloadTxsAndShortcuts() {
        self.reloadTxDataSource()
        self.reloadShortcuts()
    }
}

// MARK: - CoinJoin Recovery Sweep (post-migration)

extension HomeViewModel {
    /// Live CoinJoin-account leftover balance (duffs) — SDK source of truth,
    /// the same value the Settings "Move CoinJoin Funds" row binds to.
    var coinJoinSweepAmountDuffs: UInt64 {
        SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
    }

    /// Formatted leftover amount for the popup message.
    var coinJoinSweepAmountFormatted: String {
        String(format: "%.6f DASH", Double(coinJoinSweepAmountDuffs) / Double(kOneDash))
    }

    private func observeCoinJoinSweep() {
        // The leftover balance lands after the (wide) recovery scan completes,
        // sometimes just after `.syncDone`; observe it so the popup still
        // surfaces if the balance arrives a beat later than the state change.
        SwiftDashSDKWalletState.shared.$coinJoinBalanceDuffs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.maybeShowCoinJoinSweepDialog()
            }
            .store(in: &cancellableBag)
    }

    /// Whether the post-sync popup can offer the Shielded-balance destination:
    /// the wallet's shielded sub-wallet is bound (an Orchard address resolves)
    /// AND the CoinJoin balance is comfortably above the drain's fee overhead
    /// — the Type 18 pool fee (carved from the locked value) plus an L1-fee
    /// allowance for the many-input drain transaction — so at least half the
    /// moved amount survives the fees. Fails closed (BIP44-only popup) when
    /// the fee estimate or the shielded binding is unavailable.
    var coinJoinShieldDestinationAvailable: Bool {
        let balanceDuffs = coinJoinSweepAmountDuffs
        // Host + manager are `@MainActor`-isolated — reuse the wallet source's
        // main-thread trampoline (same file).
        return SwiftDashSDKWalletSource.onMain {
            guard let manager = SwiftDashSDKHost.shared.manager,
                  let wallet = SwiftDashSDKHost.shared.wallet,
                  ((try? manager.shieldedDefaultAddress(walletId: wallet.walletId)) ?? nil) != nil,
                  let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits
            else { return false }
            // The shared Type 18 pool-fee estimate (credits → duffs is ÷ 1000);
            // `sendFeeReserveDuffs` (0.001 DASH) allows for the L1 fee of a
            // drain spending hundreds of mixed-coin inputs.
            let overheadDuffs = poolFeeCredits / 1000 + WalletBalance.sendFeeReserveDuffs
            return balanceDuffs >= overheadDuffs * 2
        }
    }

    /// Proactively surface the "move your mixed coins" popup once per session
    /// after sync completes, while a recoverable CoinJoin balance exists.
    /// Bound to the live balance (not a persistent flag): it re-prompts each
    /// launch until the user sweeps, then self-stops (balance → 0). The durable
    /// Settings row covers the same action for users who dismiss it.
    ///
    /// When the balance is large enough to shield, the destination-choice
    /// sheet (`CoinJoinMoveFundsSheet`) is shown instead of the BIP44-only
    /// dialog.
    func maybeShowCoinJoinSweepDialog() {
        DWLogger.log("HomeViewModel: sweep dialog check — \(coinJoinSweepAmountDuffs) duffs (\(String(format: "%.6f", Double(coinJoinSweepAmountDuffs) / Double(kOneDash))) DASH), threshold \(CoinJoinRecovery.recoveryDustThresholdDuffs), above=\(coinJoinSweepAmountDuffs > CoinJoinRecovery.recoveryDustThresholdDuffs), syncDone=\(syncModel.state == .syncDone), alreadyShown=\(coinJoinSweepDialogShown)")
        guard !coinJoinSweepDialogShown,
              syncModel.state == .syncDone,
              coinJoinSweepAmountDuffs > CoinJoinRecovery.recoveryDustThresholdDuffs else { return }
        coinJoinSweepDialogShown = true
        if coinJoinShieldDestinationAvailable {
            showCoinJoinMoveFundsSheet = true
        } else {
            showCoinJoinSweepDialog = true
        }
    }

    /// Sweep the leftover CoinJoin balance into the user's spendable balance
    /// via the shared `WalletSendService` flow (PIN → own BIP44 dest → sweep →
    /// balance refresh + recovery-flag clear). Auth-cancel is an expected no-op;
    /// the Settings row remains for retry on other failures.
    func performCoinJoinSweep() async -> String? {
        do {
            _ = try await WalletSendService.shared.sweepCoinJoin()
            return nil
        } catch {
            DWLogger.log("HomeViewModel: sweep (home popup) failed: \(error)")
            // nil when the user cancelled auth; a message on real failures.
            return WalletSendService.coinJoinSweepUserMessage(for: error)
        }
    }
}

// MARK: - Metadata

extension HomeViewModel {
    private func setupMetadataProviders() {
        let giftCardMetadata = GiftCardMetadataProvider.shared
        let customIconMetadata = CustomIconMetadataProvider.shared
        let coinbaseMetadata = CoinbaseMetadataProvider.shared
        let swapOrderMetadata = SwapOrderMetadataProvider.shared
        self.metadataProviders = [giftCardMetadata, coinbaseMetadata, customIconMetadata, swapOrderMetadata]
        
        for provider in self.metadataProviders {
            provider.metadataUpdated
                .receive(on: self.queue)
                .sink { [weak self] txHash in
                    guard let self = self else { return }

                    // Providers emit the wire-order txid (`Transaction.txHashData`),
                    // which is the SDK row key. A miss (persister race) is a no-op —
                    // the NSManagedObjectContextDidSave full reload covers it.
                    if let transaction = SwiftDashSDKWalletSource.fetch(txid: txHash) {
                        self.onTransactionStatusChanged(tx: transaction)
                    }
                }
                .store(in: &cancellableBag)
        }
    }
    
    private func resolveMetadata(for txId: Data) -> TxRowMetadata? {
        resolveMetadata(for: txId, in: metadataProviders.map { $0.availableMetadata })
    }

    /// `snapshots` holds one pre-copied `availableMetadata` per provider, in
    /// provider (priority) order — full-reload loops snapshot once and reuse
    /// across all transactions instead of re-copying per row.
    private func resolveMetadata(for txId: Data, in snapshots: [[Data: TxRowMetadata]]) -> TxRowMetadata? {
        var finalMetadata: TxRowMetadata? = nil

        // Metadata will not be replaced if already found, so in case
        // of conflicts metadataProviders should be sorted by priority
        for providerMetadata in snapshots {
            guard let metadata = providerMetadata[txId] else { continue }
            
            if finalMetadata == nil {
                finalMetadata = metadata
            } else {
                if finalMetadata?.title == nil {
                    finalMetadata?.title = metadata.title
                }

                if finalMetadata?.details == nil {
                    finalMetadata?.details = metadata.details
                }
                
                if finalMetadata?.icon == nil {
                    finalMetadata?.icon = metadata.icon
                }
                
                if finalMetadata?.iconId == nil {
                    finalMetadata?.iconId = metadata.iconId
                }
                
                if finalMetadata?.secondaryIcon == nil {
                    finalMetadata?.secondaryIcon = metadata.secondaryIcon
                }
            }
        }

        return finalMetadata
    }
    
    /// Union semantics: show the tx when it belongs to any selected category.
    /// A selection covering every OFFERED category (rewards / masternode are
    /// offered only when their history flags are set) is "All" and also admits
    /// txs that fit no category (internal transfers, CoinJoin mixing groups).
    ///
    /// `giftCardTxIds` is an optional pre-snapshotted key set for the
    /// `.giftCard` category — full-reload loops pass it to avoid copying the
    /// provider's dictionary per transaction; single-tx callers omit it.
    private func passesFilter(transaction: Transaction, selected: Set<TransactionFilterCategory>, hasRewards: Bool, hasMasternodes: Bool, giftCardTxIds: Set<Data>? = nil) -> Bool {
        var offered = Set(TransactionFilterCategory.allCases)
        if !hasRewards {
            offered.remove(.rewards)
        }
        if !hasMasternodes {
            offered.remove(.masternode)
        }
        if selected.isSuperset(of: offered) {
            return true
        }
        return !selected.isDisjoint(with: categories(of: transaction, giftCardTxIds: giftCardTxIds))
    }

    /// Filter check for a pure-shielded history item — the counterpart of
    /// `passesFilter(transaction:...)` with the same "everything offered
    /// selected → show all" fast path. Direction maps to the dedicated
    /// shielded categories only (never plain sent/received: those mean
    /// on-chain transparent movements).
    private func passesShieldedFilter(
        item: ShieldedActivityItem,
        selected: Set<TransactionFilterCategory>,
        hasRewards: Bool,
        hasMasternodes: Bool
    ) -> Bool {
        var categories: Set<TransactionFilterCategory> = []
        switch item.direction {
        case .incoming:
            categories.insert(.shieldedReceived)
        case .outgoing:
            categories.insert(.shieldedSent)
        case .selfTransfer:
            categories.formUnion([.shieldedSent, .shieldedReceived])
        }
        return passesCategoryFilter(
            categories: categories,
            selected: selected,
            hasRewards: hasRewards,
            hasMasternodes: hasMasternodes)
    }

    /// Shared filter check for non-Core history items with precomputed
    /// categories — same "everything offered selected → show all" fast
    /// path as `passesFilter(transaction:...)`.
    private func passesCategoryFilter(
        categories: Set<TransactionFilterCategory>,
        selected: Set<TransactionFilterCategory>,
        hasRewards: Bool,
        hasMasternodes: Bool
    ) -> Bool {
        var offered = Set(TransactionFilterCategory.allCases)
        if !hasRewards {
            offered.remove(.rewards)
        }
        if !hasMasternodes {
            offered.remove(.masternode)
        }
        if selected.isSuperset(of: offered) {
            return true
        }
        return !selected.isDisjoint(with: categories)
    }

    /// Categories a transaction belongs to. Overlaps are allowed (a gift-card
    /// purchase is also a sent tx); rewards and shielded receipts are carved
    /// out of received, mirroring how the old single-select filter separated
    /// rewards from receives.
    private func categories(of transaction: Transaction, giftCardTxIds: Set<Data>? = nil) -> Set<TransactionFilterCategory> {
        if transaction.isCoinbaseTransaction {
            return [.rewards]
        }
        if transaction.isMasternodeTransaction {
            return [.masternode]
        }
        var categories: Set<TransactionFilterCategory> = []
        if transaction.isShieldedTransfer {
            categories.insert(.shieldedSent)
        }
        let isShieldedReceipt = transaction.isShieldedWithdrawalReceipt
        if isShieldedReceipt {
            categories.insert(.shieldedReceived)
        }
        let ids = giftCardTxIds ?? Set(GiftCardMetadataProvider.shared.availableMetadata.keys)
        if ids.contains(transaction.txHashData) {
            categories.insert(.giftCard)
        }
        switch transaction.direction {
        case .sent:
            categories.insert(.sent)
        case .received:
            if !isShieldedReceipt {
                categories.insert(.received)
            }
        case .moved, .notAccountFunds:
            break
        }
        return categories
    }
}

// MARK: - Shortcuts

extension HomeViewModel {
    @MainActor
    func checkShortcutBanner() {
        let options = DWGlobalOptions.sharedInstance()
        let newValue = (options.shortcutBannerState == 2 && options.shortcuts == nil)
        if newValue != shouldShowShortcutBanner {
            shouldShowShortcutBanner = newValue
            recalculateHeight()
        }
    }

    @MainActor
    func dismissShortcutBanner() {
        DWGlobalOptions.sharedInstance().shortcutBannerState = 3
        shouldShowShortcutBanner = false
        recalculateHeight()
    }

    func reloadShortcuts() {
        #if DEBUG
        guard !isPreviewMode else { return }
        #endif
        let options = DWGlobalOptions.sharedInstance()
        let isTestnet = WalletEnvironment.isTestnet

        // Check for custom configuration first. Mapped on main: the Switch
        // Wallet availability gate reads main-actor wallet state, and this
        // reload can run off-main (the published write lands on main anyway).
        if let customShortcuts = options.shortcuts,
           customShortcuts.count == maxShortcutsCount {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let canSwitchWallet = MainActor.assumeIsolated { WalletsViewModel.switchableWalletCount > 1 }
                let items = customShortcuts.compactMap { number -> ShortcutAction? in
                    guard var type = ShortcutActionType(rawValue: number.intValue) else { return nil }
                    // A faucet shortcut saved on testnet degrades to Spend
                    // after a switch to mainnet (no mainnet faucet exists);
                    // the saved config is untouched, so it comes back when
                    // the user returns to testnet.
                    if type == .getTestDash && !isTestnet {
                        type = .spend
                    }
                    // A Switch Wallet shortcut degrades to Receive while the
                    // device is back to a single wallet; the saved config is
                    // untouched, so it returns when another wallet is added.
                    if type == .switchWallet && !canSwitchWallet {
                        type = .receive
                    }
                    // Dash DEX is offered only on mainnet with SwapKit configured (mirrors
                    // ShortcutActionType.customizableActions and ServiceDataProvider.shouldShow);
                    // a saved DEX shortcut degrades to Spend whenever that gate isn't met. The
                    // saved config is untouched, so it returns once the gate passes again.
                    let dashDEXAvailable = !isTestnet && SwapKitConstants.isConfigured
                    if type == .dashDEX && !dashDEXAvailable {
                        type = .spend
                    }
                    return ShortcutAction(type: type)
                }
                .filter { action in
                    // A saved CrowdNode shortcut stays hidden until the user
                    // has actually signed up.
                    if action.type == .crowdNode {
                        let state = CrowdNode.shared.signUpState
                        return state == .finished || state == .linkedOnline
                    }
                    return true
                }
                if items.count == maxShortcutsCount {
                    self.shortcutItems = items
                } else {
                    self.applyDefaultShortcuts(options: options, isTestnet: isTestnet)
                }
            }
            return
        }

        applyDefaultShortcuts(options: options, isTestnet: isTestnet)
    }

    /// The default state-based bar (no custom configuration, or the saved one
    /// no longer maps to a full set of actions).
    private func applyDefaultShortcuts(options: DWGlobalOptions, isTestnet: Bool) {
        let walletNeedsBackup = options.walletNeedsBackup
        let userHasBalance = options.userHasBalance
        // On testnet the last default slot offers the faucet instead of
        // Spend — test Dash is what a testnet wallet actually needs.
        let lastSlot: ShortcutActionType = isTestnet ? .getTestDash : .spend

        var mutableItems = [ShortcutAction]()
        mutableItems.reserveCapacity(maxShortcutsCount)

        // State 1: Zero balance and not verified passphrase
        if !userHasBalance && walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .buySellDash))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }
        // State 2: Zero balance and verified passphrase
        else if !userHasBalance && !walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: .buySellDash))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }
        // State 3: Has balance and verified passphrase
        else if userHasBalance && !walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: .scanToPay))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }
        // State 4: Has balance and not verified passphrase
        else if userHasBalance && walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }

        DispatchQueue.main.async {
            self.shortcutItems = mutableItems
        }
    }

    /// Re-check banner visibility after shortcuts change (e.g., user customized via long press)
    @MainActor
    func recheckBannerAfterCustomization() {
        if shouldShowShortcutBanner {
            checkShortcutBanner()
        }
    }
}

protocol TransactionSource {
    var allTransactions: Array<Transaction> { get }
}

struct CoreWithdrawalReceiptCandidate: Equatable {
    let amountDuffs: UInt64
    let date: Date
}

struct CoreWithdrawalReceiptMatchPolicy {
    /// A withdrawal destination is the wallet's next unused Core receive
    /// address, so one transaction paying it is authoritative even when the
    /// restored shielded activity timestamp or reconstructed amount differs.
    /// Address reuse is handled conservatively: require one unambiguous
    /// amount/time candidate rather than consuming an unrelated receipt.
    static func selectedIndex(
        expectedAmountDuffs: UInt64,
        activityDate: Date,
        candidates: [CoreWithdrawalReceiptCandidate]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return 0 }

        let inWindow = candidates.indices.filter {
            isWithinMatchWindow(candidates[$0].date, around: activityDate)
        }
        if expectedAmountDuffs > 0 {
            let exactInWindow = inWindow.filter {
                candidates[$0].amountDuffs == expectedAmountDuffs
            }
            if exactInWindow.count == 1 { return exactInWindow[0] }

            let exact = candidates.indices.filter {
                candidates[$0].amountDuffs == expectedAmountDuffs
            }
            if exact.count == 1 { return exact[0] }
        }
        return inWindow.count == 1 ? inWindow[0] : nil
    }

    private static func isWithinMatchWindow(_ date: Date, around anchor: Date) -> Bool {
        let delta = date.timeIntervalSince(anchor)
        return delta >= -3600 && delta <= 86_400
    }
}

/// Pure SwiftDashSDK source for the home screen tx list. Queries the
/// `PersistentTransaction` rows persisted by Rust's SwiftData callbacks
/// (Core SPV block apply + BLAST events) directly from
/// `SwiftDashSDKHost.shared.modelContainer`. DashSync is not in the loop.
///
/// Mirrors the SwiftExampleApp's `TransactionListView` pattern, adapted
/// for the existing UIKit + Combine home view: instead of `@Query`, we do
/// a synchronous fetch and feed the existing `Transaction` wrapper.
///
/// Threading: only the `@MainActor` host's handles (`modelContainer` +
/// active `walletId`) are read through a brief main-thread hop. The fetch
/// and the per-tx wrapping run on the CALLER's thread against a private
/// `ModelContext`, so a full home-list reload never blocks the main
/// thread mid-scroll. A private context reads the last SAVED state —
/// which is exactly what the `NSManagedObjectContextDidSave` reload
/// trigger guarantees is current.
struct SwiftDashSDKWalletTransactionSnapshot {
    let walletId: Data
    let transactions: [Transaction]
}

/// Objective-C-facing, value-only projection used by the phone-side Watch
/// bridge. The archived `BRAppleWatchTransactionData` wire model stays
/// unchanged; only its source moves from frozen DashSync transactions to the
/// active SwiftDashSDK wallet snapshot.
@objcMembers
final class DWAppleWatchTransactionSnapshot: NSObject {
    let amountText: String
    let amountTextInLocalCurrency: String
    let dateText: String
    let typeRawValue: Int

    init(amountText: String,
         amountTextInLocalCurrency: String,
         dateText: String,
         typeRawValue: Int) {
        self.amountText = amountText
        self.amountTextInLocalCurrency = amountTextInLocalCurrency
        self.dateText = dateText
        self.typeRawValue = typeRawValue
    }
}

@objc
final class DWAppleWatchSnapshotProvider: NSObject {
    private enum WatchTransactionType: Int {
        case sent
        case received
        case moved
        case invalid
    }

    @objc
    static func hasWallet() -> Bool {
        SwiftDashSDKWalletSource.fetchCurrentWalletSnapshot() != nil
    }

    /// The legacy bridge sent at most the account's 100 newest Core
    /// transactions. Keep that limit and ordering so existing watches receive
    /// the same archive shape and list semantics.
    @objc
    static func recentTransactions() -> [DWAppleWatchTransactionSnapshot] {
        guard let snapshot = SwiftDashSDKWalletSource.fetchCurrentWalletSnapshot() else {
            return []
        }

        return snapshot.transactions
            .sorted { $0.date > $1.date }
            .prefix(100)
            .map(makeSnapshot)
    }

    private static func makeSnapshot(_ transaction: Transaction) -> DWAppleWatchTransactionSnapshot {
        let type: WatchTransactionType
        switch transaction.state {
        case .invalid:
            type = .invalid
        default:
            switch transaction.direction {
            case .sent:
                type = .sent
            case .received, .notAccountFunds:
                type = .received
            case .moved:
                type = .moved
            }
        }

        let signedAmount = transaction.appleWatchSignedAmount
        let localAmount = CurrencyExchanger.shared.fiatAmountString(for: signedAmount.dashAmount)

        return DWAppleWatchTransactionSnapshot(
            amountText: signedAmount.formattedDashAmount,
            amountTextInLocalCurrency: "(\(localAmount))",
            dateText: watchDateText(transaction.date),
            typeRawValue: type.rawValue)
    }

    private static func watchDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "Mdja",
                                                        options: 0,
                                                        locale: Locale.current)
        return formatter.string(from: date)
            .replacingOccurrences(of: "am", with: "a")
            .replacingOccurrences(of: "pm", with: "p")
            .replacingOccurrences(of: "AM", with: "a")
            .replacingOccurrences(of: "PM", with: "p")
            .replacingOccurrences(of: "a.m.", with: "a")
            .replacingOccurrences(of: "p.m.", with: "p")
            .replacingOccurrences(of: "A.M.", with: "a")
            .replacingOccurrences(of: "P.M.", with: "p")
    }
}

class SwiftDashSDKWalletSource: TransactionSource {
    var allTransactions: Array<Transaction> {
        Self.fetchAll().sorted { $0.date > $1.date }
    }

    /// All persisted SDK transactions wrapped for the app (`firstSeen` desc).
    /// Safe from any thread. Shared read for every tx-history consumer that
    /// used to enumerate DashSync's `DSWallet.allTransactions`.
    static func fetchAll() -> [Transaction] {
        fetchCurrentWalletSnapshot()?.transactions ?? []
    }

    /// Active wallet id and its persisted transactions, captured from one
    /// host-handle read. Callers that retain work across wallet switches use
    /// the id to prevent a pending operation from matching another wallet's
    /// transaction set.
    static func fetchCurrentWalletSnapshot() -> SwiftDashSDKWalletTransactionSnapshot? {
        guard let (container, walletId) = hostHandles() else { return nil }
        let transactions = fetchAndWrap(in: ModelContext(container), walletId: walletId)
        return SwiftDashSDKWalletTransactionSnapshot(walletId: walletId, transactions: transactions)
    }

    /// Single transaction by txid (wire order — the same `Data` as
    /// `DSTransaction.txHashData`). Safe from any thread.
    static func fetch(txid: Data) -> Transaction? {
        guard let (container, walletId) = hostHandles() else { return nil }
        return fetchOne(txid: txid, in: ModelContext(container), walletId: walletId)
    }

    /// The active wallet's shielded operations as history items, for
    /// interleaving with the Core rows. Safe from any thread.
    ///
    /// Three reductions happen here rather than in the view model:
    /// - ShieldFromAssetLock entries are dropped: their Core asset-lock
    ///   spend always renders as a history row already
    ///   (`Transaction.isShieldedTransfer`).
    /// - An internal Withdrawal is projected as Pending until its matching
    ///   Core receipt appears, then dropped so the receipt becomes the single
    ///   authoritative history row. A withdrawal to an EXTERNAL Core address
    ///   produces no wallet-side Core transaction, so it always stays and
    ///   renders as a Sent row.
    /// - Rows are deduped by `entryId`: an intra-wallet transfer writes
    ///   a Sent row on the sending account and a Received row on the
    ///   receiving account for the same operation; the outgoing
    ///   (initiating) side wins.
    static func fetchShieldedActivity(
        coreTransactions: [Transaction] = []
    ) -> [ShieldedActivityItem] {
        guard let (container, walletId) = hostHandles() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate { $0.walletId == walletId })
        guard let rows = try? context.fetch(descriptor) else { return [] }

        var byEntry: [Data: PersistentShieldedActivity] = [:]
        for row in rows where row.kindTag != ShieldedActivityItem.Kind.shieldFromAssetLock.rawValue {
            if let existing = byEntry[row.entryId] {
                if shouldPreferShieldedProjection(row, over: existing) {
                    byEntry[row.entryId] = row
                }
            } else {
                byEntry[row.entryId] = row
            }
        }

        let noteValueByCmx = shieldedNoteValueByCmx(in: context, walletId: walletId)
        let outgoingNoteValueByCmx = outgoingShieldedNoteValueByCmx(in: context, walletId: walletId)

        var items: [ShieldedActivityItem] = []
        for row in byEntry.values {
            let reconstructedAmountCredits = projectedShieldedAmountCredits(
                for: row,
                noteValueByCmx: noteValueByCmx,
                outgoingNoteValueByCmx: outgoingNoteValueByCmx)
            let reconstructedAmountDuffs = reconstructedAmountCredits / 1000

            switch row.kindTag {
            case ShieldedActivityItem.Kind.withdrawal.rawValue:
                let address = withdrawalDestinationAddress(counterparty: row.counterparty)
                if let address, isActiveWalletCoreAddress(address, walletId: walletId, in: context) {
                    // Live withdrawals record this before the payout arrives,
                    // but restored activity can rebuild the same durable tag.
                    ShieldedWithdrawalStore.shared.record(address: address)
                    let pendingItem = ShieldedActivityItem(
                        row: row,
                        amountCreditsOverride: reconstructedAmountCredits,
                        destinationAddress: address,
                        isAwaitingTransparentReceipt: true)
                    // Keep a local Pending row during the gap between the
                    // shielded spend and the asynchronously persisted L1
                    // receipt. Once a matching receipt exists, suppress the
                    // placeholder so the operation never renders twice.
                    if hasMatchingCoreReceipt(
                        for: pendingItem,
                        address: address,
                        in: coreTransactions) {
                        continue
                    }
                    items.append(pendingItem)
                    continue
                }
                // External (or undecodable-script) withdrawal: nothing
                // else in the history covers it — hiding it would make
                // funds silently vanish from the timeline.
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits,
                    destinationAddress: address,
                    isExternalDestination: true))
            case ShieldedActivityItem.Kind.unshield.rawValue:
                // Unshield destination = 21-byte serialized PlatformAddress.
                // Unlike withdrawals, both flavors stay in the list (there
                // is never a Core row for either); the ownership check only
                // decides internal-move vs Sent presentation. An
                // undecodable counterparty defaults to the internal
                // presentation — the honest reading of "destination
                // unknown" for an own-initiated operation.
                let address = unshieldDestinationAddress(counterparty: row.counterparty)
                let isExternal = address.map {
                    !isActiveWalletPlatformAddress($0, walletId: walletId, in: context)
                } ?? false
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits,
                    destinationAddress: address,
                    isExternalDestination: isExternal))
            case ShieldedActivityItem.Kind.received.rawValue:
                if matchingCoreInternalTransfer(
                    for: row,
                    amountDuffs: reconstructedAmountDuffs,
                    route: .coreToShielded,
                    in: coreTransactions) != nil {
                    // Restored Core → Shielded transfers are already covered by
                    // the authoritative L1 asset-lock row in the main list.
                    continue
                }
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits))
            case ShieldedActivityItem.Kind.shieldedSpend.rawValue:
                if let address = unshieldDestinationAddress(counterparty: row.counterparty) {
                    let isExternal = !isActiveWalletPlatformAddress(address, walletId: walletId, in: context)
                    items.append(ShieldedActivityItem(
                        row: row,
                        kindOverride: .unshield,
                        amountCreditsOverride: reconstructedAmountCredits,
                        destinationAddress: address,
                        isExternalDestination: isExternal))
                    continue
                }

                if let address = withdrawalDestinationAddress(counterparty: row.counterparty) {
                    let isOwnAddress = isActiveWalletCoreAddress(
                        address,
                        walletId: walletId,
                        in: context)
                    if isOwnAddress {
                        ShieldedWithdrawalStore.shared.record(address: address)
                    }
                    let receipt = matchingCoreReceipt(
                        amountDuffs: reconstructedAmountDuffs,
                        address: address,
                        around: Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0),
                        in: coreTransactions)
                    let receiptAmountCredits = receipt.map { $0.dashAmount * 1000 }
                    let effectiveAmount = receiptAmountCredits ?? reconstructedAmountCredits

                    if isOwnAddress {
                        // Same-seed restore: once the transparent receipt is in
                        // the wallet's L1 history, that row is authoritative.
                        if receipt != nil {
                            continue
                        }
                        items.append(ShieldedActivityItem(
                            row: row,
                            kindOverride: .withdrawal,
                            amountCreditsOverride: effectiveAmount,
                            destinationAddress: address,
                            isAwaitingTransparentReceipt: true))
                    } else {
                        items.append(ShieldedActivityItem(
                            row: row,
                            kindOverride: .withdrawal,
                            amountCreditsOverride: effectiveAmount,
                            destinationAddress: address,
                            isExternalDestination: true))
                    }
                    continue
                }

                if row.identityId.count == 32 {
                    items.append(ShieldedActivityItem(
                        row: row,
                        kindOverride: .identityCreate,
                        amountCreditsOverride: reconstructedAmountCredits))
                    continue
                }

                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits))
            default:
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits))
            }
        }
        return items
    }

    private static func shouldPreferShieldedProjection(
        _ lhs: PersistentShieldedActivity,
        over rhs: PersistentShieldedActivity
    ) -> Bool {
        let lhsScore = shieldedProjectionPreferenceScore(lhs)
        let rhsScore = shieldedProjectionPreferenceScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return lhs.createdAtMs > rhs.createdAtMs
    }

    private static func shieldedProjectionPreferenceScore(_ row: PersistentShieldedActivity) -> Int {
        var score = 0
        if row.kindTag != ShieldedActivityItem.Kind.shieldedSpend.rawValue { score += 100 }
        if row.kindTag != ShieldedActivityItem.Kind.received.rawValue { score += 40 }
        if row.amount > 0 { score += 30 }
        if !row.identityId.isEmpty { score += 20 }
        if !row.counterparty.isEmpty { score += 10 }
        if row.direction == ShieldedActivityItem.Direction.outgoing.rawValue { score += 5 }
        if row.hasBlockHeight { score += 3 }
        score += row.status
        return score
    }

    private static func projectedShieldedAmountCredits(
        for row: PersistentShieldedActivity,
        noteValueByCmx: [Data: UInt64],
        outgoingNoteValueByCmx: [Data: UInt64]
    ) -> UInt64 {
        if row.amount > 0 { return row.amount }

        let incomingCredits = sumChunked32Values(from: row.noteCmxs, using: noteValueByCmx)
        if incomingCredits > 0 { return incomingCredits }

        let outgoingCredits = sumChunked32Values(from: row.noteCmxs, using: outgoingNoteValueByCmx)
        if outgoingCredits > 0 { return outgoingCredits }

        return 0
    }

    private static func matchingCoreInternalTransfer(
        for row: PersistentShieldedActivity,
        amountDuffs: UInt64,
        route: Transaction.InternalTransferRoute,
        in transactions: [Transaction]
    ) -> Transaction? {
        let rowDate = Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0)
        let candidates = transactions.filter {
            $0.internalTransferRoute == route
                && isWithinProjectionMatchWindow($0.date, around: rowDate)
        }

        if amountDuffs > 0,
           let exact = candidates.first(where: { $0.dashAmount == amountDuffs }) {
            return exact
        }

        return candidates.count == 1 ? candidates.first : nil
    }

    private static func matchingCoreReceipt(
        amountDuffs: UInt64,
        address: String,
        around date: Date,
        in transactions: [Transaction]
    ) -> Transaction? {
        // Do not require `ShieldedWithdrawalStore` classification here. A
        // restored activity row may be the source that rehydrates that store,
        // while the Core transaction is already persisted and mined.
        let candidates = transactions.filter { transaction in
            transaction.direction == .received
                && transaction.outputReceiveAddresses.contains(address)
        }
        let summaries = candidates.map {
            CoreWithdrawalReceiptCandidate(
                amountDuffs: $0.dashAmount,
                date: $0.date)
        }
        guard let index = CoreWithdrawalReceiptMatchPolicy.selectedIndex(
            expectedAmountDuffs: amountDuffs,
            activityDate: date,
            candidates: summaries)
        else { return nil }
        return candidates[index]
    }

    /// Match the eventual Core receipt without relying on a txid the opaque
    /// shielded-withdraw call does not return. The fresh destination address is
    /// the primary key; principal/time only disambiguate unexpected address
    /// reuse. This tolerates restore-time timestamp skew and amount
    /// reconstruction differences without leaving a mined receipt unmatched.
    private static func hasMatchingCoreReceipt(
        for pending: ShieldedActivityItem,
        address: String,
        in transactions: [Transaction]
    ) -> Bool {
        matchingCoreReceipt(
            amountDuffs: pending.amountDuffs,
            address: address,
            around: pending.date,
            in: transactions) != nil
    }

    private static func isWithinProjectionMatchWindow(_ date: Date, around anchor: Date) -> Bool {
        let delta = date.timeIntervalSince(anchor)
        return delta >= -3600 && delta <= 86_400
    }

    private static func shieldedNoteValueByCmx(
        in context: ModelContext,
        walletId: Data
    ) -> [Data: UInt64] {
        let descriptor = FetchDescriptor<PersistentShieldedNote>(
            predicate: #Predicate { $0.walletId == walletId })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.cmx, $0.value) })
    }

    private static func outgoingShieldedNoteValueByCmx(
        in context: ModelContext,
        walletId: Data
    ) -> [Data: UInt64] {
        let descriptor = FetchDescriptor<PersistentShieldedOutgoingNote>(
            predicate: #Predicate { $0.walletId == walletId })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.cmx, $0.value) })
    }

    private static func sumChunked32Values(
        from data: Data,
        using map: [Data: UInt64]
    ) -> UInt64 {
        guard !data.isEmpty else { return 0 }

        var total: UInt64 = 0
        var index = data.startIndex
        while index < data.endIndex {
            let next = data.index(index, offsetBy: 32, limitedBy: data.endIndex) ?? data.endIndex
            guard data.distance(from: index, to: next) == 32 else { break }
            let chunk = Data(data[index..<next])
            total += map[chunk] ?? 0
            index = next
        }
        return total
    }

    /// Decode an unshield entry's counterparty (21-byte serialized
    /// PlatformAddress) to its bech32m string (`dash1…` / `tdash1…`).
    private static func unshieldDestinationAddress(counterparty: Data) -> String? {
        guard counterparty.count == 21 else { return nil }
        return AddressTransformer.formatAddress(
            counterparty,
            asBech32m: true,
            isTestnet: WalletEnvironment.isTestnet)
    }

    /// True when `address` is one of the ACTIVE wallet's own DIP-17
    /// Platform Payment addresses (same active-wallet scoping rationale
    /// as `isActiveWalletCoreAddress`).
    private static func isActiveWalletPlatformAddress(
        _ address: String,
        walletId: Data,
        in context: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<PersistentPlatformAddress>(
            predicate: #Predicate { $0.address == address && $0.walletId == walletId })
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    /// The active wallet's observed incoming Platform-address payments
    /// (app-recorded ledger; see PlatformAddressActivityStore.swift).
    /// Safe from any thread — the DAO's SQLite connection serializes.
    static func fetchPlatformActivity() -> [PlatformAddressActivityItem] {
        let handles: (walletId: Data, networkRaw: Int64)? = onMain {
            guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                return nil
            }
            return (walletId, Int64(network.rawValue))
        }
        guard let handles else { return [] }
        return PlatformAddressActivityDAO.shared
            .activities(walletId: handles.walletId, networkRaw: handles.networkRaw)
            .map { PlatformAddressActivityItem(record: $0) }
    }

    /// Decode a withdrawal entry's counterparty (a Core scriptPubKey)
    /// to a Base58Check address. Nil for empty / non-P2PKH/P2SH scripts.
    private static func withdrawalDestinationAddress(counterparty: Data) -> String? {
        guard !counterparty.isEmpty else { return nil }
        let network: PaymentNetwork = WalletEnvironment.isTestnet ? .testnet : .mainnet
        return ScriptAddressCodec.address(forScript: counterparty, network: network)
    }

    /// True when `address` belongs to the ACTIVE wallet's Core address
    /// pools. Scoped to the active wallet on purpose: a withdrawal to
    /// another on-device wallet's address is still external from this
    /// wallet's perspective (this wallet gets no Core receipt row).
    private static func isActiveWalletCoreAddress(
        _ address: String,
        walletId: Data,
        in context: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<PersistentCoreAddress>(
            predicate: #Predicate { $0.address == address })
        descriptor.fetchLimit = 1
        guard let row = (try? context.fetch(descriptor))?.first else { return false }
        return row.account?.wallet.walletId == walletId
    }

    /// The host is `@MainActor`-isolated; grab its container + active-wallet
    /// id in one brief main hop (two property reads — unlike the fetches,
    /// cheap enough to block a worker queue on). `ModelContainer` is
    /// `Sendable`, so the caller then opens its own `ModelContext` on its
    /// own thread and all SwiftData work stays there.
    private static func hostHandles() -> (container: ModelContainer, walletId: Data)? {
        onMain {
            guard let container = SwiftDashSDKHost.shared.modelContainer,
                  let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
                return nil
            }
            return (container, walletId)
        }
    }

    /// Main-thread trampoline for the `@MainActor`-isolated host reads.
    /// Internal: `HomeViewModel.coinJoinShieldDestinationAvailable` reuses it
    /// for its host/manager reads.
    static func onMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }

    private static func fetchOne(txid: Data, in context: ModelContext, walletId: Data) -> Transaction? {
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txid })
        descriptor.fetchLimit = 1
        guard let row = (try? context.fetch(descriptor))?.first else {
            return nil
        }
        // Membership can arrive through either side of the SDK's documented
        // union: wallet-scoped TXOs or an account's involved-transactions
        // relation. Accept both so an out-of-order receipt is not discarded.
        guard row.outputs.contains(where: { $0.walletId == walletId })
            || row.inputs.contains(where: { $0.walletId == walletId })
            || row.involvedAccounts.contains(where: { $0.wallet.walletId == walletId }) else {
            return nil
        }
        let tx = Transaction(persistentTransaction: row, walletId: walletId)
        tx.sdkCoinJoinMixing = isCoinJoinMixingTx(row)
        return tx
    }

    /// Every txid the active wallet participates in. Union the canonical TXO
    /// membership with `PersistentAccount.involvedTransactions`, as required
    /// by the SDK model: the latter closes out-of-order/payload-only indexing
    /// gaps where the transaction record is saved before its TXO relationship
    /// is available to the home timeline.
    private static func activeWalletTxids(
        in context: ModelContext,
        walletId: Data
    ) -> Set<Data> {
        let txoDescriptor = FetchDescriptor<PersistentTxo>(
            predicate: #Predicate { $0.walletId == walletId })
        let txos = (try? context.fetch(txoDescriptor)) ?? []
        var txids = Set<Data>()
        for txo in txos {
            if let producing = txo.transaction { txids.insert(producing.txid) }
            if let spending = txo.spendingTransaction { txids.insert(spending.txid) }
        }

        var walletDescriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId })
        walletDescriptor.fetchLimit = 1
        if let wallet = (try? context.fetch(walletDescriptor))?.first {
            for account in wallet.accounts {
                for transaction in account.involvedTransactions {
                    txids.insert(transaction.txid)
                }
            }
        }
        return txids
    }

    private static func fetchAndWrap(in context: ModelContext, walletId: Data) -> [Transaction] {
        let txids = activeWalletTxids(in: context, walletId: walletId)
        guard !txids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { txids.contains($0.txid) },
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)])
        let rows: [PersistentTransaction]
        do {
            rows = try context.fetch(descriptor)
        } catch {
            DWLogger.log("HomeViewModel: PersistentTransaction fetch failed: \(error)")
            return []
        }
        return rows.map { row -> Transaction in
            let tx = Transaction(persistentTransaction: row, walletId: walletId)
            tx.sdkCoinJoinMixing = Self.isCoinJoinMixingTx(row)
            return tx
        }
    }

    // PersistentAccount.accountType discriminants (stable across releases).
    private static let coinJoinAccountType: UInt32 = 1 // 0=Standard(BIP44/BIP32), 1=CoinJoin
    private static let standardAccountType: UInt32 = 0

    /// Account type owning a TXO — canonical path is `coreAddress?.account`;
    /// `account` is the fallback used before the address row is linked.
    private static func ownerAccountType(_ txo: PersistentTxo) -> UInt32? {
        (txo.coreAddress?.account ?? txo.account)?.accountType
    }

    /// CoinJoin mixing-operation detection. Traverses SwiftData relationships,
    /// so it must run on the thread that owns the row's `ModelContext` (the
    /// fetch thread). DashSync grouped by CoinJoin-account *role*, not tx
    /// structure, so the SDK's structural `typedKind` (mixing rounds only) is
    /// too narrow. We classify a tx as a mixing operation when:
    ///   1. it DEPOSITS into the CoinJoin account (≥1 CoinJoin output) — covers
    ///      create-denomination, make-collateral-inputs and the mixing rounds; or
    ///   2. it SPENDS from the CoinJoin account (≥1 CoinJoin input) and deposits
    ///      nothing into a Standard (BIP44/BIP32) account — i.e. a mixing-fee /
    ///      collateral spend (the tiny "Sent 0.0001" txs). A Standard output
    ///      marks the CoinJoin→BIP44 sweep or an internal transfer out, which
    ///      must stay an individual row — matching DashSync's "Send" exclusion.
    private static func isCoinJoinMixingTx(_ p: PersistentTransaction) -> Bool {
        if p.typedKind == .coinJoin { return true }
        if p.outputs.contains(where: { ownerAccountType($0) == coinJoinAccountType }) {
            return true
        }
        let spendsCoinJoin = p.inputs.contains { ownerAccountType($0) == coinJoinAccountType }
        guard spendsCoinJoin else { return false }
        let depositsToStandard = p.outputs.contains { ownerAccountType($0) == standardAccountType }
        return !depositsToStandard
    }
}

#if DEBUG
private struct HomeViewModelPreviewTransactionSource: TransactionSource {
    var allTransactions: [Transaction] { [] }
}
#endif

/// SDK identity data is authoritative for Join DashPay visibility. The
/// DWGlobalOptions fields are a legacy UI mirror and are deliberately cleared
/// at the start of every network switch; requiring that mirror before reading
/// the SDK username creates a short-circuit where the mirror can never
/// self-heal after returning to a network with an existing identity.
enum JoinDashPayRegistrationPolicy {
    static func hasRegisteredUsername(
        hasIdentity: Bool,
        sdkUsername: String?,
        legacyRegistrationCompleted: Bool,
        legacyUsername: String?
    ) -> Bool {
        // The legacy mirror is global, while identities are network-scoped.
        // It can only be a fallback for an identity that exists in the
        // currently-bound SDK context.
        guard hasIdentity else {
            return false
        }
        if sdkUsername?.isEmpty == false {
            return true
        }
        return legacyRegistrationCompleted && legacyUsername?.isEmpty == false
    }
}

enum JoinDashPayBannerPolicy {
    static func shouldShow(
        contextReady: Bool,
        syncDone: Bool,
        dismissed: Bool,
        hasRegisteredUsername: Bool,
        hasRegistrationInProgress: Bool
    ) -> Bool {
        contextReady &&
            syncDone &&
            !dismissed &&
            !hasRegisteredUsername &&
            !hasRegistrationInProgress
    }
}

// MARK: - DashPay

#if DASHPAY
extension HomeViewModel {
    func checkJoinDashPay() {
        let options = DWGlobalOptions.sharedInstance()
        // Read the network-scoped SDK truth unconditionally.
        let identityState = MainActor.assumeIsolated {
            let identity = DWCurrentUserIdentityInfo.shared
            return (
                contextReady: identity.isCurrentNetworkContextReady,
                hasIdentity: identity.hasIdentity,
                username: identity.username
            )
        }
        let hasRegisteredUsername = JoinDashPayRegistrationPolicy.hasRegisteredUsername(
            hasIdentity: identityState.hasIdentity,
            sdkUsername: identityState.username,
            legacyRegistrationCompleted: options.dashpayRegistrationCompleted,
            legacyUsername: options.dashpayUsername)
        // Dismissal is persisted per active wallet + network. It is valid
        // before an identity exists and remains valid when readiness is
        // re-evaluated or the user leaves and returns to this network.
        let identityScopedRegistrationState =
            identityState.hasIdentity &&
            (joinDashPayState == .voting || joinDashPayState == .registered)

        self.showJoinDashpay = JoinDashPayBannerPolicy.shouldShow(
            contextReady: identityState.contextReady,
            syncDone: syncModel.state == .syncDone,
            dismissed: UsernamePrefs.shared.joinDashPayDismissed,
            hasRegisteredUsername: hasRegisteredUsername,
            hasRegistrationInProgress: identityScopedRegistrationState)
    }
    
    private func observeDashPay() {
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .sink { [weak self] _ in
                self?.checkJoinDashPay()
                self?.reloadTxsAndShortcuts()
                // Row #18: contact syncing is owned by the SDK DashPay
                // sync loop (PlatformAddressSyncCoordinator).
            }
            .store(in: &cancellableBag)
    }
}
#endif
