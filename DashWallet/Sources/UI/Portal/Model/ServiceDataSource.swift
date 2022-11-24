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
import Combine

let kServiceUsageCount = "kServiceUsageCount"

class ServiceDataSource {
    var serviceDidUpdate: ((ServiceItem) -> Void)!
    
    var item: ServiceItem! {
        didSet {
            serviceDidUpdate?(item)
        }
    }

    func refresh() {
        assertionFailure("Override it")
    }
    
    
}

class UpholdDataSource: ServiceDataSource {
    private var dashCard: DWUpholdCardObject!
    private var isAuthorized: Bool { DWUpholdClient.sharedInstance().isAuthorized }
    
    override init() {
        super.init()
        
        self.item = .init(status: .initializing, service: .uphold)
    }
    
    override func refresh() {
        if DWUpholdClient.sharedInstance().isAuthorized {
            self.item = ServiceItem(status: .syncing, service: .uphold)
            
            if let balance: NSDecimalNumber = DWUpholdClient.sharedInstance().lastKnownBalance {
                item = .init(status: .authorized, service: .uphold, dashBalance: balance.uint64Value)
            } else {
                DWUpholdClient.sharedInstance().getCards { [weak self] dashCard, fiatCards in
                    self?.dashCard = dashCard
                    
                    if let available: NSDecimalNumber = dashCard?.available {
                        self?.item = .init(status: .authorized, service: .uphold, dashBalance: available.uint64Value)
                    } else {
                        self?.item = .init(status: .failed, service: .uphold)
                    }
                }
            }
            
        } else {
            self.item = ServiceItem(status: .idle, service: .uphold)
        }
    }
}

class CoinbaseDataSource: ServiceDataSource {
    private var coinbase: Coinbase = Coinbase.shared
    private var isAuthorized: Bool { coinbase.isAuthorized }
    
    private var cancelables = [AnyCancellable]()
    
    override init() {
        super.init()
        
        self.item = .init(status: .initializing, service: .coinbase)
    }
    
    override func refresh() {
        if isAuthorized {
            if let balance = coinbase.lastKnownBalance {
                self.item = ServiceItem(status: .authorized, service: .coinbase, dashBalance: balance)
            } else {
                self.item = ServiceItem(status: .syncing, service: .coinbase)
                
                coinbase.fetchUser()
                    .receive(on: DispatchQueue.main)
                    .sink(receiveCompletion: { [weak self] completion in
                        switch completion {
                        case .failure(_): self?.item = .init(status: .failed, service: .coinbase)
                        case .finished: break
                        }
                    }, receiveValue: { [weak self] response in
                        self?.item = .init(status: .authorized, service: .coinbase, dashBalance: response?.balance.plainAmount)
                    })
                    .store(in: &cancelables)
            }
            
        } else {
            self.item = .init(status: .idle, service: .coinbase)
        }
    }
}
