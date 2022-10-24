//
//  Pagination.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation

// MARK: - Pagination
struct Pagination: Codable {
    let endingBefore, startingAfter, previousEndingBefore, nextStartingAfter: String?
    let limit: Int?
    let order, previousURI, nextURI: String?

    enum CodingKeys: String, CodingKey {
        case endingBefore = "ending_before"
        case startingAfter = "starting_after"
        case previousEndingBefore = "previous_ending_before"
        case nextStartingAfter = "next_starting_after"
        case limit, order
        case previousURI = "previous_uri"
        case nextURI = "next_uri"
    }
}
