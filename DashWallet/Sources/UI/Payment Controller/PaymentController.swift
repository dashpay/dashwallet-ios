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

import UIKit

typealias PaymentControllerPresentationAnchor = UIViewController

// MARK: - AmountViewController

protocol AmountViewController where Self: BaseAmountViewController { }

// MARK: - PaymentControllerDelegate

@objc
protocol PaymentControllerDelegate: AnyObject {
    /// `txidWire` is the broadcast transaction's wire-order txid
    /// (`Transaction.txHashData` convention) — resolve via `TxDetailModel(txidWire:)`.
    func paymentControllerDidFinishTransaction(_ controller: PaymentController, txidWire: Data)
    func paymentControllerDidCancelTransaction(_ controller: PaymentController)
    func paymentControllerDidFailTransaction(_ controller: PaymentController)
    /// The input named a recipient but no amount — a bare address scanned,
    /// pasted, read over NFC or opened from a `dash:` link. The amount is
    /// asked for in the Send flow, which the delegate opens prefilled with
    /// `address`; this controller's part of the payment ends here.
    @objc optional func paymentController(_ controller: PaymentController, needsAmountForAddress address: String)
}

// MARK: - PaymentControllerPresentationContextProviding

@objc
protocol PaymentControllerPresentationContextProviding: AnyObject {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor
}

// MARK: - PaymentController

final class PaymentController: NSObject {
    @objc weak var delegate: PaymentControllerDelegate?
    @objc weak var presentationContextProvider: PaymentControllerPresentationContextProviding?

    @objc public var locksBalance = false

    private var paymentProcessor: DWPaymentProcessor
    private var fiatCurrency: String = App.fiatCurrency
    private weak var paymentOutput: DWPaymentOutput?
    private weak var confirmViewController: ConfirmPaymentViewController?

    static func shouldReenableSending(after error: NSError) -> Bool {
        !WalletSendService.isBroadcastUnknownError(error)
    }

    override init() {
        paymentProcessor = DWPaymentProcessor()

        super.init()

        paymentProcessor.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func performPayment(with input: DWPaymentInput) {
        paymentProcessor.reset()
        paymentProcessor.processPaymentInput(input)
    }
}

extension PaymentController {
    var presentationAnchor: PaymentControllerPresentationAnchor? {
        presentationContextProvider?.presentationAnchorForPaymentController(self)
    }

    private func showAlert(with title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: String(localized: "OK", comment: ""), style: .cancel)
        alert.addAction(okAction)
        show(modalController: alert)
    }

    private func show(modalController: UIViewController) {
        precondition(presentationAnchor != nil)
        presentationAnchor!.topController().present(modalController, animated: true)
    }
}

// MARK: ConfirmPaymentViewControllerDelegate

extension PaymentController: ConfirmPaymentViewControllerDelegate {
    func confirmPaymentViewControllerDidConfirm(_ controller: ConfirmPaymentViewController) {
        controller.dismiss(animated: true) { [weak self] in
            if let output = self?.paymentOutput {
                self?.paymentProcessor.confirmPaymentOutput(output)
            }
        }
    }

    func confirmPaymentViewControllerDidCancel(_ controller: ConfirmPaymentViewController) {
        delegate?.paymentControllerDidCancelTransaction(self)
    }
}

// MARK: DWPaymentProcessorDelegate

extension PaymentController: DWPaymentProcessorDelegate {
    func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String, amount: UInt64) {
        // The processor asks only when the input carried no amount, so
        // `amount` is 0 here. The Send flow collects it and comes back with
        // an address and an amount together, as a new payment.
        processor.reset()

        guard let handler = delegate?.paymentController(_:needsAmountForAddress:) else {
            // Every host that can receive an amount-less input opens the Send
            // flow. Coinbase's transfer always passes an amount.
            assertionFailure("PaymentController delegate can't ask for an amount")
            delegate?.paymentControllerDidFailTransaction(self)
            return
        }
        handler(self, sendingDestination)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
        self.paymentOutput = paymentOutput

        if let vc = confirmViewController {
            vc.update(with: paymentOutput)
        } else {
            let vc = ConfirmPaymentViewController(dataSource: paymentOutput, fiatCurrency: fiatCurrency)
            vc.delegate = self

            // TODO: demo mode

            presentationAnchor?.topController().present(vc, animated: true)
            confirmViewController = vc
        }
    }

    func paymentProcessorDidCancelTransactionSigning(_ processor: DWPaymentProcessor) {
        delegate?.paymentControllerDidCancelTransaction(self)
        confirmViewController?.isSendingEnabled = true
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didFailWithError error: Error?, title: String?, message: String?) {
        // Pre-existing behavior kept: nil-error failures (invalid-address rejections)
        // stay silent here. The DashSync DSErrorDomain special-case is gone — live
        // errors carry WalletSendService / SDK / BIP70 domains.
        guard let error else {
            return
        }

        presentationAnchor?.topController().view.dw_hideProgressHUD()

        confirmViewController?.isSendingEnabled =
            Self.shouldReenableSending(after: error as NSError)

        showAlert(with: title, message: message)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didSendWithTxidWire txidWire: Data) {
        presentationAnchor?.topController().view.dw_hideProgressHUD()

        let finishBlock = {
            DispatchQueue.main.async {
                self.delegate?.paymentControllerDidFinishTransaction(self, txidWire: txidWire)
            }
        }

        guard let vc = confirmViewController else {
            finishBlock()
            return
        }

        vc.dismiss(animated: true) {
            finishBlock()
        }
    }

    func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {
        presentationAnchor?.topController().view.dw_hideProgressHUD()
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {
        presentationAnchor?.topController().view.dw_showProgressHUD(withMessage: message)
    }
}
