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
    
    @Published var sortByDistance = false
    @Published var sortByName = false
    @Published var sortByDiscount = false
    
    @Published var payWithDash = false
    @Published var ctxGiftCards = false {
        didSet {
            refreshSortOptions()
        }
    }
    #if PIGGYCARDS_ENABLED
    @Published var piggyGiftCards = false {
        didSet {
            refreshSortOptions()
        }
    }
    #endif
    
    @Published var sortOptions: [PointOfUseListFilters.SortBy]
    
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
        let baseChanges = sortByDistance != initialSortByDistance ||
            sortByName != initialSortByName ||
            sortByDiscount != initialSortByDiscount ||
            payWithDash != initialPayWithDash ||
            ctxGiftCards != initialCtxGiftCard ||
            denominationFixed != initialDenominationFixed ||
            denominationFlexible != initialDenominationFlexible ||
            selectedRadius != initialRadius ||
            selectedTerritory != initialTerritory

        #if PIGGYCARDS_ENABLED
        return baseChanges || piggyGiftCards != initialPiggyGiftCard
        #else
        return baseChanges
        #endif
    }
    
    private var hasAnyFiltersApplied: Bool {
        let baseFilters = sortByDistance || sortByName || sortByDiscount ||
            payWithDash || ctxGiftCards ||
            denominationFixed || denominationFlexible ||
            selectedRadius != nil || selectedTerritory != nil

        #if PIGGYCARDS_ENABLED
        return baseFilters || piggyGiftCards
        #else
        return baseFilters
        #endif
    }
    
    // MARK: - Initial State
    
    private let initialSortByDistance: Bool
    private let initialSortByName: Bool
    private let initialSortByDiscount: Bool
    private let initialPayWithDash: Bool
    private let initialCtxGiftCard: Bool
    #if PIGGYCARDS_ENABLED
    private let initialPiggyGiftCard: Bool
    #endif
    private let initialDenominationFixed: Bool
    private let initialDenominationFlexible: Bool
    private let initialRadius: PointOfUseListFilters.Radius?
    private let initialTerritory: Territory?
    private let initialSortOptions: [PointOfUseListFilters.SortBy]
    
    // MARK: - Available Options
    
    let availableRadiusOptions: [PointOfUseListFilters.Radius] = [
        .one, .five, .twenty, .fifty
    ]
    
    let showLocationSettings: Bool
    let showRadius: Bool
    let showTerritory: Bool
    let showPaymentTypes: Bool
    let showGiftCardTypes: Bool
    
    // MARK: - Data Sources
    
    var territoriesDataSource: TerritoryDataSource?
    
    // MARK: - Initialization
    
    let currentSegment: PointOfUseListSegment?

    init(
        filters: PointOfUseListFilters?,
        filterGroups: [PointOfUseListFiltersGroup],
        territoriesDataSource: TerritoryDataSource? = nil,
        sortOptions: [PointOfUseListFilters.SortBy] = [.name, .distance],
        currentSegment: PointOfUseListSegment? = nil
    ) {
        self.currentSegment = currentSegment
        self.showLocationSettings = filterGroups.contains(.locationService)
        self.showRadius = filterGroups.contains(.radius) && DWLocationManager.shared.isAuthorized
        self.showTerritory = filterGroups.contains(.territory)
        self.showPaymentTypes = filterGroups.contains(.paymentType)
        self.showGiftCardTypes = filterGroups.contains(.denominationType)
        self.territoriesDataSource = territoriesDataSource
        self.initialSortOptions = sortOptions
        self.sortOptions = sortOptions
        
        if let filters = filters {
            self.initialSortByDistance = filters.sortBy == .distance
            self.initialSortByName = filters.sortBy == .name
            self.initialSortByDiscount = filters.sortBy == .discount
            
            self.initialPayWithDash = filters.merchantPaymentTypes?.contains(.dash) ?? false
            self.initialCtxGiftCard = filters.merchantPaymentTypes?.contains(.ctx) ?? false
            #if PIGGYCARDS_ENABLED
            self.initialPiggyGiftCard = filters.merchantPaymentTypes?.contains(.piggyCards) ?? false
            #endif
            
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

            // Set current values to match initial state (from existing filters)
            self.sortByDistance = initialSortByDistance
            self.sortByName = initialSortByName
            self.sortByDiscount = initialSortByDiscount
            self.payWithDash = initialPayWithDash
            self.ctxGiftCards = initialCtxGiftCard
            #if PIGGYCARDS_ENABLED
            self.piggyGiftCards = initialPiggyGiftCard
            #endif
            self.denominationFixed = initialDenominationFixed
            self.denominationFlexible = initialDenominationFlexible
            self.selectedRadius = initialRadius
            self.selectedTerritory = initialTerritory
        } else {
            self.initialSortByDistance = false
            self.initialSortByName = true
            self.initialSortByDiscount = false
            self.initialPayWithDash = true
            self.initialCtxGiftCard = true
            #if PIGGYCARDS_ENABLED
            self.initialPiggyGiftCard = true
            #endif
            self.initialDenominationFixed = true
            self.initialDenominationFlexible = true
            self.initialRadius = .twenty
            self.initialTerritory = nil

            resetFilters()
        }

        // Ensure sort options are refreshed based on current gift card settings
        refreshSortOptions()
    }
    
    // MARK: - Actions
    
    func resetFilters() {
        sortByDistance = false
        sortByName = true
        sortByDiscount = false
        payWithDash = true
        ctxGiftCards = true
        #if PIGGYCARDS_ENABLED
        piggyGiftCards = true
        #endif
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
        // Don't allow unselecting the current radius - user must always have a radius selected
        if selectedRadius != option {
            selectedRadius = option
        }
        // If user tries to unselect current radius, keep it selected (do nothing)
    }
    
    func togglePaymentMethod(_ method: PointOfUseListFilters.SpendingOptions) {
        switch method {
        case .dash:
            let isLastOption: Bool
            #if PIGGYCARDS_ENABLED
            isLastOption = payWithDash && !ctxGiftCards && !piggyGiftCards
            #else
            isLastOption = payWithDash && !ctxGiftCards
            #endif

            if isLastOption {
                // If unchecking the last option, check the other ones
                payWithDash = false
                ctxGiftCards = true
                #if PIGGYCARDS_ENABLED
                piggyGiftCards = true
                #endif
            } else {
                payWithDash.toggle()
            }
        case .ctx:
            let isLastOption: Bool
            #if PIGGYCARDS_ENABLED
            isLastOption = ctxGiftCards && !payWithDash && !piggyGiftCards
            #else
            isLastOption = ctxGiftCards && !payWithDash
            #endif

            if isLastOption {
                // If unchecking the last option, check the other one
                ctxGiftCards = false
                #if PIGGYCARDS_ENABLED
                piggyGiftCards = false
                #endif
                payWithDash = true
            } else {
                ctxGiftCards.toggle()
            }
            
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            if piggyGiftCards && !ctxGiftCards && !payWithDash {
                // If unchecking the last option, check the other one
                ctxGiftCards = false
                piggyGiftCards = false
                payWithDash = true
            } else {
                piggyGiftCards.toggle()
            }
        #endif
        }
        
        // Reset denomination types when gift card is unchecked
        let noGiftCardsSelected: Bool
        #if PIGGYCARDS_ENABLED
        noGiftCardsSelected = !ctxGiftCards && !piggyGiftCards
        #else
        noGiftCardsSelected = !ctxGiftCards
        #endif

        if noGiftCardsSelected {
            denominationFixed = true
            denominationFlexible = true
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
        var paymentMethods: [PointOfUseListFilters.SpendingOptions] = []
        if payWithDash {
            paymentMethods.append(.dash)
        }
        if ctxGiftCards {
            paymentMethods.append(.ctx)
        }
        #if PIGGYCARDS_ENABLED
        if piggyGiftCards {
            paymentMethods.append(.piggyCards)
        }
        #endif
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
    
    private func refreshSortOptions() {
        // Always show all initial sort options - discount is available regardless of gift card selection
        sortOptions = initialSortOptions
    }
}
