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

// MARK: - BuyDashViewController

final class BuyDashViewController: BaseAmountViewController, NetworkReachabilityHandling {
    internal var networkStatusDidChange: ((NetworkStatus) -> ())?
    internal var reachabilityObserver: Any!


    override var actionButtonTitle: String? { NSLocalizedString("Continue", comment: "Buy Dash") }

    internal var buyDashModel: BuyDashModel {
        model as! BuyDashModel
    }

    private var activePaymentMethodView: ActivePaymentMethodView!
    private var networkUnavailableView: UIView!

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Actions
    override func amountDidChange() {
        super.amountDidChange()
        actionButton?.isEnabled = buyDashModel.canContinue
    }

    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()
        buyDashModel.buy()
    }

    @objc func payWithTapGestureRecognizerAction() {
        let vc = PaymentMethodsController.controller()
        vc.paymentMethods = buyDashModel.paymentMethods
        vc.selectedPaymentMethod = buyDashModel.activePaymentMethod
        vc.selectPaymentMethodAction = { [weak self] method in
            self?.buyDashModel.select(paymentMethod: method)
            self?.activePaymentMethodView.update(with: method)
        }
        present(vc, animated: true)
    }

    // MARK: Life cycle
    override func initializeModel() {
        model = BuyDashModel()
    }

    override func configureModel() {
        super.configureModel()

        buyDashModel.delegate = self
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

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(payWithTapGestureRecognizerAction))

        activePaymentMethodView = ActivePaymentMethodView(frame: .zero)
        activePaymentMethodView.update(with: buyDashModel.activePaymentMethod)
        activePaymentMethodView.setChevronButtonHidden(buyDashModel.paymentMethods.count <= 1)
        activePaymentMethodView.translatesAutoresizingMaskIntoConstraints = false
        activePaymentMethodView.addGestureRecognizer(tapGestureRecognizer)
        contentView.addSubview(activePaymentMethodView)

        let sendingToView = SendingToView(frame: .zero)
        sendingToView.translatesAutoresizingMaskIntoConstraints = false

        topKeyboardView = sendingToView

        networkUnavailableView = NetworkUnavailableView(frame: .zero)
        networkUnavailableView.translatesAutoresizingMaskIntoConstraints = false
        networkUnavailableView.isHidden = true
        contentView.addSubview(networkUnavailableView)

        NSLayoutConstraint.activate([
            activePaymentMethodView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            activePaymentMethodView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            activePaymentMethodView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            activePaymentMethodView.heightAnchor.constraint(equalToConstant: 46),

            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            amountView.topAnchor.constraint(equalTo: activePaymentMethodView.bottomAnchor, constant: 30),

            networkUnavailableView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            networkUnavailableView.centerYAnchor.constraint(equalTo: numberKeyboard.centerYAnchor),
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

// MARK: Private
extension BuyDashViewController {
    private func reloadView() {
        let isOnline = networkStatus == .online
        networkUnavailableView.isHidden = isOnline
        keyboardContainer.isHidden = !isOnline
        if let btn = actionButton as? UIButton { btn.superview?.isHidden = !isOnline }
    }
}

// MARK: BuyDashModelDelegate

extension BuyDashViewController: BuyDashModelDelegate {
    func buyDashModelDidPlace(order: CoinbasePlaceBuyOrder) {
        guard let paymentMethod = buyDashModel.activePaymentMethod else { return }

        let vc = ConfirmOrderController(order: order, paymentMethod: paymentMethod, plainAmount: UInt64(buyDashModel.amount.plainAmount))
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
        hideActivityIndicator()
    }

    func buyDashModelFailedToPlaceOrder(with error: Coinbase.Error) {
        hideActivityIndicator()

        showAlert(with: "Error", message: error.localizedDescription)
    }
}

extension BuyDashViewController {
    @objc override func present(error: Error) {
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

