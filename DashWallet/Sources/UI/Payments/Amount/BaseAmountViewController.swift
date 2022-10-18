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
    private var contentView: UIView!
    private var numberKeyboard: NumberKeyboard!
    
    private var amountInputControl: AmountInputControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
    }
}

extension BaseAmountViewController {
    private func configureHierarchy() {
        self.contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        setupContentView(contentView)
        
        self.amountInputControl = AmountInputControl(frame: .zero)
        amountInputControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(amountInputControl)
        
        let keyboardContainer = UIView()
        keyboardContainer.backgroundColor = .dw_background()
        keyboardContainer.translatesAutoresizingMaskIntoConstraints = false
        keyboardContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        keyboardContainer.layer.cornerRadius = 10
        contentView.addSubview(keyboardContainer)
        
        self.numberKeyboard = NumberKeyboard()
        numberKeyboard.translatesAutoresizingMaskIntoConstraints = false
        numberKeyboard.backgroundColor = .clear
        contentView.addSubview(numberKeyboard)
        
        NSLayoutConstraint.activate([
            amountInputControl.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            amountInputControl.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            amountInputControl.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 20),
            
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
