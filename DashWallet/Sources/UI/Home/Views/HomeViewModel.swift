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
        #if DASHPAY
        self.observeDashPay()
        #endif
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
                
                if self.displayMode == .sent && tx.direction != .sent {
                    return nil
                }
               
                if self.displayMode == .received && (tx.direction != .received || tx is DSCoinbaseTransaction) {
                    return nil
                }
               
                if self.displayMode == .rewards && !(tx is DSCoinbaseTransaction) {
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
            
            if self.displayMode == .sent && tx.direction != .sent {
                return
            }
            
            if self.displayMode == .received && (tx.direction != .received || tx is DSCoinbaseTransaction) {
                return
            }
            
            if self.displayMode == .rewards && !(tx is DSCoinbaseTransaction) {
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
    
    private func resolveMetadata(for txId: Data) -> TxRowMetadata? {
        var finalMetadata: TxRowMetadata? = nil
        
        for provider in self.metadataProviders {
            if let metadata = provider.availableMetadata[txId] {
                if finalMetadata == nil {
                    finalMetadata = metadata
                } else {
                    if finalMetadata?.title == nil {
                        finalMetadata?.title = metadata.title
                    }
                    
                    if finalMetadata?.details == nil {
                        finalMetadata?.details = metadata.details
                    }
                }
            }
        }
        
        return finalMetadata
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
            title: NSLocalizedString(self.coinJoinService.mixingState == .finishing ? "Mixing Finishing…" : "Mixing", comment: "CoinJoin"),
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

// MARK: - Metadata Providers

extension HomeViewModel {
    private func setupMetadataProviders() {
        let privateMemoProvider = PrivateMemoProvider()
        privateMemoProvider.metadataUpdated
            .receive(on: self.queue)
            .sink { [weak self] txHash in
                guard let self = self else { return }
                
                let wallet = DWEnvironment.sharedInstance().currentWallet
                if let transaction = wallet.transaction(forHash: txHash.withUnsafeBytes { $0.load(as: UInt256.self) }) {
                    self.onTransactionStatusChanged(tx: transaction)
                }
            }
            .store(in: &cancellableBag)
        
        self.metadataProviders = [privateMemoProvider]
    }
}


// MARK: - Shortcuts

extension HomeViewModel {
    func reloadShortcuts() {
        let options = DWGlobalOptions.sharedInstance()
        let walletNeedsBackup = options.walletNeedsBackup
        let userHasBalance = options.userHasBalance

        var mutableItems = [ShortcutAction]()
        mutableItems.reserveCapacity(2)

        if walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))

            if userHasBalance {
                mutableItems.append(ShortcutAction(type: .receive))
                mutableItems.append(ShortcutAction(type: .payToAddress))
                mutableItems.append(ShortcutAction(type: .scanToPay))
            } else {
                mutableItems.append(ShortcutAction(type: .explore))
                mutableItems.append(ShortcutAction(type: .receive))

                if DWEnvironment.sharedInstance().currentChain.isMainnet() {
                    mutableItems.append(ShortcutAction(type: .buySellDash))
                }
            }
        } else {
            if userHasBalance {
                mutableItems.append(ShortcutAction(type: .explore))
                mutableItems.append(ShortcutAction(type: .receive))
                mutableItems.append(ShortcutAction(type: .payToAddress))
                mutableItems.append(ShortcutAction(type: .scanToPay))
            } else {
                mutableItems.append(ShortcutAction(type: .explore))
                mutableItems.append(ShortcutAction(type: .receive))

                if DWEnvironment.sharedInstance().currentChain.isMainnet() {
                    mutableItems.append(ShortcutAction(type: .buySellDash))
                }
            }
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
