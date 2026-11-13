//
//  Created for the SwiftDashSDK migration.
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

/// What a new identity is funded with, per funding source. Apart from the
/// resolver because that file is compiled into both app targets, and the
/// shielded readiness and the DashPay constants read here are DashPay-only.
extension ContestedUsernameFee.Amounts {
    /// What a new identity is funded with for one name. The Dash Wallet
    /// and Platform balances pay 0.03 DASH for a standard name and
    /// `fundingDuffs` for a contested one. Shielded leaves the pool as a
    /// fixed exit denomination that does not follow the protocol version.
    @MainActor
    func newIdentityFundingDuffs(isContested: Bool, fromShielded: Bool) -> UInt64 {
        if fromShielded {
            return ShieldedIdentityFundingReadiness.requiredCredits(forContestedName: isContested)
                / Self.creditsPerDuff
        }
        return isContested ? fundingDuffs : UInt64(DWDP_MIN_BALANCE_TO_CREATE_USERNAME)
    }

    /// The most a username can cost, whichever source pays.
    @MainActor
    var maximumUsernameCostDuffs: UInt64 {
        max(newIdentityFundingDuffs(isContested: true, fromShielded: false),
            newIdentityFundingDuffs(isContested: true, fromShielded: true))
    }
}
