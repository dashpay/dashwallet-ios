import Foundation

// MARK: - Request Models

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

// MARK: - Response Models

struct VerifyEmailResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct GiftCardResponse: Codable {
    let cryptoCurrency: String
    let fiatCurrency: String
    let fiatAmount: String
    let merchantName: String
    let merchantId: String
    let iconUrl: String?
    let barcode: String?
    let barcodeType: String?
    let dashPaymentUrl: String
    let dashAmount: String
    let claimCode: String?
    let status: String
    let txid: String?
    let createdAt: String
}

struct MerchantResponse: Codable {
    let id: String
    let name: String
    let website: String
    let logoUrl: String
    let enabled: Bool
    let minimumCardPurchase: Double
    let maximumCardPurchase: Double
    let savingsPercentage: Double
    let denominationType: DenominationType
    let denominations: [Double]
    
    enum CodingKeys: String, CodingKey {
        case id, name, website, enabled
        case logoUrl = "logoLocation"
        case minimumCardPurchase, maximumCardPurchase
        case savingsPercentage, denominationType, denominations
    }
}

enum DenominationType: String, Codable {
    case Range = "range"
    case Fixed = "fixed"
} 