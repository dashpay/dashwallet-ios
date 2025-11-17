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

class PiggyCardsConstants {
    static let baseURI = "https://api.piggy.cards/dash/v1/"
    static let stagingBaseURI = "https://apidev.piggy.cards/dash/v1/" // For future testnet support

    static let termsAndConditionsUrl = "https://piggy.cards/index.php?route=information/information&information_id=5"
    static let supportEmail = "support@piggy.cards"

    // Service configuration
    static let tokenExpirationSeconds = 3600
    static let serviceFeePercent = 1.5 // 1.5% service fee deducted from discount
    static let orderPollingDelayMs = 250 // Delay before first status check
}
