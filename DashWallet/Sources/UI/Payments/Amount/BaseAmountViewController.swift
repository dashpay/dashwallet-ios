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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
    }
}

extension BaseAmountViewController {
    private func configureHierarchy() {
        self.contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        setupContentView(contentView)
        
        self.numberKeyboard = NumberKeyboard()
        numberKeyboard.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(numberKeyboard)
        
        NSLayoutConstraint.activate([
            numberKeyboard.heightAnchor.constraint(equalToConstant: kKeyboardHeight),
            numberKeyboard.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            numberKeyboard.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            numberKeyboard.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: kDescKeyboardPadding)
        ])
    }
}
