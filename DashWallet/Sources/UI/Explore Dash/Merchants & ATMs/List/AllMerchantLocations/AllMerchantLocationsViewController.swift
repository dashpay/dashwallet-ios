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

        let hosting = UIHostingController(rootView: AnyView(swiftUIView))
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    private func pushDetails(for item: ExplorePointOfUse) {
        let vc = POIDetailsViewController(
            pointOfUse: item,
            searchRadius: kDefaultRadius,
            searchCenterCoordinate: searchCenterCoordinate,
            currentFilters: currentFilters
        )
        vc.payWithDashHandler = payWithDashHandler
        vc.sellDashHandler = sellDashHandler
        vc.onGiftCardPurchased = onGiftCardPurchased
        navigationController?.pushViewController(vc, animated: true)
    }
}
