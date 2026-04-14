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

    // Payment processing
    private var paymentProcessor: DWPaymentProcessor?
    private var pendingPaymentContinuation: CheckedContinuation<DSTransaction, Swift.Error>?

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
