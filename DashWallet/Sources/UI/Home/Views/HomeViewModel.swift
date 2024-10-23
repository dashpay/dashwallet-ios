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

@MainActor
class HomeViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let coinJoinService = CoinJoinService.shared
    private var timeSkewDialogShown: Bool = false
    
    static let shared: HomeViewModel = {
        return HomeViewModel()
    }()
    
    @Published private(set) var txItems: Array<(DateKey, [TransactionListDataItem])> = []
    @Published private(set) var balanceHeaderHeight: CGFloat = kBaseBalanceHeaderHeight // TDOO: move back to HomeView when fully transitioned to SwiftUI
    @Published private(set) var coinJoinItem = CoinJoinMenuItemModel(title: NSLocalizedString("Mixing", comment: "CoinJoin"), isOn: false, state: .notStarted, progress: 0.0, mixed: 0.0, total: 0.0)
    @Published var showTimeSkewAlertDialog: Bool = false
    @Published private(set) var timeSkew: TimeInterval = 0
    @Published var showJoinDashpay: Bool = true
    
    private var model: SyncModel = SyncModelImpl()
    
    var coinJoinMode: CoinJoinMode {
        get { coinJoinService.mode }
    }
    
    #if DASHPAY
    var shouldShowMixDashDialog: Bool {
        get { coinJoinService.mode == .none || !UsernamePrefs.shared.mixDashShown }
        set(value) { UsernamePrefs.shared.mixDashShown = !value }
    }
    #endif
    
    init() {
        model.networkStatusDidChange = { status in
            self.recalculateHeight()
        }
        self.recalculateHeight()
        self.observeCoinJoin()
    }
    
    func updateItems(transactions: [DSTransaction]) {
        Task.detached {
            let crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            var items: [TransactionListDataItem] = transactions.compactMap {
                if crowdNodeTxSet.isComplete { return .tx(Transaction(transaction: $0)) }
                
                return crowdNodeTxSet.tryInclude(tx: $0) ? nil : .tx(Transaction(transaction: $0))
            }

            if !crowdNodeTxSet.transactions.isEmpty {
                let crowdNodeTxs: [Transaction] = crowdNodeTxSet.transactions.values
                    .sorted { $0.date > $1.date }
                    .map { Transaction(transaction: $0) }
                
                items.insert(.crowdnode(crowdNodeTxs), at: 0)
            }

            let groupedItems = Dictionary(
                grouping: items.sorted(by: { $0.date > $1.date }),
                by: { DateKey(key: DWDateFormatter.sharedInstance.dateOnly(from: $0.date), date: $0.date) }
            )
            
            let arary = groupedItems.sorted(by: { kv1, kv2 in
                kv1.key.date > kv2.key.date
            })

            DispatchQueue.main.async {
                self.txItems = arary
            }
        }
    }
    
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

// MARK: - TransactionListDataItem

enum TransactionListDataItem {
    case tx(Transaction)
    case crowdnode([Transaction])
}

extension TransactionListDataItem: Identifiable {
    var tx: Transaction {
        switch self {
        case .crowdnode(let txs):
            return txs.first!
        case .tx(let tx):
            return tx
        }
    }
    
    var id: String {
        switch self {
        case .crowdnode(let txs):
            return txs.first!.txHashHexString
        case .tx(let tx):
            return tx.txHashHexString
        }
    }
    
    var date: Date {
        switch self {
        case .crowdnode(let txs):
            return txs.last!.date
        case .tx(let tx):
            return tx.date
        }
    }
}

struct DateKey: Hashable {
    let key: String
    let date: Date
    
    static func == (lhs: DateKey, rhs: DateKey) -> Bool {
        return lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

extension FullCrowdNodeSignUpTxSet {
    var isComplete: Bool {
        transactions.count == 5
    }
}
