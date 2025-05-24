import Foundation

// MARK: - Request Models

struct LoginRequest: Codable {
    let email: String
}

struct VerifyEmailRequest: Codable {
    let email: String
    let code: String
}

public struct PurchaseGiftCardRequest: Codable {
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
    let id: String
    let percentDiscount: String
    let paymentCryptoAmount: String
    let cardFiatAmount: String
    let cardFiatCurrency: String
    let paymentUrls: [String: String]
    let paymentCryptoCurrency: String
    let paymentCryptoNetwork: String
    let paymentFiatCurrency: String
    let userId: String
    let merchantName: String
    let userEmail: String
    let created: String
    let rate: String
    let paymentFiatAmount: String
    let status: String
    let paymentId: String
}

struct MerchantResponse: Codable {
    let id: String
    let name: String
    let logoUrl: String
    let enabled: Bool
    let savingsPercentage: Int
    let denominationsType: String
    let denominations: [String]
    let cachedLocationCount: Int
    let mapPinUrl: String
    let type: String
    let redeemType: String
    let info: MerchantInfo
    let cardImageUrl: String
    let currency: String
    
    // Computed properties for backward compatibility
    var website: String {
        return "" // This field doesn't exist in the response
    }
    
    var minimumCardPurchase: Double {
        guard denominations.count >= 1, let min = Double(denominations[0]) else { return 0.0 }
        return min
    }
    
    var maximumCardPurchase: Double {
        guard denominations.count >= 2, let max = Double(denominations[1]) else { return 0.0 }
        return max
    }
    
    var denominationType: DenominationType {
        switch denominationsType {
        case "min-max":
            return .Range
        default:
            return .Fixed
        }
    }
}

struct MerchantInfo: Codable {
    let terms: String
    let description: String
    let instructions: String
    let intro: String
}

enum DenominationType: String, Codable {
    case Range = "range"
    case Fixed = "fixed"
} 
