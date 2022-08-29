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
import CoreLocation

class BaseAtmsDataProvider: ExplorePointOfUseDataProvider {
    var types: [ExplorePointOfUse.Atm.`Type`]? { return nil }
    
    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        
        guard let bounds = bounds, let userLocation = userPoint, DWLocationManager.shared.isAuthorized else {
            items = []
            currentPage = nil
            completion(.success(items))
            return
        }
        
        if lastQuery == query && !items.isEmpty && lastBounds == bounds {
            completion(.success(items))
            return
        }
        
        lastQuery = query
        lastUserPoint = userLocation
        lastBounds = bounds
        
        fetch(by: query, in: bounds, userPoint: userLocation, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }
    
    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, in: lastBounds, userPoint: lastUserPoint, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }
    
    private func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.atms(query: query, in: types, in: bounds, userPoint: userPoint, offset: offset, completion: completion)
    }
}

class AllAtmsDataProvider: BaseAtmsDataProvider {
    
}

class BuyAtmsDataProvider: BaseAtmsDataProvider {
    override var types: [ExplorePointOfUse.Atm.`Type`] { return [.buy] }
}

class BuyAndSellAtmsDataProvider: BaseAtmsDataProvider {
    override var types: [ExplorePointOfUse.Atm.`Type`] { return [.buySell] }
}


