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
    override var title: String {
        NSLocalizedString("Mixing Transactions", comment: "CoinJoin")
    }
    
    override var iconName: String {
        "tx.item.coinjoin.icon"
    }
    
    override var infoText: String {
        NSLocalizedString("You Dash was mixed using these transactions.", comment: "CoinJoin")
    }
    
    override var fiatAmount: String {
        (try? CurrencyExchanger.shared.convertDash(amount: (UInt64(abs(amount))).dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }
    
    private let chain = DWEnvironment.sharedInstance().currentChain
    private let account = DWEnvironment.sharedInstance().currentAccount
    private let amountQueue = DispatchQueue(label: "CoinJoinMixingSet.amount", qos: .utility)
    private let amountLock = NSLock()
    private var _amount: Int64 = 0
    override var amount: Int64 {
        amountLock.lock()
        defer { amountLock.unlock() }
        return _amount
    }

    var transactionMap: [Data: Transaction] = [:]
    override var transactions: [Transaction] {
        get {
            return transactionMap.values.map { $0 }.sorted { tx1, tx2 in
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
        let existing = transactionMap[txHashData] as? CoinJoinTransaction
        
        if existing != nil {
            transactionMap[txHashData] = CoinJoinTransaction(transaction: tx, type: existing!.type)
            // Already included, return true
            return true
        }
        
        let type = DSCoinJoinWrapper.coinJoinTxType(for: tx, account: account)
        
        if type == CoinJoinTransactionType_None {
            return false
        }
        
        if transactions.isEmpty {
            groupDay = tx.date
        } else if !Calendar.current.isDate(tx.date, inSameDayAs: groupDay) {
            return false
        }
        
        transactionMap[txHashData] = CoinJoinTransaction(transaction: tx, type: type)
            
        amountQueue.async { [weak self] in
            guard let self = self else { return }
            self.amountLock.lock()
            
            switch type {
            case CoinJoinTransactionType_MixingFee,
                 CoinJoinTransactionType_CreateDenomination,
                 CoinJoinTransactionType_MakeCollateralInputs:
                let fee = tx.feeUsed
                self._amount -= (fee > 0 && fee <= Int64.max ? Int64(fee) : 0)
            default:
                break
            }
            
            self.amountLock.unlock()
        }

        return true
    }
}
