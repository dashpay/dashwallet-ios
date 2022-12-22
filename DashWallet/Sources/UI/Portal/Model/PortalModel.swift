//
//  Created by Pavel Tikhonenko
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

import AuthenticationServices
import Foundation

// MARK: - Service

enum Service: CaseIterable {
    case coinbase
    case uphold
}

// MARK: - PortalModel.Section

extension PortalModel {
    enum Section: Int {
        case main
    }
}

extension Service {
    var title: String {
        switch self {
        case .coinbase: return NSLocalizedString("Coinbase", comment: "Dash Portal")
        case .uphold: return NSLocalizedString("Uphold", comment: "Dash Portal")
        }
    }

    var icon: String {
        switch self {
        case .coinbase: return "portal.coinbase"
        case .uphold: return "portal.uphold"
        }
    }

    var status: Bool {
        switch self {
        case .coinbase: return false
        case .uphold: return true
        }
    }

    var usageCount: Int {
        UserDefaults.standard.integer(forKey: kServiceUsageCount)
    }

    func increaseUsageCount() {
        UserDefaults.standard.set(usageCount + 1, forKey: kServiceUsageCount)
    }
}

// MARK: - PortalModelDelegate

protocol PortalModelDelegate: AnyObject {
    func serviceItemsDidChange();
}

// MARK: - PortalModel

class PortalModel: NetworkReachabilityHandling {
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    internal var reachabilityObserver: Any!

    weak var delegate: PortalModelDelegate?

    var items: [ServiceItem] = [] {
        didSet {
            delegate?.serviceItemsDidChange()
        }
    }

    var services: [Service] = Service.allCases
    private var upholdDashCard: DWUpholdCardObject?

    private var serviceItemDataProvider: ServiceDataProvider

    init() {
        serviceItemDataProvider = ServiceDataProviderImpl()
        serviceItemDataProvider.listenForData { [weak self] items in
            self?.items = items
            self?.delegate?.serviceItemsDidChange()
        }

        startNetworkMonitoring()
    }

    public func refreshData() {
        serviceItemDataProvider.refresh()
    }

    deinit {
        stopNetworkMonitoring()
    }
}


