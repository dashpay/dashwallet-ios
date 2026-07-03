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

public class CoinsToAddressTxFilter: TransactionFilter {
    /// TODO(B4): tolerance window replaces DashSync's `tx.feeUsed`
    /// reconstruction for `withFee` matches — the fee of a CrowdNode-built
    /// transaction is unrecoverable from its raw bytes alone (it needs the
    /// previous outputs' amounts). A fee-deducted amount is accepted when it
    /// falls within `feeTolerance` below the expected value.
    static let feeTolerance: UInt64 = 10_000

    private let matchingAddress: String?
    private var withFee: Bool
    private(set) final var coins: UInt64
    private(set) final var toAddress: String?
    /// The matched output's exact amount (differs from `coins` on a
    /// fee-tolerance match); consumed by `CrowdNodeErrorResponse`'s
    /// known-code exclusion.
    private(set) final var matchedAmount: UInt64?
    private(set) final var fromAddresses = Set<String>()

    init(coins: UInt64, address: String?, withFee: Bool = false) {
        matchingAddress = address
        self.coins = coins
        self.withFee = withFee
    }

    func matches(_ tx: ObservedTransaction) -> Bool {
        fromAddresses.removeAll()

        let lowerBound = withFee ? coins - min(coins, Self.feeTolerance) : coins

        let output = tx.outputs.first(where: { output in
            let amountMatches = withFee
                ? (output.amount >= lowerBound && output.amount < coins)
                : output.amount == coins
            return amountMatches &&
                (matchingAddress == nil || output.address == matchingAddress)
        })

        toAddress = output?.address ?? toAddress
        matchedAmount = output?.amount ?? matchedAmount
        let doesMatch = output != nil

        if doesMatch {
            fromAddresses = tx.inputAddresses
        }

        return doesMatch
    }
}
