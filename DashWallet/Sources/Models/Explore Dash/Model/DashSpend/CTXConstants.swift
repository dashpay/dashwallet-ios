//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

class CTXConstants {
    /// Returns the appropriate CTX API base URL based on the current network
    /// - Mainnet: https://spend.ctx.com/
    /// - Testnet: http://staging.spend.ctx.com/
    static var baseURI: String {
        let environment = DWEnvironment.sharedInstance()
        let isTestnet = environment.currentChain.isTestnet()

        let url: String
        if isTestnet {
            url = "https://staging.spend.ctx.com/"  // Changed from http to https
        } else {
            url = "https://spend.ctx.com/"
        }

        DSLogger.log("🔍 CTXConstants.baseURI - isTestnet: \(isTestnet), URL: \(url)")
        return url
    }

    static let termsAndConditionsUrl = "https://ctx.com/gift-card-agreement/"
    static let supportEmail = "support@ctx.com"
}
