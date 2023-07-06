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

import UIKit

// MARK: - EnterAddressViewController

@objc(DWEnterAddressViewController)
final class EnterAddressViewController: BaseViewController, PayableViewController {
    private var addressField: DashInputField!
    private var showPasteboardContentButton: UIButton!
    private var pasteboardContentView: PasteboardContentView!

    private var scrollView: UIScrollView!
    private var continueButton: UIButton!

    private var model = EnterAddressModel()
    var payModel: DWPayModelProtocol! { model }

    internal var paymentController: PaymentController!
    weak var paymentControllerDelegate: PaymentControllerDelegate?

    // MARK: Actions
    private func continueButtonAction() {
        payModel.payToAddress(from: addressField.text) { [weak self] success in
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

    override func viewDidLoad() {
        super.viewDidLoad()

        configurePaymentController()
        configureHierarchy()

        updateView()
    }
}

extension EnterAddressViewController {
    private func configurePaymentController() {
        paymentController = PaymentController()
        paymentController.delegate = paymentControllerDelegate
        paymentController.presentationContextProvider = self
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        title = NSLocalizedString("Send", comment: "Send Screen")

        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 15
        contentView.addSubview(stackView)

        let scanButton = ImageButton(image: UIImage(named: "scan-qr.accessory.icon")!)
        scanButton.frame = .init(x: 0, y: 0, width: 18, height: 18)
        scanButton.addAction(.touchUpInside) { [weak self] _ in
            guard let self else { return }
            self.performScanQRCodeAction(delegate: self)
        }

        addressField = DashInputField()
        addressField.accessoryView = scanButton
        addressField.autocorrectionType = .no
        addressField.spellCheckingType = .no
        addressField.autocapitalizationType = .none
        addressField.textDidChange = { [weak self] _ in
            self?.updateView()
        }
        addressField.isEnabled = true
        addressField.placeholder = NSLocalizedString("Wallet Address", comment: "Enter Address Screen")
        addressField.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(addressField)

        showPasteboardContentButton = TintedButton(title: NSLocalizedString("Show content in the clipboard", comment: "Enter Address Screen"),
                                                   font: .dw_font(forTextStyle: .subheadline))
        showPasteboardContentButton.translatesAutoresizingMaskIntoConstraints = false
        showPasteboardContentButton.addAction(.touchUpInside) { [weak self] _ in
            self?.showPasteboardContentIfNeeded()
        }
        stackView.addArrangedSubview(showPasteboardContentButton)

        pasteboardContentView = PasteboardContentView()
        pasteboardContentView.isHidden = true
        pasteboardContentView.addressHandler = { [weak self] address in
            self?.addressField.text = address
            self?.updateView()
        }

        stackView.addArrangedSubview(pasteboardContentView)

        continueButton = DWActionButton(frame: .zero)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle(NSLocalizedString("Continue", comment: "Continue"), for: .normal)
        continueButton.addAction(.touchUpInside) { [weak self] _ in
            self?.continueButtonAction()
        }
        view.addSubview(continueButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(greaterThanOrEqualTo: continueButton.topAnchor, constant: -10),

            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 15),

            addressField.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            showPasteboardContentButton.heightAnchor.constraint(equalToConstant: 30),

            continueButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: 46),
            view.keyboardLayoutGuide.topAnchor.constraint(equalToSystemSpacingBelow: continueButton.bottomAnchor, multiplier: 1.0),
        ])
    }

    private func updateView() {
        continueButton.isEnabled = !addressField.text.isEmpty
        showPasteboardContentButton.isHidden = !(pasteboardContentView.isHidden && model.hasContentInPasteboard)
    }

    private func showPasteboardContentIfNeeded() {
        guard let string = model.extraxtPasteboardStrings() else { return }

        pasteboardContentView.update(with: string)
        pasteboardContentView.isHidden = false
        showPasteboardContentButton.isHidden = true
    }
}

// MARK: DWQRScanModelDelegate

extension EnterAddressViewController: DWQRScanModelDelegate {
    func qrScanModel(_ viewModel: DWQRScanModel, didScanPaymentInput paymentInput: DWPaymentInput) {
        dismiss(animated: true) { [weak self] in
            self?.paymentController.performPayment(with: paymentInput)
        }
    }

    func qrScanModelDidCancel(_ viewModel: DWQRScanModel) {
        dismiss(animated: true)
    }
}

// MARK: PaymentControllerPresentationContextProviding

extension EnterAddressViewController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}

