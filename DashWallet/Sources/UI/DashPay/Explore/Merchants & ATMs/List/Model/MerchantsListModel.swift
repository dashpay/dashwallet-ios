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

enum MerchantsListSegment: Int {
    case online = 0
    case nearby
    case all
}

extension MerchantsListSegment {
    var title: String {
        switch self {
        case .online:
            return NSLocalizedString("Online", comment: "Online")
        case .nearby:
            return NSLocalizedString("Nearby", comment: "Nearby")
        case .all:
            return NSLocalizedString("All", comment: "All")
        }
    }
}

class MerchantsListModel {
    private var lastQuery: String?
    private var isFetching: Bool = false
    
    private let onlineMerchantsDataProvider: OnlineMerchantsDataProvider
    private let nearbyMerchantsDataProvider: NearbyMerchantsDataProvider
    private let allMerchantsDataProvider: AllMerchantsDataProvider
    
    var items: [ExplorePointOfUse] = []
    var itemsDidChange: (() -> Void)?
    var nextPageDidLoaded: ((_ offset: Int, _ count: Int) -> Void)?
    
    var segments: [MerchantsListSegment] = []
    var segmentTitles: [String] { return segments.map { $0.title } }
    
    var currentSegment: MerchantsListSegment {
        didSet {
            segmentDidUpdate()
        }
    }
    
    var currentMapBounds: ExploreMapBounds? {
        didSet {
            if currentSegment != .online && DWLocationManager.shared.isAuthorized {
                _fetch(query: lastQuery)
            }
        }
    }
    
    var userCoordinates: CLLocationCoordinate2D? { return DWLocationManager.shared.currentLocation?.coordinate }
    
    init() {
        segments = [MerchantsListSegment.online, MerchantsListSegment.nearby, MerchantsListSegment.all]
        
        onlineMerchantsDataProvider = OnlineMerchantsDataProvider()
        nearbyMerchantsDataProvider = NearbyMerchantsDataProvider()
        allMerchantsDataProvider = AllMerchantsDataProvider()
        
        currentSegment = DWLocationManager.shared.isAuthorized ? .nearby : .online
        
        if currentSegment == .online {
            fetch(query: nil)
        }
    }
    
    public func fetch(query: String?) {
        lastQuery = query
        _fetch(query: query)
    }
    
    private func _fetch(query: String?) {
        let segment = currentSegment
        
        currentDataProvider.merchants(query: query, in: currentMapBounds, userPoint: userCoordinates) { [weak self] result in
            guard self?.currentSegment == segment else { return }
            
            switch result {
            case .success(let items):
                self?.items = items
                DispatchQueue.main.async {
                    self?.itemsDidChange?()
                }
                break
            case .failure(let error):
                break //TODO: handler failure
            }
        }
    }
    
    public func fetchNextPage() {
        let segment = currentSegment
        currentDataProvider.nextPage { [weak self] result in
            guard self?.currentSegment == segment else { return }
            
            switch result {
            case .success(let items):
                let offset = self?.items.count ?? 0
                let count = items.count
                
                self?.items += items
                DispatchQueue.main.async {
                    self?.nextPageDidLoaded?(offset, count)
                }
                break
            case .failure(let error):
                break //TODO: handler failure
            }
        }
    }
}

extension MerchantsListModel {
    var hasNextPage: Bool {
        return currentDataProvider.hasNextPage
    }
    
    var currentDataProvider: MerchantsDataProvider {
        switch currentSegment {
        case .online:
            return onlineMerchantsDataProvider
        case .nearby:
            return nearbyMerchantsDataProvider
        case .all:
            return allMerchantsDataProvider
        }
    }
    
    func segmentDidUpdate() {
        _fetch(query: lastQuery)
    }
}
