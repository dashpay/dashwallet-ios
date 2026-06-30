//
//  Created by Andrei Ashikhmin
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

public final class SendCoinsService: NSObject {
    private let walletSendService = WalletSendService.shared

    func sendCoins(address: String, amount: UInt64,
                   inputSelector: SingleInputAddressSelector? = nil, adjustAmountDownwards: Bool = false) async throws
        -> DSTransaction {
        return try await walletSendService.send(
            address: address,
            amount: amount,
            inputSelector: inputSelector,
            adjustAmountDownwards: adjustAmountDownwards
        )
    }

    // MARK: - BIP70

    /// Pays a `dash:`/BIP72 payment-request URL headlessly (CTX gift cards): parse → authorize →
    /// fetch + verify → build → broadcast → POST the Payment. Routes entirely through the
    /// app-side BIP70 stack (`BIP70PaymentService`) — no DashSync, no `DWPaymentProcessor`.
    ///
    /// Returns a `DSTransaction` constructed locally from the signed bytes (a data holder for the
    /// caller's txid metadata), preserving the prior `async throws -> DSTransaction` contract.
    func payWithDashUrl(url paymentUrlString: String) async throws -> DSTransaction {
        guard let uri = BIP70URI(paymentUrlString), let requestURL = uri.r else {
            throw DashSpendError.paymentProcessingError("Invalid payment request")
        }

        let network = try PaymentNetworkResolver.current()
        let service = BIP70PaymentService.makeForCurrentWallet()
        let result = try await service.confirmAndSendHeadless(
            from: requestURL, scheme: uri.scheme, network: network, callbackScheme: uri.callbackScheme)

        let chain = DWEnvironment.sharedInstance().currentChain
        return DSTransaction(message: result.signedTxData, on: chain)
    }
}
