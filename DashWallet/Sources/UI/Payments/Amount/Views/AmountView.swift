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



// MARK: - AmountView

class AmountView: UIView {
    public var textInput: UITextInput {
        amountInputControl.textField
    }

    private(set) var amountInputStyle: AmountInputControl.Style

    public var amountType: AmountInputControl.AmountType {
        set {
            amountInputControl.amountType = newValue
        }
        get {
            amountInputControl.amountType
        }
    }

    public var maxButtonAction: (() -> Void)?
    public var infoButtonHandler: (() -> Void)?

    private(set) var maxButton: UIButton!
    private(set) var amountInputControl: AmountInputControl!
    private(set) var inputTypeSwitcher: AmountInputTypeSwitcher!

    private var errorStackView: UIStackView!
    private var errorLabel: UILabel!
    private var infoButton: UIButton!

    override var intrinsicContentSize: CGSize {
        .init(width: AmountView.noIntrinsicMetric, height: 90)
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        amountInputControl.becomeFirstResponder()
    }

    init(style: AmountInputControl.Style) {
        amountInputStyle = style

        super.init(frame: .zero)

        configureHierarchy()
    }

    override init(frame: CGRect) {
        amountInputStyle = .oppositeAmount

        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        amountInputStyle = .oppositeAmount

        super.init(coder: coder)
    }

    public func showError(_ msg: String, textColor: UIColor, infoButtonAction: (() -> Void)? = nil) {
        errorStackView.isHidden = false
        errorLabel.text = msg
        errorLabel.textColor = textColor
        infoButton.isHidden = infoButtonAction == nil
        infoButtonHandler = infoButtonAction
    }

    public func hideError() {
        errorStackView.isHidden = true
        infoButton.isHidden = true

        errorLabel.text = nil
    }

    @objc
    func maxButtonActionHandler() {
        maxButtonAction?()
    }

    @objc
    func infoButtonAction() {
        infoButtonHandler?()
    }
}

extension AmountView {
    private func configureHierarchy() {
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        addSubview(contentView)

        maxButton = MaxButton(frame: .zero)
        maxButton.translatesAutoresizingMaskIntoConstraints = false
        maxButton.addTarget(self, action: #selector(maxButtonActionHandler), for: .touchUpInside)
        contentView.addSubview(maxButton)

        amountInputControl = AmountInputControl(style: amountInputStyle)
        amountInputControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(amountInputControl)

        inputTypeSwitcher = AmountInputTypeSwitcher(frame: .zero)
        inputTypeSwitcher.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inputTypeSwitcher)

        errorStackView = UIStackView()
        errorStackView.isHidden = true
        errorStackView.translatesAutoresizingMaskIntoConstraints = false
        errorStackView.axis = .horizontal
        errorStackView.alignment = .center
        errorStackView.spacing = 2
        addSubview(errorStackView)

        errorLabel = UILabel()
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.font = .dw_font(forTextStyle: .footnote)
        errorLabel.textAlignment = .center
        errorStackView.addArrangedSubview(errorLabel)

        let configuration = UIImage.SymbolConfiguration(pointSize: UIFont.dw_font(forTextStyle: .footnote).pointSize, weight: .regular)
        let image = UIImage(systemName: "info.circle", withConfiguration: configuration)

        infoButton = UIButton(type: .custom)
        infoButton.tintColor = .systemRed
        infoButton.setImage(image, for: .normal)
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        infoButton.addTarget(self, action: #selector(infoButtonAction), for: .touchUpInside)
        infoButton.isHidden = true
        errorStackView.addArrangedSubview(infoButton)

        let kMaxButtonWidth: CGFloat = 42.0
        let kAmountInputControlPadding: CGFloat = 60

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 60),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),

            maxButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            maxButton.widthAnchor.constraint(equalToConstant: kMaxButtonWidth),
            maxButton.heightAnchor.constraint(equalToConstant: kMaxButtonWidth),
            maxButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),

            amountInputControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            amountInputControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            amountInputControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: kAmountInputControlPadding),
            amountInputControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -kAmountInputControlPadding),

            inputTypeSwitcher.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            inputTypeSwitcher.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 10),
        ])
    }
}

// MARK: - MaxButton

private class MaxButton: UIButton {
    override var isHighlighted: Bool {
        didSet { }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    private func configureHierarchy() {
        layer.cornerRadius = 19
        layer.masksToBounds = true
        contentEdgeInsets = .init(top: 9, left: 9, bottom: 9, right: 9)

        titleLabel?.font = .dw_font(forTextStyle: .footnote)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.5

        let color: UIColor = .dw_dashBlue()
        setTitleColor(color, for: .normal)
        setTitleColor(.white, for: .highlighted)
        setTitleColor(color.withAlphaComponent(0.4), for: .disabled)

        backgroundColor = color.withAlphaComponent(0.1)

        setTitle(NSLocalizedString("Max", comment: "Contracted variant of 'Maximum' word"), for: .normal)
    }
}
