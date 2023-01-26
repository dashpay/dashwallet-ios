//
//  Created by tkhp
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

// MARK: - UpholdTransferViewControllerDelegate

@objc(DWUpholdTransferViewControllerDelegate)
protocol UpholdTransferViewControllerDelegate: AnyObject {
    @objc(upholdTransferViewController:didSendTransaction:)
    func upholdTransferViewController(_ vc: UpholdTransferViewController, didSend transaction: DWUpholdTransactionObject)
}

// MARK: - UpholdTransferViewController

@objc(DWUpholdTransferViewController)
final class UpholdTransferViewController: BaseAmountViewController {
    @objc weak var delegate: UpholdTransferViewControllerDelegate?

    override var actionButtonTitle: String? { NSLocalizedString("Transfer", comment: "Uphold") }

    var upholdAmountModel: UpholdAmountModel { model as! UpholdAmountModel }
    override var isMaxButtonHidden: Bool { true }

    private var converterView: ConverterView!

    @objc(initWithCard:)
    init(card: DWUpholdCardObject) {
        super.init(model: UpholdAmountModel(card: card))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configureModel() {
        super.configureModel()

        upholdAmountModel.stateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .none:
                self.view.isUserInteractionEnabled = true
                self.hideActivityIndicator()
            case .loading:
                self.view.isUserInteractionEnabled = false
                self.showActivityIndicator()
            case .success:
                guard let txModel = self.upholdAmountModel.transferModel else { return }

                let controller = DWUpholdConfirmViewController(model: txModel)
                controller.resultDelegate = self
                controller.otpProvider = self
                self.present(controller, animated: true)

                self.view.isUserInteractionEnabled = true
                self.hideActivityIndicator()
            case .fail:
                self.view.isUserInteractionEnabled = true
                self.showAlert(with: NSLocalizedString("Uphold", comment: "Uphold"), message: NSLocalizedString("Something went wrong", comment: "Uphold"))

            case .failInsufficientFunds:
                self.view.isUserInteractionEnabled = true
                self.showAlert(with: NSLocalizedString("Uphold", comment: "Uphold"), message: NSLocalizedString("Fee is greater than balance", comment: "Uphold"))
            case .otp:
                self.requestOTP { otpToken in
                    if let token = otpToken {
                        self.upholdAmountModel.createTransaction(with: token)
                    } else {
                        self.upholdAmountModel.resetCreateTransactionState()
                    }
                }
            }
        }
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.title = NSLocalizedString("Transfer from Uphold", comment: "Coinbase")
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
        converterView.dataSource = model as? ConverterViewDataSource
        converterView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(converterView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
        ])
    }

    override func maxButtonAction() {
        upholdAmountModel.selectAllFunds()
    }

    override func actionButtonAction(sender: UIView) {
        upholdAmountModel.createTransaction(with: nil)
    }
}

// MARK: DWUpholdOTPProvider

extension UpholdTransferViewController: DWUpholdOTPProvider {
    func requestOTP(completion: @escaping ((String?) -> Void)) {
        let otpController = DWUpholdOTPViewController { vc, otpToken in
            vc.dismiss(animated: true)
            completion(otpToken)
        }

        let alertOTPController = DWAlertController(contentController: otpController)
        alertOTPController.setupActions(otpController.providedActions)
        alertOTPController.preferredAction = otpController.preferredAction
        topController().present(alertOTPController, animated: true)
    }
}

// MARK: DWUpholdConfirmViewControllerDelegate

extension UpholdTransferViewController: DWUpholdConfirmViewControllerDelegate {
    func upholdConfirmViewController(_ controller: DWUpholdConfirmViewController, didSendTransaction transaction: DWUpholdTransactionObject) {
        delegate?.upholdTransferViewController(self, didSend: transaction)
    }
}
