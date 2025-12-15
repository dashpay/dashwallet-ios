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
    private let coinJoinService = CoinJoinService.shared
    private var timeSkewDialogShown: Bool = false
    
    static let shared: HomeViewModel = {
        return HomeViewModel(transactionSource: DSWalletSource())
    }()
    
    private let transactionSource: TransactionSource
    private var txByHash: [String: TransactionListDataItem] = [:]
    private var crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
    private var coinJoinTxSets: [String: CoinJoinMixingTxSet] = [:] // Grouped by date
    private var metadataProviders: [MetadataProvider] = []
    
    @Published private(set) var txItems: [TransactionGroup] = []
    @Published var shortcutItems: [ShortcutAction] = []
    @Published private(set) var coinJoinItem = CoinJoinMenuItemModel(title: NSLocalizedString("Mixing", comment: "CoinJoin"), isOn: false, state: .notStarted, progress: 0.0, mixed: 0.0, total: 0.0)
    @Published var showTimeSkewAlertDialog: Bool = false
    @Published private(set) var timeSkew: TimeInterval = 0
    @Published private(set) var showJoinDashpay: Bool = true
    @Published var displayMode: HomeTxDisplayMode = .all {
        didSet {
            reloadTxDataSource()
        }
    }

    @Published private(set) var headerHeight: CGFloat = kBaseBalanceHeaderHeight // TDOO: move back to HomeView when fully transitioned to SwiftUI
    @Published private(set) var showReclassifyTransaction: DSTransaction? = nil
    
#if DASHPAY
    var joinDashPayState: JoinDashPayState = .callToAction
#endif
    
    private var syncModel = SyncModelImpl()
    
    var coinJoinMode: CoinJoinMode {
        get { coinJoinService.mode }
    }
    
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
    var shouldShowMixDashDialog: Bool {
        get { coinJoinService.mode == .none || !UsernamePrefs.shared.mixDashShown }
        set(value) { UsernamePrefs.shared.mixDashShown = !value }
    }
    
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

        self.observeCoinJoin()
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

        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in
                self?.reloadShortcuts()
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: .DSTransactionManagerTransactionStatusDidChange)
            .sink { [weak self] notification in
                if let tx = notification.userInfo?[DSTransactionManagerNotificationTransactionKey] as? DSTransaction {
                    self?.onTransactionStatusChanged(tx: tx)
                }
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: Notification.Name.DSChainManagerSyncWillStart)
            .sink { [weak self] _ in
                if DWGlobalOptions.sharedInstance().isResyncingWallet {
                    self?.reloadTxsAndShortcuts()
                }
            }
            .store(in: &cancellableBag)
        
        syncModel.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.onSyncStateChanged()
            }
            .store(in: &cancellableBag)
    }
    
    // This is expensive and should not be called often
    private func reloadTxDataSource() {
        self.queue.async { [weak self] in
            guard let self = self else { return }
            
            let transactions = transactionSource.allTransactions
            self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            self.coinJoinTxSets = [:]
            
            var items: [TransactionListDataItem] = transactions.compactMap { tx -> TransactionListDataItem? in
                Tx.shared.updateRateIfNeeded(for: tx)
                            
                if !self.passesFilter(tx: tx, displayMode: self.displayMode) {
                    return nil
                }
                           
                if !self.crowdNodeTxSet.isComplete && self.crowdNodeTxSet.tryInclude(tx: tx) {
                    return nil
                }
                            
                if !self.crowdNodeTxSet.isComplete && self.crowdNodeTxSet.tryInclude(tx: tx) {
                    // CrowdNode transactions will be included below
                    return nil
                }

                let date = DWDateFormatter.sharedInstance.dateOnly(from: tx.date)
                let coinJoinTxSet = self.coinJoinTxSets[date] ?? CoinJoinMixingTxSet()
                self.coinJoinTxSets[date] = coinJoinTxSet
                           
                if coinJoinTxSet.tryInclude(tx: tx) {
                    // CoinJoin transactions will be included below
                    return nil
                }
                            
                return .tx(Transaction(transaction: tx), self.resolveMetadata(for: tx.txHashData))
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

            let groupedItems = Dictionary(
                grouping: items.sorted(by: { $0.date > $1.date }),
                by: { DWDateFormatter.sharedInstance.dateOnly(from: $0.date) }
            )
            
            let array = groupedItems.map { key, items in
                TransactionGroup(id: key, date: items.first!.date, items: items)
            }.sorted { $0.date > $1.date }
            
            DispatchQueue.main.async {
                self.txItems = array
            }
        }
    }
    
    private func onTransactionStatusChanged(tx: DSTransaction) {
        self.queue.async { [weak self] in
            guard let self = self else { return }
            
            if !self.passesFilter(tx: tx, displayMode: self.displayMode) {
                return
            }
            
            Tx.shared.updateRateIfNeeded(for: tx)
            var itemId = tx.txHashHexString
            var txItem: TransactionListDataItem = .tx(Transaction(transaction: tx), resolveMetadata(for: tx.txHashData))
            let dateKey = DWDateFormatter.sharedInstance.dateOnly(from: tx.date)

            if self.crowdNodeTxSet.tryInclude(tx: tx) {
                itemId = FullCrowdNodeSignUpTxSet.id
                txItem = .crowdnode(self.crowdNodeTxSet)
            } else {
                let coinJoinTxSet = self.coinJoinTxSets[dateKey] ?? CoinJoinMixingTxSet()
                self.coinJoinTxSets[dateKey] = coinJoinTxSet
               
                if coinJoinTxSet.tryInclude(tx: tx) {
                    itemId = coinJoinTxSet.id
                    txItem = .coinjoin(coinJoinTxSet)
                }
            }

            if let existingItem = self.txByHash[itemId] {
                // Updating existing item
                self.txByHash[itemId] = txItem
                var isChanged = true
                
                if case let .tx(existingTx, oldMetadata) = existingItem, case let .tx(newTx, metadata) = txItem {
                    isChanged = newTx.state != existingTx.state || oldMetadata != metadata
                }
                
                if isChanged {
                    if let groupIndex = self.txItems.firstIndex(where: { $0.id == dateKey }),
                        let itemIndex = self.txItems[groupIndex].items.firstIndex(where: { $0.id == itemId }) {
                        DispatchQueue.main.async {
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
                
                if let groupIndex = self.txItems.firstIndex(where: { $0.id == dateKey }) {
                    // Add to an existing date group
                    DispatchQueue.main.async {
                        self.txItems[groupIndex].items.append(txItem)
                        self.txItems[groupIndex].items.sort { $0.date > $1.date }
                        self.showReclassifyTransaction = shouldShowReclassify ? tx : nil
                    }
                } else {
                    // Create a new date group
                    let newGroup = TransactionGroup(id: dateKey, date: txItem.date, items: [txItem])
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

        self.headerHeight = height
    }
    
    private func getDeviceTimeSkew(force: Bool) async -> (Bool, TimeInterval) {
        do {
            let timeSkew = try await TimeUtils.getTimeSkew(force: force)
            let maxAllowedTimeSkew: TimeInterval
            
            if coinJoinService.mode == .none {
                maxAllowedTimeSkew = kTimeskewTolerance
            } else {
                maxAllowedTimeSkew = timeSkew > 0 ? kMaxAllowedAheadTimeskew * 3 : kMaxAllowedBehindTimeskew * 2
            }
            
            coinJoinService.updateTimeSkew(timeSkew: timeSkew)
            return (abs(timeSkew) > maxAllowedTimeSkew, timeSkew)
        } catch {
            // Ignore errors
            return (false, 0)
        }
    }
}

// MARK: - CoinJoin

extension HomeViewModel {
    private func observeCoinJoin() {
        coinJoinService.$progress
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCoinJoinItem()
            }
            .store(in: &cancellableBag)
        
        coinJoinService.$mode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCoinJoinItem()
            }
            .store(in: &cancellableBag)
        
        coinJoinService.$mixingState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCoinJoinItem()
            }
            .store(in: &cancellableBag)
    }
    
    private func refreshCoinJoinItem() {
        self.coinJoinItem = CoinJoinMenuItemModel(
            title: self.coinJoinService.mixingState == .finishing ? NSLocalizedString("Mixing Finishing…", comment: "CoinJoin") : NSLocalizedString("Mixing", comment: "CoinJoin"),
            isOn: coinJoinService.mixingState.isInProgress,
            state: coinJoinService.mixingState,
            progress: coinJoinService.progress.progress,
            mixed: Double(coinJoinService.progress.coinJoinBalance) / Double(DUFFS),
            total: Double(coinJoinService.progress.totalBalance) / Double(DUFFS)
        )
    }
    
    private func onSyncStateChanged() {
        self.reloadTxsAndShortcuts()
        #if DASHPAY
        self.checkJoinDashPay()
        #endif
    }
    
    func reloadTxsAndShortcuts() {
        self.reloadTxDataSource()
        self.reloadShortcuts()
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
    
    private func passesFilter(tx: DSTransaction, displayMode: HomeTxDisplayMode) -> Bool {
        switch displayMode {
        case .all:
            return true
        case .sent:
            return tx.direction == .sent
        case .received:
            return tx.direction == .received && !(tx is DSCoinbaseTransaction)
        case .rewards:
            return tx is DSCoinbaseTransaction
        case .giftCard:
            return isGiftCard(tx: tx)
        }
    }
    
    private func isGiftCard(tx: DSTransaction) -> Bool {
        return GiftCardMetadataProvider.shared.availableMetadata[tx.txHashData] != nil
    }
}

// MARK: - Shortcuts

extension HomeViewModel {
    func reloadShortcuts() {
        let options = DWGlobalOptions.sharedInstance()
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
            mutableItems.append(ShortcutAction(type: .payToAddress))
            mutableItems.append(ShortcutAction(type: .buySellDash))
            mutableItems.append(ShortcutAction(type: .spend))
        }
        // State 3: Has balance and verified passphrase
        else if userHasBalance && !walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .payToAddress))
            mutableItems.append(ShortcutAction(type: .scanToPay))
            mutableItems.append(ShortcutAction(type: .spend))
        }
        // State 4: Has balance and not verified passphrase
        else if userHasBalance && walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .payToAddress))
            mutableItems.append(ShortcutAction(type: .spend))
        }

        self.shortcutItems = mutableItems
    }
}

protocol TransactionSource {
    var allTransactions: Array<DSTransaction> { get }
}

class DSWalletSource: TransactionSource {
    var allTransactions: Array<DSTransaction> {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        return wallet.allTransactions
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
