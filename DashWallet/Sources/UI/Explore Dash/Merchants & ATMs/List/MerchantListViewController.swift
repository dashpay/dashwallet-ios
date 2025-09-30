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

    private var infoButton: UIBarButtonItem!
    
    override var locationServicePopupTitle: String {
        NSLocalizedString("Merchant search works better with Location Services turned on.", comment: "")
    }

    override var locationServicePopupDetails: String {
        NSLocalizedString("Your location is used to show your position on the map, merchants in the selected redius and improve search results.",
                          comment: "")
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

    override func show(pointOfUse: ExplorePointOfUse) {
        guard let merchant = pointOfUse.merchant else { return }

        // Pass appropriate search radius and filters based on current segment
        let isAllTab = currentSegment.tag == 2
        let searchRadius: Double? = isAllTab ? Double.greatestFiniteMagnitude : model.filters?.currentRadius

        let vc = POIDetailsViewController(pointOfUse: pointOfUse, isShowAllHidden: merchant.type == .online, searchRadius: searchRadius, searchCenterCoordinate: model.searchCenterCoordinate, currentFilters: model.filters)
        vc.payWithDashHandler = payWithDashHandler
        vc.onGiftCardPurchased = onGiftCardPurchased
        navigationController?.pushViewController(vc, animated: true)
    }

    override func subtitleForFilterCell() -> String? {
        if model.showMap &&
            DWLocationManager.shared.isAuthorized &&
            currentSegment != .all {
            let physicalMerchants = items.filter { $0.isPhysical }

            guard !physicalMerchants.isEmpty else { return nil }

            if Locale.current.usesMetricSystem {
                return String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"), items.count,
                              ExploreDash.distanceFormatter
                                  .string(from: Measurement(value: model.currentRadius, unit: UnitLength.meters)))
            } else {
                return String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"), items.count,
                              ExploreDash.distanceFormatter
                                  .string(from: Measurement(value: model.currentRadiusMiles, unit: UnitLength.miles)))
            }
        } else {
            return nil
        }
    }

    override func configureModel() {
        model = PointOfUseListModel(segments: [
            MerchantsListSegment.online.pointOfUseListSegment,
            MerchantsListSegment.nearby.pointOfUseListSegment,
            MerchantsListSegment.all.pointOfUseListSegment,
        ])

        // Determine which segment should be default based on location permission
        let defaultSegmentIndex: Int
        if DWLocationManager.shared.isAuthorized {
            defaultSegmentIndex = MerchantsListSegment.nearby.rawValue
        } else {
            defaultSegmentIndex = MerchantsListSegment.online.rawValue
        }

        // Set the current segment FIRST, then apply defaults based on that segment
        model.currentSegment = model.segments[defaultSegmentIndex]

        // Now set defaults based on the ACTUAL current segment
        let defaultSortBy: PointOfUseListFilters.SortBy = defaultSegmentIndex == MerchantsListSegment.nearby.rawValue ? .distance : .name

        var defaultPaymentTypes: [PointOfUseListFilters.SpendingOptions] = [.dash, .ctx]
        #if PIGGYCARDS_ENABLED
        defaultPaymentTypes.append(.piggyCards)
        #endif

        let defaultFilters = PointOfUseListFilters(
            sortBy: defaultSortBy,
            merchantPaymentTypes: defaultPaymentTypes, // Default to all available payment types
            radius: .twenty, // Default radius
            territory: nil,
            denominationType: .both // Default to both fixed and flexible
        )

        // Set filters but don't fetch yet - wait for map bounds to be set
        model.filters = defaultFilters
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        print("🔍 VIEW: viewWillAppear called")
        print("🔍 VIEW: Current GPS location = \(DWLocationManager.shared.currentLocation?.coordinate.latitude ?? 0), \(DWLocationManager.shared.currentLocation?.coordinate.longitude ?? 0)")
        print("🔍 VIEW: Current searchCenterCoordinate = \(model.searchCenterCoordinate?.latitude ?? 0), \(model.searchCenterCoordinate?.longitude ?? 0)")

        // Check if we're coming from within the same screen (e.g., returning from merchant detail)
        // vs. entering the screen fresh (e.g., switching from home screen or another tab)
        let isReturningFromWithinFlow = model.searchCenterCoordinate != nil

        // Only recenter to GPS if entering the screen fresh
        if !isReturningFromWithinFlow {
            print("🔍 VIEW: No search center set, will recenter to GPS")
            // If we have a GPS location and are on Nearby tab, update map center and fetch
            if let gpsLocation = DWLocationManager.shared.currentLocation,
               currentSegment.tag == MerchantsListSegment.nearby.rawValue,
               model.showMap {
                print("🔍 VIEW: Setting map center to GPS location: \(gpsLocation.coordinate.latitude), \(gpsLocation.coordinate.longitude)")

                // Set initialCenterLocation so mapViewDidFinishLoadingMap will use the correct location
                mapView.initialCenterLocation = gpsLocation
                mapView.setCenter(gpsLocation, animated: false)

                print("🔍 VIEW: After setCenter, mapView.centerCoordinate = \(mapView.centerCoordinate.latitude), \(mapView.centerCoordinate.longitude)")

                let radiusToUse = model.filters?.currentRadius ?? kDefaultRadius
                mapView.searchRadius = radiusToUse

                // Use GPS location directly instead of relying on mapView.centerCoordinate
                let newBounds = ExploreMapBounds(rect: MKCircle(center: gpsLocation.coordinate, radius: radiusToUse).boundingMapRect)
                print("🔍 VIEW: Created bounds from GPS location - NE=(\(newBounds.neCoordinate.latitude), \(newBounds.neCoordinate.longitude)), SW=(\(newBounds.swCoordinate.latitude), \(newBounds.swCoordinate.longitude))")
                model.currentMapBounds = newBounds

                print("🔍 VIEW: Refreshing items with GPS location")
                model.fetch(query: nil)
            }
        } else {
            print("🔍 VIEW: Returning from within flow, preserving panned location at (\(model.searchCenterCoordinate!.latitude), \(model.searchCenterCoordinate!.longitude))")
        }

        // Ensure filter status is visible on initial load
        updateAppliedFiltersView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Clear search center coordinate when actually leaving the screen
        // (not when navigating to a child view like merchant detail)
        if isMovingFromParent || isBeingDismissed {
            print("🔍 VIEW: viewWillDisappear - leaving screen, clearing searchCenterCoordinate")
            model.searchCenterCoordinate = nil
        } else {
            print("🔍 VIEW: viewWillDisappear - navigating to child view, preserving searchCenterCoordinate")
        }
    }

    override func configureHierarchy() {
        title = NSLocalizedString("Where to Spend", comment: "");

        super.configureHierarchy()

        tableView.register(MerchantItemCell.self, forCellReuseIdentifier: MerchantItemCell.reuseIdentifier)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupInfoButton()

        model.itemsDidChange = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.refreshFilterCell()

            if wSelf.currentSegment.showLocationServiceSettings && DWLocationManager.shared.isPermissionDenied {
                wSelf.tableView.reloadData()
            } else if wSelf.locationOffCell != nil {
                wSelf.tableView.reloadData()
                wSelf.locationOffCell = nil
            } else {
                wSelf.tableView
                    .reloadSections([ExplorePointOfUseSections.items.rawValue, ExplorePointOfUseSections.nextPage.rawValue],
                                    with: .none)
            }

            if wSelf.model.showMap {
                wSelf.mapView.show(merchants: wSelf.model.items)
            }

            wSelf.updateEmptyResultsForFilters()
        }
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
