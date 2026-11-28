//
//  CoinbaseService.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Combine
import Foundation
import Moya

// MARK: - CoinbaseService

class CoinbaseService {
    private var httpClient: CoinbaseAPI {
        CoinbaseAPI.shared
    }
}

extension CoinbaseService {
    func getCoinbaseExchangeRates(currency: String) async throws -> CoinbaseExchangeRate {
        let result: BaseDataResponse<CoinbaseExchangeRate> = try await httpClient.request(.exchangeRates(currency))
        return result.data
    }
}
