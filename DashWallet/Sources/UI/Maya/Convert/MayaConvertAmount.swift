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

/// Which currency the user is currently entering; the other two are derived.
enum CurrencyInputType {
    case dash, fiat, crypto
}

/// Mirrors Android's `Amount` model from ConvertViewViewModel.
/// Keeps dash, fiat, and selected-crypto amounts in sync via exchange rates.
/// The `anchor` indicates which value was directly user-entered; the other two are derived.
struct MayaConvertAmount {
    private(set) var dash: Decimal = 0
    private(set) var fiat: Decimal = 0
    private(set) var crypto: Decimal = 0
    private(set) var anchor: CurrencyInputType = .dash

    /// 1 DASH = x local fiat (e.g. 35 means 1 DASH = $35)
    var dashFiatRate: Decimal = 1

    /// 1 crypto token = x local fiat (e.g. 65000 means 1 BTC = $65000). Zero until pool data loads.
    var cryptoFiatRate: Decimal = 0

    /// 1 DASH = x crypto (derived: dashFiatRate / cryptoFiatRate)
    var cryptoDashRate: Decimal {
        guard !dashFiatRate.isZero, !cryptoFiatRate.isZero else { return 0 }
        return dashFiatRate / cryptoFiatRate
    }

    /// DASH amount expressed as satoshis (duffs) for use in Maya API requests.
    var dashSatoshis: Int64 {
        guard dash > 0 else { return 0 }
        let satoshis = dash * Decimal(100_000_000) // 1 DASH = 1e8 duffs
        var rounded = Decimal()
        var val = satoshis
        NSDecimalRound(&rounded, &val, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    var anchoredValue: Decimal {
        switch anchor {
        case .dash: return dash
        case .fiat: return fiat
        case .crypto: return crypto
        }
    }

    mutating func setDash(_ value: Decimal) {
        dash = value
        anchor = .dash
        recalculate()
    }

    mutating func setFiat(_ value: Decimal) {
        fiat = value
        anchor = .fiat
        recalculate()
    }

    mutating func setCrypto(_ value: Decimal) {
        crypto = value
        anchor = .crypto
        recalculate()
    }

    /// Updates exchange rates and recalculates derived values from the current anchor.
    mutating func updateRates(dashFiatRate: Decimal, cryptoFiatRate: Decimal) {
        self.dashFiatRate = dashFiatRate
        self.cryptoFiatRate = cryptoFiatRate
        recalculate()
    }

    private mutating func recalculate() {
        switch anchor {
        case .dash:
            fiat = dash * dashFiatRate
            crypto = cryptoDashRate.isZero ? 0 : dash * cryptoDashRate
        case .fiat:
            dash = dashFiatRate.isZero ? 0 : fiat / dashFiatRate
            crypto = cryptoFiatRate.isZero ? 0 : fiat / cryptoFiatRate
        case .crypto:
            // dash = crypto / (cryptoDashRate) = crypto * (cryptoFiatRate / dashFiatRate)
            dash = cryptoDashRate.isZero ? 0 : crypto / cryptoDashRate
            fiat = crypto * cryptoFiatRate
        }
    }
}
