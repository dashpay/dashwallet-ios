//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

// MARK: - TransferAmountHostingController

final class TransferAmountHostingController: BaseViewController, NavigationBarDisplayable {

    var isNavigationBarHidden: Bool { true }

    private static let transferSuccessText = NSLocalizedString(
        "It could take up to 10 minutes to transfer Dash from Coinbase to Dash Wallet on this device",
        comment: "Coinbase"
    )

    private let viewModel = TransferAmountViewModel()
    private var paymentController: PaymentController!
    weak var codeConfirmationController: TwoFactorAuthViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_secondaryBackground()
        embedSwiftUIView()
        wireCallbacks()
    }

    // MARK: - Private

    private func embedSwiftUIView() {
        let swiftUIView = TransferAmountView(
            viewModel: viewModel,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        )

        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func wireCallbacks() {
        viewModel.onInitiatePayment = { [weak self] input in
            guard let self else { return }
            self.paymentController = PaymentController()
            self.paymentController.delegate = self
            self.paymentController.presentationContextProvider = self
            self.paymentController.performPayment(with: input)
        }

        viewModel.onRequire2FA = { [weak self] idem in
            self?.showCodeConfirmationController(idem: idem)
        }

        viewModel.onInvalid2FACode = { [weak self] in
            self?.showInvalidCodeState()
        }

        viewModel.onTransferSucceeded = { [weak self] in
            self?.showSuccessTransactionStatus(text: Self.transferSuccessText)
        }

        viewModel.onTransferFailed = { [weak self] msg in
            self?.showFailedTransactionStatus(text: msg)
        }

        viewModel.onLimitExceeded = { [weak self] _ in
            guard let self else { return }
            let vc = CoinbaseInfoViewController.controller()
            vc.modalPresentationStyle = .overCurrentContext
            self.present(vc, animated: true)
        }
    }
}

// MARK: - ActivityIndicatorPreviewing

extension TransferAmountHostingController: ActivityIndicatorPreviewing {
    func showActivityIndicator() {}
    func hideActivityIndicator() {}
}

// MARK: - CoinbaseCodeConfirmationPreviewing

extension TransferAmountHostingController: CoinbaseCodeConfirmationPreviewing {
    func codeConfirmationControllerDidContinue(with code: String, for idem: UUID) {
        viewModel.continue2FA(code: code, idem: idem)
    }

    func codeConfirmationControllerDidCancel() {
        viewModel.cancel2FA()
    }
}

// MARK: - PaymentControllerDelegate

extension TransferAmountHostingController: PaymentControllerDelegate {
    func paymentControllerDidFinishTransaction(_ controller: PaymentController, txidWire: Data) {
        // Tags the tx so its home-screen row resolves the Coinbase title and icon.
        CoinbaseTransactionMetadataTagger.shared.track(sentTransactionTxidWire: txidWire)
        showSuccessTransactionStatus(text: Self.transferSuccessText)
    }

    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {}

    func paymentControllerDidFailTransaction(_ controller: PaymentController) {}
}

// MARK: - PaymentControllerPresentationContextProviding

extension TransferAmountHostingController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}
