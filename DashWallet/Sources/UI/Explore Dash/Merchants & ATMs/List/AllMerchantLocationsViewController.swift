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
import MapKit
import UIKit

@objc
class AllMerchantLocationsViewController: ExplorePointOfUseListViewController {
    private let pointOfUse: ExplorePointOfUse
    private let searchRadius: Double
    private let currentFilters: PointOfUseListFilters?

    init(pointOfUse: ExplorePointOfUse, searchRadius: Double = kDefaultRadius, currentFilters: PointOfUseListFilters? = nil) {
        self.pointOfUse = pointOfUse
        self.searchRadius = searchRadius
        self.currentFilters = currentFilters
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showMapIfNeeded() {
        guard model.showMap else { return }

        showMap()
    }

    // MARK: Table View

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = ExplorePointOfUseSections(rawValue: section) else {
            return 0
        }

        switch section {
        case .filters, .search, .segments:
            return 0
        default:
            return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
        }
    }

    // MARK: Life cycle

    override func subtitleForFilterCell() -> String? {
        nil
    }

    override func configureModel() {
        model = PointOfUseListModel(segments: [.init(tag: 0, title: "", showMap: true, showLocationServiceSettings: false,
                                                     showReversedLocation: false,
                                                     dataProvider: AllMerchantLocationsDataProvider(pointOfUse: pointOfUse),
                                                     filterGroups: [], territoriesDataSource: nil, sortOptions: [.name, .distance, .discount])])

        // Apply the current filters from parent screen if available
        if let filters = currentFilters {

            // Determine if we should remove radius filter based on source tab
            let isFromAllTab = searchRadius == Double.greatestFiniteMagnitude
            let shouldRemoveRadius = isFromAllTab

            print("🎯 AllMerchantLocationsViewController: isFromAllTab=\(isFromAllTab), shouldRemoveRadius=\(shouldRemoveRadius)")

            // Sort by distance if location authorized, otherwise use the current sort from filters
            let sortBy: PointOfUseListFilters.SortBy
            if DWLocationManager.shared.isAuthorized && isFromAllTab {
                // Only force distance sorting for All tab (infinite radius)
                sortBy = .distance
            } else {
                // Keep the existing sort from filters for other tabs
                sortBy = filters.sortBy ?? .name
            }

            let modifiedFilters = PointOfUseListFilters(
                sortBy: sortBy,
                merchantPaymentTypes: filters.merchantPaymentTypes,
                radius: shouldRemoveRadius ? nil : filters.radius, // Only remove radius for All tab
                territory: filters.territory,
                denominationType: filters.denominationType
            )
            model.apply(filters: modifiedFilters)
        } else {
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initial setup of map bounds
        updateMapBounds()

        // Trigger initial data fetch
        model.refreshItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Update map bounds FIRST to get the latest radius
        updateMapBounds()

        // Clear cache and refresh data to reflect any filter changes
        model.currentSegment.dataProvider.clearCache()

        // Trigger data fetch with new bounds
        model.refreshItems()

        refreshView()
    }

    private func updateMapBounds() {
        // AllMerchantLocationsViewController should ALWAYS show all locations for a merchant
        // regardless of which tab the user came from. The "Show All Locations" screen
        // is specifically designed to show ALL locations without radius filtering.
        model.currentMapBounds = nil
    }

    override func configureHierarchy() {
        title = NSLocalizedString("Where to Spend", comment: "");

        super.configureHierarchy()

        contentViewTopLayoutConstraint.constant = kDefaultOpenedMapPosition
        tableView.register(MerchantItemCell.self, forCellReuseIdentifier: MerchantItemCell.reuseIdentifier)
    }
}
