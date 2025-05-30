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

import SwiftUI
import UIKit


// MARK: - TransferAmountViewController

final class TransferAmountViewController: CoinbaseAmountViewController, ConverterViewDelegate {
    private var converterView: ConverterView!
    private var transferModel: TransferAmountModel { model as! TransferAmountModel }
    private var paymentController: PaymentController!
    weak var codeConfirmationController: TwoFactorAuthViewController?

    override var amountInputStyle: AmountInputControl.Style { .basic }

    override var actionButtonTitle: String? {
        NSLocalizedString("Transfer", comment: "Coinbase")
    }

    init() {
        super.init(model: TransferAmountModel())
    }

    override init(model: BaseAmountModel) {
        super.init(model: model)
    }

    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()

        if transferModel.direction == .toCoinbase {
            checkLeftoverBalance { [weak self] canContinue in
                guard canContinue, let wSelf = self else { self?.hideActivityIndicator(); return }
                wSelf.transferModel.initializeTransfer()
            }
        }
        else {
            transferModel.initializeTransfer()
        }
    }

    // MARK: ConverterViewDelegate

    func didChangeDirection() {
        transferModel.direction = transferModel.direction == .toWallet ? .toCoinbase : .toWallet
    }

    func didTapOnFromView() { }

    // MARK: Life Cycle
    override func configureModel() {
        super.configureModel()
        transferModel.delegate = self
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.title = NSLocalizedString("Transfer Dash", comment: "Coinbase")
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .fill
        contentView.addSubview(stackView)

        // Move amount view into stack view
        stackView.addArrangedSubview(amountView)

        converterView = ConverterView(frame: .zero)
        converterView.delegate = self
        converterView.dataSource = model as? ConverterViewDataSource
        converterView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(converterView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
        ])
    }
}

// MARK: TransferAmountModelDelegate

extension TransferAmountViewController: TransferAmountModelDelegate {
    func coinbaseUserDidChange() {
        converterView.reloadView()
    }

    func initiatePayment(with input: DWPaymentInput) {
        paymentController = PaymentController()
        paymentController.delegate = self
        paymentController.presentationContextProvider = self
        paymentController.performPayment(with: input)
    }
}



extension TransferAmountViewController {
    @objc
    override func reloadView() {
        super.reloadView()

        let isOnline = networkStatus == .online
        converterView.hasNetwork = isOnline
    }

    private func showSuccessTransactionStatus() {
        showSuccessTransactionStatus(text: NSLocalizedString("It could take up to 10 minutes to transfer Dash from Coinbase to Dash Wallet on this device", comment: "Coinbase"))
    }
}

// MARK: PaymentControllerDelegate

extension TransferAmountViewController: PaymentControllerDelegate {
    func paymentControllerDidFinishTransaction(_ controller: PaymentController, transaction: DSTransaction) {
        hideActivityIndicator()
        showSuccessTransactionStatus()
    }

    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {
        hideActivityIndicator()
    }

    func paymentControllerDidFailTransaction(_ controller: PaymentController) {
        hideActivityIndicator()
    }
}

// MARK: PaymentControllerPresentationContextProviding

extension TransferAmountViewController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}

// MARK: CoinbaseCodeConfirmationPreviewing, CoinbaseTransactionHandling

extension TransferAmountViewController: CoinbaseCodeConfirmationPreviewing, CoinbaseTransactionHandling {
    func codeConfirmationControllerDidContinue(with code: String, for idem: UUID) {
        transferModel.continueTransferFromCoinbase(with: code, idem: idem)
    }

    func codeConfirmationControllerDidCancel() {
        hideActivityIndicator()
    }
}

extension TransferAmountViewController {
    @objc
    override func present(error: Error) {
        if case Coinbase.Error.transactionFailed(let reason) = error, reason == .limitExceded {
            amountView.showError(error.localizedDescription, textColor: .systemRed) { [weak self] in
                let vc = CoinbaseInfoViewController.controller()
                vc.modalPresentationStyle = .overCurrentContext
                self?.present(vc, animated: true)
            }
            return
        }

        super.present(error: error)
    }
}
