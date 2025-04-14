import Foundation

// Request Models
struct LoginRequest: Codable {
    let email: String
}

struct VerifyEmailRequest: Codable {
    let email: String
    let code: String
}

struct PurchaseGiftCardRequest: Codable {
    let cryptoCurrency: String
    let fiatCurrency: String
    let fiatAmount: String
    let merchantId: String
}

// Response Models
struct VerifyEmailResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct GiftCardResponse: Codable {
    let giftCardId: String
    let dashAmount: String
    let dashTxUrl: String
    let checkoutUrl: String
}

struct MerchantResponse: Codable {
    let savingsPercentage: Double
    let minimumCardPurchase: Double
    let maximumCardPurchase: Double
} 