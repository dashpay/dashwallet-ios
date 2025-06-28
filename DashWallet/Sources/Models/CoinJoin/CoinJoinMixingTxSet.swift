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

final class CoinJoinMixingTxSet: GroupedTransactions, TransactionWrapper {
    var title: String {
        NSLocalizedString("Mixing Transactions", comment: "CoinJoin")
    }
    
    var iconName: String {
        "tx.item.coinjoin.icon"
    }
    
    var infoText: String {
        NSLocalizedString("You Dash was mixed using these transactions.", comment: "CoinJoin")
    }
    
    var fiatAmount: String {
        (try? CurrencyExchanger.shared.convertDash(amount: (UInt64(abs(amount))).dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }
    
    private let chain = DWEnvironment.sharedInstance().currentChain
    private let account = DWEnvironment.sharedInstance().currentAccount
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

    @discardableResult
    func tryInclude(tx: DSTransaction) -> Bool {
        let txHashData = tx.txHashData
        
        txMapLock.lock()
        let existing = _transactionMap[txHashData] as? CoinJoinTransaction
        
        if existing != nil {
            _transactionMap[txHashData] = CoinJoinTransaction(transaction: tx, type: existing!.type)
            txMapLock.unlock()
            // Already included, return true
            return true
        }
        
        let type = DSCoinJoinWrapper.coinJoinTxType(for: tx, account: account)
        
        if type == CoinJoinTransactionType_None || type == CoinJoinTransactionType_Send {
            txMapLock.unlock()
            return false
        }
        
        let isEmpty = _transactionMap.isEmpty
        txMapLock.unlock()
        
        if isEmpty {
            groupDay = tx.date
        } else if !Calendar.current.isDate(tx.date, inSameDayAs: groupDay) {
            return false
        }
        
        txMapLock.lock()
        _transactionMap[txHashData] = CoinJoinTransaction(transaction: tx, type: type)
        txMapLock.unlock()
            
        amountQueue.async { [weak self] in
            guard let self = self else { return }
            self.amountLock.lock()
            defer { self.amountLock.unlock() }
            
            switch type {
            case CoinJoinTransactionType_MixingFee,
                 CoinJoinTransactionType_CreateDenomination,
                 CoinJoinTransactionType_MakeCollateralInputs:
                let fee = tx.feeUsed
                self._amount -= (fee > 0 && fee <= Int64.max ? Int64(fee) : 0)
            default:
                break
            }
        }

        return true
    }
}
