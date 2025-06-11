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
        case .discount:
            return NSLocalizedString("Sorted by discount", comment: "Explore Dash/Filters")
        }
    }
}

// MARK: - PointOfUseListFilters

struct PointOfUseListFilters: Equatable {

    enum SortBy {
        case distance
        case name
        case discount
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
    
    enum DenominationType {
        case fixed
        case flexible
        case both
        
        var filterItems: [PointOfUseListFilterItem] {
            switch self {
            case .fixed:
                return [.denominationFixed]
            case .flexible:
                return [.denominationFlexible]
            case .both:
                return [.denominationFixed, .denominationFlexible]
            }
        }
    }

    var sortBy: SortBy?
    var merchantPaymentTypes: [ExplorePointOfUse.Merchant.PaymentMethod]?
    var radius: Radius?
    var territory: Territory?
    var denominationType: DenominationType?

    // In meters
    var currentRadius: Double {
        radius?.meters ?? kDefaultRadius
    }

    var appliedFiltersLocalizedString: String? {
        var string: [String] = []

        if DWLocationManager.shared.isAuthorized, let radius {
            let stringValue: String

            if Locale.current.usesMetricSystem {
                let value = ExploreDash.distanceFormatter.string(from: Measurement(value: radius.meters, unit: UnitLength.meters))
                stringValue = value
            } else {
                let value = ExploreDash.distanceFormatter
                    .string(from: Measurement(value: Double(radius.rawValue), unit: UnitLength.miles))
                stringValue = value
            }

            string.append(stringValue)
        }

//        if let value = merchantPaymentTypes { TODO: gift cards are temporary disabled, not showing filters
//            string += value.map { $0.filterLocalizedString }
//        }

        if let value = territory {
            string.append(value)
        }

        if let value = sortBy {
            string.append(value.filterLocalizedString)
        }

        return string.isEmpty ? nil : string.joined(separator: ", ")
    }
}

extension PointOfUseListFilters {
    var items: Set<PointOfUseListFilterItem> {
        var set: Set<PointOfUseListFilterItem> = []

        if let value = sortBy {
            switch value {
            case .name:
                set.insert(.sortName)
            case .distance:
                set.insert(.sortDistance)
            case .discount:
                set.insert(.sortDiscount)
            }
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
        
        if let value = denominationType {
            for item in value.filterItems {
                set.insert(item)
            }
        }

        return set
    }
}

// MARK: - PointOfUseListFilterItem

enum PointOfUseListFilterItem: String {
    case sortDistance
    case sortName
    case sortDiscount
    case paymentTypeDash
    case paymentTypeGiftCard
    case denominationFixed
    case denominationFlexible
    case radius1
    case radius5
    case radius20
    case radius50
    case location
    case locationService
    case reset

    var otherItems: [PointOfUseListFilterItem] {
        switch self {
        case .sortDistance:
            return [.sortName, .sortDiscount]
        case .sortName:
            return [.sortDistance, .sortDiscount]
        case .sortDiscount:
            return [.sortDistance, .sortName]
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
        case .sortDistance:
            return [.sortName, .sortDiscount]
        case .sortName:
            return [.sortDistance, .sortDiscount]
        case .sortDiscount:
            return [.sortDistance, .sortName]
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
        case .denominationFixed:
            return "image.explore.dash.wts.payment.gift-card"
        case .denominationFlexible:
            return "image.explore.dash.wts.payment.gift-card"
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .paymentTypeDash:
            return NSLocalizedString("Dash", comment: "Explore Dash: Filters")
        case .paymentTypeGiftCard:
            return NSLocalizedString("Gift Card", comment: "Explore Dash: Filters")
        case .denominationFixed:
            return NSLocalizedString("Fixed amounts", comment: "Explore Dash: Filters")
        case .denominationFlexible:
            return NSLocalizedString("Flexible amounts", comment: "Explore Dash: Filters")
        case .radius1:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("2 km", comment: "Explore Dash: Filters")
            } else {
                return NSLocalizedString("1 mile", comment: "Explore Dash: Filters")
            }
        case .radius5:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("8 km", comment: "Explore Dash: Filters")
            } else {
                return NSLocalizedString("5 miles", comment: "Explore Dash: Filters")
            }
        case .radius20:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("32 km", comment: "Explore Dash: Filters")
            } else {
                return NSLocalizedString("20 miles", comment: "Explore Dash: Filters")
            }
        case .radius50:
            if Locale.usesMetricMeasurementSystem {
                return NSLocalizedString("80 km", comment: "Explore Dash: Filters")
            } else {
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
        case .sortDiscount:
            return NSLocalizedString("Discount", comment: "Explore Dash: Filters")
        }
    }
}

// MARK: - PointOfUseListFiltersModel

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
        // TODO: Optimize
        selected != initialFilters || selectedTerritory != initialSelectedTerritory
    }

    var canReset: Bool {
        selected != defaultFilters || canApply
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
        } else {
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
        } else {
            selected.insert(.location)
        }

        selectedTerritory = territory
    }

    func resetFilters() {
        selected = defaultFilters
        selectedTerritory = nil
    }
}

// MARK: PointOfUseListFiltersModel
extension PointOfUseListFiltersModel {
    var appliedFilters: PointOfUseListFilters? {
        if selected.isEmpty && selectedTerritory == nil { return nil }

        var filters = PointOfUseListFilters()

        if selected.contains(.sortName) {
            filters.sortBy = .name
        }

        if selected.contains(.sortDistance) {
            filters.sortBy = .distance
        }
        
        if selected.contains(.sortDiscount) {
            filters.sortBy = .discount
        }

        if selected.contains(.radius1) {
            filters.radius = .one
        } else if selected.contains(.radius5) {
            filters.radius = .five
        } else if selected.contains(.radius20) {
            filters.radius = .twenty
        } else if selected.contains(.radius50) {
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
        
        if selected.contains(.denominationFixed) && selected.contains(.denominationFlexible) {
            filters.denominationType = .both
        } else if selected.contains(.denominationFixed) {
            filters.denominationType = .fixed
        } else if selected.contains(.denominationFlexible) {
            filters.denominationType = .flexible
        }

        return filters
    }
}

// MARK: Locale
extension Locale {
    static var usesMetricMeasurementSystem: Bool {
        if #available(iOS 16, *) {
            return current.measurementSystem == .metric
        } else {
            return current.usesMetricSystem
        }
    }
}
