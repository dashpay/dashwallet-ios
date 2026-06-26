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
    @Published private(set) var showReclassifyTransaction: DSTransaction? = nil
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
    }

    /// Clears all cached transaction data when switching networks
    private func clearCachedData() {
        DSLogger.log("HomeViewModel: Network changed, clearing cached transaction data")

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
        NotificationCenter.default.publisher(for: Notification.Name.fiatCurrencyDidChange)
            .sink { [weak self] _ in
                self?.reloadTxsAndShortcuts()
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
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DSLogger.log("HomeViewModel: SwiftData saved, reloading tx list")
                self?.reloadTxsAndShortcuts()
            }
            .store(in: &cancellableBag)

        // Fix #5: Balance changes often indicate new transactions, so reload the full
        // transaction list, not just shortcuts. This ensures newly received or sent
        // transactions appear in the UI promptly.
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in
                DSLogger.log("HomeViewModel: Wallet balance changed, reloading transactions and shortcuts")
                self?.reloadTxsAndShortcuts()
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: .DSTransactionManagerTransactionStatusDidChange)
            .sink { [weak self] notification in
                if let tx = notification.userInfo?[DSTransactionManagerNotificationTransactionKey] as? DSTransaction {
                    self?.onTransactionStatusChanged(tx: tx)
                }
            }
            .store(in: &cancellableBag)
        
        // Fix #1: Always reload transactions when sync starts, not just during resync.
        // Previously, this only reloaded if isResyncingWallet was true, which meant
        // normal sync operations wouldn't refresh the transaction list.
        NotificationCenter.default.publisher(for: Notification.Name.DSChainManagerSyncWillStart)
            .sink { [weak self] _ in
                DSLogger.log("HomeViewModel: Sync will start, reloading transactions")
                self?.reloadTxsAndShortcuts()
            }
            .store(in: &cancellableBag)
        
        syncModel.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
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
            DSLogger.log("HomeViewModel: Starting full transaction reload")

            let transactions = transactionSource.allTransactions
            self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            self.coinJoinTxSets = [:]
            self.coinJoinWithdrawalSet = CoinJoinWithdrawalTxSet()

            var items: [TransactionListDataItem] = transactions.compactMap { wrappedTx -> TransactionListDataItem? in
                Tx.shared.updateRateIfNeeded(for: wrappedTx)

                if !self.passesFilter(transaction: wrappedTx, displayMode: self.displayMode) {
                    return nil
                }

                // CrowdNode grouping only for DS-backed txs (matcher needs
                // DSTransaction for address comparison). CoinJoin mixing grouping
                // is handled for SDK-sourced txs in the branch below.
                if let dsTx = wrappedTx.tx {
                    if !self.crowdNodeTxSet.isComplete && self.crowdNodeTxSet.tryInclude(tx: dsTx) {
                        return nil
                    }
                } else if wrappedTx.isCoinJoinMixing {
                    // SDK-sourced CoinJoin mixing tx — no DSTransaction, so the
                    // DSCoinJoinWrapper path above can't see it. Group it into the
                    // same per-day "Mixing Transactions" set via the SDK overload.
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

                return .tx(wrappedTx, self.resolveMetadata(for: wrappedTx.txHashData))
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

            DSLogger.log("HomeViewModel: Full reload complete, \(array.count) groups, \(self.txByHash.count) transactions cached")

            DispatchQueue.main.async {
                self.txItems = array
            }
        }
    }
    
    private func onTransactionStatusChanged(tx: DSTransaction) {
        self.queue.async { [weak self] in
            guard let self = self else { return }

            // Fix #3: Skip incremental updates while a full reload is in progress
            // to prevent race conditions that could cause missing transactions
            if self.isReloading {
                DSLogger.log("HomeViewModel: Skipping incremental update during full reload for tx: \(tx.txHashHexString)")
                return
            }

            // Fix #2: If initial load hasn't completed yet, the cache is empty and
            // incremental updates won't work correctly. Trigger a full reload instead.
            if !self.hasCompletedInitialLoad {
                DSLogger.log("HomeViewModel: Initial load not complete, triggering full reload for tx: \(tx.txHashHexString)")
                DispatchQueue.main.async {
                    self.reloadTxsAndShortcuts()
                }
                return
            }

            let wrappedTx = Transaction(transaction: tx)
            if !self.passesFilter(transaction: wrappedTx, displayMode: self.displayMode) {
                return
            }

            Tx.shared.updateRateIfNeeded(for: tx)
            let txHashHex = tx.txHashHexString
            var itemId = txHashHex
            var txItem: TransactionListDataItem = .tx(wrappedTx, resolveMetadata(for: tx.txHashData))
            let newDateKey = DWDateFormatter.sharedInstance.dateOnly(from: tx.date)

            // Track if this transaction was absorbed by a grouped set (CrowdNode)
            var wasAbsorbedByGroup = false

            if self.crowdNodeTxSet.tryInclude(tx: tx) {
                itemId = FullCrowdNodeSignUpTxSet.id
                txItem = .crowdnode(self.crowdNodeTxSet)
                wasAbsorbedByGroup = true
                DSLogger.log("HomeViewModel: Transaction \(txHashHex) absorbed by CrowdNode group")
            }

            // Fix: Check if this transaction exists under its original hash (not group ID)
            // This handles the case where a transaction was previously shown individually
            // but is now being absorbed by a CoinJoin/CrowdNode group
            if wasAbsorbedByGroup && self.txByHash[txHashHex] != nil {
                DSLogger.log("HomeViewModel: Removing individual transaction \(txHashHex) as it's now in a group")

                // Perform iteration and removal entirely on main thread to avoid race conditions
                // where txItems could change between finding indices and performing removal
                DispatchQueue.main.async {
                    // Find the group containing this transaction by searching current state
                    for groupIndex in 0..<self.txItems.count {
                        guard groupIndex < self.txItems.count else { break }

                        if let itemIndex = self.txItems[groupIndex].items.firstIndex(where: { $0.id == txHashHex }) {
                            // Verify bounds are still valid before removal
                            guard groupIndex < self.txItems.count,
                                  itemIndex < self.txItems[groupIndex].items.count else { break }

                            self.txItems[groupIndex].items.remove(at: itemIndex)

                            // Remove empty groups (re-check bounds after item removal)
                            if groupIndex < self.txItems.count && self.txItems[groupIndex].items.isEmpty {
                                self.txItems.remove(at: groupIndex)
                            }

                            // Only remove from cache after confirming UI removal succeeded
                            self.queue.async {
                                self.txByHash.removeValue(forKey: txHashHex)
                            }
                            break
                        }
                    }
                }
            }

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
                    DSLogger.log("HomeViewModel: Transaction \(itemId) date changed from \(oldDateKey) to \(newDateKey)")

                    // Remove from old group
                    if let oldGIdx = oldGroupIndex, let oldIIdx = oldItemIndex {
                        DispatchQueue.main.async {
                            // Validate both group index and item index bounds before removal
                            // txItems may have changed between when indices were captured and now
                            guard oldGIdx >= 0,
                                  oldGIdx < self.txItems.count,
                                  oldIIdx >= 0,
                                  oldIIdx < self.txItems[oldGIdx].items.count else {
                                DSLogger.log("HomeViewModel: Skipping removal - indices out of bounds (groupIdx: \(oldGIdx), itemIdx: \(oldIIdx))")
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
            DSLogger.log("HomeViewModel: Sync state changed (debounced), reloading")
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
        DSLogger.log("CJTEST HomeViewModel: sweep dialog check — \(coinJoinSweepAmountDuffs) duffs (\(String(format: "%.6f", Double(coinJoinSweepAmountDuffs) / Double(DUFFS))) DASH), threshold \(CoinJoinRecovery.recoveryDustThresholdDuffs), above=\(coinJoinSweepAmountDuffs > CoinJoinRecovery.recoveryDustThresholdDuffs), syncDone=\(syncModel.state == .syncDone), alreadyShown=\(coinJoinSweepDialogShown)")
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
            DSLogger.log("CJTEST HomeViewModel: sweep (home popup) failed: \(error)")
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

                    let wallet = DWEnvironment.sharedInstance().currentWallet
                    if let transaction = wallet.transaction(forHash: txHash.withUnsafeBytes { $0.load(as: UInt256.self) }) {
                        self.onTransactionStatusChanged(tx: transaction)
                    }
                }
                .store(in: &cancellableBag)
        }
    }
    
    private func resolveMetadata(for txId: Data) -> TxRowMetadata? {
        var finalMetadata: TxRowMetadata? = nil

        // Metadata will not be replaced if already found, so in case
        // of conflicts metadataProviders should be sorted by priority
        for provider in self.metadataProviders {
            let providerMetadata = provider.availableMetadata
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
    
    private func passesFilter(transaction: Transaction, displayMode: HomeTxDisplayMode) -> Bool {
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
            return GiftCardMetadataProvider.shared.availableMetadata[transaction.txHashData] != nil
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

        // Check for custom configuration first
        if let customShortcuts = options.shortcuts,
           customShortcuts.count == maxShortcutsCount {
            let items = customShortcuts.compactMap { number -> ShortcutAction? in
                guard let type = ShortcutActionType(rawValue: number.intValue) else { return nil }
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

        var mutableItems = [ShortcutAction]()
        mutableItems.reserveCapacity(maxShortcutsCount)

        // State 1: Zero balance and not verified passphrase
        if !userHasBalance && walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .buySellDash))
            mutableItems.append(ShortcutAction(type: .spend))
        }
        // State 2: Zero balance and verified passphrase
        else if !userHasBalance && !walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: .buySellDash))
            mutableItems.append(ShortcutAction(type: .spend))
        }
        // State 3: Has balance and verified passphrase
        else if userHasBalance && !walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: .scanToPay))
            mutableItems.append(ShortcutAction(type: .spend))
        }
        // State 4: Has balance and not verified passphrase
        else if userHasBalance && walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: .spend))
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
/// `SwiftDashSDKHost` is `@MainActor`-isolated; this getter is invoked
/// from `HomeViewModel.queue` (a background dispatch queue), so the read
/// trampolines through `DispatchQueue.main.sync`. The fetch itself is
/// fast (<10ms for a few hundred rows), so blocking the worker queue
/// briefly is acceptable.
class SwiftDashSDKWalletSource: TransactionSource {
    var allTransactions: Array<Transaction> {
        let wrapped: [Transaction]
        if Thread.isMainThread {
            wrapped = MainActor.assumeIsolated { Self.fetchAndWrapOnMain() }
        } else {
            var fetched: [Transaction] = []
            DispatchQueue.main.sync {
                fetched = MainActor.assumeIsolated { Self.fetchAndWrapOnMain() }
            }
            wrapped = fetched
        }
        return wrapped.sorted { $0.date > $1.date }
    }

    /// Fetch + wrap on the main actor. Wrapping (and the per-tx CoinJoin
    /// membership computation it performs) must run here, not on the caller's
    /// background queue: `Transaction.sdkCoinJoinMixing` is derived by walking
    /// SwiftData relationships (outputs → coreAddress → account), which are
    /// bound to `mainContext`'s actor. The fetch is fast (<10ms for a few
    /// hundred rows) so briefly blocking the worker queue is acceptable.
    @MainActor
    private static func fetchAndWrapOnMain() -> [Transaction] {
        guard let container = SwiftDashSDKHost.shared.modelContainer else {
            return []
        }
        let descriptor = FetchDescriptor<PersistentTransaction>(
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)])
        let rows: [PersistentTransaction]
        do {
            rows = try container.mainContext.fetch(descriptor)
        } catch {
            DSLogger.log("HomeViewModel: PersistentTransaction fetch failed: \(error)")
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
    @MainActor
    private static func ownerAccountType(_ txo: PersistentTxo) -> UInt32? {
        (txo.coreAddress?.account ?? txo.account)?.accountType
    }

    /// CoinJoin mixing-operation detection (main actor — traverses SwiftData
    /// relationships). DashSync grouped by CoinJoin-account *role*, not tx
    /// structure, so the SDK's structural `typedKind` (mixing rounds only) is
    /// too narrow. We classify a tx as a mixing operation when:
    ///   1. it DEPOSITS into the CoinJoin account (≥1 CoinJoin output) — covers
    ///      create-denomination, make-collateral-inputs and the mixing rounds; or
    ///   2. it SPENDS from the CoinJoin account (≥1 CoinJoin input) and deposits
    ///      nothing into a Standard (BIP44/BIP32) account — i.e. a mixing-fee /
    ///      collateral spend (the tiny "Sent 0.0001" txs). A Standard output
    ///      marks the CoinJoin→BIP44 sweep or an internal transfer out, which
    ///      must stay an individual row — matching DashSync's "Send" exclusion.
    @MainActor
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
                DWDashPayContactsUpdater.sharedInstance().beginUpdating()
            }
            .store(in: &cancellableBag)
        
        // TODO: update notifications
//        NotificationCenter.default.addObserver(self,
//                                               selector: #selector(updateHeaderView),
//                                               name:NSNotification.Name.DWNotificationsProviderDidUpdate,
//                                               object:nil);
    }
}
#endif
