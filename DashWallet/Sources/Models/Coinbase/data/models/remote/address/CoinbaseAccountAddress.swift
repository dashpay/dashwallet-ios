//
//  CoinbaseAccountAddress.swift
//  Coinbase
//
//  Created by hadia on 02/06/2022.
//

import Foundation

// MARK: - Datum
struct CoinbaseAccountAddress: Codable {
    let id, address: String?
    let addressInfo: AddressInfo?
    let name: String?
    let createdAt, updatedAt: Date?
    let network, uriScheme, resource, resourcePath: String?
    let qrCodeImageURL: String?
    let addressLabel, depositURI: String?

    enum CodingKeys: String, CodingKey {
        case id, address
        case addressInfo = "address_info"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case network
        case uriScheme = "uri_scheme"
        case resource
        case resourcePath = "resource_path"
        case qrCodeImageURL = "qr_code_image_url"
        case addressLabel = "address_label"
        case depositURI = "deposit_uri"
    }
}
