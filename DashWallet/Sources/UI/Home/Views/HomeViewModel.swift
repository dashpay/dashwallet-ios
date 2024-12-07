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

private let kBaseBalanceHeaderHeight: CGFloat = 250
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
        return HomeViewModel()
    }()
    
    private var txByHash: [String: TransactionListDataItem] = [:]
    private var crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
    
    @Published private(set) var txItems: [TransactionGroup] = []
    @Published var shortcutItems: [ShortcutAction] = []
    @Published private(set) var coinJoinItem = CoinJoinMenuItemModel(title: NSLocalizedString("Mixing", comment: "CoinJoin"), isOn: false, state: .notStarted, progress: 0.0, mixed: 0.0, total: 0.0)
    @Published var showTimeSkewAlertDialog: Bool = false
    @Published private(set) var timeSkew: TimeInterval = 0
    @Published var showJoinDashpay: Bool = true
    @Published var displayMode: HomeTxDisplayMode = .all {
        didSet {
            // TODO
        }
    }
    @Published private(set) var balanceHeaderHeight: CGFloat = kBaseBalanceHeaderHeight // TDOO: move back to HomeView when fully transitioned to SwiftUI
    
    private var model: SyncModel = SyncModelImpl()
    
    var coinJoinMode: CoinJoinMode {
        get { coinJoinService.mode }
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
    
    init() {
        model.networkStatusDidChange = { status in
            self.recalculateHeight()
        }
        model.stateDidChage = { state in
            self.reloadTxDataSource()
            self.reloadShortcuts()
        }
        self.reloadTxDataSource();
        self.reloadShortcuts()
        self.recalculateHeight()

        self.observeCoinJoin()
        self.observeWallet()
        #if DASHPAY
        self.observeDashPay()
        #endif
    }
    
    private func observeWallet() {
        NotificationCenter.default.publisher(for: Notification.Name.fiatCurrencyDidChange)
            .sink { [weak self] _ in
                self?.reloadTxDataSource()
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: .DSTransactionManagerTransactionStatusDidChange)
            .sink { [weak self] notification in
                if let tx = notification.userInfo?[DSTransactionManagerNotificationTransactionKey] as? DSTransaction {
                    self?.onTransactionStatusChanged(tx: tx)
                }
            }
            .store(in: &cancellableBag)
    }
    
    // This is expensive and should not be called often
    private func reloadTxDataSource() {
        self.queue.async { [weak self] in
            guard let self = self else { return }
            let wallet = DWEnvironment.sharedInstance().currentWallet
            let transactions = wallet.allTransactions
            self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            
            var items: [TransactionListDataItem] = transactions.compactMap {
                if self.crowdNodeTxSet.isComplete { return .tx(Transaction(transaction: $0)) }
                
                return self.crowdNodeTxSet.tryInclude(tx: $0) ? nil : .tx(Transaction(transaction: $0))
            }

            self.txByHash.removeAll()
            items.forEach { item in
                self.txByHash[item.id] = item
            }

            if !crowdNodeTxSet.transactions.isEmpty {
                let item: TransactionListDataItem = .crowdnode(crowdNodeTxSet)
                items.insert(item, at: 0)
                self.txByHash[FullCrowdNodeSignUpTxSet.id] = item
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
            var itemId = tx.txHashHexString
            var isCrowdNode = false

            if self.crowdNodeTxSet.tryInclude(tx: tx) {
                itemId = FullCrowdNodeSignUpTxSet.id
                isCrowdNode = true
            }

            let txItem: TransactionListDataItem = isCrowdNode ? .crowdnode(self.crowdNodeTxSet) : .tx(Transaction(transaction: tx))
            let dateKey = DWDateFormatter.sharedInstance.dateOnly(from: txItem.date)

            if let existingItem = self.txByHash[itemId] {
                // Updating existing item
                self.txByHash[itemId] = txItem
                var isChanged = true
                
                if case let .tx(existingTx) = existingItem, case let .tx(newTx) = txItem {
                    isChanged = newTx.state != existingTx.state
                }
                
                if isChanged {
                    if let groupIndex = self.txItems.firstIndex(where: { $0.id == dateKey }),
                        let itemIndex = self.txItems[groupIndex].items.firstIndex(where: { $0.id == itemId }) {
                        DispatchQueue.main.async {
                            self.txItems[groupIndex].items[itemIndex] = txItem
                        }
                    }
                }
            } else {
                // New item
                self.txByHash[itemId] = txItem
                
                if let groupIndex = self.txItems.firstIndex(where: { $0.id == dateKey }) {
                    // Add to an existing date group
                    DispatchQueue.main.async {
                        self.txItems[groupIndex].items.append(txItem)
                        self.txItems[groupIndex].items.sort { $0.date > $1.date }
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
                    }
                }
            }
        }
    }

    
//    private func reloadTxDataSource() {
//        queue.async { [weak self] in
//            guard let self = self else { return }
//            let wallet = DWEnvironment.sharedInstance().currentWallet
//            let transactions = wallet.allTransactions
//            let transactions = wallet.allTransactions.sorted { tx1, tx2 in
//                let val1 = tx1.timestamp
//                let val2 = tx2.timestamp
//                    
//                switch (val1, val2) {
//                    case (0, 0): return false
//                    case (0, _): return true
//                    case (_, 0): return false
//                    default: return val1 > val2
//                }
//            }
            
//            var receivedNewTransaction = false
//            var allowedToShowReclassifyYourTransactions = false
//            var shouldAnimate = true
            
//            let prevTransaction = self.allDataSource.first // TODO
//            let newTransaction = transactions.first
//            
//            if prevTransaction == nil || prevTransaction === newTransaction {
//                shouldAnimate = false
//            }
//            
//            if let newTransaction = newTransaction, prevTransaction !== newTransaction {
//                receivedNewTransaction = true
//                
//                let dateReclassifyYourTransactionsFlowActivated = DWGlobalOptions.shared().dateReclassifyYourTransactionsFlowActivated
//                allowedToShowReclassifyYourTransactions = newTransaction.transactionDate.compare(dateReclassifyYourTransactionsFlowActivated) == .orderedDescending
//            }
            
//            transactions.forEach { tx in TODO: separate thread?
//                Tx.shared.updateRateIfNeeded(for: tx)
//            }
            
//            self.allDataSource = transactions
//            self.receivedDataSource = nil
//            self.sentDataSource = nil
            
            // Pre-filter while in background queue
//            switch self.displayMode {
//            case .received:
//                _ = self.receivedDataSource
//            case .sent:
//                _ = self.sentDataSource
//            case .rewards:
//                _ = self.rewardsDataSource
//            default:
//                break
//            }
            
//            let datasource = self.dataSource
//            
//            DispatchQueue.main.async {
//                self.setAllowedToShowReclassifyYourTransactions(allowedToShowReclassifyYourTransactions)
//                
//                if receivedNewTransaction {
//                    // TODO: try to do for all transactions
//                    if newTransaction?.direction == .received {
//                        self.updatesObserver?.homeModel(self, didReceiveNewIncomingTransaction: newTransaction!)
//                    }
//                }
//                self.updatesObserver?.homeModel(self, didUpdate: datasource, shouldAnimate: shouldAnimate)
//            }
//        }
//    }
    
    
    
    // TODO
//    - (NSArray<DSTransaction *> *)filterTransactions:(NSArray<DSTransaction *> *)allTransactions
//                                      forDisplayMode:(DWHomeTxDisplayMode)displayMode {
//        NSAssert(displayMode != DWHomeTxDisplayMode_All, @"All transactions should not be filtered");
//        if (displayMode == DWHomeTxDisplayMode_All) {
//            return allTransactions;
//        }
//
//        DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
//        NSMutableArray<DSTransaction *> *mutableTransactions = [NSMutableArray array];
//
//        for (DSTransaction *tx in allTransactions) {
//            uint64_t sent = [account amountSentByTransaction:tx];
//            if (displayMode == DWHomeTxDisplayMode_Sent && sent > 0) {
//                [mutableTransactions addObject:tx];
//            }
//            else if (displayMode == DWHomeTxDisplayMode_Received && sent == 0 && ![tx isKindOfClass:[DSCoinbaseTransaction class]]) {
//                [mutableTransactions addObject:tx];
//            }
//            else if (displayMode == DWHomeTxDisplayMode_Rewards && sent == 0 && [tx isKindOfClass:[DSCoinbaseTransaction class]]) {
//                [mutableTransactions addObject:tx];
//            }
//        }
//
//        return [mutableTransactions copy];
//    }
    
    
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
    
    private func recalculateHeight() {
        var height = kBaseBalanceHeaderHeight
        let hasNetwork = model.networkStatus == .online
        
        if !hasNetwork {
            height += 85
        }
        
        self.balanceHeaderHeight = height
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
            title: NSLocalizedString("Mixing", comment: "CoinJoin"),
            isOn: coinJoinService.mixingState.isInProgress,
            state: coinJoinService.mixingState,
            progress: coinJoinService.progress.progress,
            mixed: Double(coinJoinService.progress.coinJoinBalance) / Double(DUFFS),
            total: Double(coinJoinService.progress.totalBalance) / Double(DUFFS)
        )
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

// MARK: - DashPay

#if DASHPAY
extension HomeViewModel {
    private func observeDashPay() {
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .sink { [weak self] _ in
                self?.reloadTxDataSource()
                DWDashPayContactsUpdater.sharedInstance().beginUpdating()
            }
            .store(in: &cancellableBag)
    }
}
#endif

// MARK: - TransactionListDataItem

class TransactionGroup: Identifiable {
    let id: String
    let date: Date
    var items: [TransactionListDataItem]
    
    init(id: String, date: Date, items: [TransactionListDataItem]) {
        self.id = id
        self.date = date
        self.items = items
    }
}

enum TransactionListDataItem {
    case tx(Transaction)
    case crowdnode(FullCrowdNodeSignUpTxSet)
    case coinjoin(CoinJoinMixingTxSet)
}

extension TransactionListDataItem: Identifiable {
    var id: String {
        switch self {
        case .crowdnode(_):
            return FullCrowdNodeSignUpTxSet.id
        case .coinjoin(let set):
            return set.id
        case .tx(let tx):
            return tx.txHashHexString
        }
    }
    
    var date: Date {
        switch self {
        case .crowdnode(let set):
            return set.transactions.values.first!.date
        case .coinjoin(let set):
            return set.groupDay
        case .tx(let tx):
            return tx.date
        }
    }
}
