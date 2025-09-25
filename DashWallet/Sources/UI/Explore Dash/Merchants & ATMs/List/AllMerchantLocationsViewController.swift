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
        print("🔍 AllMerchantLocationsViewController.configureModel: Creating new model")
        model = PointOfUseListModel(segments: [.init(tag: 0, title: "", showMap: true, showLocationServiceSettings: false,
                                                     showReversedLocation: false,
                                                     dataProvider: AllMerchantLocationsDataProvider(pointOfUse: pointOfUse),
                                                     filterGroups: [], territoriesDataSource: nil, sortOptions: [.name, .distance, .discount])])
        print("🔍 AllMerchantLocationsViewController.configureModel: Created model \(Unmanaged.passUnretained(model).toOpaque())")

        // Apply the current filters from parent screen if available
        if let filters = currentFilters {
            print("🔍 AllMerchantLocationsViewController.configureModel: Applying currentFilters \(filters)")
            model.apply(filters: filters)
        } else {
            print("🔍 AllMerchantLocationsViewController.configureModel: No currentFilters to apply")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initial setup of map bounds
        updateMapBounds()

        // Trigger initial data fetch
        print("🔍 AllMerchantLocationsViewController.viewDidLoad: Triggering initial data fetch")
        model.refreshItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Update map bounds FIRST to get the latest radius
        updateMapBounds()

        // Clear cache and refresh data to reflect any filter changes
        model.currentSegment.dataProvider.clearCache()

        // Trigger data fetch with new bounds
        print("🔍 AllMerchantLocationsViewController.viewWillAppear: Triggering data fetch with new bounds")
        model.refreshItems()

        refreshView()
    }

    private func updateMapBounds() {
        // Get current radius from the parent if it exists, otherwise use stored radius
        let currentRadius: Double

        let allVCs = navigationController?.viewControllers ?? []
        let dropLastVCs = allVCs.dropLast()
        let potentialParent = dropLastVCs.last
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: navigationController has \(allVCs.count) VCs")
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: dropLast gives us \(dropLastVCs.count) VCs")
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: potentialParent is \(String(describing: potentialParent))")

        if let poiDetailsVC = potentialParent as? POIDetailsViewController {
            // Get the radius from POI Details VC (which has the current filter state)
            currentRadius = poiDetailsVC.currentFilters?.currentRadius ?? searchRadius
            print("🔍 AllMerchantLocationsViewController.updateMapBounds: Got radius \(currentRadius) from POIDetailsViewController (currentFilters.radius=\(String(describing: poiDetailsVC.currentFilters?.currentRadius)), searchRadius=\(searchRadius))")
        } else if let parentVC = potentialParent as? ExplorePointOfUseListViewController {
            currentRadius = parentVC.model.filters?.currentRadius ?? searchRadius
            print("🔍 AllMerchantLocationsViewController.updateMapBounds: Got radius \(currentRadius) from ExplorePointOfUseListViewController (parentRadius=\(String(describing: parentVC.model.filters?.currentRadius)), searchRadius=\(searchRadius))")
        } else {
            currentRadius = searchRadius
            print("🔍 AllMerchantLocationsViewController.updateMapBounds: No parent VC, using searchRadius \(searchRadius)")
        }

        // Use the same bounds calculation as POIDetailsViewModel
        guard let currentLocation = DWLocationManager.shared.currentLocation else {
            model.currentMapBounds = nil
            print("🔍 AllMerchantLocationsViewController.updateMapBounds: No current location")
            return
        }

        // Create bounds using current search radius around current location (same as POIDetailsViewModel)
        let circle = MKCircle(center: currentLocation.coordinate, radius: currentRadius)
        let boundingRect = circle.boundingMapRect
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: MKCircle radius=\(currentRadius) center=\(currentLocation.coordinate)")
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: boundingMapRect=\(boundingRect)")

        let bounds = ExploreMapBounds(rect: boundingRect)
        let oldBounds = model.currentMapBounds
        model.currentMapBounds = bounds
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: Set bounds with radius \(currentRadius) on model \(Unmanaged.passUnretained(model).toOpaque())")
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: OLD bounds=\(String(describing: oldBounds))")
        print("🔍 AllMerchantLocationsViewController.updateMapBounds: NEW bounds=\(String(describing: bounds))")

    }

    override func configureHierarchy() {
        title = NSLocalizedString("Where to Spend", comment: "");

        super.configureHierarchy()

        contentViewTopLayoutConstraint.constant = kDefaultOpenedMapPosition
        tableView.register(MerchantItemCell.self, forCellReuseIdentifier: MerchantItemCell.reuseIdentifier)
    }
}
