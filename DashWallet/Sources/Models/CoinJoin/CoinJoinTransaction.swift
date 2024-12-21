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

class CoinJoinTransaction: Transaction {
    let type: CoinJoinTransactionType
    
    init(transaction: DSTransaction, type: CoinJoinTransactionType) {
        self.type = type
        super.init(transaction: transaction)
    }
    
    override var stateTitle: String {
        switch type {
        case CoinJoinTransactionType_CreateDenomination:
            NSLocalizedString("CoinJoin Create Denominations", comment: "CoinJoin")
        case CoinJoinTransactionType_MakeCollateralInputs:
            NSLocalizedString("CoinJoin Collateral Inputs", comment: "CoinJoin")
        case CoinJoinTransactionType_MixingFee:
            NSLocalizedString("CoinJoin Mixing Fee", comment: "CoinJoin")
        case CoinJoinTransactionType_Mixing:
            NSLocalizedString("CoinJoin Mixing", comment: "CoinJoin")
        case CoinJoinTransactionType_Send:
            NSLocalizedString("CoinJoin Send", comment: "CoinJoin")
        default:
            ""
        }
    }
    
    override var iconName: String {
        switch type {
        case CoinJoinTransactionType_MixingFee, CoinJoinTransactionType_Send:
            "tx.item.sent.icon"
        default:
            "tx.item.internal.icon"
        }
    }
}
