//
//  Endpoint.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation

protocol Endpoint {
    var url: URL { get }
    var path: String { get }
}
