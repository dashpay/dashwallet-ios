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

final class FullCrowdNodeSignUpTxSet: TransactionWrapper {
    private var matchedFilters: [CoinsToAddressTxFilter] = []

    var transactions: [Data: DSTransaction] = [:]

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
        if transactions[tx.txHashData] != nil {
            // Already included, return true
            return true
        }

        var crowdNodeTxFilters = [
            CrowdNodeRequest(requestCode: ApiCode.signUp),
            CrowdNodeResponse(responseCode: ApiCode.welcomeToApi, accountAddress: nil),
            CrowdNodeRequest(requestCode: ApiCode.acceptTerms),
            CrowdNodeResponse(responseCode: ApiCode.pleaseAcceptTerms, accountAddress: nil),
        ]
        
        if let accountAddress = CrowdNodeDefaults.shared.crowdNodeAccountAddress {
            crowdNodeTxFilters.append(CrowdNodeTopUpTx(address: accountAddress))
        }

        if let matchedFilter = crowdNodeTxFilters.first(where: { $0.matches(tx: tx) }) {
            transactions[tx.txHashData] = tx
            matchedFilters.append(matchedFilter)

            return true
        }

        return false
    }
}
