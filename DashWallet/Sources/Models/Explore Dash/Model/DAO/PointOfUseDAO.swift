//  
//  Created by Pavel Tikhonenko
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

let pageLimit = 100

struct PaginationResult<Item> {
    var items: [Item]
    var offset: Int
}

enum PointOfUseDAOFilterKey: Int {
    case radius
    case query
    case userLocation
    case bounds
    case types
    case territory
    case sortDirection
}

typealias PointOfUseDAOFilters = [PointOfUseDAOFilterKey: Any?]

protocol PointOfUseDAO {
    associatedtype Item
    
    func items(filters: PointOfUseDAOFilters, offset: Int?, completion: @escaping (Swift.Result<PaginationResult<Item>, Error>) -> Void)
}
