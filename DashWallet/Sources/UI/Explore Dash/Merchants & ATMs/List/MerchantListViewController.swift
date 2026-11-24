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
import MapKit
import UIKit
import SwiftUI
import DashUIKit

// MARK: - MerchantsListSegment

enum MerchantsListSegment: Int {
    case online = 0
    case nearby
    case all

    static func ==(lhs: PointOfUseListSegment, rhs: MerchantsListSegment) -> Bool {
        lhs.tag == rhs.rawValue
    }

    static func !=(lhs: PointOfUseListSegment, rhs: MerchantsListSegment) -> Bool {
        lhs.tag != rhs.rawValue
    }

    var pointOfUseListSegment: PointOfUseListSegment {
        let dataProvider: PointOfUseDataProvider
        let showReversedLocation: Bool
        let showMap: Bool
        let showLocationServiceSettings: Bool
        var sortOptions: [PointOfUseListFilters.SortBy] = [.name, .distance, .discount]

        switch self {
        case .online:
            showLocationServiceSettings = false
            showReversedLocation = false
            showMap = false
            dataProvider = OnlineMerchantsDataProvider()
            sortOptions = [.name, .discount]
            
        case .nearby:
            showLocationServiceSettings = true
            showReversedLocation = true
            showMap = true
            dataProvider = NearbyMerchantsDataProvider()

        case .all:
            showLocationServiceSettings = false
            showReversedLocation = false
            showMap = true
            dataProvider = AllMerchantsDataProvider()
            sortOptions = [.name, .discount]
        }

        return .init(tag: rawValue, title: title, showMap: showMap, showLocationServiceSettings: showLocationServiceSettings, showReversedLocation: showReversedLocation, dataProvider: dataProvider, filterGroups: filterGroups, territoriesDataSource: territories, sortOptions: sortOptions)
    }
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

    var filterGroups: [PointOfUseListFiltersGroup] {
        switch self {
        case .online:
            return [.sortBy, .paymentType, .denominationType]
        case .nearby:
            return [.sortBy, .paymentType, .denominationType, .territory, .radius, .locationService]
        case .all:
            return [.sortBy, .paymentType, .denominationType]
        }
    }

    var territories: TerritoryDataSource {
        ExploreDash.shared.fetchTerritoriesForMerchants
    }
}

// MARK: - MerchantListViewController

@objc
class MerchantListViewController: ExplorePointOfUseListViewController {

    var initialSegment: MerchantsListSegment?

    private var infoButton: UIBarButtonItem!

    override var customNavBarInfoAction: (() -> Void)? {
        customNavBar?.onInfo ?? { [weak self] in self?.infoButtonAction() }
    }

    internal var locationOffCell: MerchantListLocationOffCell?
    // MARK: Table View

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell!

        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .items:
            if currentSegment == .nearby && DWLocationManager.shared.isPermissionDenied {
                let itemCell: MerchantListLocationOffCell = tableView
                    .dequeueReusableCell(withIdentifier: MerchantListLocationOffCell.reuseIdentifier,
                                         for: indexPath) as! MerchantListLocationOffCell
                cell = itemCell
                cell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0)
                locationOffCell = itemCell
            } else {
                let cell = super.tableView(tableView, cellForRowAt: indexPath) as! PointOfUseItemCell
                return cell
            }
        default:
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = ExplorePointOfUseSections(rawValue: section) else {
            return 0
        }

        switch section {
        case .filters, .search:
            return currentSegment == .nearby ? (DWLocationManager.shared.isPermissionDenied ? 0 : 1) : 1
        case .items:
            if currentSegment == .nearby {
                if DWLocationManager.shared.isAuthorized {
                    return items.count;
                } else if DWLocationManager.shared.needsAuthorization {
                    return 0;
                } else if DWLocationManager.shared.isPermissionDenied {
                    return 1;
                }
            } else {
                return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
            }
        default:
            return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
        }

        return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return 0
        }

        switch section {
        case .items:
            return (currentSegment.showLocationServiceSettings && DWLocationManager.shared.isPermissionDenied)
                ? tableView.frame.size.height
                : 56.0
        default:
            return super.tableView(tableView, heightForRowAt: indexPath)
        }
    }

    // MARK: Life cycle

    override func makeConfiguration() -> PointOfUseListConfiguration {
        .merchants(initialSegment: initialSegment, isLocationAuthorized: DWLocationManager.shared.isAuthorized)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // A search center is left over from a details screen pushed on top;
        // without one the screen is opening and starts at the device's
        // location. Every map-showing segment (Nearby and All) needs these
        // bounds, or the All map stays empty until it is panned.
        if viewModel.searchCenterCoordinate == nil,
           let gpsLocation = DWLocationManager.shared.currentLocation,
           viewModel.showsMap {
            // mapViewDidFinishLoadingMap centers on initialCenterLocation.
            mapView.initialCenterLocation = gpsLocation
            mapView.setCenter(gpsLocation, animated: false)
            mapView.searchRadius = viewModel.searchRadius

            // The GPS location, not mapView.centerCoordinate, which may not
            // have moved yet.
            let bounds = ExploreMapBounds(rect: MKCircle(center: gpsLocation.coordinate, radius: viewModel.searchRadius).boundingMapRect)
            viewModel.searchAround(bounds: bounds)
        }

        // Ensure filter status is visible on initial load
        updateAppliedFiltersView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Leaving the screen, not pushing details over it.
        if isMovingFromParent || isBeingDismissed {
            viewModel.screenDidClose()
        }
    }

    override func configureHierarchy() {
//        title = NSLocalizedString("Where to Spend", comment: "");

        super.configureHierarchy()

        tableView.register(MerchantItemCell.self, forCellReuseIdentifier: MerchantItemCell.reuseIdentifier)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if customNavBar == nil {
            setupInfoButton()
        }
    }

    override func listDidUpdate(_ update: PointOfUseListViewModel.ListUpdate) {
        guard update == .replaced else {
            super.listDidUpdate(update)
            return
        }

        refreshFilterCell()

        // The location-off row replaces the whole list, so it needs a full
        // reload both to appear and to go away.
        if currentSegment.showLocationServiceSettings && DWLocationManager.shared.isPermissionDenied {
            tableView.reloadData()
        } else if locationOffCell != nil {
            tableView.reloadData()
            locationOffCell = nil
        } else {
            tableView.reloadSections([ExplorePointOfUseSections.items.rawValue, ExplorePointOfUseSections.nextPage.rawValue],
                                     with: .none)
        }

        updateEmptyResultsForFilters()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    private func setupInfoButton() {
        let infoImage = UIImage(systemName: "info.circle")?.withRenderingMode(.alwaysOriginal).withTintColor(.systemBlue)
        infoButton = UIBarButtonItem(image: infoImage, style: .plain, target: self, action: #selector(infoButtonAction))
        navigationItem.rightBarButtonItem = infoButton
    }

    @objc
    func infoButtonAction() {
        let hostingController = UIHostingController(rootView: MerchantTypesDialog())
        hostingController.setDetent(640)
        self.present(hostingController, animated: true)
    }
}
