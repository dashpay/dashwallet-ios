//
//  CoinbaseAccountAddress.swift
//  Coinbase
//
//  Created by hadia on 02/06/2022.
//

import Foundation

// MARK: - Datum

struct CoinbaseAccountAddress: Codable {
    let id: String?
    let address: String
    let name: String?
    let network: String?
    let uriScheme: String?
    let resource: String?
    let resourcePath: String?
    let qrCodeImageURL: String?
    let addressLabel, depositURI: String?

    enum CodingKeys: String, CodingKey {
        case id
        case address
        case name
        case network
        case uriScheme = "uri_scheme"
        case resource
        case resourcePath = "resource_path"
        case qrCodeImageURL = "qr_code_image_url"
        case addressLabel = "address_label"
        case depositURI = "deposit_uri"
    }
}
