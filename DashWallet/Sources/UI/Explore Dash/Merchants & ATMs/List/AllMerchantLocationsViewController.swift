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
import UIKit

@objc
class AllMerchantLocationsViewController: ExplorePointOfUseListViewController {
    private let pointOfUse: ExplorePointOfUse

    init(pointOfUse: ExplorePointOfUse) {
        self.pointOfUse = pointOfUse
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
                                                     filterGroups: [], defaultFilters: nil, territoriesDataSource: nil)])
    }

    override func configureHierarchy() {
        title = NSLocalizedString("Where to Spend", comment: "");

        super.configureHierarchy()

        contentViewTopLayoutConstraint.constant = kDefaultOpenedMapPosition
        tableView.register(MerchantItemCell.self, forCellReuseIdentifier: MerchantItemCell.reuseIdentifier)
    }

}
