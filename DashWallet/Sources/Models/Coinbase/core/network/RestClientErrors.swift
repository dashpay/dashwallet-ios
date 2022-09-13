//
//  RestClientErrors.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation

enum RestClientErrors: Error {
    case requestFailed(error: Error)
    case requestFailed(code: Int)
    case noDataReceived
    case jsonDecode(error: Error)
}
