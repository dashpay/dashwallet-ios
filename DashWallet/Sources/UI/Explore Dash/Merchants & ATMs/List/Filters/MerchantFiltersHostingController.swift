//
//  Created by Claude Code
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

import SwiftUI
import UIKit

class MerchantFiltersHostingController: UIHostingController<MerchantFiltersView> {
    
    weak var delegate: PointOfUseListFiltersViewControllerDelegate?
    
    init(
        currentFilters: PointOfUseListFilters?,
        defaultFilters: PointOfUseListFilters?,
        showLocationSettings: Bool = false,
        showRadius: Bool = false,
        showTerritory: Bool = false,
        territoriesDataSource: TerritoryDataSource? = nil
    ) {
        let filtersView = MerchantFiltersView(
            currentFilters: currentFilters,
            defaultFilters: defaultFilters,
            showLocationSettings: showLocationSettings,
            showRadius: showRadius,
            showTerritory: showTerritory,
            territoriesDataSource: territoriesDataSource
        ) { [weak delegate] filters in
            delegate?.apply(filters: filters)
        }
        
        super.init(rootView: filtersView)
        
        // Configure modal presentation
        modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = false
            }
        }
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.dw_background()
    }
}

// MARK: - Extension to support the existing filter groups

extension MerchantFiltersHostingController {
    
    static func create(
        for filterGroups: [PointOfUseListFiltersGroup],
        currentFilters: PointOfUseListFilters?,
        defaultFilters: PointOfUseListFilters?,
        territoriesDataSource: TerritoryDataSource?
    ) -> MerchantFiltersHostingController {
        
        let showLocationSettings = filterGroups.contains(.locationService)
        let showRadius = filterGroups.contains(.radius) && DWLocationManager.shared.isAuthorized
        let showTerritory = filterGroups.contains(.territory)
        
        return MerchantFiltersHostingController(
            currentFilters: currentFilters,
            defaultFilters: defaultFilters,
            showLocationSettings: showLocationSettings,
            showRadius: showRadius,
            showTerritory: showTerritory,
            territoriesDataSource: territoriesDataSource
        )
    }
}
