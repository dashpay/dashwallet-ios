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

// MARK: - PaymentController

final class PaymentController: NSObject {
    @objc weak var delegate: PaymentControllerDelegate?
    @objc weak var presentationContextProvider: PaymentControllerPresentationContextProviding?

    @objc public var contactItem: DWDPBasicUserItem?

    private var paymentProcessor: DWPaymentProcessor
    private weak var confirmViewController: DWConfirmSendPaymentViewController?

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
        presentationContextProvider?.presentationAnchorForPaymentController(self)
    }

    private func showAlert(with title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel)
        alert.addAction(okAction)
        show(modalController: alert)
    }

    private func show(modalController: UIViewController) {
        precondition(presentationAnchor != nil)
        presentationAnchor!.present(modalController, animated: true)
    }
}

// MARK: DWConfirmPaymentViewControllerDelegate

extension PaymentController: DWConfirmPaymentViewControllerDelegate {
    func confirmPaymentViewControllerDidConfirm(_ controller: DWConfirmPaymentViewController) {
        if let vc = controller as? DWConfirmSendPaymentViewController, let output = vc.paymentOutput {
            paymentProcessor.confirmPaymentOutput(output)
        }
    }

    func confirmPaymentViewControllerDidCancel(_ controller: DWConfirmPaymentViewController) {
        delegate?.paymentControllerDidCancelTransaction(self)
    }
}

// MARK: DWPaymentProcessorDelegate

extension PaymentController: DWPaymentProcessorDelegate {
    func paymentProcessor(_ processor: DWPaymentProcessor, didSweepRequest protocolRequest: DSPaymentRequest,
                          transaction: DSTransaction) {
        presentationAnchor?.view.dw_showInfoHUD(withText: NSLocalizedString("Swept!", comment: ""))

        if let vc = presentationContextProvider as? UIViewController,
           vc.navigationController?.topViewController is ProvideAmountViewController {
            vc.navigationController?.popViewController(animated: true)
        }
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String,
                          details: DSPaymentProtocolDetails?, contactItem: DWDPBasicUserItem) {
        let vc = ProvideAmountViewController(address: sendingDestination)
        vc.delegate = self
        vc.hidesBottomBarWhenPushed = true
        // vc.contactItem = nil //TODO: pass contactItem
        // vc.demoMode = self.demoMode; //TODO: demoMode
        presentationAnchor!.navigationController?.pushViewController(vc, animated: true)
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

            self.confirmViewController?.sendingEnabled = true
        }

        alert.addAction(actionAction)
        show(modalController: alert)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
        if let vc = confirmViewController {
            vc.paymentOutput = paymentOutput
        } else {
            let vc = DWConfirmSendPaymentViewController()
            vc.paymentOutput = paymentOutput
            vc.delegate = self

            // TODO: demo mode

            presentationAnchor?.present(vc, animated: true)
            confirmViewController = vc
        }
    }

    func paymentProcessorDidCancelTransactionSigning(_ processor: DWPaymentProcessor) {
        confirmViewController?.sendingEnabled = true
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didFailWithError error: Error?, title: String?, message: String?) {
        guard let error = error as? NSError else {
            return
        }

        if error.domain == DSErrorDomain &&
            (error.code == DSErrorInsufficientFunds || error.code == DSErrorInsufficientFundsForNetworkFee) {
            // TODO: Show insufficient amount
        }

        delegate?.paymentControllerDidFailTransaction(self)
        presentationContextProvider?.presentationAnchorForPaymentController(self).view.dw_hideProgressHUD()
        showAlert(with: title, message: message)
        confirmViewController?.sendingEnabled = true
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didSend protocolRequest: DSPaymentProtocolRequest,
                          transaction: DSTransaction, contactItem: DWDPBasicUserItem?) {
        presentationContextProvider?.presentationAnchorForPaymentController(self).view.dw_hideProgressHUD()

        if let vc = confirmViewController {
            vc.dismiss(animated: true) {
                if let vc = self.presentationContextProvider as? UIViewController,
                   vc.navigationController?.topViewController is ProvideAmountViewController {
                    vc.navigationController?.popViewController(animated: true)
                }
                self.delegate?.paymentControllerDidFinishTransaction(self, transaction: transaction)
            }
        } else {
            if let vc = presentationContextProvider as? UIViewController,
               vc.navigationController?.topViewController is ProvideAmountViewController {
                vc.navigationController?.popViewController(animated: true)
            }

            delegate?.paymentControllerDidFinishTransaction(self, transaction: transaction)
        }
    }

    func paymentProcessorDidFinishProcessingFile(_ processor: DWPaymentProcessor) { }

    func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {
        presentationAnchor?.view.dw_hideProgressHUD()
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, displayFileProcessResult message: String) {
        showAlert(with: message, message: nil)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {
        presentationAnchor?.view.dw_showProgressHUD(withMessage: message)
    }
}

// MARK: ProvideAmountViewControllerDelegate

extension PaymentController: ProvideAmountViewControllerDelegate {
    func provideAmountViewControllerDidInput(amount: UInt64) {
        paymentProcessor.provideAmount(amount)
    }
}
