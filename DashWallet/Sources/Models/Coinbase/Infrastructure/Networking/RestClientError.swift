//
//  RestClientErrors.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation

enum RestClientError: Error {
    case requestFailed(code: Int)
    case noDataReceived
    case jsonDecode(error: Error)
}
