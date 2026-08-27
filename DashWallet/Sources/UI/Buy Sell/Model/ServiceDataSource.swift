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

import Combine
import Foundation
import StoreKit

let kServiceUsageCount = "kServiceUsageCount"

enum Status: Int {
    case unknown
    case idle
    case initializing
    case syncing
    case authorized
    case failed
}

// MARK: - ServiceDataSource

class ServiceDataSource {
    var serviceDidUpdate: (() -> Void)!

    var status: Status = .initializing
    var dashBalance: UInt64 = 0

    func refresh() {
        assertionFailure("Override it")
    }
}

// MARK: - UpholdDataSource

class UpholdDataSource: ServiceDataSource {
    private var dashCard: DWUpholdCardObject!
    private var isAuthorized: Bool { DWUpholdClient.sharedInstance().isAuthorized }

    override func refresh() {
        if DWUpholdClient.sharedInstance().isAuthorized {
            if let balance = DWUpholdClient.sharedInstance().lastKnownBalance as? Decimal {
                self.status = .authorized
                self.dashBalance = balance.plainDashAmount
            } else {
                DWUpholdClient.sharedInstance().getCards { [weak self] dashCard, _ in
                    self?.dashCard = dashCard

                    if let available = dashCard?.available as? Decimal {
                        self?.status = .authorized
                        self?.dashBalance = available.plainDashAmount
                    } else {
                        self?.status = .failed
                    }
                }
            }
        } else {
            status = .idle
        }
        
        serviceDidUpdate?()
    }
}

// MARK: - CoinbaseDataSource

class CoinbaseDataSource: ServiceDataSource {
    private var coinbase = Coinbase.shared
    private var isAuthorized: Bool { coinbase.isAuthorized }

    private var cancelables = [AnyCancellable]()

    private var userDidChangeListenerHandle: UserDidChangeListenerHandle!

    private var accountDidChangeHandle: AnyObject?
    
    static func shouldShow() -> Bool {
        if let storefront = SKPaymentQueue.default().storefront {
            return storefront.countryCode != "GB"
        } else {
            return true
        }
    }

    override init() {
        super.init()

        userDidChangeListenerHandle = Coinbase.shared.addUserDidChangeListener { [weak self] _ in
            self?.refresh()
        }

        accountDidChangeHandle = NotificationCenter.default.addObserver(forName: .accountDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.refresh()
        })
    }

    override func refresh() {
        if isAuthorized {
            if let balance = coinbase.lastKnownBalance {
                status = .authorized
                dashBalance = balance
            } else {
                status = .syncing
            }
        } else {
            status = .idle
        }
        
        serviceDidUpdate?()
    }

    deinit {
        NotificationCenter.default.removeObserver(accountDidChangeHandle!)
        Coinbase.shared.removeUserDidChangeListener(handle: userDidChangeListenerHandle)
    }
}
