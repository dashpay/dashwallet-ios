//  
//  Created by Andrei Ashikhmin
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

public final class TxWithinTimePeriod: TransactionFilter {
    private let from: Date
    private let to: Date
    
    init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }

    func matches(tx: DSTransaction) -> Bool {
        return tx.timestamp >= from.timeIntervalSince1970 && tx.timestamp <= to.timeIntervalSince1970
    }
}
