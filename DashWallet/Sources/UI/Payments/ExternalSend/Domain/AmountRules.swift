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

/// Whether a typed amount can be sent from a source.
enum AmountCheck: Equatable {
    case ok
    /// Allowed, but it leaves the identity below the DashPay reserve (AC-09).
    case okWithReserveWarning
    case notEnough
}

/// Amount rules of the Send screen. Max for Core, Shielded and Platform comes from the existing per-route
/// planners; this type covers the Identity Max and its DashPay reserve, the balance check and the DASH value
/// of credits.
enum AmountRules {
    enum MaxResult: Equatable {
        case amount(UInt64)
        /// Nothing is left above the DashPay reserve once the fee is paid.
        case disabledReserveSpent
    }

    /// The most an identity can send: its credits less the fee and the DashPay reserve.
    static func identityMax(balanceCredits: UInt64, feeCredits: UInt64) -> MaxResult {
        let reserve = IdentityCreditBalance.lowBalance
        guard let spendable = spendable(balance: balanceCredits, fee: feeCredits), spendable > reserve else {
            return .disabledReserveSpent
        }
        return .amount(spendable - reserve)
    }

    /// `balance`, `fee` and `amount` are in the source's own unit: duffs for Core, Shielded and Platform,
    /// credits for Identity.
    static func check(amount: UInt64, source: SendSource, balance: UInt64, fee: UInt64) -> AmountCheck {
        guard let spendable = spendable(balance: balance, fee: fee), amount <= spendable else {
            return .notEnough
        }
        if source == .identity, spendable - amount < IdentityCreditBalance.lowBalance {
            return .okWithReserveWarning
        }
        return .ok
    }

    /// The DASH value of credits in duffs, rounded down, as the biometric spending limit counts it.
    static func dashValue(of credits: UInt64) -> UInt64 {
        UInt64(PlatformAddressActivityUnitPolicy.duffs(fromCredits: credits))
    }

    private static func spendable(balance: UInt64, fee: UInt64) -> UInt64? {
        balance >= fee ? balance - fee : nil
    }
}
