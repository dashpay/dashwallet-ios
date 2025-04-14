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
