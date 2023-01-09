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

// MARK: - AssociatedKeys

private enum AssociatedKeys {
    static var paymentProcessor: UInt8 = 0
    static var confirmViewController: UInt8 = 1
}

// MARK: - PaymentViewController

protocol PaymentViewController: DWPaymentProcessorDelegate,
    DWConfirmPaymentViewControllerDelegate where Self: UIViewController { }

extension PaymentViewController {
    fileprivate var paymentProcessor: DWPaymentProcessor {
        get {
            if let processor = objc_getAssociatedObject(self, &AssociatedKeys.paymentProcessor) as? DWPaymentProcessor {
                return processor
            } else {
                let processor = DWPaymentProcessor(delegate: self)
                self.paymentProcessor = processor
                return processor
            }
        }
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.paymentProcessor,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    fileprivate var confirmViewController: DWConfirmSendPaymentViewController? {
        get {
            if let vc = objc_getAssociatedObject(self,
                                                 &AssociatedKeys.confirmViewController) as? DWConfirmSendPaymentViewController {
                return vc
            } else {
                return nil
            }
        }
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.confirmViewController,
                                     newValue,
                                     objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private func showAlert(with title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel)
        alert.addAction(okAction)
        show(modalController: alert)
    }

    private func show(modalController: UIViewController) {
        let presentingViewController = confirmViewController ?? presentingViewController
        presentingViewController?.present(modalController, animated: true)
    }
}

// MARK: DWConfirmPaymentViewControllerDelegate
extension PaymentViewController {
    func confirmPaymentViewControllerDidConfirm(_ controller: DWConfirmPaymentViewController) {
        if let vc = controller as? DWConfirmSendPaymentViewController, let output = vc.paymentOutput {
            paymentProcessor.confirmPaymentOutput(output)
        }
    }
}

// MARK: DWPaymentProcessorDelegate
extension PaymentViewController {
    func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String,
                          details: DSPaymentProtocolDetails?, contactItem: DWDPBasicUserItem) {
        fatalError("Must be implemented")
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, requestUserActionTitle title: String?, message: String?,
                          actionTitle: String, cancel cancelBlock: (() -> Void)?, actionBlock: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            cancelBlock?()

//            assert(!self.confirmViewController || self.confirmViewController.sendingEnabled, "paymentProcessorDidCancelTransactionSigning: should be called")
        }

        alert.addAction(cancelAction)

        let actionAction = UIAlertAction(title: actionTitle, style: .cancel) { _ in
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

            present(vc, animated: true)
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
            // show insufficient amount
        }

        presentingViewController?.view.dw_hideProgressHUD()
        showAlert(with: title, message: message)

        confirmViewController?.sendingEnabled = true
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didSend protocolRequest: DSPaymentProtocolRequest,
                          transaction: DSTransaction, contactItem: DWDPBasicUserItem?) {
        presentingViewController?.view.dw_hideProgressHUD()

        if let vc = confirmViewController {
            dismiss(animated: true)
        } else { }

        let vc = SuccessTxDetailViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.model = TxDetailModel(transaction: transaction, dataProvider: DWTransactionListDataProvider())
        vc.contactItem = contactItem
        // vc.delegate = self
        present(vc, animated: true)
    }

    func paymentProcessorDidFinishProcessingFile(_ processor: DWPaymentProcessor) { }

    func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {
        presentingViewController?.view.dw_hideProgressHUD()
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {
        presentingViewController?.view.dw_showProgressHUD(withMessage: message)
    }
}


