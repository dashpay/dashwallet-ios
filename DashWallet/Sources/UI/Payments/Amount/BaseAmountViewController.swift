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
    
    internal var model: BaseAmountModel!
    
    func maxButtonAction() {
        
    }
    
    internal func configureModel() {
        model = BaseAmountModel()
        model.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        amountView.becomeFirstResponder()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureModel()
        configureHierarchy()
    }
}

extension BaseAmountViewController {
    
}

extension BaseAmountViewController {
    
        
    @objc internal func configureHierarchy() {
        self.contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        setupContentView(contentView)
        
        self.amountView = AmountView(frame: .zero)
        amountView.maxButtonAction = { [weak self] in
            self?.maxButtonAction()
        }
        amountView.dataSource = model
        amountView.delegate = model
        amountView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(amountView)
        
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
        numberKeyboard.textInput = amountView.textInput
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

extension BaseAmountViewController: BaseAmountModelDelegate {
    @objc func amountDidChange() {
        amountView.reloadData()
    }
}
//extension BaseAmountViewController: AmountViewDataSource {
//    var dashAttributedString: NSAttributedString {
//        NSAttributedString.dw_dashAttributedString(forAmount: UInt64(254223), tintColor: .dw_darkTitle(), symbolSize: CGSize(width: 14.0, height: 11.0) )
//
//    }
//
//    var localCurrencyAttributedString: NSAttributedString {
//        return NSAttributedString(string: DSPriceManager.sharedInstance().localCurrencyString(forDashAmount: Int64(UInt64(254223)))!)
//    }
//
//
//}

