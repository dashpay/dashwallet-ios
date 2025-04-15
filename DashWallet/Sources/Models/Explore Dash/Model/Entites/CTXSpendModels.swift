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

// Request Models
public struct LoginRequest: Codable {
    let email: String
}

public struct VerifyEmailRequest: Codable {
    let email: String
    let code: String
}

public struct PurchaseGiftCardRequest: Codable {
    let cryptoCurrency: String
    let fiatCurrency: String
    let fiatAmount: String
    let merchantId: String
}

// Response Models
public struct VerifyEmailResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

public struct GiftCardResponse: Codable {
    let giftCardId: String
    let dashAmount: String
    let dashTxUrl: String
    let checkoutUrl: String
}

public struct MerchantResponse: Codable {
    let savingsPercentage: Double
    let minimumCardPurchase: Double
    let maximumCardPurchase: Double
} 
