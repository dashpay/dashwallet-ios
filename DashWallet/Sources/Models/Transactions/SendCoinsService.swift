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

    /// DashSync publish path, used only by `sendMayaSwap` — the Maya swap builds a
    /// raw `DSTransaction` (OP_RETURN memo + fixed output order), which
    /// SwiftDashSDK's sender cannot express yet. Every other spend goes through
    /// `walletSendService`. TODO(maya-sdk-port): drop with the SDK OP_RETURN support.
    private let transactionManager: DSTransactionManager = DWEnvironment.sharedInstance().currentChainManager.transactionManager

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

    /// Sends a MAYA swap transaction where:
    /// - VOUT0 pays DASH to the MAYA vault address
    /// - VOUT1 stores MAYA memo in OP_RETURN
    /// - VOUT2 is change back to the wallet (if any)
    ///
    /// DSTransactionSortType.none is used so the wallet builder preserves the
    /// vault→memo→change insertion order without BIP69 sorting or shuffling,
    /// matching the Android sendRequest.sortByBIP69 = false / shuffleOutputs = false
    /// requirement from MayaBlockchainApi.kt.
    func sendMayaSwap(vaultAddress: String, dashAmount: UInt64, memo: String) async throws -> DSTransaction {
        // Serialise swaps: don't start a new one until the previous swap tx is InstantSend-locked.
        if MayaSwapPendingGate.shared.isAwaitingISLock {
            throw DashSpendError.swapAwaitingInstantLock
        }

        let memoByteCount = memo.utf8.count
        DSLogger.log("sendMayaSwap memo=\(memo) bytes=\(memoByteCount)")
        guard memoByteCount <= 80 else {
            throw DashSpendError.paymentProcessingError("Swap memo (\(memoByteCount) bytes) exceeds the 80-byte OP_RETURN limit. Try a simpler destination asset.")
        }

        let chain = DWEnvironment.sharedInstance().currentChain
        let account = DWEnvironment.sharedInstance().currentAccount

        let transaction = DSTransaction(on: chain)

        let vaultScript = NSData.scriptPubKey(forAddress: vaultAddress, for: chain)
        let memoScript = opReturnScript(for: memo)

        _ = account.update(
            transaction,
            forAmounts: [NSNumber(value: dashAmount), NSNumber(value: 0)],
            toOutputScripts: [vaultScript, memoScript],
            withFee: true,
            sortType: DSTransactionSortType.none  // preserve vault→memo→change order
        )

        guard transaction.outputs.count >= 2 else {
            logOutputs(transaction, label: "build-failed")
            throw DashSpendError.paymentProcessingError("Failed to build MAYA swap outputs")
        }

        // Validate VOUT0: must be the vault payment output
        guard transaction.outputs[0].address == vaultAddress else {
            logOutputs(transaction, label: "order-invalid")
            throw DashSpendError.paymentProcessingError("MAYA swap output ordering is invalid")
        }

        // Validate VOUT1: must be the OP_RETURN memo output (amount 0, script starts with 0x6a)
        let memoOutput = transaction.outputs[1]
        guard memoOutput.amount == 0,
              let firstByte = memoOutput.outScript.first, firstByte == 0x6a else {
            logOutputs(transaction, label: "memo-invalid")
            throw DashSpendError.paymentProcessingError("MAYA memo output is invalid")
        }

        // Pre-sign diagnostics: log full tx structure, fee, and VIN0 relationship
        // (mirrors Android's log.info("maya swap transaction: {}", sendRequest.tx))
        let txSize = transaction.size
        let estimatedFee = chain.fee(forTxSize: UInt(txSize))
        let feePerByte = txSize > 0 ? estimatedFee / UInt64(txSize) : 0

        // Real wire size of the OP_RETURN output: transaction.size uses TX_OUTPUT_SIZE=34
        // for every output, but OP_RETURN is 8 (value) + varint(scriptLen) + scriptLen.
        let memoScriptLen = memoOutput.outScript.count
        let varintLen = memoScriptLen < 253 ? 1 : 3
        let realOpReturnSize = 8 + varintLen + memoScriptLen
        let realEstimatedSize = Int(txSize) - 34 + realOpReturnSize

        // FEE FIX: account.update uses TX_OUTPUT_SIZE=34 for every output, but the
        // OP_RETURN output is realOpReturnSize bytes. The builder therefore under-pays
        // the fee by extraBytes duffs. Close the gap by reducing the change output (VOUT2)
        // so the effective fee rate clears TX_FEE_PER_B against the real wire size.
        // DSTransactionOutput.amount is readonly in the public header but readwrite in its
        // class extension, so KVC setValue(_:forKey:) reaches the private setter safely.
        var correctedFee = estimatedFee
        let extraBytes = realEstimatedSize > Int(txSize) ? realEstimatedSize - Int(txSize) : 0
        if extraBytes > 0 {
            let requiredFee = chain.fee(forTxSize: UInt(realEstimatedSize) + 1) // +1 byte safety margin
            if requiredFee > estimatedFee, transaction.outputs.count >= 3 {
                let feeDelta = requiredFee - estimatedFee
                let changeOutput = transaction.outputs[2]
                guard changeOutput.amount >= feeDelta + chain.minOutputAmount else {
                    throw DashSpendError.paymentProcessingError(
                        "Change output (\(changeOutput.amount) duffs) too small to absorb fee correction (\(feeDelta) duffs)"
                    )
                }
                let correctedChangeAmount = changeOutput.amount - feeDelta
                changeOutput.setValue(NSNumber(value: correctedChangeAmount), forKey: "amount")
                correctedFee = requiredFee
                DSLogger.log("sendMayaSwap FEE FIX: extraBytes=\(extraBytes) feeDelta=\(feeDelta) requiredFee=\(requiredFee) correctedChange=\(correctedChangeAmount)")
            }
        }

        DSLogger.log("sendMayaSwap pre-sign: inputs=\(transaction.inputs.count) outputs=\(transaction.outputs.count) size=\(txSize) estimatedFee=\(estimatedFee) feePerByte=\(feePerByte)")
        logOutputs(transaction, label: "pre-sign")
        logVin0(transaction, chain: chain)

        // Guard: check fee rate against the REAL wire size, not the builder's undercount.
        // Before this fix, feePerByte was measured against txSize (= under-counted estimate),
        // giving a false pass even when the relay fee was below the 1 duff/byte minimum.
        let correctedFeePerByte = realEstimatedSize > 0 ? correctedFee / UInt64(realEstimatedSize) : 0
        guard correctedFeePerByte >= TX_FEE_PER_B else {
            throw DashSpendError.paymentProcessingError(
                "Transaction fee too low: \(correctedFeePerByte) duff/byte against real size \(realEstimatedSize) (min \(TX_FEE_PER_B))"
            )
        }

        // Guard against stale UTXOs caused by DSAccount.updateBalance treating the
        // Maya swap tx as "pending" (OP_RETURN output amount=0 < TX_MIN_OUTPUT_AMOUNT,
        // i.e. 546 duffs). The pending path calls `continue` before the reconciliation
        // step that removes spent entries from `utxos`, so the just-spent input stays
        // visible to the next coin-selection call and gets re-selected — producing a
        // double-spend. `spentOutputs` IS always updated correctly (before the continue);
        // `-isInputSpent:atIndex:` reads that set and catches stale re-use early.
        for input in transaction.inputs {
            if account.isInputSpent(input.inputHash, at: input.index) {
                throw DashSpendError.previousSwapPending
            }
        }

        let authenticated = await authenticate()
        if !authenticated {
            throw DashSpendError.paymentProcessingError("Authentication cancelled")
        }

        account.sign(transaction)
        DSLogger.log("sendMayaSwap post-sign txid=\(transaction.txHashHexString)")
        // saveImmediately:true: crash-safe — tx is in Core Data before broadcast.
        // Does NOT affect UTXO state; updateBalance runs the same either way.
        account.register(transaction, saveImmediately: true)
        try await transactionManager.publishTransaction(transaction)
        DSLogger.log("sendMayaSwap published txid=\(transaction.txHashHexString)")
        MayaSwapPendingGate.shared.register(txid: transaction.txHashHexString)
        return transaction
    }

    private func logOutputs(_ tx: DSTransaction, label: String) {
        DSLogger.log("sendMayaSwap [\(label)] \(tx.outputs.count) output(s):")
        for (i, out) in tx.outputs.enumerated() {
            let scriptHex = out.outScript.map { String(format: "%02x", $0) }.joined()
            let isOpReturn = out.outScript.first == 0x6a
            if isOpReturn {
                let payload = out.outScript.dropFirst(2)
                let memoStr = String(bytes: payload, encoding: .utf8) ?? scriptHex
                DSLogger.log("  [\(i)] amount=\(out.amount) OP_RETURN memo=\(memoStr)")
            } else {
                DSLogger.log("  [\(i)] amount=\(out.amount) addr=\(out.address ?? "(none)") script=\(scriptHex.prefix(40))")
            }
        }
    }

    private func logVin0(_ tx: DSTransaction, chain: DSChain) {
        guard let vin0 = tx.inputs.first else { return }
        var hash = vin0.inputHash
        let hashData = withUnsafeBytes(of: &hash) { Data($0) }
        let hashHex = hashData.reversed().map { String(format: "%02x", $0) }.joined()
        DSLogger.log("sendMayaSwap VIN0: prevout=\(hashHex):\(vin0.index)")
        if let parentTx = chain.transaction(forHash: vin0.inputHash),
           Int(vin0.index) < parentTx.outputs.count {
            let vin0Out = parentTx.outputs[Int(vin0.index)]
            DSLogger.log("sendMayaSwap VIN0 script: addr=\(vin0Out.address ?? "(none)")")
        }
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
        let result = try await service.confirmAndSendHeadless(
            from: requestURL, scheme: uri.scheme, network: network, callbackScheme: uri.callbackScheme)

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
    
    private func authenticate() async -> Bool {
        @MainActor func performAuthentication() async -> Bool {
            await withCheckedContinuation { continuation in
                DSAuthenticationManager.sharedInstance().authenticate(
                    withPrompt: nil,
                    usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
                    alertIfLockout: true
                ) { authenticatedOrSuccess, _, cancelled in
                    continuation.resume(returning: authenticatedOrSuccess && !cancelled)
                }
            }
        }
        return await performAuthentication()
    }
    
    private func opReturnScript(for memo: String) -> Data {
        let payload = Data(memo.utf8)
        var script = Data([0x6a]) // OP_RETURN

        let count = payload.count
        if count <= 0x4b {
            script.append(UInt8(count))
        } else if count <= 0xff {
            script.append(0x4c) // OP_PUSHDATA1
            script.append(UInt8(count))
        } else {
            script.append(0x4d) // OP_PUSHDATA2
            script.append(UInt8(count & 0xff))
            script.append(UInt8((count >> 8) & 0xff))
        }

        script.append(payload)
        return script
    }
}
