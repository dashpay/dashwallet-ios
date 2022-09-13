//
//  File.swift
//  Coinbase
//
//  Created by hadia on 02/06/2022.
//

import Foundation
// MARK: - CoinbaseAccountAddressesResponse
struct CoinbaseAccountAddressesResponse: Codable {
    let pagination: Pagination?
    let data: [CoinbaseAccountAddress]?
}
