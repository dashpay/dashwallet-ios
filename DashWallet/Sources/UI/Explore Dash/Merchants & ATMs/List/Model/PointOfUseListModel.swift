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

class PointOfUseDataProvider {
    var items: [ExplorePointOfUse] = []
    var currentPage: PaginationResult<ExplorePointOfUse>?
    
    var hasNextPage: Bool {
        //TODO: get total amount first from data base 
        return !items.isEmpty && currentPage?.items.count == pageLimit
    }
    
    var nextOffset: Int {
        let offset: Int
        
        if let pageOffset = currentPage?.offset {
            offset = pageOffset + pageLimit
        }else{
            offset = 0
        }
        
        return offset
    }
    
    internal let dataSource: ExploreDash
    
    //To support paging we need to keep query and last user point
    internal var lastQuery: String?
    internal var lastUserPoint: CLLocationCoordinate2D?
    internal var lastBounds: ExploreMapBounds?
    
    init() {
        self.dataSource = ExploreDash.shared
    }
    
    func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        //NOTE: must be overriden
    }
    
    
    func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        //NOTE: must be overriden
    }
    
    internal func handle(result: Swift.Result<PaginationResult<ExplorePointOfUse>, Error>, appending: Bool = false, completion: (Result<[ExplorePointOfUse], Error>) -> Void) {
        switch result {
        case .success(let page):
            currentPage = page
            
            if appending {
                items += page.items
            }else{
                items = page.items
            }
            
            completion(.success(page.items))
        case .failure(let error):
            completion(.failure(error))
        }
    }
}

struct PointOfUseListSegment: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }
    
    static func == (lhs: PointOfUseListSegment, rhs: PointOfUseListSegment) -> Bool {
        return lhs.tag == rhs.tag
    }
    
    var tag: Int
    var title: String
    var showMap: Bool
    var showLocationServiceSettings: Bool
    var showReversedLocation: Bool
    var dataProvider: PointOfUseDataProvider
}

final class PointOfUseListModel {
    internal var lastQuery: String?
    internal var isFetching: Bool = false
    
    var items: [ExplorePointOfUse] = []
    var itemsDidChange: (() -> Void)?
    var nextPageDidLoaded: ((_ offset: Int, _ count: Int) -> Void)?
    
    var segments: [PointOfUseListSegment] = []
    var segmentTitles: [String] { return segments.map { $0.title } }
    
    internal var dataProviders: [PointOfUseListSegment: PointOfUseDataProvider] = [:]
    
    var currentSegment: PointOfUseListSegment {
        didSet {
            if oldValue != currentSegment {
                segmentDidUpdate()
            }
        }
    }
    
    var currentMapBounds: ExploreMapBounds? {
        didSet {
            if currentSegment.showMap && DWLocationManager.shared.isAuthorized {
                _fetch(query: lastQuery)
            }
        }
    }
    
    var userCoordinates: CLLocationCoordinate2D? { return DWLocationManager.shared.currentLocation?.coordinate }
    
    var hasNextPage: Bool {
        return currentDataProvider?.hasNextPage ?? false
    }
    
    var currentDataProvider: PointOfUseDataProvider? {
        return dataProviders[currentSegment]
    }
    
    var territories: [Territory] = []
    
    init(segments: [PointOfUseListSegment]) {
        self.segments = segments
        for segment in segments {
            dataProviders[segment] = segment.dataProvider
        }
       
        self.currentSegment = segments.first!
        self.segmentDidUpdate()
        
        
    }
    
    func segmentDidUpdate() {
        _fetch(query: lastQuery)
    }
}

extension PointOfUseListModel {
    public func fetch(query: String?) {
        lastQuery = query
        _fetch(query: query)
    }
    
    internal func _fetch(query: String?) {
        let segment = currentSegment
        
        currentDataProvider?.items(query: query, in: currentMapBounds, userPoint: userCoordinates) { [weak self] result in
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
        currentDataProvider?.nextPage { [weak self] result in
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
