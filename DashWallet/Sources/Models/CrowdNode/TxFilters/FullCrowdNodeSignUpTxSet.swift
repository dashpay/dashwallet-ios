//
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

final class FullCrowdNodeSignUpTxSet: GroupedTransactions, TransactionWrapper {
    var title: String {
        NSLocalizedString("CrowdNode · Account", comment: "CrowdNode")
    }
    
    var iconName: String {
        "tx.item.cn.icon"
    }
    
    var infoText: String {
        NSLocalizedString("Your CrowdNode account was created using these transactions.", comment: "Crowdnode")
    }
    
    var fiatAmount: String {
        (try? CurrencyExchanger.shared.convertDash(amount: UInt64(abs(amount)).dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }
    
    static let id = "FullCrowdNodeSignUpTxSet"
    private let savedAccountAddress = CrowdNodeDefaults.shared.accountAddress
    private let januaryFirst2022 = 1640995200.0 // Safe to assume there weren't any CrowdNode accounts before this point
    private var matchedFilters: [CoinsToAddressTxFilter] = []
    private let txMapLock = NSLock()

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
    private var _amount: Int64 = 0
    var amount: Int64 { _amount }
    
    var isComplete: Bool {
        txMapLock.lock()
        defer { txMapLock.unlock() }
        return _transactionMap.count == 5
    }

    var welcomeToApiResponse: CoinsToAddressTxFilter? {
        matchedFilters.first { filter in
            (filter as? CrowdNodeResponse)?.responseCode == ApiCode.welcomeToApi
        }
    }

    var acceptTermsRequest: CoinsToAddressTxFilter? {
        matchedFilters.first { filter in
            (filter as? CrowdNodeRequest)?.requestCode == ApiCode.acceptTerms
        }
    }

    var acceptTermsResponse: CoinsToAddressTxFilter? {
        matchedFilters.first { filter in
            (filter as? CrowdNodeResponse)?.responseCode == ApiCode.pleaseAcceptTerms
        }
    }

    var signUpRequest: CoinsToAddressTxFilter? {
        matchedFilters.first { filter in
            (filter as? CrowdNodeRequest)?.requestCode == ApiCode.signUp
        }
    }

    @discardableResult
    func tryInclude(tx: DSTransaction) -> Bool {
        if tx.timestamp < januaryFirst2022 {
            return false
        }

        let txHashData = tx.txHashData

        txMapLock.lock()
        if _transactionMap[txHashData] != nil {
            _transactionMap[txHashData] = Transaction(transaction: tx)
            txMapLock.unlock()
            // Already included, return true
            return true
        }
        txMapLock.unlock()

        var crowdNodeTxFilters = [
            CrowdNodeRequest(requestCode: ApiCode.signUp),
            CrowdNodeResponse(responseCode: ApiCode.welcomeToApi, accountAddress: nil),
            CrowdNodeRequest(requestCode: ApiCode.acceptTerms),
            CrowdNodeResponse(responseCode: ApiCode.pleaseAcceptTerms, accountAddress: nil),
        ]

        if let accountAddress = savedAccountAddress {
            crowdNodeTxFilters.append(CrowdNodeTopUpTx(address: accountAddress))
        }

        if let matchedFilter = crowdNodeTxFilters.first(where: { $0.matches(tx: tx) }) {
            txMapLock.lock()
            _transactionMap[txHashData] = Transaction(transaction: tx)
            txMapLock.unlock()
            
            matchedFilters.append(matchedFilter)
            
            let dashAmount = tx.dashAmount
            switch tx.direction {
            case .sent:
                _amount -= Int64(dashAmount)
            case .received:
                _amount += Int64(dashAmount)
            default:
                break
            }

            return true
        }

        return false
    }
}
