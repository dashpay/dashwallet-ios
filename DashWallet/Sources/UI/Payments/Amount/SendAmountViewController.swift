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

class SendAmountViewController: BaseAmountViewController {
    fileprivate var paymentProcessor: DWPaymentProcessor
    fileprivate weak var confirmViewController: DWConfirmSendPaymentViewController?
    
    private var sendAmountModel: SendAmountModel {
        model as! SendAmountModel
    }
    
    init() {
        paymentProcessor = DWPaymentProcessor()
        
        super.init(nibName: nil, bundle: nil)
        
        paymentProcessor.delegate = self
    }

    override func initializeModel() {
        model = SendAmountModel()
    }
  
    override func actionButtonAction(sender: UIView) {
        
    }

    override func maxButtonAction() {
        sendAmountModel.selectAllFunds { [weak self] in
            self?.amountView.amountType = .main
        }
    }
     
    override func amountDidChange() {
        super.amountDidChange()
        
        actionButton?.isEnabled = model.amount.plainAmount > 0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SendAmountViewController {
    fileprivate func show(modalController: UIViewController) {
        let presentingViewController = confirmViewController ?? self.presentingViewController
        presentingViewController?.present(modalController, animated: true)
    }
}

//MARK: DWConfirmPaymentViewControllerDelegate
extension SendAmountViewController: DWConfirmPaymentViewControllerDelegate {
    func confirmPaymentViewControllerDidConfirm(_ controller: DWConfirmPaymentViewController) {
        if let vc = controller as? DWConfirmSendPaymentViewController, let output = vc.paymentOutput
        {
            self.paymentProcessor.confirmPaymentOutput(output)
        }
    }
}

//MARK: DWPaymentProcessorDelegate
extension SendAmountViewController: DWPaymentProcessorDelegate{
    func paymentProcessor(_ processor: DWPaymentProcessor, didSweepRequest protocolRequest: DSPaymentRequest, transaction: DSTransaction) {
        
    }
    
    func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String, details: DSPaymentProtocolDetails?, contactItem: DWDPBasicUserItem) {
        fatalError("Must be implemented")
    }
    
    func paymentProcessor(_ processor: DWPaymentProcessor, requestUserActionTitle title: String?, message: String?, actionTitle: String, cancel cancelBlock: (() -> Void)?, actionBlock: (() -> Void)? = nil) {
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
        self.show(modalController: alert)
    }
    
    func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
        if let vc = confirmViewController {
            vc.paymentOutput = paymentOutput
        }else{
            let vc = DWConfirmSendPaymentViewController()
            vc.paymentOutput = paymentOutput
            vc.delegate = self
            
            //TODO: demo mode
            
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
            //show insufficient amount
        }
        
        self.presentingViewController?.view.dw_hideProgressHUD()
        self.showAlert(with: title, message: message)
        
        self.confirmViewController?.sendingEnabled = true
    }
    
    func paymentProcessor(_ processor: DWPaymentProcessor, didSend protocolRequest: DSPaymentProtocolRequest, transaction: DSTransaction, contactItem: DWDPBasicUserItem?) {
        presentingViewController?.view.dw_hideProgressHUD()
        
        if let vc = confirmViewController {
            dismiss(animated: true)
        }else{
            
        }
        
        let vc = SuccessTxDetailViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.model = TxDetailModel(transaction: transaction, dataProvider: DWTransactionListDataProvider())
        vc.contactItem = contactItem
        //vc.delegate = self
        present(vc, animated: true)
    }
    
    func paymentProcessorDidFinishProcessingFile(_ processor: DWPaymentProcessor) {
        
    }
    
    func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {
        self.presentingViewController?.view.dw_hideProgressHUD()
    }
    
    func paymentProcessor(_ processor: DWPaymentProcessor, displayFileProcessResult message: String) {
        showAlert(with: message, message: nil)
    }
    
    func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {
        self.presentingViewController?.view.dw_showProgressHUD(withMessage: message)
    }
}

