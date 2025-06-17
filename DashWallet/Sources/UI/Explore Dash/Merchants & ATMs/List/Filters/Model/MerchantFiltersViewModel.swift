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

import Foundation
import Combine

class MerchantFiltersViewModel: ObservableObject {
    
    // MARK: - Filter Options
    
    let showSortByDistance: Bool
    
    @Published var sortByDistance = false
    @Published var sortByName = false
    @Published var sortByDiscount = false
    
    @Published var payWithDash = false
    @Published var useGiftCard = false
    
    @Published var denominationFixed = false
    @Published var denominationFlexible = false
    
    @Published var selectedRadius: PointOfUseListFilters.Radius?
    @Published var selectedTerritory: Territory?
    
    @Published var isLocationServiceEnabled = DWLocationManager.shared.isAuthorized
    
    // MARK: - Computed Properties
    
    var canApply: Bool {
        hasChanges
    }
    
    var canReset: Bool {
        hasAnyFiltersApplied || hasChanges
    }
    
    private var hasChanges: Bool {
        sortByDistance != initialSortByDistance ||
        sortByName != initialSortByName ||
        sortByDiscount != initialSortByDiscount ||
        payWithDash != initialPayWithDash ||
        useGiftCard != initialUseGiftCard ||
        denominationFixed != initialDenominationFixed ||
        denominationFlexible != initialDenominationFlexible ||
        selectedRadius != initialRadius ||
        selectedTerritory != initialTerritory
    }
    
    private var hasAnyFiltersApplied: Bool {
        sortByDistance || sortByName || sortByDiscount ||
        payWithDash || useGiftCard ||
        denominationFixed || denominationFlexible ||
        selectedRadius != nil || selectedTerritory != nil
    }
    
    // MARK: - Initial State
    
    private let initialSortByDistance: Bool
    private let initialSortByName: Bool
    private let initialSortByDiscount: Bool
    private let initialPayWithDash: Bool
    private let initialUseGiftCard: Bool
    private let initialDenominationFixed: Bool
    private let initialDenominationFlexible: Bool
    private let initialRadius: PointOfUseListFilters.Radius?
    private let initialTerritory: Territory?
    
    // MARK: - Available Options
    
    let availableRadiusOptions: [PointOfUseListFilters.Radius] = [
        .one, .five, .twenty, .fifty
    ]
    
    var showLocationSettings: Bool
    var showRadius: Bool
    var showTerritory: Bool
    
    // MARK: - Data Sources
    
    var territoriesDataSource: TerritoryDataSource?
    
    // MARK: - Initialization
    
    init(
        filters: PointOfUseListFilters?,
        showLocationSettings: Bool = false,
        showRadius: Bool = false,
        showTerritory: Bool = false,
        territoriesDataSource: TerritoryDataSource? = nil,
        showSortByDistance: Bool = true
    ) {
        self.showSortByDistance = showSortByDistance
        self.showLocationSettings = showLocationSettings
        self.showRadius = showRadius
        self.showTerritory = showTerritory
        self.territoriesDataSource = territoriesDataSource
        
        if let filters = filters {
            self.initialSortByDistance = filters.sortBy == .distance
            self.initialSortByName = filters.sortBy == .name
            self.initialSortByDiscount = filters.sortBy == .discount
            
            self.initialPayWithDash = filters.merchantPaymentTypes?.contains(.dash) ?? false
            self.initialUseGiftCard = filters.merchantPaymentTypes?.contains(.giftCard) ?? false
            
            self.initialDenominationFixed = filters.denominationType == .fixed || filters.denominationType == .both
            self.initialDenominationFlexible = filters.denominationType == .flexible || filters.denominationType == .both
            
            // Convert PointOfUseListFilters.Radius to RadiusOption
            if let filtersRadius = filters.radius {
                switch filtersRadius {
                case .one: self.initialRadius = .one
                case .five: self.initialRadius = .five
                case .twenty: self.initialRadius = .twenty
                case .fifty: self.initialRadius = .fifty
                }
            } else {
                self.initialRadius = nil
            }
            
            self.initialTerritory = filters.territory
            
            // Set current values
            self.sortByDistance = initialSortByDistance
            self.sortByName = initialSortByName
            self.sortByDiscount = initialSortByDiscount
            self.payWithDash = initialPayWithDash
            self.useGiftCard = initialUseGiftCard
            self.denominationFixed = initialDenominationFixed
            self.denominationFlexible = initialDenominationFlexible
            self.selectedRadius = initialRadius
            self.selectedTerritory = initialTerritory
        } else {
            self.initialSortByDistance = false
            self.initialSortByName = true
            self.initialSortByDiscount = false
            self.initialPayWithDash = true
            self.initialUseGiftCard = true
            self.initialDenominationFixed = true
            self.initialDenominationFlexible = true
            self.initialRadius = .twenty
            self.initialTerritory = nil
            
            resetFilters()
        }
    }
    
    // MARK: - Actions
    
    func resetFilters() {
        sortByDistance = false
        sortByName = true
        sortByDiscount = false
        payWithDash = true
        useGiftCard = true
        denominationFixed = true
        denominationFlexible = true
        selectedRadius = .twenty
        selectedTerritory = nil
    }
    
    func toggleSortBy(_ option: PointOfUseListFilters.SortBy) {
        // Only one sort option can be selected at a time
        sortByDistance = (option == .distance)
        sortByName = (option == .name)
        sortByDiscount = (option == .discount)
    }
    
    func toggleRadius(_ option: PointOfUseListFilters.Radius) {
        if selectedRadius == option {
            selectedRadius = nil
        } else {
            selectedRadius = option
        }
    }
    
    func togglePaymentMethod(_ method: ExplorePointOfUse.Merchant.PaymentMethod) {
        switch method {
        case .dash:
            if payWithDash && !useGiftCard {
                // If unchecking the last option, check the other one
                payWithDash = false
                useGiftCard = true
            } else {
                payWithDash.toggle()
            }
        case .giftCard:
            if useGiftCard && !payWithDash {
                // If unchecking the last option, check the other one
                useGiftCard = false
                payWithDash = true
            } else {
                useGiftCard.toggle()
            }
            // Reset denomination types when gift card is unchecked
            if !useGiftCard {
                denominationFixed = true
                denominationFlexible = true
            }
        }
    }
    
    func toggleDenominationType(_ type: PointOfUseListFilters.DenominationType) {
        switch type {
        case .flexible:
            if denominationFlexible && !denominationFixed {
                // If unchecking the last option, check the other one
                denominationFlexible = false
                denominationFixed = true
            } else {
                denominationFlexible.toggle()
            }
        case .fixed:
            if denominationFixed && !denominationFlexible {
                // If unchecking the last option, check the other one
                denominationFixed = false
                denominationFlexible = true
            } else {
                denominationFixed.toggle()
            }
        case .both:
            // Not used in toggle
            break
        }
    }
    
    func buildFilters() -> PointOfUseListFilters? {
        var filters = PointOfUseListFilters()
        var hasAnyFilters = false
        
        // Sort By
        if sortByDistance {
            filters.sortBy = .distance
            hasAnyFilters = true
        } else if sortByName {
            filters.sortBy = .name
            hasAnyFilters = true
        } else if sortByDiscount {
            filters.sortBy = .discount
            hasAnyFilters = true
        }
        
        // Payment Methods
        var paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod] = []
        if payWithDash {
            paymentMethods.append(.dash)
        }
        if useGiftCard {
            paymentMethods.append(.giftCard)
        }
        if !paymentMethods.isEmpty {
            filters.merchantPaymentTypes = paymentMethods
            hasAnyFilters = true
        }
        
        // Denomination Type
        if denominationFixed && denominationFlexible {
            filters.denominationType = .both
            hasAnyFilters = true
        } else if denominationFixed {
            filters.denominationType = .fixed
            hasAnyFilters = true
        } else if denominationFlexible {
            filters.denominationType = .flexible
            hasAnyFilters = true
        }
        
        // Radius
        if let radius = selectedRadius {
            filters.radius = radius
            hasAnyFilters = true
        }
        
        // Territory
        if let territory = selectedTerritory {
            filters.territory = territory
            hasAnyFilters = true
        }
        
        return hasAnyFilters ? filters : nil
    }
}
