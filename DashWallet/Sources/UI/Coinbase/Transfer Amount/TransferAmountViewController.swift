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
import SwiftUI

struct TransferAmountView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TransferAmountViewController {
        return TransferAmountViewController()
    }
    
    func updateUIViewController(_ viewController: TransferAmountViewController, context: Context) {
    }
}

final class TransferAmountViewController: SendAmountViewController {
    private var converterView: ConverterView!
    private var transferModel: TransferAmountModel { model as! TransferAmountModel }
    private var paymentController: PaymentController!
    
    override var amountInputStyle: AmountInputControl.Style { .basic }
    
    private weak var codeConfirmationController: TwoFactorAuthViewController?
    
    override var actionButtonTitle: String? {
        return NSLocalizedString("Transfer", comment: "Coinbase")
    }
    
    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()
        transferModel.initializeTransfer()
    }
    
    override func initializeModel() {
        model = TransferAmountModel()
    }
    
    override func configureModel() {
        super.configureModel()
        
        transferModel.delegate = self
    }
    
    override func configureHierarchy() {
        super.configureHierarchy()
        
        self.converterView = ConverterView(direction: .toCoinbase)
        converterView.delegate = self
        converterView.dataSource = model
        converterView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(converterView)
        
        NSLayoutConstraint.activate([
            converterView.topAnchor.constraint(equalTo: amountView.bottomAnchor, constant: 20),
            converterView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            converterView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            converterView.heightAnchor.constraint(equalToConstant: 128)
        ])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.dw_secondaryBackground()
        
        navigationItem.title = NSLocalizedString("Transfer Dash", comment: "Coinbase")
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never
    }
}

extension TransferAmountViewController: ConverterViewDelegate {
    func didChangeDirection(_ direction: ConverterViewDirection) {
        transferModel.direction = direction == .toCoinbase ? .toCoinbase : .toWallet
    }
}

extension TransferAmountViewController: TransferAmountModelDelegate {
    func initiatePayment(with input: DWPaymentInput) {
        paymentController = PaymentController()
        paymentController.delegate = self
        paymentController.presentationContextProvider = self
        paymentController.performPayment(with: input)
    }
    
    func initiateTwoFactorAuth() {
        let vc = TwoFactorAuthViewController.controller()
        vc.verifyHandler = { [weak self] code in
            self?.transferModel.continueTransferFromCoinbase(with: code)
        }
        navigationController?.pushViewController(vc, animated: true)
        
        codeConfirmationController = vc
    }

    func transferFromCoinbaseToWalletDidSucceed() {
        codeConfirmationController?.dismiss(animated: true)
        codeConfirmationController = nil
    }
    
    func transferFromCoinbaseToWalletDidFail(with error: Error) {
        codeConfirmationController?.show(error: error)
    }
}

extension BaseAmountModel: ConverterViewDataSource {
    var coinbaseBalance: String {
        return Coinbase.shared.lastKnownBalance ?? NSLocalizedString("Unknown Balance", comment: "Coinbase")
    }
    
    var walletBalance: String {
        let plainNumber = Decimal(DWEnvironment.sharedInstance().currentWallet.balance)
        let duffsNumber = Decimal(DUFFS)
        let dashNumber = plainNumber/duffsNumber
        if #available(iOS 15.0, *) {
            return dashNumber.formatted(.number)
        } else {
            return "\(dashNumber)"
        }
    }
}

extension TransferAmountViewController {
    private func startTransfering() {
        
    }
}

extension TransferAmountViewController: PaymentControllerDelegate {
    func paymentControllerDidFinishTransaction(_ controller: PaymentController) {
        hideActivityIndicator()
        showAlert(with: "Success!", message: "You have sent Dash to Coinbase")
    }
    
    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {
        hideActivityIndicator()
    }
}

extension TransferAmountViewController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        return self
    }
}
