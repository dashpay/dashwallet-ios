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

class BaseAmountViewController: ActionButtonViewController {
    internal var contentView: UIView!
    internal var amountView: AmountView!
    
    private var numberKeyboard: NumberKeyboard!
    private var textField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
    }
}

extension BaseAmountViewController {
    @objc internal func configureHierarchy() {
        self.contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        setupContentView(contentView)
        
        self.amountView = AmountView(frame: .zero)
        amountView.dataSource = self
        amountView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(amountView)
        
        let textFieldRect = CGRect(x: 0.0, y: -500.0, width: 320, height: 44)
        self.textField = UITextField(frame: textFieldRect)
        textField.delegate = self
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        
        //TODO: demo mode
        let inputViewRect = CGRect(x: 0.0, y: 0.0, width: UIScreen.main.bounds.width, height: 1.0)
        textField.inputView = DWNumberKeyboardInputViewAudioFeedback(frame: inputViewRect)

        let inputAssistantItem = textField.inputAssistantItem
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        view.addSubview(textField)
        
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
        numberKeyboard.textInput = textField
        contentView.addSubview(numberKeyboard)
        
        NSLayoutConstraint.activate([
            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            amountView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 22),
            amountView.heightAnchor.constraint(equalToConstant: 60),
            
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
}

extension BaseAmountViewController: AmountViewDataSource {
    var dashAttributedString: NSAttributedString {
        NSAttributedString.dw_dashAttributedString(forAmount: UInt64(254223), tintColor: .dw_darkTitle(), symbolSize: CGSize(width: 14.0, height: 11.0) )
        
    }
    
    var localCurrencyAttributedString: NSAttributedString {
        return NSAttributedString(string: DSPriceManager.sharedInstance().localCurrencyString(forDashAmount: Int64(UInt64(254223)))!)
    }
    
    
}

extension BaseAmountViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return false
    }
}
