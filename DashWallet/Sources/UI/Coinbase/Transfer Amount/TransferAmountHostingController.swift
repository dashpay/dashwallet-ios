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

    private let viewModel: TransferAmountViewModel
    /// The latest wallet send's controller, fresh for each send and kept after
    /// its outcome until the next one replaces it.
    private(set) var paymentController: PaymentController?
    /// A wallet send started here has not reported its outcome yet.
    private(set) var isWalletPaymentInFlight = false

    init(viewModel: TransferAmountViewModel? = nil) {
        self.viewModel = viewModel ?? TransferAmountViewModel()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
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

    /// One wallet send at a time. Replacing the controller mid-send would drop
    /// the first send's outcome: its processor's delegate is weak, so the old
    /// controller would deallocate without showing it.
    private func startWalletPayment(with input: DWPaymentInput) {
        guard !isWalletPaymentInFlight else {
            DWLogger.log("Coinbase: transfer from the wallet ignored — another one has not finished")
            return
        }
        let controller = PaymentController()
        controller.delegate = self
        controller.presentationContextProvider = self
        // A confirm sheet whose swipe-down was reported as a cancel and then
        // abandoned stays up and can still confirm: its broadcast takes the
        // screen back.
        controller.sendInProgressHandler = { [weak self, weak controller] inProgress in
            guard inProgress, let self, let controller, controller === self.paymentController else { return false }
            self.isWalletPaymentInFlight = true
            self.viewModel.walletPaymentDidStart()
            return false
        }
        paymentController = controller
        isWalletPaymentInFlight = true
        controller.performPayment(with: input)
    }

    /// Only the current send's outcome counts; an earlier controller's late
    /// callback changes nothing.
    private func walletPaymentDidEnd(_ controller: PaymentController, keypadBack: Bool = true) {
        guard controller === paymentController else { return }
        isWalletPaymentInFlight = false
        if keypadBack {
            viewModel.walletPaymentDidEnd()
        }
    }

    private func wireCallbacks() {
        viewModel.onInitiatePayment = { [weak self] input in
            self?.startWalletPayment(with: input)
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

        viewModel.onNeedsLeftoverWarning = { [weak self] completion in
            guard let self else { completion(false); return }
            let title = NSLocalizedString(
                "Looks like you are emptying your Dash Wallet",
                comment: "Leftover balance warning"
            )
            let message = String.localizedStringWithFormat(
                NSLocalizedString(
                    "Please note, you will not be able to withdraw your funds from CowdNode to this wallet until you increase your balance to %@ Dash.",
                    comment: "Leftover balance warning"
                ),
                CrowdNode.minimumLeftoverBalance.formattedDashAmountWithoutCurrencySymbol
            )
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Continue", comment: "Leftover balance warning"),
                style: .default,
                handler: { _ in completion(true) }
            ))
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Cancel", comment: "Leftover balance warning"),
                style: .cancel,
                handler: { _ in completion(false) }
            ))
            self.present(alert, animated: true)
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
        // The success screen replaces this one: the keypad stays off, or a
        // hardware Return during the push would start another transfer.
        walletPaymentDidEnd(controller, keypadBack: false)
        showSuccessTransactionStatus(text: Self.transferSuccessText, holdsExitsWhileShown: true)
    }

    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {
        walletPaymentDidEnd(controller)
    }

    /// Arrives after the failure's alert is up, or with nothing shown for a
    /// failure that carries no error.
    func paymentControllerDidFailTransaction(_ controller: PaymentController) {
        walletPaymentDidEnd(controller)
    }
}

// MARK: - PaymentControllerPresentationContextProviding

extension TransferAmountHostingController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}
