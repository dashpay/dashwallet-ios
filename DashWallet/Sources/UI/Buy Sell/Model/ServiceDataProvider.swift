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

// MARK: - ServiceDataProvider

protocol ServiceDataProvider {
    func listenForData(handler: @escaping (([ServiceItem]) -> Void))
    func refresh()
}

// MARK: - ServiceDataProviderImpl

class ServiceDataProviderImpl: ServiceDataProvider {
    private var handler: (([ServiceItem]) -> Void)?
    private var items: [ServiceItem]

    init() {
        items = [
            .init(service: .uphold, dataProvider: UpholdDataSource()),
            .init(service: .topper, dataProvider: nil)
        ]
        
        if CoinbaseDataSource.shouldShow() {
            items.insert(.init(service: .coinbase, dataProvider: CoinbaseDataSource()), at: 0)
        }
        
        for item in items {
            item.didUpdate = { [weak self] in
                self?.updateServices()
            }
        }
    }

    func listenForData(handler: @escaping (([ServiceItem]) -> Void)) {
        self.handler = handler
    }

    func refresh() {
        for item in items {
            item.refresh()
        }
    }

    private func updateServices() {
        let sortedItems = items
            .sorted(by: { $0.usageCount > $1.usageCount })
            .sorted(by: { $0.isInUse && !$1.isInUse })

        handler?(sortedItems)
    }
}
