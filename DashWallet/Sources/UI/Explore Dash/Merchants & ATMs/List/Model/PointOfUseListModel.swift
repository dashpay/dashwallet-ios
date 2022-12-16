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

import CoreLocation
import Foundation

// MARK: - PointOfUseDataProvider

class PointOfUseDataProvider {
    var items: [ExplorePointOfUse] = []
    var currentPage: PaginationResult<ExplorePointOfUse>?
    var hasFilters = false

    var hasNextPage: Bool {
        // TODO: get total amount first from data base
        !items.isEmpty && currentPage?.items.count == pageLimit
    }

    var nextOffset: Int {
        let offset: Int

        if let pageOffset = currentPage?.offset {
            offset = pageOffset + pageLimit
        } else {
            offset = 0
        }

        return offset
    }

    internal let dataSource: ExploreDash

    // To support paging we need to keep query and last user point
    internal var lastQuery: String?
    internal var lastUserPoint: CLLocationCoordinate2D?
    internal var lastBounds: ExploreMapBounds?
    internal var lastFilters: PointOfUseListFilters?

    init() {
        dataSource = ExploreDash.shared
    }

    func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
               with filters: PointOfUseListFilters?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        // NOTE: must be overriden
    }


    func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        // NOTE: must be overriden
    }

    internal func handle(result: Swift.Result<PaginationResult<ExplorePointOfUse>, Error>, appending: Bool = false,
                         completion: (Result<[ExplorePointOfUse], Error>) -> Void) {
        switch result {
        case .success(let page):
            currentPage = page

            if appending {
                items += page.items
            } else {
                items = page.items
            }

            completion(.success(page.items))
        case .failure(let error):
            completion(.failure(error))
        }
    }
}

// MARK: - PointOfUseListSegment

struct PointOfUseListSegment: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    static func == (lhs: PointOfUseListSegment, rhs: PointOfUseListSegment) -> Bool {
        lhs.tag == rhs.tag
    }

    var tag: Int
    var title: String
    var showMap: Bool
    var showLocationServiceSettings: Bool
    var showReversedLocation: Bool
    var dataProvider: PointOfUseDataProvider
    var filterGroups: [PointOfUseListFiltersGroup]
    var defaultFilters: PointOfUseListFilters!
    var territoriesDataSource: TerritoryDataSource?
}

// MARK: - PointOfUseListModel

final class PointOfUseListModel {
    internal var lastQuery: String?
    internal var isFetching = false

    var items: [ExplorePointOfUse] = []
    var itemsDidChange: (() -> Void)?
    var nextPageDidLoaded: ((_ offset: Int, _ count: Int) -> Void)?

    var segments: [PointOfUseListSegment] = []
    var segmentTitles: [String] { segments.map { $0.title } }

    internal var dataProviders: [PointOfUseListSegment: PointOfUseDataProvider] = [:]
    var filters: PointOfUseListFilters?
    var initialFilters: PointOfUseListFilters! {
        currentSegment.defaultFilters
    }

    var currentSegment: PointOfUseListSegment {
        didSet {
            if oldValue != currentSegment {
                segmentDidUpdate()
            }
        }
    }

    var currentMapBounds: ExploreMapBounds?

    var userCoordinates: CLLocationCoordinate2D? { DWLocationManager.shared.currentLocation?.coordinate }

    var hasNextPage: Bool {
        !isFetching && (currentDataProvider?.hasNextPage ?? false)
    }

    var currentDataProvider: PointOfUseDataProvider? {
        dataProviders[currentSegment]
    }

    var hasFilters: Bool {
        filters != nil
    }

    var appliedFiltersLocalizedString: String? {
        filters?.appliedFiltersLocalizedString
    }

    var showMap: Bool {
        lastQuery == nil && filters?.territory == nil && currentSegment.showMap
    }

    var showEmptyResults: Bool {
        !isFetching && filters != nil && items.isEmpty
    }

    // In meters
    var currentRadius: Double {
        filters?.currentRadius ?? 32000
    }

    var currentRadiusMiles: Double {
        Double(filters?.radius?.rawValue ?? 20)
    }

    var territories: [Territory] = []

    init(segments: [PointOfUseListSegment]) {
        self.segments = segments
        for segment in segments {
            dataProviders[segment] = segment.dataProvider
        }

        currentSegment = segments.first!
        segmentDidUpdate()
    }

    func apply(filters: PointOfUseListFilters?) {
        self.filters = filters
        refreshItems()
    }

    func resetFilters() {
        filters = nil
        refreshItems()
    }

    func segmentDidUpdate() {
        _fetch(query: lastQuery)
    }
}

extension PointOfUseListModel {
    public func refreshItems() {
        _fetch(query: lastQuery)
    }

    public func fetch(query: String?) {
        lastQuery = query
        _fetch(query: query)
    }

    internal func _fetch(query: String?) {
        let segment = currentSegment
        isFetching = true
        currentDataProvider?
            .items(query: query, in: currentMapBounds, userPoint: userCoordinates, with: filters) { [weak self] result in
                guard self?.currentSegment == segment else { return }

                switch result {
                case .success(let items):
                    DispatchQueue.main.async {
                        self?.items = items
                        self?.isFetching = false
                        self?.itemsDidChange?()
                    }
                    break
                case .failure(let error):
                    self?.isFetching = false
                    break // TODO: handler failure
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
                break // TODO: handler failure
            }
        }
    }
}
