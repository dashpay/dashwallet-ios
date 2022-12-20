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

final class CBTransactions {
    private var httpClient: CoinbaseAPI { CoinbaseAPI.shared }

    func send(from accountId: String, amount: String, verificationCode: String?) async throws -> CoinbaseTransaction {
        guard let dashWalletAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress else {
            fatalError("No wallet")
        }

        // TODO: validate amount here

        do {
            let dto = CoinbaseTransactionsRequest(type: .send,
                                                  to: dashWalletAddress,
                                                  amount: amount,
                                                  currency: kDashCurrency,
                                                  idem: UUID())

            let result: BaseDataResponse<CoinbaseTransaction> = try await httpClient
                .request(.sendCoinsToWallet(accountId: accountId, verificationCode: verificationCode, dto: dto))
            DSLogger.log("Tranfer from coinbase: transferToWallet - success")
            return result.data
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 402 {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 402")
            throw Coinbase.Error.transactionFailed(.twoFactorRequired)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 400 {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 400")
            throw Coinbase.Error.transactionFailed(.invalidVerificationCode)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 401")
            throw Coinbase.Error.userSessionExpired
        } catch {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - \(error)")
            throw Coinbase.Error.transactionFailed(.unknown(error))
        }
    }

    func placeCoinbaseBuyOrder(accountId: String, request: CoinbasePlaceBuyOrderRequest) async throws -> CoinbasePlaceBuyOrder {
        do {
            let result: BaseDataResponse<CoinbasePlaceBuyOrder> = try await httpClient.request(.placeBuyOrder(accountId, request))
            return result.data
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 401")
            throw Coinbase.Error.userSessionExpired
        } catch HTTPClientError.statusCode(let r) {
            if let error = r.error?.errors.first {
                throw Coinbase.Error.transactionFailed(.message(error.message))
            }

            throw Coinbase.Error.unknownError
        } catch {
            throw error
        }
    }

    func commitCoinbaseBuyOrder(accountId: String, orderID: String) async throws -> CoinbasePlaceBuyOrder {
        let result: BaseDataResponse<CoinbasePlaceBuyOrder> = try await httpClient.request(.commitBuyOrder(accountId, orderID))

        return result.data
    }
}
