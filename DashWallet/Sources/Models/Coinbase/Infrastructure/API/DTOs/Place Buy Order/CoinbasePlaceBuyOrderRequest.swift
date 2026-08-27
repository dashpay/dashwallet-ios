//
//  CoinBasePlaceBuyOrderRequest.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinbasePlaceOrderParams

public struct CoinbasePlaceBuyOrderRequest: Codable {
    var clientOrderId: UUID
    var productId: String
    var side: String
    var orderConfiguration: OrderConfiguration
    
    enum CodingKeys: String, CodingKey {
        case clientOrderId = "client_order_id"
        case productId = "product_id"
        case side
        case orderConfiguration = "order_configuration"
    }
}

public struct OrderConfiguration: Codable {
    var marketMarketIoc: MarketMarketIoc
    
    enum CodingKeys: String, CodingKey {
        case marketMarketIoc = "market_market_ioc"
    }
}

public struct MarketMarketIoc: Codable {
    var quoteSize: String
    
    enum CodingKeys: String, CodingKey {
        case quoteSize = "quote_size"
    }
}
