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
    func paymentControllerDidFinishTransaction(_ controller: PaymentController, transaction: DSTransaction)
    func paymentControllerDidCancelTransaction(_ controller: PaymentController)
    func paymentControllerDidFailTransaction(_ controller: PaymentController)
}

// MARK: - PaymentControllerPresentationContextProviding

@objc
protocol PaymentControllerPresentationContextProviding: AnyObject {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor
}

// MARK: - AmountProviding

protocol AmountProviding: ActivityIndicatorPreviewing, ErrorPresentable, PaymentControllerPresentationAnchor { }

// MARK: - PaymentController

final class PaymentController: NSObject {
    @objc weak var delegate: PaymentControllerDelegate?
    @objc weak var presentationContextProvider: PaymentControllerPresentationContextProviding?

    @objc public var contactItem: DWDPBasicUserItem?
    @objc public var locksBalance = false

    private var paymentProcessor: DWPaymentProcessor
    private var fiatCurrency: String = App.fiatCurrency
    private weak var paymentOutput: DWPaymentOutput?
    private weak var confirmViewController: ConfirmPaymentViewController?
    private weak var provideAmountViewController: AmountProviding?

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

    @objc(performPaymentWithFile:)
    public func performPayment(with file: Data) {
        paymentProcessor.reset()
        paymentProcessor.processFile(file)
    }
}

extension PaymentController {
    var presentationAnchor: PaymentControllerPresentationAnchor? {
        provideAmountViewController ?? presentationContextProvider?.presentationAnchorForPaymentController(self)
    }

    private func showAlert(with title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel)
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
        if let output = paymentOutput {
            paymentProcessor.confirmPaymentOutput(output)
        }
    }

    func confirmPaymentViewControllerDidCancel(_ controller: ConfirmPaymentViewController) {
        provideAmountViewController?.hideActivityIndicator()
        delegate?.paymentControllerDidCancelTransaction(self)
    }
}

// MARK: DWPaymentProcessorDelegate

extension PaymentController: DWPaymentProcessorDelegate {
    func paymentProcessor(_ processor: DWPaymentProcessor, didSweepRequest protocolRequest: DSPaymentRequest,
                          transaction: DSTransaction) {
        presentationAnchor?.topController().view.dw_showInfoHUD(withText: NSLocalizedString("Swept!", comment: ""))

        if let vc = presentationContextProvider as? UIViewController,
           vc.navigationController?.topViewController is ProvideAmountViewController {
            vc.navigationController?.popViewController(animated: true)
        }
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String,
                          details: DSPaymentProtocolDetails?, contactItem: DWDPBasicUserItem) {
        let vc = ProvideAmountViewController(address: sendingDestination)
        vc.locksBalance = locksBalance
        vc.delegate = self
        vc.hidesBottomBarWhenPushed = true
        vc.definesPresentationContext = true
        // vc.contactItem = nil //TODO: pass contactItem
        // vc.demoMode = self.demoMode; //TODO: demoMode
        presentationAnchor!.navigationController?.pushViewController(vc, animated: true)
        provideAmountViewController = vc
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, requestUserActionTitle title: String?, message: String?,
                          actionTitle: String, cancel cancelBlock: (() -> Void)?, actionBlock: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            cancelBlock?()
        }

        alert.addAction(cancelAction)

        let actionAction = UIAlertAction(title: actionTitle, style: .default) { _ in
            actionBlock?()

            self.confirmViewController?.isSendingEnabled = true
        }

        alert.addAction(actionAction)
        show(modalController: alert)
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
        provideAmountViewController?.hideActivityIndicator()
        confirmViewController?.isSendingEnabled = true
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didFailWithError error: Error?, title: String?, message: String?) {
        guard let error = error as? NSError else {
            return
        }

        presentationAnchor?.topController().view.dw_hideProgressHUD()
        provideAmountViewController?.hideActivityIndicator()

        confirmViewController?.isSendingEnabled = true

        if error.domain == DSErrorDomain,
           error.code == DSErrorInsufficientFunds
           || error.code == DSErrorInsufficientFundsForNetworkFee
           || error.code == DSErrorPaymentAmountLessThenMinOutputAmount
           || error.code == DSErrorPaymentTransactionOutputTooSmall {
            provideAmountViewController?.present(error: error)
        } else {
            showAlert(with: title, message: message)
        }
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didSend protocolRequest: DSPaymentProtocolRequest,
                          transaction: DSTransaction, contactItem: DWDPBasicUserItem?) {
        presentationAnchor?.topController().view.dw_hideProgressHUD()

        let finishBlock = {
            if let vc = self.presentationAnchor?.navigationController?.topViewController as? AmountProviding {
                vc.navigationController?.popViewController(animated: true)

                DispatchQueue.main.async {
                    self.delegate?.paymentControllerDidFinishTransaction(self, transaction: transaction)
                }
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

    func paymentProcessorDidFinishProcessingFile(_ processor: DWPaymentProcessor) { }

    func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {
        presentationAnchor?.topController().view.dw_hideProgressHUD()
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, displayFileProcessResult message: String) {
        showAlert(with: message, message: nil)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {
        presentationAnchor?.topController().view.dw_showProgressHUD(withMessage: message)
    }
}

// MARK: ProvideAmountViewControllerDelegate

extension PaymentController: ProvideAmountViewControllerDelegate {
    func provideAmountViewControllerDidInput(amount: UInt64, selectedCurrency: String) {
        fiatCurrency = selectedCurrency
        paymentProcessor.provideAmount(amount)
    }
}
