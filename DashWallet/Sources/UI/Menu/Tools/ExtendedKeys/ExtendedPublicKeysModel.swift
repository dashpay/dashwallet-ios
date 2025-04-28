//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - ExtendedPublicKeysModel

final class ExtendedPublicKeysModel {
    let derivationPaths: [DSDerivationPath]

    init() {
        let currentAccount = DWEnvironment.sharedInstance().currentAccount
        derivationPaths = currentAccount.fundDerivationPaths ?? []
    }
}

extension DSDerivationPath {
    var item: DerivationPathKeysItem {
        let title: String

        if let dp = self as? DSIncomingFundsDerivationPath,
           let username = dp.chain.identity(forUniqueId: dp.contactDestinationIdentityUniqueId, foundIn: nil, includeForeignIdentities: true).currentDashpayUsername {
            title = username
        } else {
            title = referenceName
        }
        
        let value = DSDerivationPathFactory.serializedExtendedPublicKey(self) ?? NSLocalizedString("Not available", comment: "")

        return DerivationPathKeysItem(title: title, value: value)
    }
}
