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
    
    enum SpendingOptions {
        case dash
        case ctx
        #if PIGGYCARDS_ENABLED
        case piggyCards
        #endif

        var filterLocalizedString: String {
            switch self {
            case .dash:
                return NSLocalizedString("Pay with Dash", comment: "Explore Dash/Filters")
            case .ctx:
                return NSLocalizedString("CTX gift card", comment: "Explore Dash/Filters")
            #if PIGGYCARDS_ENABLED
            case .piggyCards:
                return NSLocalizedString("PiggyCards gift card", comment: "Explore Dash/Filters")
            #endif
            }
        }
    }

    enum SortBy {
        case distance
        case name
        case discount
    }

    enum Radius: Int, Identifiable {
        case one = 1
        case five = 5
        case twenty = 20
        case fifty = 50

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
        
        var id: Int { rawValue }
        
        var displayText: String {
            if Locale.usesMetricMeasurementSystem {
                switch self {
                case .one: return NSLocalizedString("2 km", comment: "Explore Dash: Filters")
                case .five: return NSLocalizedString("8 km", comment: "Explore Dash: Filters")
                case .twenty: return NSLocalizedString("32 km", comment: "Explore Dash: Filters")
                case .fifty: return NSLocalizedString("80 km", comment: "Explore Dash: Filters")
                }
            } else {
                switch self {
                case .one: return NSLocalizedString("1 mile", comment: "Explore Dash: Filters")
                case .five: return NSLocalizedString("5 miles", comment: "Explore Dash: Filters")
                case .twenty: return NSLocalizedString("20 miles", comment: "Explore Dash: Filters")
                case .fifty: return NSLocalizedString("50 miles", comment: "Explore Dash: Filters")
                }
            }
        }
    }
    
    enum DenominationType {
        case fixed
        case flexible
        case both
    }

    var sortBy: SortBy?
    var merchantPaymentTypes: [SpendingOptions]?
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

        if let value = merchantPaymentTypes {
            string += value.map { $0.filterLocalizedString }
        }

        if let value = territory {
            string.append(value)
        }

        if let value = sortBy {
            string.append(value.filterLocalizedString)
        }

        return string.isEmpty ? nil : string.joined(separator: ", ")
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
