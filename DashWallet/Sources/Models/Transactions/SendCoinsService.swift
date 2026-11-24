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
    private let makeBIP70Service: () -> BIP70PaymentService
    private let sendToAddress: AddressSend

    /// A send to a plain address. `sessionAuthSufficient` is `WalletSendService`'s flag:
    /// `false` asks for the PIN or biometrics even when the app was just unlocked.
    typealias AddressSend = (_ address: String, _ amount: UInt64, _ sessionAuthSufficient: Bool) async throws -> Data

    /// - Parameters:
    ///   - makeBIP70Service: builds the service `payWithDashUrl` pays through.
    ///   - sendToAddress: the send `payGiftCardOrder` pays through; `nil` for
    ///     `WalletSendService.sendCarryingUnknownOutcome`.
    init(makeBIP70Service: @escaping () -> BIP70PaymentService = {
        // The headless gift-card purchase keeps its own transport rule; https is required
        // only on the interactive path (`BIP70InteractiveCoordinator`).
        BIP70PaymentService.makeForCurrentWallet(requiresHTTPS: false)
    }, sendToAddress: AddressSend? = nil) {
        self.makeBIP70Service = makeBIP70Service
        self.sendToAddress = sendToAddress ?? { address, amount, sessionAuthSufficient in
            try await WalletSendService.shared.sendCarryingUnknownOutcome(
                address: address, amount: amount, sessionAuthSufficient: sessionAuthSufficient)
        }
        super.init()
    }

    /// Pays a gift card order that names a plain address and an amount (PiggyCards). The send
    /// is asked with `sessionAuthSufficient: false`, so `WalletSendService` prompts for the
    /// PIN or biometrics even when the app was just unlocked.
    ///
    /// An unknown broadcast outcome is thrown as `DashSpendError.paymentStatusUnknown` with
    /// the txid, as `payWithDashUrl` does, so the caller can record the order against the
    /// transaction it just handed to the network. Every other failure is thrown as
    /// `WalletSendService.send` throws it.
    ///
    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention).
    func payGiftCardOrder(address: String, amount: UInt64) async throws -> Data {
        do {
            return try await sendToAddress(address, amount, false)
        } catch let unknown as WalletSendService.BroadcastOutcomeUnknown {
            throw Self.paymentStatusUnknown(from: unknown)
        }
    }

    /// The gift card error for a payment whose broadcast outcome is unknown. The reason is the
    /// SDK's diagnostic when the send error carries one; it is logged, never shown.
    static func paymentStatusUnknown(from unknown: WalletSendService.BroadcastOutcomeUnknown) -> DashSpendError {
        let reason = unknown.underlying.userInfo[WalletSendService.diagnosticKey] as? String
        return .paymentStatusUnknown(
            txIdWire: unknown.txidWire, reason: reason ?? unknown.underlying.localizedDescription)
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

    /// Pays a `dash:`/BIP72 payment-request URL headlessly (CTX gift cards): parse → fetch +
    /// verify → the caller's `validate` → authorize → build → POST the Payment → broadcast.
    /// Routes entirely through the app-side BIP70 stack (`BIP70PaymentService`) — no DashSync,
    /// no `DWPaymentProcessor`.
    ///
    /// - Parameter validate: the caller's acceptance check on the fetched request, run before
    ///   the PIN prompt. It may suspend to ask the user. A throw ends the payment with no
    ///   prompt and nothing built. This method holds no acceptance policy of its own.
    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention — the caller's metadata key).
    /// - Parameter awaitAcceptance: `false` returns once the merchant has acknowledged the
    ///   Payment and the broadcast is under way, without waiting out the SDK's network-acceptance
    ///   window (30 s). The gift-card flow uses it: CTX fulfils the order from the bytes it just
    ///   acknowledged, so the verdict decides nothing the buyer is standing by for.
    func payWithDashUrl(url paymentUrlString: String, awaitAcceptance: Bool = true,
                        validate: @escaping (Confirmation) async throws -> Void) async throws -> Data {
        // The link's terms are judged as every reader judges them (`BIP70URI.amountSource`): one that leaves what it
        // asks open, a malformed or contradictory required amount among them, is refused like any invalid link. The
        // invoice is paid as fetched, so a malformed optional amount is left to it.
        guard let uri = BIP70URI(paymentUrlString), uri.amountSource != nil,
              let requestURL = uri.fetchableRequestURL else {
            throw DashSpendError.paymentProcessingError(String(localized: "Invalid payment request", comment: "DashSpend"))
        }

        let network = try PaymentNetworkResolver.current()
        let service = makeBIP70Service()
        let result: SendResult
        do {
            result = try await service.confirmAndSendHeadless(
                from: requestURL, scheme: uri.scheme, network: network,
                callbackScheme: uri.callbackScheme, awaitAcceptance: awaitAcceptance,
                validate: validate)
        } catch BIP70Error.paymentNotAcknowledged(let txHashDisplay, let reason) {
            // The merchant may already hold the signed bytes; hand the caller the txid so the
            // order is recorded rather than dropped on the floor.
            throw DashSpendError.paymentNotAcknowledged(
                txIdWire: Data(txHashDisplay.reversed()), reason: reason)
        } catch BIP70Error.broadcastOutcomeUnknown(let txHashDisplay, let reason) {
            // The coins are gone as far as the merchant is concerned — it already holds the
            // signed bytes and can broadcast them itself. Hand the caller the txid so the
            // purchase is recorded rather than dropped; the caller decides how to present it.
            throw DashSpendError.paymentStatusUnknown(
                txIdWire: Data(txHashDisplay.reversed()), reason: reason)
        } catch BIP70Error.failedAfterAcknowledgement(let txHashDisplay, let reason) {
            // The merchant acknowledged the Payment, so it holds the signed bytes and may fulfil the
            // order although the broadcast failed or the request expired: the same in-progress state.
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
