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

class BaseAmountViewController: ActionButtonViewController, AmountProviding {
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
    internal var amountInputStyle: AmountInputControl.Style { .oppositeAmount }
    internal var isMaxButtonHidden: Bool { true }

    internal var keyboardContainer: UIView!
    internal var keyboardStackView: UIStackView!
    private var keyboardTopConstraint: NSLayoutConstraint!

    internal var numberKeyboard: NumberKeyboard!

    internal let model: BaseAmountModel

    func maxButtonAction() { }

    init(model: BaseAmountModel) {
        self.model = model

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal func configureModel() {
        model.amountChangeHandler = { [weak self] _ in
            self?.amountDidChange()
        }

        model.errorHandler = { [weak self] error in
            self?.show(error: error)
        }

        model.amountInputItemsChangeHandler = { [weak self] in
            self?.amountView.inputTypeSwitcher.reloadData()
        }
    }

    internal func errorInfoButtonDidTap() {
        // NOP
    }

    internal func amountDidChange() {
        amountView.amountInputControl.reloadData()
        showErrorIfNeeded()
    }

    internal func show(error: Error) {
        hideActivityIndicator()
        present(error: error)
    }

    internal func showErrorIfNeeded() {
        guard let error = model.error else {
            amountView.hideError()
            return
        }

        show(error: error)
    }

    internal func validateInputAmount() -> Bool {
        if model.isEnteredAmountLessThenMinimumOutputAmount {
            let msg = String(format: "Dash payments can't be less than %@", model.minimumOutputAmountFormattedString)
            present(message: msg, level: .error)
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
        showErrorIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureModel()
    }
}

extension BaseAmountViewController {
    @objc
    internal func configureHierarchy() {
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        contentView.preservesSuperviewLayoutMargins = true
        setupContentView(contentView)

        amountView = AmountView(style: amountInputStyle)
        amountView.maxButtonAction = { [weak self] in
            self?.maxButtonAction()
        }
        amountView.maxButton.isHidden = isMaxButtonHidden
        amountView.translatesAutoresizingMaskIntoConstraints = false
        amountView.infoButtonHandler = { [weak self] in
            self?.errorInfoButtonDidTap()
        }
        contentView.addSubview(amountView)

        amountView.amountInputControl.delegate = self
        amountView.amountInputControl.dataSource = model
        amountView.inputTypeSwitcher.delegate = self

        buttonContainer.backgroundColor = .dw_background()

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
            keyboardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            keyboardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            keyboardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            keyboardTopConstraint,
            keyboardStackView.leadingAnchor.constraint(equalTo: keyboardContainer.leadingAnchor),
            keyboardStackView.trailingAnchor.constraint(equalTo: keyboardContainer.trailingAnchor),
            keyboardStackView.bottomAnchor.constraint(equalTo: keyboardContainer.bottomAnchor, constant: -15),
        ])

        configureConstraints()
    }

    @objc
    func configureConstraints() {
        NSLayoutConstraint.activate([
            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            amountView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
        ])
    }
}

// MARK: DWLocalCurrencyViewControllerDelegate

extension BaseAmountViewController: DWLocalCurrencyViewControllerDelegate {
    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        model.setupCurrencyCode(currencyCode)
        amountView.amountInputControl.reloadData()
        amountView.inputTypeSwitcher.reloadData()

        controller.dismiss(animated: true)
    }

    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        controller.dismiss(animated: true)
    }
}

// MARK: ErrorPresentable

extension BaseAmountViewController: ErrorPresentable {
    @objc
    func present(error: Error) {
        let color: UIColor

        if let error = error as? ColorizedText {
            color = error.textColor
        } else {
            color = .systemRed
        }

        amountView.showError(error.localizedDescription, textColor: color)
    }

    func present(message: String, level: MessageLevel) {
        amountView.showError(message, textColor: level.textColor)
    }
}

// MARK: AmountInputControlDelegate

extension BaseAmountViewController: AmountInputControlDelegate {
    var isCurrencySelectorHidden: Bool {
        model.isCurrencySelectorHidden
    }

    func updateInputField(with replacementText: String, in range: NSRange) {
        model.updateInputField(with: replacementText, in: range)
    }

    func amountInputControlDidSwapInputs() {
        model.amountInputControlDidSwapInputs()
        amountView.inputTypeSwitcher.reloadData()
    }

    func amountInputControlChangeCurrencyDidTap() {
        showCurrencyList()
    }

    func amountInputWantToPasteFromClipboard() {
        model.pasteFromClipboard()
    }
}

// MARK: AmountInputTypeSwitcherDelegate

extension BaseAmountViewController: AmountInputTypeSwitcherDelegate {
    var numberOfInputTypes: Int {
        model.inputItems.count
    }

    func amountInputTypeSwitcher(_ switcher: AmountInputTypeSwitcher, didSelectItemAt index: Int) {
        model.selectInputItem(at: index)

        let type: AmountInputControl.AmountType = model.currentInputItem.isMain ? .main : .supplementary
        amountView.amountInputControl.setActiveType(type, animated: true, completion: nil)
    }

    func amountInputTypeSwitcher(_ switcher: AmountInputTypeSwitcher, valueForItemAt index: Int) -> String {
        model.inputItems[index].currencyCode
    }

    func amountInputTypeSwitcher(_ switcher: AmountInputTypeSwitcher, isValueSelectedForItemAt index: Int) -> Bool {
        let item = model.inputItems[index]
        return item == model.currentInputItem
    }
}

