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

extension UInt64 {
    var dashAmount: Decimal {
        Decimal(self)/Decimal(DUFFS)
    }

    var formattedDashAmount: String {
        dashAmount.formattedDashAmount
    }

    func formattedCryptoAmount(exponent: Int = 8) -> String {
        let plainNumber = Decimal(self)
        let number = plainNumber/pow(10, exponent)
        if #available(iOS 15.0, *) {
            return number.formatted(.number)
        } else {
            return "\(number)"
        }
    }
}

extension Int64 {
    var dashAmount: Decimal {
        Decimal(self)/Decimal(DUFFS)
    }

    var formattedDashAmount: String {
        dashAmount.formattedDashAmount
    }
}

extension Decimal {
    static var duffs: Decimal { Decimal(DUFFS) }

    var plainDashAmount: UInt64 {
        let plainAmount = self * .duffs
        return NSDecimalNumber(decimal: plainAmount).uint64Value
    }

    var formattedDashAmount: String {
        NumberFormatter.dashFormatter.string(from: self as NSNumber)!
    }
}
