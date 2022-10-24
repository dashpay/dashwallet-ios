//  
//  Created by tkhp
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

import Foundation

enum CoinbaseEntryPointItem: CaseIterable {
    case buyDash
    case sellDash
    case convertCrypto
    case transferDash
}

extension CoinbaseEntryPointItem {
    var title: String
    {
        switch self {
            
        case .buyDash:
            return NSLocalizedString("Buy Dash", comment: "Coinbase Entry Point")
        case .sellDash:
            return NSLocalizedString("Sell Dash", comment: "Coinbase Entry Point")
        case .convertCrypto:
            return NSLocalizedString("Convert Crypto", comment: "Coinbase Entry Point")
        case .transferDash:
            return NSLocalizedString("Transfer Dash", comment: "Coinbase Entry Point")
        }
    }
    
    var description: String {
        switch self {
            
        case .buyDash:
            return NSLocalizedString("Receive directly into Dash Wallet", comment: "Coinbase Entry Point")
        case .sellDash:
            return NSLocalizedString("Receive directly into Coinbase", comment: "Coinbase Entry Point")
        case .convertCrypto:
            return NSLocalizedString("Between Dash Wallet and Coinbase", comment: "Coinbase Entry Point")
        case .transferDash:
            return NSLocalizedString("Between Dash Wallet and Coinbase", comment: "Coinbase Entry Point")
        }
    }
    
    var icon: String {
        switch self {
            
        case .buyDash:
            return "buyCoinbase"
        case .sellDash:
            return "sellDash"
        case .convertCrypto:
            return "convertCrypto"
        case .transferDash:
            return "transferCoinbase"
        }
    }
}

final class CoinbaseEntryPointModel {
    let items: [CoinbaseEntryPointItem] = CoinbaseEntryPointItem.allCases
}
