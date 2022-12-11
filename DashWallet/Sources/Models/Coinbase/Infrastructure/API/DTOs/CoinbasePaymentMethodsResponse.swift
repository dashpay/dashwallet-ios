//
//  CoinbasePaymentMethodsResponse.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation


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
    let primaryBuy: Bool
    let primarySell: Bool
    let instantBuy: Bool
    let instantSell: Bool

    let fiatAccount: FiatAccount?
    let verified: Bool
    let minimumPurchaseAmount: MinimumPurchaseAmount?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case currency
        case primaryBuy = "primary_buy"
        case primarySell = "primary_sell"
        case instantBuy = "instant_buy"
        case instantSell = "instant_sell"
        case allowBuy = "allow_buy"
        case allowSell = "allow_sell"
        case allowDeposit = "allow_deposit"
        case allowWithdraw = "allow_withdraw"
        case fiatAccount = "fiat_account"
        case verified
        case minimumPurchaseAmount = "minimum_purchase_amount"
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
    case achBankAccount = "ach_bank_account"
    case sepaBankAccount = "sepa_bank_account"
    case idealBankAccount = "ideal_bank_account"
    case fiatAccount = "fiat_account"
    case bankWire = "bank_wire"
    case creditCard = "credit_card"
    case secure3dCard = "secure3d_card"
    case eftBankAccount = "eft_bank_account"
    case interac
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case payPal = "paypal"

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
