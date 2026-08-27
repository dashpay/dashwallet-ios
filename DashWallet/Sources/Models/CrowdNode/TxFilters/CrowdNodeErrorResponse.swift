//
//  Created by Andrei Ashikhmin
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

/// CrowdNode returns the sent amount - fee as the indication of an error
public final class CrowdNodeErrorResponse: CoinsToAddressTxFilter {
    /// Every well-known API response amount (apiOffset + code). The
    /// fee-tolerance window of the base class can overlap these (e.g. a
    /// 25 000-duff error window contains 20 002/20 004/20 008), and a known
    /// response code must never be classified as an error payout. TODO(B4)
    private static let knownApiAmounts: Set<UInt64> =
        Set(ApiCode.allCases.map { CrowdNode.apiOffset + $0.rawValue })

    init(errorValue: UInt64, accountAddress: String?) {
        let accountAddress = accountAddress
        super.init(coins: errorValue, address: accountAddress, withFee: true)
    }

    override func matches(_ tx: ObservedTransaction) -> Bool {
        guard super.matches(tx),
              fromAddresses.contains(CrowdNode.crowdNodeAddress),
              let amount = matchedAmount
        else { return false }
        return !Self.knownApiAmounts.contains(amount)
    }
}
