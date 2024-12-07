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

struct CoinJoinTxFilter: TransactionFilter {
    let type: CoinJoinTransactionType
    
    init(type: CoinJoinTransactionType) {
        self.type = type
    }
    
    func matches(tx: DSTransaction) -> Bool {
        return DSCoinJoinWrapper.coinJoinTxType(for: tx) == self.type
    }
    
    static let createDenomination = CoinJoinTxFilter(type: CoinJoinTransactionType_CreateDenomination)
    static let makeCollateral = CoinJoinTxFilter(type: CoinJoinTransactionType_MakeCollateralInputs)
    static let mixingFee = CoinJoinTxFilter(type: CoinJoinTransactionType_MixingFee)
    static let mixing = CoinJoinTxFilter(type: CoinJoinTransactionType_Mixing)
}
