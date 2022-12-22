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

// MARK: - TransferAmountView

struct TransferAmountView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TransferAmountViewController {
        TransferAmountViewController()
    }

    func updateUIViewController(_ viewController: TransferAmountViewController, context: Context) { }
}

// MARK: - TransferAmountViewController

final class TransferAmountViewController: SendAmountViewController, NetworkReachabilityHandling {
    /// Conform to NetworkReachabilityHandling
    internal var networkStatusDidChange: ((NetworkStatus) -> ())?
    internal var reachabilityObserver: Any!

    private var converterView: ConverterView!
    private var transferModel: TransferAmountModel { model as! TransferAmountModel }
    private var paymentController: PaymentController!

    private var networkUnavailableView: UIView!

    override var amountInputStyle: AmountInputControl.Style { .basic }

    internal weak var codeConfirmationController: TwoFactorAuthViewController?

    override var actionButtonTitle: String? {
        NSLocalizedString("Transfer", comment: "Coinbase")
    }

    override func actionButtonAction(sender: UIView) {
        DSLogger.log("Tranfer from coinbase: actionButtonAction")
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

        converterView = ConverterView(direction: .toCoinbase)
        converterView.delegate = self
        converterView.dataSource = model
        converterView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(converterView)

        networkUnavailableView = NetworkUnavailableView(frame: .zero)
        networkUnavailableView.translatesAutoresizingMaskIntoConstraints = false
        networkUnavailableView.isHidden = true
        contentView.addSubview(networkUnavailableView)

        NSLayoutConstraint.activate([
            converterView.topAnchor.constraint(equalTo: amountView.bottomAnchor, constant: 20),
            converterView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            converterView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            converterView.heightAnchor.constraint(equalToConstant: 128),

            networkUnavailableView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            networkUnavailableView.centerYAnchor.constraint(equalTo: numberKeyboard.centerYAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()

        navigationItem.title = NSLocalizedString("Transfer Dash", comment: "Coinbase")
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
        startNetworkMonitoring()
    }

    deinit {
        stopNetworkMonitoring()
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

// MARK: ConverterViewDelegate

extension TransferAmountViewController: ConverterViewDelegate {
    func didChangeDirection(_ direction: ConverterViewDirection) {
        transferModel.direction = direction == .toCoinbase ? .toCoinbase : .toWallet
    }
}

// MARK: - BaseAmountModel + ConverterViewDataSource

extension BaseAmountModel: ConverterViewDataSource {
    var coinbaseBalanceFormatted: String {
        guard let balance = Coinbase.shared.lastKnownBalance else {
            return NSLocalizedString("Unknown Balance", comment: "Coinbase")
        }

        return balance.formattedDashAmount
    }
}

extension TransferAmountViewController {
    private func reloadView() {
        let isOnline = networkStatus == .online
        networkUnavailableView.isHidden = isOnline
        numberKeyboard.isHidden = !isOnline
        actionButton?.isHidden = !isOnline
        converterView.hasNetwork = isOnline
    }

    private func showSuccessTransactionStatus() {
        showSuccessTransactionStatus(text: NSLocalizedString("It could take up to 10 minutes to transfer Dash from Coinbase to Dash Wallet on this device", comment: "Coinbase"))
    }
}

// MARK: - TransferAmountViewController + PaymentControllerDelegate

extension TransferAmountViewController: PaymentControllerDelegate {
    func paymentControllerDidFinishTransaction(_ controller: PaymentController, transaction: DSTransaction) {
        hideActivityIndicator()
        showSuccessTransactionStatus()
    }

    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {
        hideActivityIndicator()
    }
}

// MARK: - TransferAmountViewController + PaymentControllerPresentationContextProviding

extension TransferAmountViewController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}

// MARK: - TransferAmountViewController + CoinbaseCodeConfirmationPreviewing, CoinbaseTransactionHandling

extension TransferAmountViewController: CoinbaseCodeConfirmationPreviewing, CoinbaseTransactionHandling {
    func codeConfirmationControllerDidContinue(with code: String) {
        transferModel.continueTransferFromCoinbase(with: code)
    }

    func codeConfirmationControllerDidCancel() {
        hideActivityIndicator()
    }
}
