//
//  CoinbasePaymentMethodsResponse.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinbasePaymentMethodsResponse

struct CoinbasePaymentMethodsResponse: Codable {
    let paymentMethods: [CoinbasePaymentMethod]
    
    enum CodingKeys: String, CodingKey {
        case paymentMethods = "payment_methods"
    }
}

// MARK: - CoinbasePaymentMethod + Equatable

extension CoinbasePaymentMethod: Equatable {
    static func == (lhs: CoinbasePaymentMethod, rhs: CoinbasePaymentMethod) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CoinbasePaymentMethod

struct CoinbasePaymentMethod: Codable {
    let id: String
    let name: String
    let type: PaymentMethodType
    let allowBuy: Bool
    let allowSell: Bool
    let allowDeposit: Bool
    let allowWithdraw: Bool
    let currency: String?
    let updatedAt: String?
    let createdAt: String?
    let verified: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case currency
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case allowBuy = "allow_buy"
        case allowSell = "allow_sell"
        case allowDeposit = "allow_deposit"
        case allowWithdraw = "allow_withdraw"
        case verified
    }
}

// MARK: - FiatAccount

struct FiatAccount: Codable {
    let id: String?
    let resource: String?
    let resourcePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case resource
        case resourcePath = "resource_path"
    }
}

// MARK: - MinimumPurchaseAmount

struct MinimumPurchaseAmount: Codable {
    let amount, currency: String?
}

// MARK: - PaymentMethodType

public enum PaymentMethodType: String, Codable {
    case achBankAccount = "ACH"
    case sepaBankAccount = "SEPA"
    case idealBankAccount = "IDEAL"
    case fiatAccount = "COINBASE_FIAT_ACCOUNT"
    case bankWire = "BANK_WIRE"
    case creditCard = "CREDIT_CARD"
    case secure3dCard = "SECURE3D_CARD"
    case eftBankAccount = "EFT"
    case interac = "INTERAC"
    case applePay = "APPLE_PAY"
    case googlePay = "GOOGLE_PAY"
    case payPal = "PAYPAL"

    var displayString: String {
        switch self {
        case .achBankAccount, .sepaBankAccount, .idealBankAccount, .eftBankAccount:
            return NSLocalizedString("Bank Account", comment: "Coinbase/Payment Methods")
        case .fiatAccount:
            return NSLocalizedString("Fiat Account", comment: "Coinbase/Payment Methods")
        case .bankWire:
            return NSLocalizedString("Bank Wire", comment: "Coinbase/Payment Methods")
        case .creditCard:
            return NSLocalizedString("Credit Card", comment: "Coinbase/Payment Methods")
        case .secure3dCard:
            return NSLocalizedString("Credit Card", comment: "Coinbase/Payment Methods")
        case .interac:
            return NSLocalizedString("Interac", comment: "Coinbase/Payment Methods")
        case .applePay:
            return NSLocalizedString("Apple Pay", comment: "Coinbase/Payment Methods")
        case .googlePay:
            return NSLocalizedString("Google Pay", comment: "Coinbase/Payment Methods")
        case .payPal:
            return NSLocalizedString("PayPal", comment: "Coinbase/Payment Methods")
        }
    }

    var showNameLabel: Bool {
        switch self {
        case .achBankAccount, .sepaBankAccount, .idealBankAccount, .eftBankAccount:
            return true
        case .fiatAccount:
            return true
        case .bankWire:
            return true
        case .creditCard:
            return true
        case .secure3dCard:
            return true
        case .interac, .applePay, .googlePay:
            return false
        case .payPal:
            return false
        }
    }
}

extension PaymentMethodType {
    var isBankAccount: Bool {
        get {
            switch self {
            case .achBankAccount, .sepaBankAccount, .idealBankAccount, .eftBankAccount:
                return true
            default:
                return false
            }
        }
    }
}
