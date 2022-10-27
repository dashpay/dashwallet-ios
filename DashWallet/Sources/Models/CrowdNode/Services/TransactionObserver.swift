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

import Combine

public class TransactionObserver {
    /// Observes status changes for transactions that match `filter`
    func observe(filters: [TransactionFilter]) -> AnyPublisher<DSTransaction, Never> {
        return NotificationCenter.default.publisher(for: NSNotification.Name.DSTransactionManagerTransactionStatusDidChange)
            .compactMap { notification in
                let txKey = DSTransactionManagerNotificationTransactionKey

                if let info = notification.userInfo {
                    if let tx = info[txKey] as? DSTransaction {
                        return tx
                    }
                }

                return nil
            }
            .filter { tx in filters.contains { $0.matches(tx: tx) } }
            .eraseToAnyPublisher()
    }

    /// Waits for the first status change that matches `filter`
    func first(filters: TransactionFilter...) async -> DSTransaction {
        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = observe(filters: filters).first().sink(receiveValue: { tx in
                cancellable?.cancel()
                continuation.resume(returning: tx)
            })
        }
    }
}
