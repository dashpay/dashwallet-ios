//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

// MARK: - BasePaginationResponse

struct BasePaginationResponse<T: Codable>: Codable {
    let pagination: Pagination
    let data: [T]

    struct Pagination: Codable {
        let endingBefore: String?
        let previousEndingBefore: String?
        let nextStartingAfter: String?
        let startingAfter: String?
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
}

// MARK: - BaseDataResponse

struct BaseDataResponse<T: Codable>: Codable {
    let data: T
}

// MARK: - BaseDataCollectionResponse

struct BaseDataCollectionResponse<T: Codable>: Codable {
    let data: [T]
}

