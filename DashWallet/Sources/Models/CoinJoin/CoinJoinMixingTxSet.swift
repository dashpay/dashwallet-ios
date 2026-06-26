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

final class CoinJoinMixingTxSet: GroupedTransactions {
    var title: String {
        NSLocalizedString("Mixing Transactions", comment: "CoinJoin")
    }
    
    var iconName: String {
        "tx.item.coinjoin.icon"
    }
    
    var infoText: String {
        NSLocalizedString("Your Dash was mixed using these transactions.", comment: "CoinJoin") // MO-720 BEF
    }
    
    var fiatAmount: String {
        (try? CurrencyExchanger.shared.convertDash(amount: (UInt64(abs(amount))).dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }
    
    private let chain = DWEnvironment.sharedInstance().currentChain
    private let amountQueue = DispatchQueue(label: "CoinJoinMixingSet.amount", qos: .utility)
    private let amountLock = NSLock()
    private let txMapLock = NSLock()
    private var _amount: Int64 = 0
    var amount: Int64 {
        return _amount
    }

    private var _transactionMap: [Data: Transaction] = [:]
    var transactionMap: [Data: Transaction] {
        txMapLock.lock()
        defer { txMapLock.unlock() }
        return _transactionMap
    }
    var transactions: [Transaction] {
        get {
            txMapLock.lock()
            defer { txMapLock.unlock() }
            return _transactionMap.values.map { $0 }.sorted { tx1, tx2 in
                tx1.date > tx2.date
            }
        }
    }
    
    var id: String = "coinjoin"
    var groupDay: Date = Date.now {
        didSet {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            id = "coinjoin-\(dateFormatter.string(from: groupDay))"
        }
    }

    /// Includes a SwiftDashSDK-sourced CoinJoin mixing transaction. SDK rows
    /// carry no `DSTransaction`, but the wallet already classifies them by
    /// CoinJoin-account membership, so we gate on `Transaction.isCoinJoinMixing`
    /// (a tx with ≥1 output owned by the CoinJoin account — see
    /// `SwiftDashSDKWalletSource.isCoinJoinMixingTx`) and store the wrapper directly.
    /// Per-calendar-day grouping. A `CoinJoinMixingTxSet` is rebuilt from scratch
    /// on every full `reloadTxDataSource`, so `_amount` accumulates each tx
    /// exactly once per build (no cross-reload double count).
    @discardableResult
    func tryInclude(_ tx: Transaction) -> Bool {
        guard tx.isCoinJoinMixing else { return false }

        let key = tx.txHashData

        txMapLock.lock()
        if _transactionMap[key] != nil {
            // Already in this build — refresh the stored wrapper (state may have
            // advanced, e.g. mempool → confirmed) without re-counting the amount.
            _transactionMap[key] = tx
            txMapLock.unlock()
            return true
        }
        let isEmpty = _transactionMap.isEmpty
        txMapLock.unlock()

        if isEmpty {
            groupDay = tx.date
        } else if !Calendar.current.isDate(tx.date, inSameDayAs: groupDay) {
            return false
        }

        txMapLock.lock()
        _transactionMap[key] = tx
        txMapLock.unlock()

        amountLock.lock()
        _amount += (tx.sdkNetAmount ?? 0)
        amountLock.unlock()

        return true
    }
}
