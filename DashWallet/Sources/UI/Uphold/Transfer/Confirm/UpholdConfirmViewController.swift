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

// MARK: - UpholdConfirmViewControllerDelegate

protocol UpholdConfirmViewControllerDelegate: AnyObject {
    func upholdConfirmViewController(_ controller: UpholdConfirmViewController, didSendTransaction transaction: DWUpholdTransactionObject)
    func upholdConfirmViewControllerDidCancelTransaction(_ controller: UpholdConfirmViewController)
}

// MARK: - UpholdConfirmViewController

final class UpholdConfirmViewController: ConfirmPaymentViewController {
    public weak var otpProvider: DWUpholdOTPProvider?
    public weak var resultDelegate: UpholdConfirmViewControllerDelegate?

    public var upholdModel: UpholdConfirmTransferModel { model as! UpholdConfirmTransferModel }

    init(card: DWUpholdCardObject, transaction: DWUpholdTransactionObject) {
        let model = UpholdConfirmTransferModel(card: card, transaction: transaction)

        super.init(model: model)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        upholdModel.stateNotifier = self
    }
}

// MARK: UpholdConfirmTransferModelStateNotifier

extension UpholdConfirmViewController: UpholdConfirmTransferModelStateNotifier {
    func upholdConfirmTransferModel(_ model: UpholdConfirmTransferModel, didUpdateState state: UpholdConfirmTransferModel.State) {
        switch state {
        case .none:
            isSendingEnabled = true
        case .loading:
            isSendingEnabled = false

        case .success:
            dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.resultDelegate?.upholdConfirmViewController(self, didSendTransaction: self.upholdModel.transaction)
            }
        case .fail:
            isSendingEnabled = true
            showError(with: NSLocalizedString("Something went wrong", comment: ""))
        case .otp:
            otpProvider?.requestOTP { [weak self] otpToken in
                guard let strongSelf = self else { return }

                if let otpToken {
                    strongSelf.upholdModel.confirm(withOTPToken: otpToken)
                } else {
                    strongSelf.upholdModel.resetState()
                }
            }
        }
    }
}

// MARK: ConfirmPaymentViewControllerDelegate

extension UpholdConfirmViewController: ConfirmPaymentViewControllerDelegate {
    func confirmPaymentViewControllerDidCancel(_ controller: ConfirmPaymentViewController) {
        resultDelegate?.upholdConfirmViewControllerDidCancelTransaction(self)
    }

    func confirmPaymentViewControllerDidConfirm(_ controller: ConfirmPaymentViewController) {
        upholdModel.confirm(withOTPToken: nil)
    }
}

// MARK: - Private

extension UpholdConfirmViewController {
    private func showError(with message: String) {
        let alert = UIAlertController(title: NSLocalizedString("Uphold", comment: ""), message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil)
        alert.addAction(okAction)
        present(alert, animated: true, completion: nil)
    }
}
