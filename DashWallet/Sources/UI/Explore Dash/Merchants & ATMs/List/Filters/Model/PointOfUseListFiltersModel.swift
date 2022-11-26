//  
//  Created by tkhp
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

import Foundation

extension ExplorePointOfUse.Merchant.PaymentMethod {
    var filterLocalizedString: String {
        switch self {
        case .dash:
            return NSLocalizedString("Pay with Dash", comment: "Explore Dash/Filters")
        case .giftCard:
            return NSLocalizedString("Use gift card", comment: "Explore Dash/Filters")
        }
    }
}

extension PointOfUseListFilters.SortBy {
    var filterLocalizedString: String {
        switch self {
        case .distance:
            return NSLocalizedString("Sorted by distance", comment: "Explore Dash/Filters")
        case .name:
            return NSLocalizedString("Sorted by name", comment: "Explore Dash/Filters")
        }
    }
}

extension PointOfUseListFilters.SortDirection {
    var filterLocalizedString: String {
        switch self {
        case .ascending:
            return NSLocalizedString("Sorting: A to Z", comment: "Explore Dash/Filters")
        case .descending:
            return NSLocalizedString("Sorting: Z to A", comment: "Explore Dash/Filters")
        }
    }
}

//MARK: PointOfUseListFilters
struct PointOfUseListFilters: Equatable {
    
    enum SortBy {
        case distance
        case name
    }
    
    enum SortDirection {
        case ascending
        case descending
    }
    
    enum Radius: Int {
        case one = 1
        case five = 5
        case twenty = 20
        case fifty = 50
        
        var filterItem: PointOfUseListFilterItem {
            switch self {
            case .one:
                return .radius1
            case .five:
                return .radius5
            case .twenty:
                return .radius20
            case .fifty:
                return .radius50
            }
        }
        
        var meters: Double {
            switch self {
            case .one:
                return 2000
            case .five:
                return 8000
            case .twenty:
                return 32000
            case .fifty:
                return 80000
            }
        }
    }
    
    var sortBy: SortBy?
    var sortNameDirection: SortDirection?
    var merchantPaymentTypes: [ExplorePointOfUse.Merchant.PaymentMethod]?
    var radius: Radius?
    var territory: Territory?
  
    //In meters
    var currentRadius: Double {
        radius?.meters ?? kDefaultRadius
    }
    
    var appliedFiltersLocalizedString: String? {
        var string: [String] = []
        
        if DWLocationManager.shared.isAuthorized, let radius = self.radius {
            let stringValue: String
            
            if Locale.current.usesMetricSystem {
                let value = ExploreDash.distanceFormatter.string(from: Measurement(value: radius.meters, unit: UnitLength.meters))
                stringValue = value
            }else{
                let value = ExploreDash.distanceFormatter.string(from: Measurement(value: Double(radius.rawValue), unit: UnitLength.miles))
                stringValue = value
            }
            
            string.append(stringValue)
        }
        
        if let value = merchantPaymentTypes {
            string += value.map({ $0.filterLocalizedString })
        }
        
        if let value = territory {
            string.append(value)
        }
        
        if let value = sortBy {
            string.append(value.filterLocalizedString)
        }
        
        if let value = sortNameDirection {
            string.append(value.filterLocalizedString)
        }
        
        return string.isEmpty ? nil : string.joined(separator: ", ")
    }
}

extension PointOfUseListFilters {
    var items: Set<PointOfUseListFilterItem> {
        var set: Set<PointOfUseListFilterItem> = []
        
        if let value = sortBy {
            set.insert(value == .name ? .sortName : .sortDistance)
        }
        
        if let value = sortNameDirection {
            set.insert(value == .ascending ? .sortAZ : .sortZA)
        }
        
        if let value = merchantPaymentTypes {
            let filterItems: [PointOfUseListFilterItem] = value.map { $0 == .dash ? .paymentTypeDash : .paymentTypeGiftCard }
            for item in filterItems {
                set.insert(item)
            }
        }
        
        if let value = radius {
            set.insert(value.filterItem)
        }
        
        return set
    }
}

//MARK: PointOfUseListFilterItem
enum PointOfUseListFilterItem: String {
    case sortAZ
    case sortZA
    case sortDistance
    case sortName
    case paymentTypeDash
    case paymentTypeGiftCard
    case radius1
    case radius5
    case radius20
    case radius50
    case location
    case locationService
    case reset
    
    var otherItems: [PointOfUseListFilterItem] {
        switch self {
            
        case .sortAZ:
            return [.sortZA]
        case .sortZA:
            return [.sortAZ]
        case .sortDistance:
            return [.sortName]
        case .sortName:
            return [.sortDistance]
        case .radius1:
            return [.radius5, .radius20, .radius50]
        case .radius5:
            return [.radius1, .radius20, .radius50]
        case .radius20:
            return [.radius1, .radius5, .radius50]
        case .radius50:
            return [.radius1, .radius5, .radius20]
        case .paymentTypeDash:
            return [.paymentTypeGiftCard]
        case .paymentTypeGiftCard:
            return [.paymentTypeDash]
        default:
            return []
        }
    }
    
    var itemsToUnselect: [PointOfUseListFilterItem] {
        switch self {
            
        case .sortAZ:
            return [.sortZA]
        case .sortZA:
            return [.sortAZ]
        case .sortDistance:
            return [.sortName]
        case .sortName:
            return [.sortDistance]
        case .radius1:
            return [.radius5, .radius20, .radius50]
        case .radius5:
            return [.radius1, .radius20, .radius50]
        case .radius20:
            return [.radius1, .radius5, .radius50]
        case .radius50:
            return [.radius1, .radius5, .radius20]
        default:
            return []
        }
    }
    
    var cellIdentifier: String {
        switch self {
        case .reset: return "FilterItemResetCell"
        case .location, .locationService: return "FilterItemDisclosureCell"
        default: return "FilterItemSelectableCell"
        }
    }
    
    var image: String? {
        switch self {
        case .paymentTypeDash:
            return "image.explore.dash.wts.payment.dash"
        case .paymentTypeGiftCard:
            return "image.explore.dash.wts.payment.gift-card"
        default: return nil
        }
    }
    
    var title: String {
        switch self {
            
        case .sortAZ:
            return NSLocalizedString("Name: from A to Z", comment: "Explore Dash: Filters")
        case .sortZA:
            return NSLocalizedString("Name: from Z to A", comment: "Explore Dash: Filters")
        case .paymentTypeDash:
            return NSLocalizedString("Dash", comment: "Explore Dash: Filters")
        case .paymentTypeGiftCard:
            return NSLocalizedString("Gift Card", comment: "Explore Dash: Filters")
        case .radius1:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("2 km", comment: "Explore Dash: Filters")
            }else{
                return NSLocalizedString("1 mile", comment: "Explore Dash: Filters")
            }
        case .radius5:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("8 km", comment: "Explore Dash: Filters")
            }else{
                return NSLocalizedString("5 miles", comment: "Explore Dash: Filters")
            }
        case .radius20:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("32 km", comment: "Explore Dash: Filters")
            }else{
                return NSLocalizedString("20 miles", comment: "Explore Dash: Filters")
            }
        case .radius50:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("80 km", comment: "Explore Dash: Filters")
            }else{
                return NSLocalizedString("50 miles", comment: "Explore Dash: Filters")
            }
        case .location:
            return NSLocalizedString("Current location", comment: "Explore Dash: Filters")
        case .locationService:
            return DWLocationManager.shared.localizedStatus
        case .reset:
            return NSLocalizedString("Reset Filters", comment: "Explore Dash: Filters")
        case .sortDistance:
            return NSLocalizedString("Distance", comment: "Explore Dash: Filters")
        case .sortName:
            return NSLocalizedString("Name", comment: "Explore Dash: Filters")
            
        }
    }
}

//MARK: PointOfUseListFiltersModel
final class PointOfUseListFiltersModel {
    var selected: Set<PointOfUseListFilterItem> = []
    var initialFilters: Set<PointOfUseListFilterItem>!
    var defaultFilters: Set<PointOfUseListFilterItem>!
    var selectedTerritory: Territory?
    var initialSelectedTerritory: Territory? {
        didSet {
            selectedTerritory = initialSelectedTerritory
        }
    }
    
    var canApply: Bool {
        //TODO: Optimize
        return selected != initialFilters || selectedTerritory != initialSelectedTerritory
    }
    
    var canReset: Bool {
        return selected != defaultFilters || canApply
    }
    
    func isFilterSelected(_ filter: PointOfUseListFilterItem) -> Bool {
        selected.contains(filter)
    }
    
    func toggle(filter: PointOfUseListFilterItem) -> Bool {
        if isFilterSelected(filter) {
            if !filter.otherItems.filter({ isFilterSelected($0) }).isEmpty {
                selected.remove(filter)
                return true
            }
        }else{
            unselect(filters: filter.itemsToUnselect)
            selected.insert(filter)
            return true
        }
        
        return false
    }
    
    func unselect(filters: [PointOfUseListFilterItem]) {
        for item in filters {
            selected.remove(item)
        }
    }
    
    func select(territory: Territory?) {
        if territory == nil {
            selected.remove(.location)
        }else{
            selected.insert(.location)
        }

        selectedTerritory = territory
    }
    
    func resetFilters() {
        selected = defaultFilters
        selectedTerritory = nil
    }
}

//MARK: PointOfUseListFiltersModel
extension PointOfUseListFiltersModel {
    var appliedFilters: PointOfUseListFilters? {
        if selected.isEmpty && selectedTerritory == nil { return nil }
        
        var filters: PointOfUseListFilters = PointOfUseListFilters()
        
        if selected.contains(.sortName) {
            filters.sortBy = .name
        }
        
        if selected.contains(.sortDistance) {
            filters.sortBy = .distance
        }
        
        if selected.contains(.sortAZ) {
            filters.sortNameDirection = .ascending
        }
        
        if selected.contains(.sortZA) {
            filters.sortNameDirection = .descending
        }
        
        if selected.contains(.radius1) {
            filters.radius = .one
        }else if selected.contains(.radius5) {
            filters.radius = .five
        }else if selected.contains(.radius20) {
            filters.radius = .twenty
        }else if selected.contains(.radius50) {
            filters.radius = .fifty
        }
        
        if selected.contains(.paymentTypeDash) {
            filters.merchantPaymentTypes = [.dash]
        }
        
        if selected.contains(.paymentTypeGiftCard) {
            var arr = (filters.merchantPaymentTypes ?? [])
            arr.append(.giftCard)
            
            filters.merchantPaymentTypes = arr
        }
        
        if let territory = selectedTerritory {
            filters.territory = territory
        }
        
        return filters
    }
}

//MARK: Locale
extension Locale {
    static var usesMetricMeasurementSystem: Bool {
        if #available(iOS 16, *) {
            return current.measurementSystem == .metric
        } else {
            return current.usesMetricSystem
        }
    }
}
