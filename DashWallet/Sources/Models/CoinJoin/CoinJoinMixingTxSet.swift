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

final class CoinJoinMixingTxSet: TransactionWrapper {
    private var matchedFilters: [CoinJoinTxFilter] = []
    private let coinjoinTxFilters = [
        CoinJoinTxFilter.createDenomination,
        CoinJoinTxFilter.makeCollateral,
        CoinJoinTxFilter.mixingFee,
        CoinJoinTxFilter.mixing
    ]
    
    private(set) var amount: Int64 = 0
    var transactions: [Data: DSTransaction] = [:]
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

        if transactions[txHashData] != nil {
            transactions[txHashData] = tx
            // Already included, return true
            return true
        }

        if let matchedFilter = coinjoinTxFilters.first(where: { $0.matches(tx: tx) }) {
            if transactions.isEmpty {
                groupDay = tx.date
            } else if !Calendar.current.isDate(tx.date, inSameDayAs: groupDay) {
                return false
            }
            
            transactions[txHashData] = tx
            matchedFilters.append(matchedFilter)
            
            switch tx.direction {
            case .sent:
                amount -= Int64(tx.dashAmount)
            case .received:
                amount += Int64(tx.dashAmount)
            default:
                break
            }

            return true
        }

        return false
    }
}
