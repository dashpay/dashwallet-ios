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

protocol AmountViewDataSource: AmountInputControlDataSource {
    
}

protocol AmountViewDelegte: AmountInputControlDelegate {
    
}

class AmountView: UIView {
    public weak var dataSource: AmountViewDataSource? {
        didSet {
            amountInputControl.dataSource = dataSource
        }
    }
    
    public weak var delegate: AmountViewDelegte? {
        didSet {
            amountInputControl.delegate = delegate
        }
    }
    
    public var textInput: UITextInput {
        return amountInputControl.textField
    }
    
    private var maxButton: UIButton!
    private var amountInputControl: AmountInputControl!
    private var inputTypeSwitcher: AmountInputTypeSwitcher!
    
    override var intrinsicContentSize: CGSize {
        .init(width: AmountView.noIntrinsicMetric, height: 60)
    }
    
    override func becomeFirstResponder() -> Bool {
        return amountInputControl.becomeFirstResponder()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    public func reloadData() {
        amountInputControl.reloadData()
    }
    
    @objc func maxButtonAction() {
        amountInputControl.style = amountInputControl.style == .oppositeAmount ? .basic : .oppositeAmount
    }
}

extension AmountView {
    private func configureHierarchy() {
        self.maxButton = MaxButton(frame: CGRect(x: 0, y: 0, width: 38, height: 38))
        maxButton.translatesAutoresizingMaskIntoConstraints = false
        maxButton.addTarget(self, action: #selector(maxButtonAction), for: .touchUpInside)
        addSubview(maxButton)
        
        self.amountInputControl = AmountInputControl(style: .basic)
        amountInputControl.dataSource = dataSource
        amountInputControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(amountInputControl)
    
        self.inputTypeSwitcher = .init(frame: .zero)
        inputTypeSwitcher.translatesAutoresizingMaskIntoConstraints = false
        inputTypeSwitcher.items = [.init(currencySymbol: "US$", currencyCode: "USD"), .init(currencySymbol: "DASH", currencyCode: "DASH")]
        addSubview(inputTypeSwitcher)
        
        NSLayoutConstraint.activate([
            maxButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            maxButton.widthAnchor.constraint(equalToConstant: 38),
            maxButton.heightAnchor.constraint(equalToConstant: 38),
            maxButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            
            amountInputControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            amountInputControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            amountInputControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 60),
            amountInputControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -60),
            
            inputTypeSwitcher.centerYAnchor.constraint(equalTo: centerYAnchor),
            inputTypeSwitcher.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

//MARK: MaxButton
private class MaxButton: UIButton {
    
    override var isHighlighted: Bool {
        didSet {
            
        }
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
