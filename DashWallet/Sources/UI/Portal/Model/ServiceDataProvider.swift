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

protocol ServiceDataProvider {
    func listenForData(handler: @escaping (([ServiceItem]) -> Void))
    func refresh()
}

class MookServiceDataProvider: ServiceDataProvider {
    func listenForData(handler: @escaping (([ServiceItem]) -> Void)) {
        handler([.init(status: .authorized, service: .uphold), .init(status: .idle, service: .coinbase)])
    }
    
    func refresh() {
        
    }
}

class ServiceDataProviderImpl: ServiceDataProvider {
    private var handler: (([ServiceItem]) -> Void)?
    
    private var upholdDataSource: ServiceDataSource = UpholdDataSource()
    private var coinbaseDataSource: ServiceDataSource = CoinbaseDataSource()
    
    private var items: [ServiceItem] = []
    
    init() {
        self.initializeDataSources()
    }
    
    func listenForData(handler: @escaping (([ServiceItem]) -> Void)) {
        self.handler = handler
    }
    
    func refresh() {
        upholdDataSource.refresh()
        coinbaseDataSource.refresh()
    }
    
    private func initializeDataSources() {
        upholdDataSource.serviceDidUpdate = { [weak self] item in
            self?.updateService(with: item)
        }
        
        coinbaseDataSource.serviceDidUpdate = { [weak self] item in
            self?.updateService(with: item)
        }
    }
    
    private func updateService(with item: ServiceItem) {
        if let idx = items.firstIndex(where: { $0.service == item.service }) {
            items[idx] = item
        }else{
            items.append(item)
        }
        
        let sortedItems = items
            .sorted(by: { $0.usageCount > $1.usageCount })
            .sorted(by: { $0.isInUse && !$1.isInUse })
        
        self.handler?(sortedItems)
    }
}
