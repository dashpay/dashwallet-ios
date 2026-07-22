//
//  Created by Roman Chornyi
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

/// The routing network that will execute a swap for a given asset.
/// Mirrors Android's RouteProvider concept in `SwapKitApiAggregator.kt`.
enum RouteProvider {
    /// Only MAYACHAIN can route this asset.
    case maya
    /// Only NEAR can route this asset.
    case near
    /// Both MAYACHAIN and NEAR can route this asset; preferred provider resolved by quote.
    case multiple

    var displayLabel: String {
        switch self {
        case .maya: return NSLocalizedString("Maya", comment: "Swap route provider")
        case .near: return NSLocalizedString("NEAR", comment: "Swap route provider")
        case .multiple: return NSLocalizedString("Multiple networks", comment: "Swap route provider")
        }
    }

    /// Compact label for narrow trailing column in CoinSelector.
    var shortLabel: String {
        switch self {
        case .maya: return NSLocalizedString("Maya", comment: "Swap route provider short")
        case .near: return NSLocalizedString("NEAR", comment: "Swap route provider short")
        case .multiple: return NSLocalizedString("Multiple", comment: "Swap route provider short")
        }
    }
}
