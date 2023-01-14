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

    func tryInclude(tx: DSTransaction) {
        if transactions[tx.txHashData] != nil {
            // Already included
            return
        }
        
        let signUpRequestFilter = CrowdNodeRequest(requestCode: ApiCode.signUp)
        let crowdNodeTxFilters = [
            CrowdNodeResponse(responseCode: ApiCode.welcomeToApi, accountAddress: nil),
            CrowdNodeRequest(requestCode: ApiCode.acceptTerms),
            CrowdNodeResponse(responseCode: ApiCode.pleaseAcceptTerms, accountAddress: nil),
        ]

        if signUpRequestFilter.matches(tx: tx) {
            let chain = DWEnvironment.sharedInstance().currentChain
            guard let possibleTopUpTx = chain.transaction(forHash: tx.inputs.first!.inputHash) else { return }
            // TopUp transaction can only be matched if we know the account address
            let topUpFilter = CrowdNodeTopUpTx(address: signUpRequestFilter.fromAddresses.first!)

            if topUpFilter.matches(tx: possibleTopUpTx) {
                transactions[possibleTopUpTx.txHashData] = possibleTopUpTx
                transactions[tx.txHashData] = tx
                matchedFilters.append(topUpFilter)
                matchedFilters.append(signUpRequestFilter)
            }

            return
        }

        if let matchedFilter = crowdNodeTxFilters.first(where: { $0.matches(tx: tx) }) {
            transactions[tx.txHashData] = tx
            matchedFilters.append(matchedFilter)
        }
    }
}
