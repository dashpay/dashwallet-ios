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
import SwiftUI
import UIKit

@objc
class AllMerchantLocationsViewController: UIViewController {
    private let pointOfUse: ExplorePointOfUse
    private let searchRadius: Double
    private let searchCenterCoordinate: CLLocationCoordinate2D?
    private let currentFilters: PointOfUseListFilters?
    private var mapView: ExploreMapView!
    private weak var detailsSheetViewController: UIViewController?
    private var didPresentDetailsSheet = false
    private var didConfigureInitialMapCenter = false
    private let defaultBottomSheetHeight: CGFloat = 450

    @objc var payWithDashHandler: (() -> Void)?
    @objc var sellDashHandler: (() -> Void)?
    @objc var onGiftCardPurchased: ((Data) -> Void)?

    init(pointOfUse: ExplorePointOfUse, searchRadius: Double = kDefaultRadius, searchCenterCoordinate: CLLocationCoordinate2D? = nil, currentFilters: PointOfUseListFilters? = nil) {
        self.pointOfUse = pointOfUse
        self.searchRadius = searchRadius
        self.searchCenterCoordinate = searchCenterCoordinate
        self.currentFilters = currentFilters
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Where to Spend", comment: "")
        configureHierarchy()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Re-present the sheet whenever this screen becomes visible again (e.g. after
        // returning from a pushed location details screen). `didPresentDetailsSheet` is
        // reset to false when the sheet is dismissed for navigation, and the guard inside
        // `presentDetailsSheetIfNeeded` prevents a duplicate while one is already shown.
        presentDetailsSheetIfNeeded()
    }

    private func configureHierarchy() {
        mapView = ExploreMapView()
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)

        if searchRadius != Double.greatestFiniteMagnitude {
            mapView.centerRadius = max(searchRadius / 1609.344, 1)
        }

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        configureInitialMapCenterIfNeeded(preferredItem: pointOfUse)
        adjustMapForBottomSheet()
    }

    private func makeLocationsView() -> AllMerchantLocationsView {
        var swiftUIView = AllMerchantLocationsView(
            pointOfUse: pointOfUse,
            searchRadius: searchRadius,
            searchCenterCoordinate: searchCenterCoordinate,
            currentFilters: currentFilters
        )
        swiftUIView.payWithDashHandler = payWithDashHandler
        swiftUIView.sellDashHandler = sellDashHandler
        swiftUIView.onItemTapped = { [weak self] item in
            self?.pushDetails(for: item)
        }
        swiftUIView.onItemsUpdated = { [weak self] items in
            self?.updateMap(with: items)
        }
        return swiftUIView
    }

    private func presentDetailsSheetIfNeeded() {
        guard !didPresentDetailsSheet, presentedViewController == nil else { return }

        let sheetViewController = UIHostingController(rootView: makeLocationsView())
        sheetViewController.view.backgroundColor = .dw_secondaryBackground()
        sheetViewController.modalPresentationStyle = .pageSheet
        sheetViewController.isModalInPresentation = true

        if let sheet = sheetViewController.sheetPresentationController {
            // A small "collapsed" detent lets the user drop the sheet down to a peek
            // so they can see/interact with the map underneath (custom detent is iOS 16+).
            if #available(iOS 16.0, *) {
                // Collapsed peek shows the header + start of the list, matching the POIDetails sheet.
                let collapsed = UISheetPresentationController.Detent.custom(identifier: .init("collapsed")) { context in
                    max(140, context.maximumDetentValue * 0.14)
                }
                sheet.detents = [collapsed, .medium(), .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .large
            if #available(iOS 16.4, *) {
                if #unavailable(iOS 26.0) {
                    sheet.preferredCornerRadius = 20
                }
            }
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }

        detailsSheetViewController = sheetViewController
        didPresentDetailsSheet = true
        present(sheetViewController, animated: true)
    }

    private func adjustMapForBottomSheet() {
        guard let mapView, let location = mapView.initialCenterLocation else { return }

        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: defaultBottomSheetHeight, right: 0)
        mapView.setContentInsets(contentInsets, animated: false)
        mapView.setCenter(location, animated: false)
    }

    private func updateMap(with items: [ExplorePointOfUse]) {
        guard let mapView else { return }

        if !didConfigureInitialMapCenter {
            let firstMappableItem = items.first(where: { location(for: $0) != nil })
            configureInitialMapCenterIfNeeded(preferredItem: firstMappableItem)
        }

        mapView.show(merchants: items)
    }

    private func configureInitialMapCenterIfNeeded(preferredItem: ExplorePointOfUse?) {
        guard !didConfigureInitialMapCenter else { return }

        if let location = location(for: preferredItem) ?? searchCenterLocation() {
            mapView.initialCenterLocation = location
            mapView.setCenter(location, animated: false)
            didConfigureInitialMapCenter = true
            adjustMapForBottomSheet()
        }
    }

    private func location(for item: ExplorePointOfUse?) -> CLLocation? {
        guard let lat = item?.latitude, let lon = item?.longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    private func searchCenterLocation() -> CLLocation? {
        guard let searchCenterCoordinate, CLLocationCoordinate2DIsValid(searchCenterCoordinate) else { return nil }
        return CLLocation(latitude: searchCenterCoordinate.latitude, longitude: searchCenterCoordinate.longitude)
    }

    private func performAfterDismissingDetailsSheetIfNeeded(_ action: @escaping () -> Void) {
        guard let sheetViewController = detailsSheetViewController else {
            action()
            return
        }

        detailsSheetViewController = nil
        didPresentDetailsSheet = false
        sheetViewController.dismiss(animated: false, completion: action)
    }

    private func pushDetails(for item: ExplorePointOfUse) {
        performAfterDismissingDetailsSheetIfNeeded { [weak self] in
            guard let self else { return }

            let vc = POIDetailsViewController(
                pointOfUse: item,
                searchRadius: searchRadius,
                searchCenterCoordinate: searchCenterCoordinate,
                currentFilters: currentFilters
            )
            vc.payWithDashHandler = payWithDashHandler
            vc.sellDashHandler = sellDashHandler
            vc.onGiftCardPurchased = onGiftCardPurchased
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

extension AllMerchantLocationsViewController: ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleBounds bounds: ExploreMapBounds) {
        // The full-screen map is for spatial context only; list paging drives data loading.
    }

    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: ExplorePointOfUse) {
        pushDetails(for: merchant)
    }
}
