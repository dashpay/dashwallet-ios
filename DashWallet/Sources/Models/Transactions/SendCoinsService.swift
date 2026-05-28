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

import Combine

public final class SendCoinsService: NSObject {
    private let transactionManager: DSTransactionManager = DWEnvironment.sharedInstance().currentChainManager.transactionManager
    
    // Payment processing
    private var paymentProcessor: DWPaymentProcessor?
    private var pendingPaymentContinuation: CheckedContinuation<DSTransaction, Swift.Error>?

    func sendCoins(address: String, amount: UInt64,
                   inputSelector: SingleInputAddressSelector? = nil, adjustAmountDownwards: Bool = false) async throws
        -> DSTransaction {
        let chain = DWEnvironment.sharedInstance().currentChain
        let account = DWEnvironment.sharedInstance().currentAccount
        let transaction = DSTransaction(on: chain)

        if inputSelector == nil {
            // Forming transaction normally
            let script = NSData.scriptPubKey(forAddress: address, for: chain)
            account.update(transaction, forAmounts: [amount], toOutputScripts: [script], withFee: true)
        }
        else {
            // Selecting proper inputs
            let balance = inputSelector!.selectFor(tx: transaction)
            transaction.addOutputAddress(address, amount: amount)
            let feeAmount = chain.fee(forTxSize: UInt(transaction.size) + UInt(TX_OUTPUT_SIZE))

            if amount + feeAmount > balance {
                if adjustAmountDownwards {
                    let adjustedAmount = amount - feeAmount
                    let adjustedTx = try await sendCoins(address: address, amount: adjustedAmount, inputSelector: inputSelector)
                    return adjustedTx
                } else {
                    throw DashSpendError.paymentProcessingError("Not enough funds. Selected: \(balance), Amount: \(amount), Fee: \(feeAmount)")
                }
            }

            let change = balance - (amount + feeAmount)

            if change > 0 {
                let changeAddress = inputSelector!.address
                transaction.addOutputAddress(changeAddress, amount: change)
                transaction.sortOutputsAccordingToBIP69()
            }
        }

        // Explicitly authenticate before signing to ensure PIN is requested
        // Must run on main thread as it's a UI operation
        @MainActor func authenticate() async -> Bool {
            return await withCheckedContinuation { continuation in
                DSAuthenticationManager.sharedInstance().authenticate(
                    withPrompt: nil,
                    usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
                    alertIfLockout: true
                ) { authenticatedOrSuccess, usedBiometrics, cancelled in
                    continuation.resume(returning: authenticatedOrSuccess && !cancelled)
                }
            }
        }

        let authenticated = await authenticate()

        if !authenticated {
            throw DashSpendError.paymentProcessingError("Authentication cancelled")
        }

        // Sign the transaction after authentication
        account.sign(transaction)

        // Register the transaction
        account.register(transaction, saveImmediately: false)

        // Publish the transaction
        try await transactionManager.publishTransaction(transaction)

        return transaction
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
        DSLogger.log("sendMayaSwap pre-sign: inputs=\(transaction.inputs.count) outputs=\(transaction.outputs.count) size=\(txSize) estimatedFee=\(estimatedFee) feePerByte=\(feePerByte)")
        logOutputs(transaction, label: "pre-sign")
        logVin0(transaction, chain: chain)

        // Guard: fee rate must be at least the network minimum (1 duff/byte).
        // Mirrors Android: fee < Transaction.DEFAULT_TX_FEE → failure.
        guard feePerByte >= TX_FEE_PER_B else {
            throw DashSpendError.paymentProcessingError(
                "Transaction fee too low: \(feePerByte) duff/byte (min \(TX_FEE_PER_B))"
            )
        }

        let authenticated = await authenticate()
        if !authenticated {
            throw DashSpendError.paymentProcessingError("Authentication cancelled")
        }

        account.sign(transaction)
        DSLogger.log("sendMayaSwap post-sign txid=\(transaction.txHashHexString)")
        account.register(transaction, saveImmediately: false)
        try await transactionManager.publishTransaction(transaction)
        DSLogger.log("sendMayaSwap published txid=\(transaction.txHashHexString)")
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
    
    func payWithDashUrl(url paymentUrlString: String) async throws -> DSTransaction {
        // Create payment input from the URL
        guard let paymentUrl = URL(string: paymentUrlString) else {
            throw DashSpendError.paymentProcessingError("Invalid payment URL")
        }
        
        // Use the existing payment infrastructure
        let payModel = DWPayModel()
        let paymentInput = payModel.paymentInput(with: paymentUrl)
        
        // If we have a BIP70 payment request URL, we need to fetch it first
        guard paymentInput.request?.r != nil else {
            throw DashSpendError.paymentProcessingError("Invalid payment request")
        }
        
        return try await fetchAndProcessPaymentRequest(paymentInput: paymentInput)
    }
    
    private func fetchAndProcessPaymentRequest(paymentInput: DWPaymentInput) async throws -> DSTransaction {
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingPaymentContinuation = continuation
            
            // Create and retain the processor
            let processor = DWPaymentProcessor(delegate: self)
            self.paymentProcessor = processor
            
            // Process the payment on the main actor to avoid Sendable issues
            Task { @MainActor in
                processor.processPaymentInput(paymentInput)
            }
        }
    }
    
    private func completePayment(transaction: DSTransaction?, error: Swift.Error?) {
        guard let continuation = pendingPaymentContinuation else { return }
        
        pendingPaymentContinuation = nil
        
        // Clean up the payment processor
        paymentProcessor = nil
        
        if let error = error {
            continuation.resume(throwing: error)
        } else if let transaction = transaction {
            continuation.resume(returning: transaction)
        } else {
            continuation.resume(throwing: DashSpendError.paymentProcessingError("No transaction returned"))
        }
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

// MARK: - DWPaymentProcessorDelegate

extension SendCoinsService: DWPaymentProcessorDelegate {
    public func paymentProcessor(_ processor: DWPaymentProcessor, didSend protocolRequest: DSPaymentProtocolRequest, transaction: DSTransaction, contactItem: DWDPBasicUserItem?) {
        completePayment(transaction: transaction, error: nil)
    }
    
    public func paymentProcessor(_ processor: DWPaymentProcessor, didFailWithError error: Swift.Error?, title: String?, message: String?) {
        let fullError = NSError(
            domain: "DashSpend",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: message ?? title ?? NSLocalizedString("Payment failed", comment: "")
            ]
        )
        completePayment(transaction: nil, error: error ?? fullError)
    }
    
    public func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String, details: DSPaymentProtocolDetails?, contactItem: DWDPBasicUserItem?) {
        completePayment(transaction: nil, error: DashSpendError.paymentProcessingError("Request is missing destination"))
    }
    
    public func paymentProcessor(_ processor: DWPaymentProcessor, requestUserActionTitle title: String?, message: String?, actionTitle: String, cancel cancelBlock: (() -> Void)?, actionBlock: (() -> Void)?) {
        actionBlock?()
    }
    
    public func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
        processor.confirmPaymentOutput(paymentOutput)
    }
    
    public func paymentProcessorDidCancelTransactionSigning(_ processor: DWPaymentProcessor) {
        completePayment(transaction: nil, error: NSError(domain: "DashSpend", code: -2, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Transaction cancelled", comment: "")]))
    }
    
    public func paymentProcessor(_ processor: DWPaymentProcessor, didSweepRequest protocolRequest: DSPaymentRequest, transaction: DSTransaction) {
        completePayment(transaction: transaction, error: nil)
    }
    
    public func paymentProcessor(_ processor: DWPaymentProcessor, displayFileProcessResult result: String) { }
    
    public func paymentProcessorDidFinishProcessingFile(_ processor: DWPaymentProcessor) { }
    
    public func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) { }
    
    public func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) { }
}
