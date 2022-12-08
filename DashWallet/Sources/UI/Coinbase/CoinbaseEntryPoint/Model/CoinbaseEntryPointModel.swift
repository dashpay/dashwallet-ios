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

// MARK: - CoinbaseEntryPointItem

enum CoinbaseEntryPointItem: CaseIterable {
    case buyDash
    case sellDash
    case convertCrypto
    case transferDash
}

extension CoinbaseEntryPointItem {
    var title: String {
        switch self {
        case .buyDash:
            return NSLocalizedString("Buy Dash", comment: "Coinbase Entry Point")
        case .sellDash:
            return NSLocalizedString("Sell Dash", comment: "Coinbase Entry Point")
        case .convertCrypto:
            return NSLocalizedString("Convert Crypto", comment: "Coinbase Entry Point")
        case .transferDash:
            return NSLocalizedString("Transfer Dash", comment: "Coinbase Entry Point")
        }
    }

    var description: String {
        switch self {
        case .buyDash:
            return NSLocalizedString("Receive directly into Dash Wallet", comment: "Coinbase Entry Point")
        case .sellDash:
            return NSLocalizedString("Receive directly into Coinbase", comment: "Coinbase Entry Point")
        case .convertCrypto:
            return NSLocalizedString("Between Dash Wallet and Coinbase", comment: "Coinbase Entry Point")
        case .transferDash:
            return NSLocalizedString("Between Dash Wallet and Coinbase", comment: "Coinbase Entry Point")
        }
    }

    var icon: String {
        switch self {
        case .buyDash:
            return "buyCoinbase"
        case .sellDash:
            return "sellDash"
        case .convertCrypto:
            return "convertCrypto"
        case .transferDash:
            return "transferCoinbase"
        }
    }
}

// MARK: - CoinbaseEntryPointModel

final class CoinbaseEntryPointModel {
    let items: [CoinbaseEntryPointItem] = CoinbaseEntryPointItem.allCases

    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var networkStatus: NetworkStatus!
    var userDidSignOut: (() -> ())?
    var userDidChange: (() -> ())?

    var balance: UInt64 {
        guard let amount = Coinbase.shared.lastKnownBalance else { return 0 }

        return amount
    }

    private var reachability: DSReachabilityManager { DSReachabilityManager.shared() }
    private var reachabilityObserver: Any!

    private var userDidChangeListenerHandle: UserDidChangeListenerHandle!

    init() {
        initializeReachibility()

        userDidChangeListenerHandle = Coinbase.shared.addUserDidChangeListener { [weak self] user in
            if user == nil {
                self?.userDidSignOut?()
            } else {
                self?.userDidChange?()
            }
        }
    }

    public func signOut() {
        Task {
            try await Coinbase.shared.signOut()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(reachabilityObserver!)
        Coinbase.shared.removeUserDidChangeListener(handle: userDidChangeListenerHandle)
    }
}

extension CoinbaseEntryPointModel {
    private func initializeReachibility() {
        if !reachability.isMonitoring {
            reachability.startMonitoring()
        }

        reachabilityObserver = NotificationCenter.default
            .addObserver(forName: NSNotification.Name(rawValue: "org.dash.networking.reachability.change"),
                         object: nil,
                         queue: nil,
                         using: { [weak self] _ in
                             self?.updateNetworkStatus()
                         })

        updateNetworkStatus()
    }

    private func updateNetworkStatus() {
        networkStatus = reachability.networkStatus
        networkStatusDidChange?(networkStatus)
    }
}
