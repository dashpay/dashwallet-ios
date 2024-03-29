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

// MARK: - EnterAddressViewControllerDelegate

protocol EnterAddressViewControllerDelegate: AnyObject {
    func enterAddressViewControllerDidPreparePaymentInput(_ viewController: EnterAddressViewController, input: DWPaymentInput)
}

// MARK: - EnterAddressViewController

final class EnterAddressViewController: BaseViewController {
    private var addressField: DashInputField!
    private var showPasteboardContentButton: TintedButton!
    private var pasteboardContentView: PasteboardContentView!

    private var scrollView: UIScrollView!
    private var continueButton: ActionButton!

    private var model = EnterAddressModel()
    var payModel: DWPayModelProtocol! { model }

    weak var delegate: EnterAddressViewControllerDelegate?

    // MARK: Actions
    private func continueButtonAction() {
        payModel.payToAddress(from: addressField.text) { [weak self] success in
            guard let self else { return }

            guard success, let paymentInput = payModel?.pasteboardPaymentInput else {
                self.addressField.errorMessage = NSLocalizedString("Invalid Dash address", comment: "")
                return
            }

            self.delegate?.enterAddressViewControllerDidPreparePaymentInput(self, input: paymentInput)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        addressField.resignFirstResponder()

        super.viewWillDisappear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()

        updateView()
    }
}

extension EnterAddressViewController {
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

        showPasteboardContentButton = TintedButton()
        showPasteboardContentButton.titleLabelFont = UIFont.dw_font(forTextStyle: .footnote)
        showPasteboardContentButton.setTitle(NSLocalizedString("Show content in the clipboard", comment: "Enter Address Screen"), for: .normal)
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

        continueButton = ActionButton()
        continueButton.setTitle(NSLocalizedString("Continue", comment: "Continue"), for: .normal)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
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

        pasteboardContentView.isHidden = false
        showPasteboardContentButton.isHidden = true

        pasteboardContentView.update(with: string)
    }
}

// MARK: DWQRScanModelDelegate

extension EnterAddressViewController: DWQRScanModelDelegate {
    func performScanQRCodeAction(delegate: DWQRScanModelDelegate) {
        if let vc = presentedViewController, vc is DWQRScanViewController {
            return;
        }

        let controller = DWQRScanViewController()
        controller.model.delegate = delegate
        present(controller, animated: true, completion: nil)
    }

    func qrScanModel(_ viewModel: DWQRScanModel, didScanPaymentInput paymentInput: DWPaymentInput) {
        dismiss(animated: true) { [weak self] in
            guard let self else { return }

            self.delegate?.enterAddressViewControllerDidPreparePaymentInput(self, input: paymentInput)
        }
    }

    func qrScanModelDidCancel(_ viewModel: DWQRScanModel) {
        dismiss(animated: true)
    }
}

