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

final class TwoFactorAuthViewController: ActionButtonViewController {
    
    @IBOutlet weak var screenLabel: UILabel!
    @IBOutlet weak var subTitle: UILabel!
    @IBOutlet weak var contactCoinbase: UILabel!
    @IBOutlet weak var twoFactorAuthField: UITextField!
    @IBOutlet weak var hintLabel: UILabel!
    
    private var numberKeyboard: NumberKeyboard!
    internal var contentView: UIView!
    
    let contactCoinbaseString =  NSLocalizedString("Contact Coinbase Support", comment: "Coinbase Two Factor Auth")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        setupContentView(contentView)
        
        screenLabel.text = NSLocalizedString("Enter Coinbase 2FA code", comment: "Coinbase Two Factor Auth")
        screenLabel.font = UIFont.dw_font(forTextStyle: .headline).withWeight(UIFont.Weight.semibold.rawValue).withSize(20)
        screenLabel.translatesAutoresizingMaskIntoConstraints = false
        
        subTitle.text = NSLocalizedString("This extra step shows it’s really you trying to make a transaction.", comment: "Coinbase Two Factor Auth")
        subTitle.font = UIFont.dw_font(forTextStyle: .body)
        subTitle.numberOfLines = 0
        subTitle.translatesAutoresizingMaskIntoConstraints = false
        subTitle.lineBreakMode = .byWordWrapping
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tappedOnLabel(_ :)))
        tapGesture.numberOfTapsRequired = 1
        contactCoinbase.addGestureRecognizer(tapGesture)
        contactCoinbase.isUserInteractionEnabled = true
        
        let  needHelpAttributedString = NSMutableAttributedString(string:  NSLocalizedString(" Need help? ", comment: "Coinbase Two Factor Auth"), attributes: nil)
        let contactCoinbasnAttributedLinkString = NSMutableAttributedString(string: contactCoinbaseString, attributes:[.foregroundColor: UIColor.dw_dashBlue(), NSAttributedString.Key.link: URL(string: "https://help.coinbase.com/en/contact-us")!])
        
        let fullAttributedString = NSMutableAttributedString()
        fullAttributedString.append( needHelpAttributedString)
        fullAttributedString.append(contactCoinbasnAttributedLinkString)
        
        contactCoinbase.isUserInteractionEnabled = true
        contactCoinbase.font = UIFont.dw_font(forTextStyle: .body)
        contactCoinbase.attributedText = fullAttributedString
        styleContactCoinbase(attributedString:fullAttributedString)
        
        twoFactorAuthField.layer.borderColor = UIColor.dw_dashBlue().cgColor
        twoFactorAuthField.layer.borderWidth = 1.0
        twoFactorAuthField.layer.cornerRadius = 10.5
        twoFactorAuthField.placeholder = NSLocalizedString("Coinbase 2FA code", comment: "Coinbase Two Factor Auth")
        twoFactorAuthField.autocorrectionType = .no
        twoFactorAuthField.autocapitalizationType = .none
        twoFactorAuthField.spellCheckingType = .no
        
        let inputViewRect = CGRect(x: 0.0, y: 0.0, width: UIScreen.main.bounds.width, height: 1.0)
        twoFactorAuthField.inputView = DWNumberKeyboardInputViewAudioFeedback(frame: inputViewRect)
        
        let inputAssistantItem = twoFactorAuthField.inputAssistantItem
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        
        hintLabel.text = NSLocalizedString("It could be the code from the SMS on your phone.If not, enter the code from the authentication app.",
                                           comment: "Coinbase Two Factor Auth")
        hintLabel.font = UIFont.dw_font(forTextStyle: .caption1)
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.textColor = .dw_secondaryText()
        
        contentView.addSubview(screenLabel)
        contentView.addSubview(subTitle)
        contentView.addSubview(contactCoinbase)
        contentView.addSubview(twoFactorAuthField)
        contentView.addSubview(hintLabel)
        
        let keyboardContainer = UIView()
        keyboardContainer.backgroundColor = .dw_background()
        keyboardContainer.translatesAutoresizingMaskIntoConstraints = false
        keyboardContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        keyboardContainer.layer.cornerRadius = 10
        contentView.addSubview(keyboardContainer)
        
        
        self.numberKeyboard = NumberKeyboard()
        numberKeyboard.customButtonBackgroundColor = .dw_background()
        numberKeyboard.translatesAutoresizingMaskIntoConstraints = false
        numberKeyboard.backgroundColor = .clear
        numberKeyboard.textInput = twoFactorAuthField
        contentView.addSubview(numberKeyboard)
        
        NSLayoutConstraint.activate([
            
            //keyboardContainer.heightAnchor.constraint(equalToConstant: kKeyboardHeight + 15),
            keyboardContainer.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            keyboardContainer.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            keyboardContainer.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            
            numberKeyboard.topAnchor.constraint(equalTo: keyboardContainer.topAnchor, constant: 15),
            numberKeyboard.leadingAnchor.constraint(equalTo: keyboardContainer.leadingAnchor),
            numberKeyboard.trailingAnchor.constraint(equalTo: keyboardContainer.trailingAnchor),
            numberKeyboard.bottomAnchor.constraint(equalTo: keyboardContainer.bottomAnchor, constant: -15)
        ])
        
    }
    
    override var actionButtonTitle: String? {
        return NSLocalizedString("Verfiy", comment: "Coinbase")
    }
    
    func styleContactCoinbase(attributedString:NSMutableAttributedString){
        guard let text = contactCoinbase.text else { return }
        let contactCoinbaseRange = (text as NSString).range(of:  contactCoinbaseString)
        
        attributedString.enumerateAttributes(in: contactCoinbaseRange, options: []) { attributes, range, stop in
            attributedString.removeAttribute(.link, range: range)
            attributedString.removeAttribute(.underlineStyle, range: range)
        }
        
        contactCoinbase.attributedText = attributedString
    }
    
    //MARK:- tappedOnLabel
    @objc func tappedOnLabel(_ gesture: UITapGestureRecognizer) {
        guard let text = self.contactCoinbase.text else { return }
        let contactCoinbaseRange = (text as NSString).range(of:  contactCoinbaseString)
        
        if gesture.didTapAttributedTextInLabel(label: contactCoinbase, inRange: contactCoinbaseRange) {
            let url = URL(string: "https://help.coinbase.com/en/contact-us")!
            UIApplication.shared.open(url)
        }
        
    }
    
    @IBAction func textFieldEditingDidChange(_ sender: Any) {
        guard let text = self.twoFactorAuthField.text else { return }
        
        if (text.isEmpty) {
            actionButton?.isEnabled = false
        } else {
            actionButton?.isEnabled = true
        }
    }
    
    
    @objc class func controller() -> TwoFactorAuthViewController {
        return vc(TwoFactorAuthViewController.self, from: sb("Coinbase"))
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
        
        let locationOfTouchInLabel = self.location(in: label)
        let textBoundingBox = layoutManager.usedRect(for: textContainer)
        let textContainerOffset = CGPoint(x: (labelSize.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x, y: (labelSize.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y)
        let locationOfTouchInTextContainer = CGPoint(x: locationOfTouchInLabel.x - textContainerOffset.x, y: locationOfTouchInLabel.y - textContainerOffset.y)
        let indexOfCharacter = layoutManager.characterIndex(for: locationOfTouchInTextContainer, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        return NSLocationInRange(indexOfCharacter, targetRange)
    }
}
