//
//  CoinBasePlaceBuyOrderResponse.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinbasePlaceBuyOrder

struct CoinbasePlaceBuyOrder: Codable {
    let success: Bool
    let failureReason: String?
    let clientOrderId: String?
    let errorResponse: ErrorResponse?
    let successResponse: SuccessResponse?
    let orderConfiguration: OrderConfiguration?
    
    enum CodingKeys: String, CodingKey {
        case success
        case failureReason = "failure_reason"
        case clientOrderId = "client_order_id"
        case errorResponse = "error_response"
        case successResponse = "success_response"
        case orderConfiguration = "order_configuration"
    }
}

struct SuccessResponse: Codable {
    let orderId: String
    let productId: String
    let side: String
    let clientOrderId: String
    
    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case productId = "product_id"
        case side
        case clientOrderId = "client_order_id"
    }
}

struct ErrorResponse: Codable {
    let error: String
    let message: String
    let errorDetails: String
    let previewFailureReason: String
    
    enum CodingKeys: String, CodingKey {
        case error
        case message
        case errorDetails = "error_details"
        case previewFailureReason = "preview_failure_reason"
    }
}
