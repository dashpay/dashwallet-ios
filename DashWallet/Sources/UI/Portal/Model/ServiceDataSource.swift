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

let kServiceUsageCount = "kServiceUsageCount"

// MARK: - ServiceDataSource

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

// MARK: - UpholdDataSource

class UpholdDataSource: ServiceDataSource {
    private var dashCard: DWUpholdCardObject!
    private var isAuthorized: Bool { DWUpholdClient.sharedInstance().isAuthorized }

    override init() {
        super.init()

        item = .init(status: .initializing, service: .uphold)
    }

    override func refresh() {
        if DWUpholdClient.sharedInstance().isAuthorized {
            item = ServiceItem(status: .syncing, service: .uphold)

            if let balance = DWUpholdClient.sharedInstance().lastKnownBalance as? Decimal {
                item = .init(status: .authorized, service: .uphold, dashBalance: balance.plainDashAmount)
            } else {
                DWUpholdClient.sharedInstance().getCards { [weak self] dashCard, _ in
                    self?.dashCard = dashCard

                    if let available = dashCard?.available as? Decimal {
                        self?.item = .init(status: .authorized, service: .uphold, dashBalance: available.plainDashAmount)
                    } else {
                        self?.item = .init(status: .failed, service: .uphold)
                    }
                }
            }
        } else {
            item = ServiceItem(status: .idle, service: .uphold)
        }
    }
}

// MARK: - CoinbaseDataSource

class CoinbaseDataSource: ServiceDataSource {
    private var coinbase = Coinbase.shared
    private var isAuthorized: Bool { coinbase.isAuthorized }

    private var cancelables = [AnyCancellable]()

    private var userDidChangeListenerHandle: UserDidChangeListenerHandle!

    private var accountDidChangeHandle: AnyObject?

    override init() {
        super.init()

        item = .init(status: .initializing, service: .coinbase)

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
                item = ServiceItem(status: .authorized, service: .coinbase, dashBalance: balance)
            } else {
                item = ServiceItem(status: .syncing, service: .coinbase)
            }
        } else {
            item = .init(status: .idle, service: .coinbase)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(accountDidChangeHandle!)
        Coinbase.shared.removeUserDidChangeListener(handle: userDidChangeListenerHandle)
    }
}
