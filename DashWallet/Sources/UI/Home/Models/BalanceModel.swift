//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

@objc(DWBalanceModel)
final class BalanceModel: NSObject {
    @objc
    let value: UInt64

    @objc
    init(with value: UInt64) {
        self.value = value

        super.init()
    }

    @objc
    func dashAmountStringWithFont(_ font: UIFont, tintColor: UIColor) -> NSAttributedString {
        NSAttributedString.dw_dashAttributedString(forAmount: value, tintColor: tintColor, font: font)
    }

    @objc
    func fiatAmountString() -> String {
        CurrencyExchanger.shared.fiatAmountString(for: value.dashAmount)
    }
}
