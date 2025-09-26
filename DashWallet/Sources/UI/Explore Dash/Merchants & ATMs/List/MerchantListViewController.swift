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

        print("🔍🔍🔍 MerchantListViewController.show: CALLED for merchant '\(pointOfUse.name)'")
        print("🔍🔍🔍 MerchantListViewController.show: currentSegment.tag=\(currentSegment.tag), title='\(currentSegment.title)'")
        print("🔍🔍🔍 MerchantListViewController.show: model has \(model.segments.count) segments")

        // Pass appropriate search radius and filters based on current segment
        let isAllTab = currentSegment.tag == 2
        let searchRadius: Double? = isAllTab ? Double.greatestFiniteMagnitude : model.filters?.currentRadius
        print("🔍🔍🔍 MerchantListViewController.show: isAllTab=\(isAllTab)")
        print("🔍🔍🔍 MerchantListViewController.show: model.filters?.currentRadius=\(String(describing: model.filters?.currentRadius))")
        print("🔍🔍🔍 MerchantListViewController.show: searchRadius=\(String(describing: searchRadius))")
        print("🔍🔍🔍 MerchantListViewController.show: model.filters.radius=\(String(describing: model.filters?.radius))")

        let vc = POIDetailsViewController(pointOfUse: pointOfUse, isShowAllHidden: merchant.type == .online, searchRadius: searchRadius, currentFilters: model.filters)
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
        print("🔍🔍🔍 MerchantListViewController.configureModel: CALLED")
        print("🔍🔍🔍 MerchantListViewController.configureModel: Location authorized: \(DWLocationManager.shared.isAuthorized)")
        print("🔍🔍🔍 MerchantListViewController.configureModel: Location permission denied: \(DWLocationManager.shared.isPermissionDenied)")
        print("🔍🔍🔍 MerchantListViewController.configureModel: Location needs authorization: \(DWLocationManager.shared.needsAuthorization)")

        model = PointOfUseListModel(segments: [
            MerchantsListSegment.online.pointOfUseListSegment,
            MerchantsListSegment.nearby.pointOfUseListSegment,
            MerchantsListSegment.all.pointOfUseListSegment,
        ])

        print("🔍🔍🔍 MerchantListViewController.configureModel: Created model with \(model.segments.count) segments")
        for (index, segment) in model.segments.enumerated() {
            print("🔍🔍🔍 MerchantListViewController.configureModel: Segment[\(index)]: tag=\(segment.tag), title='\(segment.title)'")
        }

        // Determine which segment should be default based on location permission
        let defaultSegmentIndex: Int
        if DWLocationManager.shared.isAuthorized {
            defaultSegmentIndex = MerchantsListSegment.nearby.rawValue
        } else {
            defaultSegmentIndex = MerchantsListSegment.online.rawValue
        }

        print("🔍🔍🔍 MerchantListViewController.configureModel: defaultSegmentIndex=\(defaultSegmentIndex)")

        // Set the current segment FIRST, then apply defaults based on that segment
        model.currentSegment = model.segments[defaultSegmentIndex]

        print("🔍🔍🔍 MerchantListViewController.configureModel: Set currentSegment to tag=\(model.currentSegment.tag), title='\(model.currentSegment.title)'")

        // Now set defaults based on the ACTUAL current segment
        let defaultSortBy: PointOfUseListFilters.SortBy = defaultSegmentIndex == MerchantsListSegment.nearby.rawValue ? .distance : .name
        print("🔍🔍🔍 MerchantListViewController.configureModel: defaultSegmentIndex=\(defaultSegmentIndex), defaultSortBy=\(defaultSortBy)")

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

        model.apply(filters: defaultFilters)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Ensure filter status is visible on initial load
        print("🔍 MerchantListViewController.viewWillAppear: Updating applied filters view")
        updateAppliedFiltersView()
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
