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

import Combine
import UIKit

// MARK: - BuyDashViewController

final class BuyDashViewController: CoinbaseAmountViewController {
    override var actionButtonTitle: String? { NSLocalizedString("Continue", comment: "Buy Dash") }

    override var amountInputStyle: AmountInputControl.Style { .oppositeAmount }

    internal var buyDashModel: BuyDashModel {
        model as! BuyDashModel
    }

    internal var cancellables = Set<AnyCancellable>()

    override var isMaxButtonHidden: Bool { true }

    init() {
        super.init(model: BuyDashModel())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Actions
    override func actionButtonAction(sender: UIView) {
        handleBuy(retryWithDeposit: false)
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        let titleViewStackView = UIStackView()
        titleViewStackView.alignment = .center
        titleViewStackView.translatesAutoresizingMaskIntoConstraints = false
        titleViewStackView.axis = .vertical
        titleViewStackView.spacing = 1
        navigationItem.titleView = titleViewStackView

        let titleLabel = UILabel()
        titleLabel.font = .dw_mediumFont(ofSize: 16)
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.text = NSLocalizedString("Buy Dash", comment: "Coinbase/Buy Dash")
        titleViewStackView.addArrangedSubview(titleLabel)

        let dashPriceLabel = UILabel()
        dashPriceLabel.font = .dw_font(forTextStyle: .footnote)
        dashPriceLabel.textColor = .dw_secondaryText()
        dashPriceLabel.minimumScaleFactor = 0.5
        dashPriceLabel.text = buyDashModel.dashPriceDisplayString
        titleViewStackView.addArrangedSubview(dashPriceLabel)

        amountView.removeFromSuperview()
        contentView.addSubview(amountView)

        let sendingToView = SendingToView(frame: .zero)
        sendingToView.translatesAutoresizingMaskIntoConstraints = false

        topKeyboardView = sendingToView

        NSLayoutConstraint.activate([
            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            NSLayoutConstraint(item: amountView!, attribute: .top, relatedBy: .equal, toItem: contentView, attribute: .centerY, multiplier: 0.35, constant: 0),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
        startNetworkMonitoring()
    }
}

extension BuyDashViewController {
    private func handleBuy(retryWithDeposit: Bool) {
        showActivityIndicator()
        
        Task {
            let error = await buyDashModel.validateBuyDash(retryWithDeposit: retryWithDeposit)
            hideActivityIndicator()
            
            switch error {
            case .unknownError:
                guard let paymentMethod = buyDashModel.activePaymentMethod else { return }

                let vc = ConfirmOrderController(paymentMethod: paymentMethod, plainAmount: UInt64(buyDashModel.amount.plainAmount))
                vc.hidesBottomBarWhenPushed = true
                navigationController?.pushViewController(vc, animated: true)
            default:
                showError(error)
            }
        }
    }
}

extension BuyDashViewController {
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

extension BuyDashViewController {
    private func showError(_ error: Coinbase.Error) {
        let title: String
        let message: String
        let action: UIAlertAction?
        
        switch error {
        case .general(.noCashAccount), .general(.noPaymentMethods):
            title = error.failureReason ?? NSLocalizedString("Error", comment: "")
            message = error.localizedDescription
            action = UIAlertAction(title: NSLocalizedString("Add", comment: "Coinbase"), style: .default) { [weak self] _ in
                self?.addPaymentMethod()
            }
        case .transactionFailed(.notEnoughFunds):
            title = NSLocalizedString("You don’t have enough balance", comment: "Coinbase")
            message = NSLocalizedString("Would you like to make a deposit for your purchase using a linked bank account?", comment: "Coinbase")
            action = UIAlertAction(title: NSLocalizedString("Confirm", comment: "Coinbase"), style: .default) { [weak self] _ in
                self?.handleBuy(retryWithDeposit: true)
            }
        default:
            title = error.failureReason ?? NSLocalizedString("Error", comment: "")
            message = error.localizedDescription
            action = nil
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let action = action {
            alert.addAction(action)
        }

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
    
    private func addPaymentMethod() {
        UIApplication.shared.open(kCoinbaseAddPaymentMethodsURL)
    }
}
