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
    var localCurrency: String { get }
    
}

protocol AmountViewDelegate: AmountInputControlDelegate {
    var amountInputStyle: AmountInputControl.Style { get }
}

class AmountView: UIView {
    public weak var dataSource: AmountViewDataSource? {
        didSet {
            amountInputControl.dataSource = dataSource
            updateView()
        }
    }
    
    public weak var delegate: AmountViewDelegate? {
        didSet {
            amountInputControl.delegate = delegate
            updateView()
        }
    }
    
    public var textInput: UITextInput {
        return amountInputControl.textField
    }
    
    public var amountInputStyle: AmountInputControl.Style
    
    public var isMaxButtonHidden: Bool = false {
        didSet {
            maxButton.isHidden = isMaxButtonHidden
        }
    }
    
    public var amountType: AmountInputControl.AmountType {
        set {
            amountInputControl.amountType = newValue
        }
        get {
            amountInputControl.amountType
        }
    }
    
    public var maxButtonAction: (() -> Void)?
    
    private var maxButton: UIButton!
    private var amountInputControl: AmountInputControl!
    private var inputTypeSwitcher: AmountInputTypeSwitcher!
    
    override var intrinsicContentSize: CGSize {
        .init(width: AmountView.noIntrinsicMetric, height: 60)
    }
    
    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return amountInputControl.becomeFirstResponder()
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
    
    public func reloadData() {
        amountInputControl.reloadData()
    }
    
    public func reloadInputTypeSwitcher() {
        updateView()
    }
    
    @objc func maxButtonActionHandler() {
        maxButtonAction?()
    }
}

extension AmountView {
    private func updateView() {
        inputTypeSwitcher.items = [.init(currencySymbol: "DASH", currencyCode: "DASH"), .init(currencySymbol: dataSource?.localCurrency ?? "", currencyCode: "FIAT")]
    }
    
    private func configureHierarchy() {
        self.maxButton = MaxButton(frame: CGRect(x: 0, y: 0, width: 38, height: 38))
        maxButton.translatesAutoresizingMaskIntoConstraints = false
        maxButton.addTarget(self, action: #selector(maxButtonActionHandler), for: .touchUpInside)
        addSubview(maxButton)
        
        self.amountInputControl = AmountInputControl(style: amountInputStyle)
        amountInputControl.swapingHandler = { [weak self] type in
            self?.inputTypeSwitcher.selectedNextItem()
        }
        amountInputControl.dataSource = dataSource
        amountInputControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(amountInputControl)
    
        self.inputTypeSwitcher = .init(frame: .zero)
        inputTypeSwitcher.translatesAutoresizingMaskIntoConstraints = false
        inputTypeSwitcher.selectItemHandler = { [weak self] item in
            let type: AmountInputControl.AmountType = item.isMain ? .main : .supplementary
            self?.amountInputControl.setActiveType(type, animated: true, completion: nil)
        }
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
