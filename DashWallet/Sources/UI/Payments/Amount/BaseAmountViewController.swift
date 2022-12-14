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

private let kKeyboardHeight: CGFloat = 215.0
private let kDescKeyboardPadding: CGFloat = 8.0

// MARK: - BaseAmountViewController

class BaseAmountViewController: ActionButtonViewController {
    public var topKeyboardView: UIView? {
        didSet {
            if let view = oldValue {
                keyboardStackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }

            guard let view = topKeyboardView else {
                keyboardTopConstraint.constant = 10
                return
            }

            keyboardTopConstraint.constant = 0
            keyboardStackView.insertArrangedSubview(view, at: 0)
        }
    }

    internal var contentView: UIView!
    internal var amountView: AmountView!

    internal var keyboardContainer: UIView!
    internal var keyboardStackView: UIStackView!
    private var keyboardTopConstraint: NSLayoutConstraint!

    internal var numberKeyboard: NumberKeyboard!

    internal var model: BaseAmountModel!
    internal var amountInputStyle: AmountInputControl.Style { .oppositeAmount }

    func maxButtonAction() { }

    internal func initializeModel() {
        model = BaseAmountModel()
    }

    internal func configureModel() {
        model.amountChangeHandler = { [weak self] _ in
            self?.amountDidChange()
        }

        model.presentCurrencyPickerHandler = { [weak self] in
            self?.showCurrencyList()
        }
    }

    internal func amountDidChange() {
        amountView.reloadData()
    }

    internal func validateInputAmount() -> Bool {
        if model.isEnteredAmountLessThenMinimumOutputAmount {
            let msg = String(format: "Dash payments can't be less than %@", model.minimumOutputAmountFormattedString)
            showAlert(with: NSLocalizedString("Amount too small", comment: ""), message: msg)
            return false
        }

        return true
    }

    internal func showCurrencyList() {
        let currencyController = DWLocalCurrencyViewController(navigationAppearance: .white,
                                                               currencyCode: model.localCurrencyCode)
        currencyController.isGlobal = false
        currencyController.delegate = self
        let nvc = BaseNavigationController(rootViewController: currencyController)
        present(nvc, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        amountView.becomeFirstResponder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        initializeModel()
        configureModel()
        configureHierarchy()
    }
}

extension BaseAmountViewController {
    @objc internal func configureHierarchy() {
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        contentView.preservesSuperviewLayoutMargins = true
        setupContentView(contentView)

        amountView = AmountView(style: amountInputStyle)
        amountView.maxButtonAction = { [weak self] in
            self?.maxButtonAction()
        }
        amountView.dataSource = model
        amountView.delegate = model
        amountView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(amountView)

        keyboardContainer = UIView()
        keyboardContainer.backgroundColor = .dw_background()
        keyboardContainer.translatesAutoresizingMaskIntoConstraints = false
        keyboardContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        keyboardContainer.layer.cornerRadius = 10
        contentView.addSubview(keyboardContainer)

        keyboardStackView = UIStackView()
        keyboardStackView.translatesAutoresizingMaskIntoConstraints = false
        keyboardStackView.axis = .vertical
        keyboardContainer.addSubview(keyboardStackView)

        numberKeyboard = NumberKeyboard()
        numberKeyboard.customButtonBackgroundColor = .dw_background()
        numberKeyboard.translatesAutoresizingMaskIntoConstraints = false
        numberKeyboard.backgroundColor = .clear
        numberKeyboard.textInput = amountView.textInput
        keyboardStackView.addArrangedSubview(numberKeyboard)

        keyboardTopConstraint = keyboardStackView.topAnchor.constraint(equalTo: keyboardContainer.topAnchor, constant: 10)

        NSLayoutConstraint.activate([
            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            amountView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            amountView.heightAnchor.constraint(equalToConstant: 60),

            keyboardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            keyboardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            keyboardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            keyboardTopConstraint,
            keyboardStackView.leadingAnchor.constraint(equalTo: keyboardContainer.leadingAnchor),
            keyboardStackView.trailingAnchor.constraint(equalTo: keyboardContainer.trailingAnchor),
            keyboardStackView.bottomAnchor.constraint(equalTo: keyboardContainer.bottomAnchor, constant: -15),
        ])
    }
}

// MARK: DWLocalCurrencyViewControllerDelegate

extension BaseAmountViewController: DWLocalCurrencyViewControllerDelegate {
    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        model.setupCurrencyCode(currencyCode)
        amountView.reloadInputTypeSwitcher()
        controller.dismiss(animated: true)
    }

    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        controller.dismiss(animated: true)
    }


}
