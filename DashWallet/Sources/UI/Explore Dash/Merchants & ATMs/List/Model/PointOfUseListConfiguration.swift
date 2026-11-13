//
//  Created by Dash Core Group
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

// MARK: - PointOfUseListConfiguration

/// What one point-of-use list screen (ATMs, Where to Spend) adds to the shared
/// list: its segments, the segment and filters it opens with, and its copy.
struct PointOfUseListConfiguration {
    enum Kind {
        /// Every row is a map pin; details open with the search radius.
        case atms
        /// The map shows each physical location of the listed merchants, not
        /// one pin per row.
        case merchants
    }

    let kind: Kind
    let segments: [PointOfUseListSegment]
    let initialSegmentIndex: Int
    let initialFilters: PointOfUseListFilters?
    let locationServicePopupTitle: String
    let locationServicePopupDetails: String
}

extension PointOfUseListConfiguration {
    static func atms() -> PointOfUseListConfiguration {
        PointOfUseListConfiguration(
            kind: .atms,
            segments: [
                AtmListSegmnets.all.pointOfUseListSegment,
                AtmListSegmnets.buy.pointOfUseListSegment,
                AtmListSegmnets.sell.pointOfUseListSegment,
                AtmListSegmnets.buyAndSell.pointOfUseListSegment,
            ],
            initialSegmentIndex: AtmListSegmnets.all.rawValue,
            initialFilters: nil,
            locationServicePopupTitle: NSLocalizedString("ATM search works better with Location Services turned on.", comment: ""),
            locationServicePopupDetails: NSLocalizedString(
                "Your location is used to show your position on the map, ATMs in the selected redius and improve search results.",
                comment: ""))
    }

    /// Opens on `initialSegment` when given, otherwise on Nearby when location
    /// is authorized and on Online when it is not.
    static func merchants(initialSegment: MerchantsListSegment?, isLocationAuthorized: Bool) -> PointOfUseListConfiguration {
        let segment = initialSegment ?? (isLocationAuthorized ? .nearby : .online)

        return PointOfUseListConfiguration(
            kind: .merchants,
            segments: [
                MerchantsListSegment.online.pointOfUseListSegment,
                MerchantsListSegment.nearby.pointOfUseListSegment,
                MerchantsListSegment.all.pointOfUseListSegment,
            ],
            initialSegmentIndex: segment.rawValue,
            // Set before the model's first fetch, so the opening segment never
            // races an unfiltered request against the filtered one.
            initialFilters: .defaults(sortBy: segment == .nearby ? .distance : .name),
            locationServicePopupTitle: NSLocalizedString("Merchant search works better with Location Services turned on.", comment: ""),
            locationServicePopupDetails: NSLocalizedString(
                "Your location is used to show your position on the map, merchants in the selected redius and improve search results.",
                comment: ""))
    }
}

// MARK: - Default filters

extension PointOfUseListFilters {
    /// Every payment type, both denomination types, a 20-mile radius.
    static func defaults(sortBy: SortBy) -> PointOfUseListFilters {
        var paymentTypes: [SpendingOptions] = [.dash, .ctx]
        #if PIGGYCARDS_ENABLED
        paymentTypes.append(.piggyCards)
        #endif

        return PointOfUseListFilters(
            sortBy: sortBy,
            merchantPaymentTypes: paymentTypes,
            radius: .twenty,
            territory: nil,
            denominationType: .both)
    }
}
