//
//  Created by tkhp
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

extension Notification.Name {
    static let accountDidChangeNotification: Notification.Name = .init(rawValue: "accountDidChangeNotification")
}

// MARK: - CBAccount

class CBAccount {
    private weak var authInterop: CBAuthInterop!

    private var httpClient: CoinbaseAPI { CoinbaseAPI.shared }

    var info: CoinbaseUserAccountData!

    private let accountName: String

    init(accountName: String, authInterop: CBAuthInterop) {
        self.authInterop = authInterop
        self.accountName = accountName
    }

    init(info: CoinbaseUserAccountData, authInterop: CBAuthInterop) {
        self.authInterop = authInterop
        accountName = info.name
        self.info = info
    }

    init(accountName: String, info: CoinbaseUserAccountData, authInterop: CBAuthInterop) {
        self.authInterop = authInterop
        self.info = info
        self.accountName = accountName
    }
}

extension CBAccount {
    var accountId: String {
        info.id
    }

    var balance: UInt64 {
        info.plainAmount
    }

    var isDashAccount: Bool {
        info.currency.code == kDashAccount
    }

    private var accountNameForApiRequest: String {
        guard let info else { return accountName }
        return info.id
    }
}

// MARK: Account
extension CBAccount {
    @discardableResult
    public func refreshAccount() async throws -> CoinbaseUserAccountData {
        try await authInterop.refreshTokenIfNeeded()

        let result: BaseDataResponse<CoinbaseUserAccountData> = try await CoinbaseAPI.shared.request(.account(accountNameForApiRequest))
        let newAccount = result.data
        info = newAccount

        await MainActor.run {
            NotificationCenter.default.post(name: .accountDidChangeNotification, object: self)
        }

        return newAccount
    }

    func retrieveAddress() async throws -> String {
        do {
            let result: BaseDataResponse<CoinbaseAccountAddress> = try await httpClient.request(.createCoinbaseAccountAddress(accountId))
            return result.data.address
        } catch {
            throw Coinbase.Error.transactionFailed(.failedToObtainNewAddress)
        }
    }
}

// MARK: Transfer
extension CBAccount {
    public func send(amount: UInt64, verificationCode: String?) async throws -> CoinbaseTransaction {
        // NOTE: Maybe better to get the address once and use it during the tx flow
        guard let dashWalletAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress else {
            fatalError("No wallet")
        }

        let fiatCurrency = Coinbase.sendLimitCurrency
        if let localNumber = try? Coinbase.shared.currencyExchanger.convertDash(amount: Decimal(amount), to: fiatCurrency),
           localNumber > Coinbase.shared.sendLimit {
            throw Coinbase.Error.transactionFailed(.limitExceded)
        }

        guard amount >= DSTransaction.txMinOutputAmount() else {
            throw Coinbase.Error.transactionFailed(.invalidAmount)
        }

        guard amount >= kMinDashAmountToTransfer else {
            throw Coinbase.Error.transactionFailed(.enteredAmountTooLow(minimumAmount: kMinDashAmountToTransfer.formattedDashAmount))
        }

        // NOTE: Make sure we format the amount back into coinbase format (en_US)
        let amount = amount.formattedDashAmount.coinbaseAmount()

        do {
            try await authInterop.refreshTokenIfNeeded()

            let dto = CoinbaseTransactionsRequest(type: .send,
                                                  to: dashWalletAddress,
                                                  amount: amount,
                                                  currency: kDashCurrency,
                                                  idem: UUID())

            let result: BaseDataResponse<CoinbaseTransaction> = try await httpClient
                .request(.sendCoinsToWallet(accountId: accountId, verificationCode: verificationCode, dto: dto))
            try await refreshAccount()

            return result.data
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 402 {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 402")
            if let err = r.error?.errors.first {
                if err.id == .twoFactorRequired {
                    throw Coinbase.Error.transactionFailed(.twoFactorRequired)
                } else {
                    throw Coinbase.Error.transactionFailed(.unknown(err))
                }
            }

            throw Coinbase.Error.unknownError
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 400 && verificationCode != nil {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 400")
            throw Coinbase.Error.transactionFailed(.invalidVerificationCode)
        } catch HTTPClientError.statusCode(let r) where r.error?.errors.first != nil {
            if let error = r.error?.errors.first {
                throw Coinbase.Error.transactionFailed(.unknown(error))
            } else {
                throw HTTPClientError.statusCode(r)
            }
        } catch {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - \(error)")
            throw Coinbase.Error.transactionFailed(.unknown(error))
        }
    }
}

// MARK: Buy
extension CBAccount {
    public func placeCoinbaseBuyOrder(amount: UInt64, paymentMethod: CoinbasePaymentMethod) async throws -> CoinbasePlaceBuyOrder {
        let fiatCurrency = Coinbase.sendLimitCurrency
        if let localNumber = try? Coinbase.shared.currencyExchanger.convertDash(amount: Decimal(amount), to: fiatCurrency) {
            if localNumber < kMinUSDAmountOrder {
                let min = NSDecimalNumber(decimal: kMinUSDAmountOrder)
                let localFormatter = NumberFormatter.fiatFormatter(currencyCode: fiatCurrency)
                let str = localFormatter.string(from: min) ?? "$1.99"
                throw Coinbase.Error.transactionFailed(.enteredAmountTooLow(minimumAmount: str))
            } else if localNumber > Coinbase.shared.sendLimit {
                throw Coinbase.Error.transactionFailed(.limitExceded)
            }
        }

        // NOTE: Make sure we format the amount back into coinbase format (en_US)
        let amount = amount.formattedDashAmount.coinbaseAmount()

        let request = CoinbasePlaceBuyOrderRequest(amount: amount, currency: kDashCurrency, paymentMethod: paymentMethod.id, commit: false, quote: nil)

        do {
            try await authInterop.refreshTokenIfNeeded()
            let result: BaseDataResponse<CoinbasePlaceBuyOrder> = try await httpClient.request(.placeBuyOrder(accountId, request))
            return result.data
        } catch HTTPClientError.statusCode(let r) {
            if let error = r.error?.errors.first {
                throw Coinbase.Error.transactionFailed(.message(error.message))
            }

            throw Coinbase.Error.unknownError
        } catch {
            throw error
        }
    }

    public func commitCoinbaseBuyOrder(orderID: String) async throws -> CoinbasePlaceBuyOrder {
        do {
            try await authInterop.refreshTokenIfNeeded()
            let result: BaseDataResponse<CoinbasePlaceBuyOrder> = try await httpClient.request(.commitBuyOrder(accountId, orderID))
            try await refreshAccount()

            return result.data
        } catch HTTPClientError.statusCode(let r) {
            if let error = r.error?.errors.first {
                throw Coinbase.Error.transactionFailed(.message(error.message))
            }

            throw Coinbase.Error.unknownError
        } catch {
            throw error
        }
    }
}

// MARK: Trade
extension CBAccount {
    func convert(amount: String, to destination: CBAccount) async throws -> CoinbaseSwapeTrade {
        let baseIds: BaseDataCollectionResponse<CoinbaseBaseIDForCurrency> = try await CoinbaseAPI.shared.request(.getBaseIdForUSDModel("USD"))

        var targetAsset: String!
        var sourceAsset: String!

        for item in baseIds.data {
            if item.base == info.currencyCode {
                sourceAsset = item.baseID
            }

            if item.base == destination.info.currencyCode {
                targetAsset = item.baseID
            }
        }

        guard let sourceAsset, let targetAsset else {
            throw Coinbase.Error.transactionFailed(.message("Can't find source or target asset"))
        }

        let dto = CoinbaseSwapeTradeRequest(amount: amount,
                                            amountAsset: info.currencyCode,
                                            targetAsset: targetAsset,
                                            sourceAsset: sourceAsset)

        let response: BaseDataResponse<CoinbaseSwapeTrade> = try await CoinbaseAPI.shared.request(.swapTrade(dto))
        return response.data
    }

    public func commitTradeOrder(orderID: String) async throws -> CoinbaseSwapeTrade {
        do {
            try await authInterop.refreshTokenIfNeeded()
            let result: BaseDataResponse<CoinbaseSwapeTrade> = try await httpClient.request(.swapTradeCommit(orderID))
            try await refreshAccount()

            return result.data
        } catch HTTPClientError.statusCode(let r) {
            if let error = r.error?.errors.first {
                throw Coinbase.Error.transactionFailed(.message(error.message))
            }

            throw Coinbase.Error.unknownError
        } catch {
            throw error
        }
    }
}

// MARK: SourceViewDataProvider

extension CBAccount: SourceViewDataProvider {
    var image: SourceItemImage {
        .remote(info.iconURL)
    }

    var title: String {
        info.currency.code
    }

    var subtitle: String? {
        accountName
    }

    var balanceFormatted: String {
        info.balanceFormatted
    }

    var fiatBalanceFormatted: String {
        info.fiatBalanceFormatted
    }
}
