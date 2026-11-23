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

    /// Numbers the requests this provider starts; see `beginRequest()`.
    private var requestGeneration = 0

    /// Starts a request and supersedes every request in flight: only the
    /// latest one's response is written to `items`, `currentPage` and the
    /// recorded parameters, so a page fetched next is never built on a
    /// superseded request. Call it first in every `items(...)` and
    /// `nextPage(...)`, before any early return.
    internal func beginRequest() -> Int {
        requestGeneration += 1
        return requestGeneration
    }

    /// Supersedes every request in flight and keeps the rows already taken,
    /// so a page that lands after the list has moved to another segment
    /// writes nothing; coming back answers from the rows the list last showed.
    func cancelRequests() {
        requestGeneration += 1
    }

    func clearCache() {
        requestGeneration += 1
        items = []
        currentPage = nil
        lastQuery = nil
        lastUserPoint = nil
        lastBounds = nil
        lastFilters = nil
    }

    init() {
        dataSource = ExploreDash.shared
    }

    /// Answers on the main queue in a later turn, never from inside the call:
    /// through `handleFirstPage`, `answerFromCache` or `answerEmpty`.
    func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
               with filters: PointOfUseListFilters?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        // NOTE: must be overriden
    }


    func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        // NOTE: must be overriden
    }

    /// Handles a first page and records the parameters it answered together
    /// with its rows. Recording them only when the rows land keeps the cache
    /// check and paging from pairing one request's parameters with an earlier
    /// request's rows while it is still in flight.
    ///
    /// `alsoCommit` runs with the commit, for state a provider keeps beside its
    /// rows (a total count).
    internal func handleFirstPage(request: Int, result: Swift.Result<PaginationResult<ExplorePointOfUse>, Error>,
                                  query: String?, bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                                  filters: PointOfUseListFilters?, alsoCommit: (() -> Void)? = nil,
                                  completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        commit(request) { [weak self] in
            guard let self else { return }
            if case .success = result {
                self.lastQuery = query
                self.lastUserPoint = userPoint
                self.lastBounds = bounds
                self.lastFilters = filters
                alsoCommit?()
            }
            self.apply(result: result, appending: false, completion: completion)
        }
    }

    internal func handle(request: Int, result: Swift.Result<PaginationResult<ExplorePointOfUse>, Error>,
                         appending: Bool = false,
                         completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        commit(request) { [weak self] in
            self?.apply(result: result, appending: appending, completion: completion)
        }
    }

    /// Answers `request` with the rows already held, when they match it.
    /// Like every answer, it arrives through `commit`, so the caller always
    /// gets it on the main queue in a turn of its own.
    internal func answerFromCache(request: Int, completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        commit(request) { [weak self] in
            completion(.success(self?.items ?? []))
        }
    }

    /// Answers `request` with no rows (no location to search around) and
    /// drops the rows held, both only if `request` is still the latest.
    internal func answerEmpty(request: Int, completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        commit(request) { [weak self] in
            self?.items = []
            self?.currentPage = nil
            completion(.success([]))
        }
    }

    /// Runs `work` on the main queue if `request` is still the latest, so the
    /// provider's state is written on one queue (the DAOs answer on their
    /// own) and a superseded response writes nothing and calls no completion.
    /// `PointOfUseListModel` applies the answer in the same main-queue turn,
    /// so the provider and the list never disagree on which rows are shown.
    private func commit(_ request: Int, _ work: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, request == self.requestGeneration else { return }
            work()
        }
    }

    private func apply(result: Swift.Result<PaginationResult<ExplorePointOfUse>, Error>, appending: Bool,
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
    var territoriesDataSource: TerritoryDataSource?
    var sortOptions: [PointOfUseListFilters.SortBy]
}

// MARK: - PointOfUseListModel

final class PointOfUseListModel {
    internal var lastQuery: String?
    internal var isFetching = false
    /// Numbers each request; see `beginRequest()`.
    private var requestGeneration = 0

    var items: [ExplorePointOfUse] = []
    var itemsDidChange: (() -> Void)?
    var nextPageDidLoaded: ((_ offset: Int, _ count: Int) -> Void)?
    var fetchingStateDidChange: (() -> Void)?

    var segments: [PointOfUseListSegment] = []
    var segmentTitles: [String] { segments.map { $0.title } }

    internal var dataProviders: [PointOfUseListSegment: PointOfUseDataProvider] = [:]
    private var segmentFilters: [PointOfUseListSegment: PointOfUseListFilters] = [:]

    var filters: PointOfUseListFilters? {
        get {
            return segmentFilters[currentSegment]
        }
        set {
            setFilters(newValue, for: currentSegment)
        }
    }

    /// Stores filters for a segment without fetching. Lets callers configure a segment's
    /// filters before making it current, so the fetch triggered by the segment switch
    /// already runs with them.
    func filters(for segment: PointOfUseListSegment) -> PointOfUseListFilters? {
        segmentFilters[segment]
    }

    func setFilters(_ newFilters: PointOfUseListFilters?, for segment: PointOfUseListSegment) {
        if let newFilters {
            segmentFilters[segment] = newFilters
        } else {
            segmentFilters.removeValue(forKey: segment)
        }
    }

    var currentSegment: PointOfUseListSegment {
        didSet {
            if oldValue != currentSegment {
                segmentDidUpdate()
            }
        }
    }

    var currentMapBounds: ExploreMapBounds?

    // The center coordinate for searching - typically the map center
    var searchCenterCoordinate: CLLocationCoordinate2D?

    var userCoordinates: CLLocationCoordinate2D? {
        // Use the search center if available (map center when panning)
        // Otherwise fall back to device's GPS location
        if let searchCenter = searchCenterCoordinate {
            return searchCenter
        }
        let location = DWLocationManager.shared.currentLocation
        return location?.coordinate
    }

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

    init(segments: [PointOfUseListSegment], initialSegment: PointOfUseListSegment? = nil,
         initialFilters: PointOfUseListFilters? = nil) {
        self.segments = segments
        for segment in segments {
            dataProviders[segment] = segment.dataProvider
        }

        currentSegment = initialSegment ?? segments.first!
        setFilters(initialFilters, for: currentSegment)
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
        let request = beginRequest()
        currentDataProvider?
            .items(query: query, in: currentMapBounds, userPoint: userCoordinates, with: filters) { [weak self] result in
                Self.onMain {
                    guard let self, self.isLatest(request) else { return }

                    switch result {
                    case .success(let items):
                        self.items = items
                        self.endRequest()
                        self.itemsDidChange?()
                    case .failure:
                        // TODO(explore-errors): a failed fetch keeps the previous rows and shows no error.
                        self.endRequest()
                    }
                }
            }
    }

    public func fetchNextPage() {
        let request = beginRequest()
        currentDataProvider?.nextPage { [weak self] result in
            Self.onMain {
                guard let self, self.isLatest(request) else { return }

                switch result {
                case .success(let items):
                    let offset = self.items.count
                    self.items += items
                    self.endRequest()
                    self.nextPageDidLoaded?(offset, items.count)
                case .failure:
                    // TODO(explore-errors): a failed page shows no error.
                    self.endRequest()
                }
            }
        }
    }

    /// Starts a request that supersedes every one still in flight: a segment
    /// switch, a new search, a map move or a page. Only the latest request's
    /// response is applied, so an earlier one that lands late can neither
    /// overwrite newer rows nor end the loading state early.
    private func beginRequest() -> Int {
        requestGeneration += 1
        // The segment left behind may still have a request in flight; it must
        // not commit rows or a paging offset the list will never show.
        for provider in dataProviders.values where provider !== currentDataProvider {
            provider.cancelRequests()
        }
        isFetching = true
        DispatchQueue.main.async { [weak self] in
            self?.fetchingStateDidChange?()
        }
        return requestGeneration
    }

    private func endRequest() {
        isFetching = false
        fetchingStateDidChange?()
    }

    private func isLatest(_ request: Int) -> Bool {
        request == requestGeneration
    }

    /// Applies a provider's answer in the turn it arrives in when that is on
    /// the main queue. Providers write their own state in that same turn
    /// (`PointOfUseDataProvider.commit`), so a request started in between
    /// cannot leave the provider holding rows the list dropped.
    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
