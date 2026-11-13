//
//  Created by Dash Core Group
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import Combine
import CoreLocation
import Foundation

private let kSignificantLocationChange: CLLocationDistance = 500
private let kSyncedDatabaseReloadDelay: TimeInterval = 0.5

// MARK: - PointOfUseLocationService

/// The parts of `DWLocationManager` the list reads, so tests can stand in
/// for the device's location.
protocol PointOfUseLocationService: AnyObject {
    var isAuthorized: Bool { get }
    var needsAuthorization: Bool { get }
    var isPermissionDenied: Bool { get }
    var currentLocation: CLLocation? { get }
    func reverseGeocodeLocation(_ location: CLLocation, completion: @escaping ((String, CLPlacemark?) -> Void))
}

extension DWLocationManager: PointOfUseLocationService { }

// MARK: - PointOfUseDetailsRequest

/// What the details screen of a tapped row opens with.
struct PointOfUseDetailsRequest {
    let pointOfUse: ExplorePointOfUse
    let isShowAllHidden: Bool
    let searchRadius: Double?
    let searchCenterCoordinate: CLLocationCoordinate2D?
    let filters: PointOfUseListFilters?
}

// MARK: - PointOfUseListViewModel

/// State and behaviour of a point-of-use list (ATMs, Where to Spend): the
/// segments, filters, search, paging, map pins and the database sync banner.
/// The screen owns the map view and the sheet; it hands map changes in and
/// draws what is published here.
@MainActor
final class PointOfUseListViewModel: ObservableObject {
    enum ListUpdate {
        /// A new result set replaced the rows.
        case replaced
        /// A page was added after the last row.
        case appended
    }

    struct SegmentSelection {
        /// The segment had no filters, so it got the defaults.
        let appliedDefaultFilters: Bool
        /// The segment wants location, which has not been asked for yet.
        let needsLocationPrompt: Bool
    }

    let configuration: PointOfUseListConfiguration

    @Published private(set) var items: [ExplorePointOfUse] = []
    /// What the map pins: the rows for ATMs, every physical location of the
    /// listed merchants for Where to Spend.
    @Published private(set) var mapItems: [ExplorePointOfUse] = []
    /// The filter row's title: the segment, or the place at the map's center
    /// for a segment that shows it.
    @Published private(set) var filterTitle: String
    @Published private(set) var isSyncBannerVisible = false

    var listUpdates: AnyPublisher<ListUpdate, Never> { listUpdatesSubject.eraseToAnyPublisher() }

    private let model: PointOfUseListModel
    private let location: PointOfUseLocationService
    private let databaseURL: URL
    private let listUpdatesSubject = PassthroughSubject<ListUpdate, Never>()
    private var lastLocationDrivenFetch: CLLocation?
    private var cancellables = Set<AnyCancellable>()

    init(configuration: PointOfUseListConfiguration,
         location: PointOfUseLocationService = DWLocationManager.shared,
         databaseURL: URL = FileManager.documentsDirectoryURL.appendingPathComponent(kExploreDashDatabaseName),
         notificationCenter: NotificationCenter = .default) {
        self.configuration = configuration
        self.location = location
        self.databaseURL = databaseURL

        let initialSegment = configuration.segments[configuration.initialSegmentIndex]
        filterTitle = initialSegment.title
        model = PointOfUseListModel(segments: configuration.segments,
                                    initialSegment: initialSegment,
                                    initialFilters: configuration.initialFilters)

        // The model calls back on the main queue.
        model.itemsDidChange = { [weak self] in
            MainActor.assumeIsolated { self?.modelDidReplaceItems() }
        }
        model.nextPageDidLoaded = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.modelDidAppendItems() }
        }

        notificationCenter.publisher(for: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.databaseDidUpdate() }
            .store(in: &cancellables)
    }

    // MARK: Segments

    var segments: [PointOfUseListSegment] { model.segments }
    var segmentTitles: [String] { model.segmentTitles }
    var currentSegment: PointOfUseListSegment { model.currentSegment }

    func selectSegment(at index: Int) -> SegmentSelection {
        let segment = model.segments[index]
        model.currentSegment = segment

        // A segment keeps its filters once it has been shown; the first visit
        // gets the defaults.
        let appliesDefaults = model.filters == nil
        if appliesDefaults {
            model.apply(filters: .defaults(sortBy: defaultSortBy(for: segment)))
        }

        // TODO(atm-segments): tag 1 is Nearby for merchants but Buy for ATMs,
        // so the ATM Buy tab asks for location too.
        let needsLocationPrompt = segment.tag == MerchantsListSegment.nearby.rawValue && location.needsAuthorization

        return SegmentSelection(appliedDefaultFilters: appliesDefaults, needsLocationPrompt: needsLocationPrompt)
    }

    // MARK: Filters

    var filters: PointOfUseListFilters? { model.filters }

    /// The search radius in meters.
    var searchRadius: Double { model.currentRadius }

    var appliedFiltersText: String {
        model.appliedFiltersLocalizedString ?? NSLocalizedString("Default filters applied", comment: "Explore Dash")
    }

    /// The filters the filter screen opens with: the current ones, with a sort
    /// this segment offers.
    var filtersForEditing: PointOfUseListFilters {
        let segment = model.currentSegment
        var filters = model.filters ?? PointOfUseListFilters()

        if let sortBy = filters.sortBy, segment.sortOptions.contains(sortBy) {
            return filters
        }
        filters.sortBy = defaultSortBy(for: segment)
        return filters
    }

    /// Applies filters and searches `bounds`, the map area the new radius
    /// covers.
    func apply(filters: PointOfUseListFilters?, searchBounds bounds: ExploreMapBounds) {
        model.currentMapBounds = bounds
        model.apply(filters: filters)
    }

    // MARK: Results

    var showsMap: Bool { model.showMap }
    var hasNextPage: Bool { model.hasNextPage }
    var showsEmptyResults: Bool { model.showEmptyResults }
    var searchCenterCoordinate: CLLocationCoordinate2D? { model.searchCenterCoordinate }

    /// The count under the filter row's title, "12 ATM(s) in 20 miles", when
    /// the results are bounded by the map.
    var resultsSubtitle: String? {
        guard location.isAuthorized else { return nil }

        let format: String
        switch configuration.kind {
        case .atms:
            guard model.currentSegment.showMap else { return nil }
            format = NSLocalizedString("%d ATM(s) in %@", comment: "#bc-ignore!")
        case .merchants:
            guard model.showMap,
                  model.currentSegment != MerchantsListSegment.all,
                  items.contains(where: { $0.isPhysical })
            else { return nil }
            format = NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!")
        }

        return String.localizedStringWithFormat(format, items.count, formattedSearchRadius)
    }

    func fetchNextPage() {
        model.fetchNextPage()
    }

    // MARK: Search

    func search(query: String?) {
        model.fetch(query: query)
    }

    /// Searches around `bounds` with no query, the way the screen opens.
    func searchAround(bounds: ExploreMapBounds) {
        model.currentMapBounds = bounds
        model.fetch(query: nil)
    }

    // MARK: Map and location

    /// The user moved the map: search around its new center.
    func mapDidMove(center: CLLocationCoordinate2D, bounds: ExploreMapBounds) {
        model.searchCenterCoordinate = center
        model.currentMapBounds = bounds
        model.refreshItems()
    }

    /// A new GPS fix: the search follows the device again. Fixes can arrive
    /// every ~100 m, which is too chatty to requery for, so the list is
    /// fetched again only after a significant move.
    func locationDidChange(to newLocation: CLLocation, bounds: ExploreMapBounds) {
        model.searchCenterCoordinate = nil
        guard model.showMap else { return }

        model.currentMapBounds = bounds
        let movedSignificantly = lastLocationDrivenFetch
            .map { newLocation.distance(from: $0) > kSignificantLocationChange } ?? true
        if movedSignificantly {
            lastLocationDrivenFetch = newLocation
            model.fetch(query: nil)
        }
    }

    /// Location was turned on or off. Without a fix yet, the next
    /// `locationDidChange` fetches instead.
    func locationAvailabilityDidChange() {
        guard model.showMap else { return }

        if !location.isAuthorized || location.currentLocation != nil {
            model.fetch(query: nil)
        }
    }

    /// Leaving the screen, not pushing details over it: the next visit starts
    /// from the device's location again.
    func screenDidClose() {
        model.searchCenterCoordinate = nil
    }

    func refreshFilterTitle(mapCenter: CLLocationCoordinate2D) {
        filterTitle = model.currentSegment.title

        guard location.isAuthorized, model.currentSegment.showReversedLocation else { return }

        let center = CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude)
        location.reverseGeocodeLocation(center) { [weak self] place, _ in
            DispatchQueue.main.async {
                guard let self, self.model.showMap else { return }
                self.filterTitle = place
            }
        }
    }

    // MARK: Details

    /// `nil` for a Where to Spend row that is not a merchant.
    func detailsRequest(for pointOfUse: ExplorePointOfUse) -> PointOfUseDetailsRequest? {
        switch configuration.kind {
        case .atms:
            return PointOfUseDetailsRequest(
                pointOfUse: pointOfUse,
                isShowAllHidden: true,
                searchRadius: model.filters?.currentRadius ?? kDefaultRadius,
                searchCenterCoordinate: model.searchCenterCoordinate,
                filters: model.filters)
        case .merchants:
            guard let merchant = pointOfUse.merchant else { return nil }

            // All lists merchants from anywhere, so their other locations are
            // not limited to the radius.
            let searchRadius = model.currentSegment == MerchantsListSegment.all
                ? Double.greatestFiniteMagnitude
                : model.filters?.currentRadius
            return PointOfUseDetailsRequest(
                pointOfUse: pointOfUse,
                isShowAllHidden: merchant.type == .online,
                searchRadius: searchRadius,
                searchCenterCoordinate: model.searchCenterCoordinate,
                filters: model.filters)
        }
    }

    // MARK: Database sync

    /// Shows the banner while the explore database is missing or still has
    /// the old schema.
    func refreshSyncBanner() {
        let fileExists = FileManager.default.fileExists(atPath: databaseURL.path)
        isSyncBannerVisible = !fileExists || ExploreDatabaseConnection.hasOldMerchantIdSchema(at: databaseURL)
    }

    private func databaseDidUpdate() {
        isSyncBannerVisible = false

        // The database connection is reopened after an update; refetch once
        // it has been.
        DispatchQueue.main.asyncAfter(deadline: .now() + kSyncedDatabaseReloadDelay) { [weak self] in
            guard let self else { return }

            self.model.items = []
            if let provider = self.model.currentDataProvider {
                provider.items = []
                provider.currentPage = nil
            }
            self.items = []
            // Fetching starts first, so the cleared list is not taken for an
            // empty result.
            self.model.refreshItems()
            self.listUpdatesSubject.send(.replaced)
        }
    }

    // MARK: Model callbacks

    private func modelDidReplaceItems() {
        items = model.items
        updateMapItems()
        listUpdatesSubject.send(.replaced)
    }

    private func modelDidAppendItems() {
        items = model.items
        listUpdatesSubject.send(.appended)
    }

    private func updateMapItems() {
        guard model.showMap else { return }

        switch configuration.kind {
        case .atms:
            mapItems = model.items
        case .merchants:
            updateMerchantLocations()
        }
    }

    /// The map shows every physical location inside the search area (the
    /// closest to the search center), while the list keeps one row per
    /// merchant.
    private func updateMerchantLocations() {
        // The All list also has online merchants from anywhere; only physical
        // rows belong on the map.
        let physicalItems = model.items.filter { $0.isPhysical }

        guard let bounds = model.currentMapBounds, let center = model.userCoordinates else {
            mapItems = physicalItems
            return
        }

        ExploreDash.shared.merchantPhysicalLocations(in: bounds, center: center,
                                                     paymentMethods: model.filters?.merchantPaymentTypes,
                                                     denominationType: model.filters?.denominationType) { [weak self] result in
            DispatchQueue.main.async {
                // A pan or zoom may have started another fetch; only the
                // response for the bounds on screen applies.
                guard let self, self.model.showMap, self.model.currentMapBounds == bounds else { return }

                switch result {
                case .success(let locations):
                    self.mapItems = locations
                case .failure:
                    self.mapItems = self.model.items.filter { $0.isPhysical }
                }
            }
        }
    }

    // MARK: Helpers

    // TODO(atm-segments): keyed on tag 1, which is Nearby for merchants but
    // Buy for ATMs, so the ATM Buy tab defaults to distance.
    private func defaultSortBy(for segment: PointOfUseListSegment) -> PointOfUseListFilters.SortBy {
        segment.tag == MerchantsListSegment.nearby.rawValue ? .distance : .name
    }

    private var formattedSearchRadius: String {
        if Locale.current.usesMetricSystem {
            return ExploreDash.distanceFormatter
                .string(from: Measurement(value: model.currentRadius, unit: UnitLength.meters))
        } else {
            return ExploreDash.distanceFormatter
                .string(from: Measurement(value: model.currentRadiusMiles, unit: UnitLength.miles))
        }
    }
}
