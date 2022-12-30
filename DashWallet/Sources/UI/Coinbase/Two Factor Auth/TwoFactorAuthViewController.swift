//
//  Created by hadia
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

import Foundation
import UIKit

// MARK: - TwoFactorAuthViewController

final class TwoFactorAuthViewController: ActionButtonViewController {
    @IBOutlet var screenLabel: UILabel!
    @IBOutlet var subTitle: UILabel!
    @IBOutlet var contactCoinbase: UILabel!
    @IBOutlet var twoFactorAuthField: UITextField!
    @IBOutlet var hintLabel: UILabel!

    public var isVerifying = false
    public var verifyHandler: ((String) -> Void)?
    public var cancelHandler: (() -> Void)?
    private var numberKeyboard: NumberKeyboard!
    internal var contentView: UIView!

    let contactCoinbaseString = NSLocalizedString("Contact Coinbase Support", comment: "Coinbase Two Factor Auth")

    internal var isErrorShown = false

    public func showInvalidCodeState() {
        isVerifying = false
        isErrorShown = true
        styleHintFieldErrorState()
        styleTwoFactorAuthFieldErrorState()
        hideActivityIndicator()
    }

    override func viewWillDisappear(_ animated: Bool) {
        if !isVerifying {
            cancelHandler?()
        }

        super.viewWillDisappear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        setupContentView(contentView)

        twoFactorAuthField.delegate = self

        styleTitle()
        styleSubTitle()
        styleContactCoinbase()
        styleTwoFactorAuthFieldDefaultState()
        styleHintFieldDefaultState()

        let keyboardContainer = UIView()
        keyboardContainer.backgroundColor = .dw_background()
        keyboardContainer.translatesAutoresizingMaskIntoConstraints = false
        keyboardContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        keyboardContainer.layer.cornerRadius = 10
        contentView.addSubview(keyboardContainer)

        numberKeyboard = NumberKeyboard()
        numberKeyboard.customButtonBackgroundColor = .dw_background()
        numberKeyboard.translatesAutoresizingMaskIntoConstraints = false
        numberKeyboard.backgroundColor = .clear
        numberKeyboard.textInput = twoFactorAuthField
        contentView.addSubview(numberKeyboard)

        NSLayoutConstraint.activate([
            keyboardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            keyboardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            keyboardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            numberKeyboard.topAnchor.constraint(equalTo: keyboardContainer.topAnchor, constant: 15),
            numberKeyboard.leadingAnchor.constraint(equalTo: keyboardContainer.leadingAnchor),
            numberKeyboard.trailingAnchor.constraint(equalTo: keyboardContainer.trailingAnchor),
            numberKeyboard.bottomAnchor.constraint(equalTo: keyboardContainer.bottomAnchor, constant: -15),
        ])
    }

    override var actionButtonTitle: String? {
        NSLocalizedString("Verfiy", comment: "Coinbase")
    }

    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()
        isVerifying = true
        verifyHandler?(twoFactorAuthField.text!)
    }

    func styleTitle() {
        screenLabel.text = NSLocalizedString("Enter Coinbase 2FA code", comment: "Coinbase Two Factor Auth")
        screenLabel.font = UIFont.dw_font(forTextStyle: .headline).withWeight(UIFont.Weight.semibold.rawValue).withSize(20)
        screenLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(screenLabel)
    }

    func styleSubTitle() {
        subTitle.text = NSLocalizedString("This extra step shows it’s really you trying to make a transaction.",
                                          comment: "Coinbase Two Factor Auth")
        subTitle.font = UIFont.dw_font(forTextStyle: .body)
        subTitle.numberOfLines = 0
        subTitle.translatesAutoresizingMaskIntoConstraints = false
        subTitle.lineBreakMode = .byWordWrapping
        contentView.addSubview(subTitle)
    }

    func styleContactCoinbase() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tappedOnLabel(_:)))
        tapGesture.numberOfTapsRequired = 1
        contactCoinbase.addGestureRecognizer(tapGesture)
        contactCoinbase.isUserInteractionEnabled = true

        let needHelpAttributedString =
            NSMutableAttributedString(string: NSLocalizedString("Need help? ", comment: "Coinbase Two Factor Auth"),
                                      attributes: nil)
        let contactCoinbasnAttributedLinkString = NSMutableAttributedString(string: contactCoinbaseString,
                                                                            attributes: [
                                                                                .foregroundColor: UIColor.dw_dashBlue(),
                                                                                NSAttributedString.Key
                                                                                    .link: URL(string: "https://help.coinbase.com/en/contact-us")!,
                                                                            ])

        let fullAttributedString = NSMutableAttributedString()
        fullAttributedString.append(needHelpAttributedString)
        fullAttributedString.append(contactCoinbasnAttributedLinkString)

        contactCoinbase.isUserInteractionEnabled = true
        contactCoinbase.font = UIFont.dw_font(forTextStyle: .body)
        contactCoinbase.attributedText = fullAttributedString

        guard let text = contactCoinbase.text else { return }
        let contactCoinbaseRange = (text as NSString).range(of: contactCoinbaseString)

        fullAttributedString.enumerateAttributes(in: contactCoinbaseRange, options: []) { _, range, _ in
            fullAttributedString.removeAttribute(.link, range: range)
            fullAttributedString.removeAttribute(.underlineStyle, range: range)
        }

        contactCoinbase.attributedText = fullAttributedString
        contentView.addSubview(contactCoinbase)
    }

    func styleTwoFactorAuthFieldDefaultState() {
        twoFactorAuthField.backgroundColor = .clear
        twoFactorAuthField.layer.borderColor = UIColor.dw_dashBlue().cgColor
        twoFactorAuthField.layer.borderWidth = 1.0
        twoFactorAuthField.layer.cornerRadius = 10.5
        twoFactorAuthField.autocorrectionType = .no
        twoFactorAuthField.autocapitalizationType = .none
        twoFactorAuthField.spellCheckingType = .no
        twoFactorAuthField.placeholder = NSLocalizedString("Coinbase 2FA code", comment: "Coinbase Two Factor Auth")
        contentView.addSubview(twoFactorAuthField)
    }

    func styleTwoFactorAuthFieldErrorState() {
        twoFactorAuthField.borderStyle = .none
        twoFactorAuthField.layer.cornerRadius = 10.5
        twoFactorAuthField.backgroundColor = UIColor.dw_red().withAlphaComponent(0.1)
    }

    func styleHintFieldDefaultState() {
        hintLabel
            .text =
            NSLocalizedString("It could be the code from the SMS on your phone. If not, enter the code from the authentication app.",
                              comment: "Coinbase Two Factor Auth")
        hintLabel.font = UIFont.dw_font(forTextStyle: .caption1)
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.textColor = .dw_secondaryText()
        contentView.addSubview(hintLabel)
    }

    func styleHintFieldErrorState() {
        let errorColor = UIColor.dw_red().withAlphaComponent(0.55)
        hintLabel.textColor = errorColor
        let image = UIImage(named: "icon_exclamation")?.withTintColor(errorColor)

        let textAttachment = NSTextAttachment()
        textAttachment.image = image
        textAttachment.adjustsImageSizeForAccessibilityContentSizeCategory = true
        textAttachment.bounds = CGRect(x: -3.0, y: -2.0, width: 14, height: 14)

        let attributedText = NSMutableAttributedString()
        attributedText.beginEditing()
        attributedText.append(NSAttributedString(string: ""))
        attributedText.append(NSAttributedString(attachment: textAttachment))
        attributedText.append(NSAttributedString(string: " "))
        attributedText
            .append(NSAttributedString(string: NSLocalizedString("The code is incorrect. Please check and try again!",
                                                                 comment: "Coinbase Two Factor Auth")))

        hintLabel.attributedText = attributedText
    }

    @objc func tappedOnLabel(_ gesture: UITapGestureRecognizer) {
        guard let text = contactCoinbase.text else { return }
        let contactCoinbaseRange = (text as NSString).range(of: contactCoinbaseString)

        if gesture.didTapAttributedTextInLabel(label: contactCoinbase, inRange: contactCoinbaseRange) {
            UIApplication.shared.open(kCoinbaseContactURL)
        }
    }

    @IBAction func textFieldEditingDidChange(_ sender: Any) {
        guard let text = twoFactorAuthField.text else { return }

        if text.isEmpty {
            actionButton?.isEnabled = false
        } else {
            actionButton?.isEnabled = true
        }
    }

    @objc class func controller() -> TwoFactorAuthViewController {
        vc(TwoFactorAuthViewController.self, from: sb("Coinbase"))
    }
}

// MARK: UITextFieldDelegate

extension TwoFactorAuthViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if isErrorShown {
            textField.text = ""
            styleHintFieldDefaultState()
            styleTwoFactorAuthFieldDefaultState()
            isErrorShown = false
        }

        return true
    }
}

// MARK: TwoFactorAuthModelDelegate

extension TwoFactorAuthViewController: TwoFactorAuthModelDelegate {
    func transferFromCoinbaseSuccess() {
        // TODO: naigate to success screen
    }

    func transferFromCoinbaseForTwoFactorAuthError(error: Error) {
        styleTwoFactorAuthFieldErrorState()
        styleHintFieldErrorState()
    }

    func transferFromCoinbaseForUnkownError(error: Error) {
        // TODO: naigate to error screen
    }
}

extension UITapGestureRecognizer {
    func didTapAttributedTextInLabel(label: UILabel, inRange targetRange: NSRange) -> Bool {
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize.zero)
        let textStorage = NSTextStorage(attributedString: label.attributedText!)

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        textContainer.lineFragmentPadding = 0.0
        textContainer.lineBreakMode = label.lineBreakMode
        textContainer.maximumNumberOfLines = label.numberOfLines
        let labelSize = label.bounds.size
        textContainer.size = labelSize

        let locationOfTouchInLabel = location(in: label)
        let textBoundingBox = layoutManager.usedRect(for: textContainer)
        let textContainerOffset = CGPoint(x: (labelSize.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x,
                                          y: (labelSize.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y)
        let locationOfTouchInTextContainer = CGPoint(x: locationOfTouchInLabel.x - textContainerOffset.x,
                                                     y: locationOfTouchInLabel.y - textContainerOffset.y)
        let indexOfCharacter = layoutManager.characterIndex(for: locationOfTouchInTextContainer, in: textContainer,
                                                            fractionOfDistanceBetweenInsertionPoints: nil)
        return NSLocationInRange(indexOfCharacter, targetRange)
    }
}

// MARK: - TwoFactorAuthTextField

class TwoFactorAuthTextField: UITextField {
    var textInsets: UIEdgeInsets = .init(top: 0, left: 15, bottom: 0, right: 15) {
        didSet {
            setNeedsLayout()
        }
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: bounds.origin.x + textInsets.left,
               y: bounds.origin.y + textInsets.top,
               width: bounds.size.width - (textInsets.left + textInsets.right),
               height: bounds.size.height - (textInsets.top + textInsets.bottom))
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        textRect(forBounds: bounds)
    }
}
