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
    private let matchingAddress: String?
    private var withFee: Bool
    private(set) final var coins: UInt64
    private(set) final var toAddress: String?
    private(set) final var fromAddresses = Set<String>()

    init(coins: UInt64, address: String?, withFee: Bool = false) {
        matchingAddress = address
        self.coins = coins
        self.withFee = withFee
    }

    func matches(tx: DSTransaction) -> Bool {
        fromAddresses.removeAll()
        tx.inputAddresses.forEach {
            if let address = $0 as? String {
                fromAddresses.insert(address)
            }
        }

        // TODO: if CrowdNode inputs aren't from our own transaction, the fee might not be present.
        // Need another way to detect an error response in this case.
        let feeUsed = tx.feeUsed
        let withFee = feeUsed == UInt64.max ? false : withFee

        let output = tx.outputs.first(where: { output in
            let amountToMatch = withFee ? output.amount + feeUsed : output.amount
            return amountToMatch == coins &&
                (matchingAddress == nil || output.address == matchingAddress)
        })

        toAddress = output?.address ?? toAddress
        return output != nil
    }
}
