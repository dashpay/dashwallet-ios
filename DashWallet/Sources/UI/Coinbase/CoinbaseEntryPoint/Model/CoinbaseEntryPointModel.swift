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

// MARK: ItemCellDataProvider

extension CoinbaseEntryPointItem: ItemCellDataProvider {
    static let supportedCases: [CoinbaseEntryPointItem] = [.buyDash, .convertCrypto, .transferDash]

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
            return NSLocalizedString("Between Dash Wallet and Coinbase.", comment: "Coinbase Entry Point")
        case .transferDash:
            return NSLocalizedString("Between Dash Wallet and Coinbase.", comment: "Coinbase Entry Point")
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
    let items: [CoinbaseEntryPointItem] = CoinbaseEntryPointItem.supportedCases

    var hasPaymentMethods = false

    var userDidSignOut: (() -> ())?
    var userDidChange: (() -> ())?

    var balance: UInt64 {
        guard let amount = Coinbase.shared.lastKnownBalance else { return 0 }

        return amount
    }

    private var userDidChangeListenerHandle: UserDidChangeListenerHandle!
    private var accountDidChangeHandle: AnyObject?

    init() {
        userDidChangeListenerHandle = Coinbase.shared.addUserDidChangeListener { [weak self] user in
            if user == nil {
                self?.userDidSignOut?()
            } else {
                self?.userDidChange?()
            }
        }

        accountDidChangeHandle = NotificationCenter.default.addObserver(forName: .accountDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.userDidChange?()
        })

        Task {
            let paymentMethods = try await Coinbase.shared.paymentMethods
            hasPaymentMethods = !paymentMethods.isEmpty
        }
    }

    public func signOut() {
        Task {
            try await Coinbase.shared.signOut()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(accountDidChangeHandle!)
        Coinbase.shared.removeUserDidChangeListener(handle: userDidChangeListenerHandle)
    }
}

// MARK: BalanceViewDataSource

extension CoinbaseEntryPointModel: BalanceViewDataSource {
    var mainAmountString: String {
        balance.formattedDashAmount
    }

    var supplementaryAmountString: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: balance.dashAmount, to: App.fiatCurrency) {
            fiat = NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing...", comment: "Balance")
        }

        return fiat
    }
}
