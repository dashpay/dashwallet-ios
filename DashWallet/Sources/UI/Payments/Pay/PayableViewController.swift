//  
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

protocol PayableViewController: DWQRScanModelDelegate {
    var payModel: DWPayModelProtocol! { get }
    var paymentController: PaymentController! { get }
}

extension PayableViewController where Self: UIViewController {
    func payToAddressAction() {
        guard let payModel = payModel else { return }

        payModel.payToAddress { [weak self] success in
            guard let strongSelf = self else { return }

            if success {
                strongSelf.performPayToPasteboardAction()
            } else {
                let title = NSLocalizedString("Clipboard doesn't contain a valid Dash address", comment: "")
                let message = NSLocalizedString("Please copy the Dash address first and try again", comment: "");
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil)
                alert.addAction(okAction)

                strongSelf.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    func performScanQRCodeAction(delegate: DWQRScanModelDelegate) {
        if let vc = presentedViewController, vc is DWQRScanViewController {
            return;
        }
        
        let controller = DWQRScanViewController()
        controller.model.delegate = delegate
        present(controller, animated: true, completion: nil)
    }
    
    func performNFCReadingAction() {
        payModel?.performNFCReading(completion: { [weak self] paymentInput in
            guard let strongSelf = self else { return }
            strongSelf.processPaymentInput(paymentInput)
        })
    }
    
    func performPayToPasteboardAction() {
        guard let paymentInput = payModel?.pasteboardPaymentInput else { return }
        processPaymentInput(paymentInput)
    }
    
    func processPaymentInput(_ input: DWPaymentInput) {
        paymentController.performPayment(with: input)
    }
}

extension PayableViewController where Self: UIViewController {
    
}
