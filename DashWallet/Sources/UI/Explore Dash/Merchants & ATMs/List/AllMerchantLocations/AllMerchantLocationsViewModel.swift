//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

@MainActor
class AllMerchantLocationsViewModel: ObservableObject {
    private let model: PointOfUseListModel?
    private var distanceComputationRevision = 0

    @Published private(set) var currentItem: ExplorePointOfUse
    @Published private(set) var items: [ExplorePointOfUse] = []
    @Published private(set) var distanceTexts: [Int64: String] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingNextPage: Bool = false
    @Published private(set) var hasNextPage: Bool = false
    @Published private(set) var showMap: Bool = true
    @Published var selectedItem: ExplorePointOfUse? = nil

    var onItemsUpdated: (([ExplorePointOfUse]) -> Void)?

    var currentRadius: Double { model?.filters?.currentRadius ?? kDefaultRadius }
    var modelFilters: PointOfUseListFilters? { model?.filters }
    var modelSearchCenter: CLLocationCoordinate2D? { model?.searchCenterCoordinate }

    init(pointOfUse: ExplorePointOfUse, searchRadius: Double, searchCenterCoordinate: CLLocationCoordinate2D?, currentFilters: PointOfUseListFilters?) {
        currentItem = pointOfUse

        let listModel = PointOfUseListModel(segments: [
            .init(
                tag: 0, title: "", showMap: true,
                showLocationServiceSettings: false,
                showReversedLocation: false,
                dataProvider: AllMerchantLocationsDataProvider(pointOfUse: pointOfUse),
                filterGroups: [], territoriesDataSource: nil,
                sortOptions: [.name, .distance, .discount]
            )
        ])

        listModel.searchCenterCoordinate = searchCenterCoordinate
        listModel.currentMapBounds = nil

        if let filters = currentFilters {
            let isFromAllTab = searchRadius == Double.greatestFiniteMagnitude
            let sortBy: PointOfUseListFilters.SortBy
            if DWLocationManager.shared.isAuthorized && isFromAllTab {
                sortBy = .distance
            } else {
                sortBy = filters.sortBy ?? .name
            }
            let modifiedFilters = PointOfUseListFilters(
                sortBy: sortBy,
                merchantPaymentTypes: filters.merchantPaymentTypes,
                radius: isFromAllTab ? nil : filters.radius,
                territory: filters.territory,
                denominationType: filters.denominationType
            )
            listModel.apply(filters: modifiedFilters)
        }

        self.model = listModel
        self.isLoading = true

        listModel.itemsDidChange = { [weak self] in
            guard let self, let model = self.model else { return }
            self.apply(items: model.items, appendedRange: nil)
            self.updateFetchingState()
        }

        listModel.nextPageDidLoaded = { [weak self] offset, count in
            guard let self, let model = self.model else { return }
            let upperBound = min(offset + count, model.items.count)
            let range = offset..<upperBound
            self.apply(items: model.items, appendedRange: range)
            self.updateFetchingState()
        }

        listModel.fetchingStateDidChange = { [weak self] in
            guard let self else { return }
            self.updateFetchingState()
        }
    }

    #if DEBUG
    init(currentItem: ExplorePointOfUse, previewItems: [ExplorePointOfUse] = [], isLoading: Bool = false) {
        self.currentItem = currentItem
        self.model = nil
        self.items = previewItems
        self.isLoading = isLoading
        self.hasNextPage = false
    }
    #endif

    func onAppear() {
        guard let model else { return }
        isLoading = true
        model.currentMapBounds = nil
        model.currentSegment.dataProvider.clearCache()
        model.refreshItems()
    }

    func refresh() {
        guard let model else { return }
        isLoading = true
        model.currentMapBounds = nil
        model.refreshItems()
    }

    func onItemSelected(_ item: ExplorePointOfUse) {
        selectedItem = item
    }

    func loadMoreIfNeeded(currentItem item: ExplorePointOfUse) {
        guard let model else { return }
        guard hasNextPage, !isLoadingNextPage else { return }
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }

        let thresholdIndex = max(items.count - 5, 0)
        guard currentIndex >= thresholdIndex else { return }

        model.fetchNextPage()
    }

    // MARK: - Private

    private func updateFetchingState() {
        guard let model else { return }
        let hasLoadedItems = !model.items.isEmpty
        isLoading = model.isFetching && !hasLoadedItems
        isLoadingNextPage = model.isFetching && hasLoadedItems
        hasNextPage = model.hasNextPage
    }

    private func apply(items newItems: [ExplorePointOfUse], appendedRange: Range<Int>?) {
        items = newItems
        onItemsUpdated?(newItems)

        let itemsToMeasure: [ExplorePointOfUse]
        let shouldResetDistances = appendedRange == nil

        if let appendedRange, !appendedRange.isEmpty {
            itemsToMeasure = Array(newItems[appendedRange])
        } else {
            itemsToMeasure = newItems
        }

        let reference = referenceLocation()
        distanceComputationRevision += 1
        let revision = distanceComputationRevision

        DispatchQueue.global(qos: .userInitiated).async {
            let newDistanceTexts = Self.computeDistanceTexts(for: itemsToMeasure, reference: reference)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.distanceComputationRevision == revision else { return }

                if shouldResetDistances {
                    self.distanceTexts = newDistanceTexts
                } else {
                    self.distanceTexts.merge(newDistanceTexts) { _, new in new }
                }
            }
        }
    }

    private func referenceLocation() -> CLLocation? {
        if let center = modelSearchCenter, CLLocationCoordinate2DIsValid(center) {
            return CLLocation(latitude: center.latitude, longitude: center.longitude)
        }
        if DWLocationManager.shared.isAuthorized {
            return DWLocationManager.shared.currentLocation
        }
        return nil
    }

    nonisolated private static func computeDistanceTexts(for items: [ExplorePointOfUse], reference: CLLocation?) -> [Int64: String] {
        guard let reference else { return [:] }

        var result: [Int64: String] = [:]
        for item in items {
            if case .merchant(let merchant) = item.category, merchant.type == .online {
                continue
            }

            guard let lat = item.latitude, let lon = item.longitude else { continue }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            guard CLLocationCoordinate2DIsValid(coord) else { continue }

            let distance = CLLocation(latitude: lat, longitude: lon).distance(from: reference)
            let measurement = Measurement(value: floor(distance), unit: UnitLength.meters)
            result[item.id] = ExploreDash.distanceFormatter.string(from: measurement)
        }

        return result
    }
}
