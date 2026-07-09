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

@objc(DWHomeTxDisplayMode)
public enum HomeTxDisplayMode: UInt {
    case all = 0
    case received
    case sent
    case rewards
    case giftCard
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
    
    @Published private(set) var txItems: [TransactionGroup] = []
    @Published var shortcutItems: [ShortcutAction] = []
    @Published var showTimeSkewAlertDialog: Bool = false
    @Published var showCoinJoinSweepDialog: Bool = false
    @Published private(set) var timeSkew: TimeInterval = 0
    @Published private(set) var showJoinDashpay: Bool = true
    @Published var displayMode: HomeTxDisplayMode = .all {
        didSet {
            reloadTxDataSource()
        }
    }

    @Published private(set) var headerHeight: CGFloat = kBaseBalanceHeaderHeight // TDOO: move back to HomeView when fully transitioned to SwiftUI
    @Published private(set) var showReclassifyTransaction: Transaction? = nil
    @Published var shouldShowShortcutBanner: Bool = false
    
#if DASHPAY
    var joinDashPayState: JoinDashPayState = .callToAction
#endif
    
    private var syncModel = SyncModelImpl()
    
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
    
    #if DASHPAY
    var shouldShowDashPayInfo: Bool {
        get { !UsernamePrefs.shared.joinDashPayInfoShown }
        set(value) { UsernamePrefs.shared.joinDashPayInfoShown = !value }
    }
    #endif
    
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

    /// Observes network changes (testnet <-> mainnet) to clear cached transaction data
    private func observeNetworkChange() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearCachedData()
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

            // Update UI-bound property on main thread
            DispatchQueue.main.async {
                self.txItems = []
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

        // Balance changes often indicate new transactions, so reload the full
        // transaction list, not just shortcuts. This ensures newly received or
        // sent transactions appear in the UI promptly.
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
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
        self.queue.async { [weak self] in
            guard let self = self else { return }

            // Fix #3: Set reload flag to prevent race conditions with incremental updates
            self.isReloading = true
            DWLogger.log("HomeViewModel: Starting full transaction reload")

            let transactions = transactionSource.allTransactions
            self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            self.coinJoinTxSets = [:]
            self.coinJoinWithdrawalSet = CoinJoinWithdrawalTxSet()

            // Snapshot each provider's metadata once per reload —
            // `availableMetadata` copies the whole dictionary through the
            // provider's serial queue, so reading it per-transaction costs
            // O(n) queue hops + dictionary copies per reload.
            let metadataSnapshots = self.metadataProviders.map { $0.availableMetadata }
            let giftCardTxIds = Set(GiftCardMetadataProvider.shared.availableMetadata.keys)

            var items: [TransactionListDataItem] = transactions.compactMap { wrappedTx -> TransactionListDataItem? in
                Tx.shared.updateRateIfNeeded(for: wrappedTx)

                if !self.passesFilter(transaction: wrappedTx, displayMode: self.displayMode, giftCardTxIds: giftCardTxIds) {
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

            DWLogger.log("HomeViewModel: Full reload complete, \(array.count) groups, \(self.txByHash.count) transactions cached")

            DispatchQueue.main.async {
                self.txItems = array
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

            if !self.passesFilter(transaction: tx, displayMode: self.displayMode) {
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

                for (gIdx, group) in self.txItems.enumerated() {
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
                            let updatedGroup = self.txItems[groupIndex]
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

                if let groupIndex = self.txItems.firstIndex(where: { $0.id == newDateKey }) {
                    // Add to an existing date group
                    DispatchQueue.main.async {
                        self.txItems[groupIndex].items.append(txItem)
                        self.txItems[groupIndex].items.sort { $0.date > $1.date }
                        self.showReclassifyTransaction = shouldShowReclassify ? tx : nil
                    }
                } else {
                    // Create a new date group
                    let newGroup = TransactionGroup(id: newDateKey, date: txItem.date, items: [txItem])
                    let insertIndex = self.txItems.firstIndex(where: { $0.date < txItem.date })

                    DispatchQueue.main.async {
                        if let index = insertIndex {
                            self.txItems.insert(newGroup, at: index)
                        } else {
                            self.txItems.append(newGroup)
                        }
                        self.showReclassifyTransaction = shouldShowReclassify ? tx : nil
                    }
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
            height += 70
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
            DWLogger.log("HomeViewModel: Sync state changed (debounced), reloading")
            self.reloadTxsAndShortcuts()
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
        String(format: "%.6f DASH", Double(coinJoinSweepAmountDuffs) / Double(DUFFS))
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

    /// Proactively surface the "move your mixed coins" popup once per session
    /// after sync completes, while a recoverable CoinJoin balance exists.
    /// Bound to the live balance (not a persistent flag): it re-prompts each
    /// launch until the user sweeps, then self-stops (balance → 0). The durable
    /// Settings row covers the same action for users who dismiss it.
    func maybeShowCoinJoinSweepDialog() {
        DWLogger.log("CJTEST HomeViewModel: sweep dialog check — \(coinJoinSweepAmountDuffs) duffs (\(String(format: "%.6f", Double(coinJoinSweepAmountDuffs) / Double(DUFFS))) DASH), threshold \(CoinJoinRecovery.recoveryDustThresholdDuffs), above=\(coinJoinSweepAmountDuffs > CoinJoinRecovery.recoveryDustThresholdDuffs), syncDone=\(syncModel.state == .syncDone), alreadyShown=\(coinJoinSweepDialogShown)")
        guard !coinJoinSweepDialogShown,
              syncModel.state == .syncDone,
              coinJoinSweepAmountDuffs > CoinJoinRecovery.recoveryDustThresholdDuffs else { return }
        coinJoinSweepDialogShown = true
        showCoinJoinSweepDialog = true
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
            DWLogger.log("CJTEST HomeViewModel: sweep (home popup) failed: \(error)")
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
        self.metadataProviders = [giftCardMetadata, customIconMetadata]
        
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
    
    /// `giftCardTxIds` is an optional pre-snapshotted key set for the
    /// `.giftCard` mode — full-reload loops pass it to avoid copying the
    /// provider's dictionary per transaction; single-tx callers omit it.
    private func passesFilter(transaction: Transaction, displayMode: HomeTxDisplayMode, giftCardTxIds: Set<Data>? = nil) -> Bool {
        switch displayMode {
        case .all:
            return true
        case .sent:
            return transaction.direction == .sent
        case .received:
            return transaction.direction == .received && !transaction.isCoinbaseTransaction
        case .rewards:
            return transaction.isCoinbaseTransaction
        case .giftCard:
            let ids = giftCardTxIds ?? Set(GiftCardMetadataProvider.shared.availableMetadata.keys)
            return ids.contains(transaction.txHashData)
        }
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
        let options = DWGlobalOptions.sharedInstance()
        let isTestnet = WalletEnvironment.isTestnet

        // Check for custom configuration first
        if let customShortcuts = options.shortcuts,
           customShortcuts.count == maxShortcutsCount {
            let items = customShortcuts.compactMap { number -> ShortcutAction? in
                guard var type = ShortcutActionType(rawValue: number.intValue) else { return nil }
                // A faucet shortcut saved on testnet degrades to Spend
                // after a switch to mainnet (no mainnet faucet exists);
                // the saved config is untouched, so it comes back when
                // the user returns to testnet.
                if type == .getTestDash && !isTestnet {
                    type = .spend
                }
                return ShortcutAction(type: type)
            }
            if items.count == maxShortcutsCount {
                DispatchQueue.main.async {
                    self.shortcutItems = items
                }
                return
            }
        }

        // Fall back to default state-based logic
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
class SwiftDashSDKWalletSource: TransactionSource {
    var allTransactions: Array<Transaction> {
        Self.fetchAll().sorted { $0.date > $1.date }
    }

    /// All persisted SDK transactions wrapped for the app (`firstSeen` desc).
    /// Safe from any thread. Shared read for every tx-history consumer that
    /// used to enumerate DashSync's `DSWallet.allTransactions`.
    static func fetchAll() -> [Transaction] {
        guard let (container, walletId) = hostHandles() else { return [] }
        return fetchAndWrap(in: ModelContext(container), walletId: walletId)
    }

    /// Single transaction by txid (wire order — the same `Data` as
    /// `DSTransaction.txHashData`). Safe from any thread.
    static func fetch(txid: Data) -> Transaction? {
        guard let (container, walletId) = hostHandles() else { return nil }
        return fetchOne(txid: txid, in: ModelContext(container), walletId: walletId)
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
    private static func onMain<T>(_ body: @MainActor () -> T) -> T {
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
        // Membership check: a tx the active wallet doesn't participate in
        // (no TXO row denorm'd to its walletId, via either the producing
        // `transaction` or the spending `spendingTransaction`) is not its
        // transaction and reads as absent.
        guard row.outputs.contains(where: { $0.walletId == walletId })
            || row.inputs.contains(where: { $0.walletId == walletId }) else {
            return nil
        }
        let tx = Transaction(persistentTransaction: row)
        tx.sdkCoinJoinMixing = isCoinJoinMixingTx(row)
        return tx
    }

    /// Every txid the active wallet participates in, recovered by the
    /// TXO join `PersistentTransaction` deliberately can't express itself
    /// (it has no walletId — one row is shared across wallets; see the
    /// model doc). A wallet's TXO rows carry its walletId denorm; each row
    /// names the wallet's transactions on both sides — the producing
    /// `transaction` (funds in) and the `spendingTransaction` (funds out).
    /// One walletId-scoped fetch per reload (not per transaction), so the
    /// timeline stays a single indexed scan on large wallets.
    private static func activeWalletTxids(
        in context: ModelContext,
        walletId: Data
    ) -> Set<Data> {
        let descriptor = FetchDescriptor<PersistentTxo>(
            predicate: #Predicate { $0.walletId == walletId })
        guard let txos = try? context.fetch(descriptor) else { return [] }
        var txids = Set<Data>()
        for txo in txos {
            if let producing = txo.transaction { txids.insert(producing.txid) }
            if let spending = txo.spendingTransaction { txids.insert(spending.txid) }
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
            let tx = Transaction(persistentTransaction: row)
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

// MARK: - DashPay

#if DASHPAY
extension HomeViewModel {
    func checkJoinDashPay() {
        self.showJoinDashpay = syncModel.state == .syncDone &&
            !UsernamePrefs.shared.joinDashPayDismissed &&
            joinDashPayState != .voting && joinDashPayState != .registered
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
