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

import Foundation

public final class SendCoinsService: NSObject {
    private let walletSendService = WalletSendService.shared

    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention).
    func sendCoins(address: String, amount: UInt64,
                   inputSelector: SingleInputAddressSelector? = nil, adjustAmountDownwards: Bool = false,
                   sessionAuthSufficient: Bool = false) async throws
        -> Data {
        return try await walletSendService.send(
            address: address,
            amount: amount,
            inputSelector: inputSelector,
            adjustAmountDownwards: adjustAmountDownwards,
            sessionAuthSufficient: sessionAuthSufficient
        )
    }

    /// Submits a DashDEX (SwapKit) deposit. Memo-less routes remain a plain send to the
    /// route's deposit address; memo-bearing routes build a MAYACHAIN-style deposit with the
    /// memo encoded in a zero-value OP_RETURN output.
    ///
    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention).
    func sendSwapKitSwap(depositAddress: String, dashAmount: UInt64, memo: String?) async throws -> Data {
        // Serialise swaps: don't start a new one until the previous swap tx is InstantSend-locked.
        if SwapPendingGate.shared.isAwaitingISLock {
            throw DashSpendError.swapAwaitingInstantLock
        }

        let txidWire: Data
        do {
            let trimmedMemo = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedMemo, !trimmedMemo.isEmpty {
                txidWire = try await walletSendService.sendSwapDeposit(
                    vaultAddress: depositAddress,
                    amount: dashAmount,
                    memo: trimmedMemo
                )
            } else {
                txidWire = try await walletSendService.send(address: depositAddress, amount: dashAmount)
            }
        } catch let error as NSError where WalletSendService.isAuthenticationCancelledError(error) {
            // Preserve the swap flow's existing auth-cancel handling, which keys on
            // `DashSpendError.authenticationCancelled` rather than the send service's NSError.
            throw DashSpendError.authenticationCancelled
        }

        SwapPendingGate.shared.register(txidWire: txidWire)
        return txidWire
    }

    // MARK: - BIP70

    /// Pays a `dash:`/BIP72 payment-request URL headlessly (CTX gift cards): parse → authorize →
    /// fetch + verify → build → broadcast → POST the Payment. Routes entirely through the
    /// app-side BIP70 stack (`BIP70PaymentService`) — no DashSync, no `DWPaymentProcessor`.
    ///
    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention — the caller's metadata key).
    func payWithDashUrl(url paymentUrlString: String) async throws -> Data {
        guard let uri = BIP70URI(paymentUrlString), let requestURL = uri.r else {
            throw DashSpendError.paymentProcessingError("Invalid payment request")
        }

        let network = try PaymentNetworkResolver.current()
        let service = BIP70PaymentService.makeForCurrentWallet()
        let result: SendResult
        do {
            result = try await service.confirmAndSendHeadless(
                from: requestURL, scheme: uri.scheme, network: network, callbackScheme: uri.callbackScheme)
        } catch BIP70Error.broadcastOutcomeUnknown(let txHashDisplay, let reason) {
            // The coins are gone as far as the merchant is concerned — it already holds the
            // signed bytes and can broadcast them itself. Hand the caller the txid so the
            // purchase is recorded rather than dropped; the caller decides how to present it.
            throw DashSpendError.paymentStatusUnknown(
                txIdWire: Data(txHashDisplay.reversed()), reason: reason)
        }

        let txidWire = Data(result.txHashDisplay.reversed())

        // Defensive registry write (the headless caller shows no success
        // screen today, but a courier resolved later should still find the
        // send facts if the persister row hasn't landed).
        WalletSendService.shared.recentSends.record(
            txidWire: txidWire,
            address: result.primaryAddress,
            amount: result.amount,
            fee: result.fee)

        return txidWire
    }
}
