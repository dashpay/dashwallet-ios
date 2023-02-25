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

public final class SingleInputAddressSelector {
    let candidates: [DSTransaction]
    let address: String
    private let account = DWEnvironment.sharedInstance().currentAccount

    init(candidates: [DSTransaction], address: String) {
        self.candidates = candidates
        self.address = address
    }

    func selectFor(tx: DSTransaction) -> UInt64 {
        var balance: UInt64 = 0

        candidates
            .filter { _ in !account.transactionOutputsAreLocked(tx) }
            .forEach { candidate in
                for (i, output) in candidate.outputs.enumerated() {
                    if output.address == self.address {
                        tx.addInputHash(candidate.txHash, index: UInt(i), script: output.outScript)
                        balance += output.amount
                    }
                }
            }

        return balance
    }
}
