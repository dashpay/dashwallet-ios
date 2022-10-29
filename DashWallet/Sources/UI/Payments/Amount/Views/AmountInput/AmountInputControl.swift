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

private let kBigAmountTextAlpha = 1.0
private let kSmallAmountTextAlpha = 0.47

private let kMainAmountLabelHeight: CGFloat = 40
private let kSupplementaryAmountLabelHeight: CGFloat = 20

private let kMainAmountFontSize: CGFloat = 34
private let kSupplementaryAmountFontSize: CGFloat = 17

protocol AmountInputControlDelegate: AnyObject {
    func updateInputField(with replacementText: String, in range: NSRange)
    func amountInputControlChangeCurrencyDidTap(_ control: AmountInputControl)
}

protocol AmountInputControlDataSource: AnyObject {
    var currentInputString: String { get }
    var mainAmountString: String { get }
    var supplementaryAmountString: String { get }
}

extension AmountInputControl.AmountType {
    func toggle() -> Self {
        self == .main ? .supplementary : .main
    }
}

class AmountInputControl: UIControl {
    enum Style {
        case basic
        case oppositeAmount
    }
    
    enum AmountType {
        case main
        case supplementary
    }
    
    public var style: Style = .oppositeAmount {
        didSet {
            updateAppearance()
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }
    
    public var amountType: AmountType = .main
    
    public weak var delegate: AmountInputControlDelegate?
    public weak var dataSource: AmountInputControlDataSource? {
        didSet {
            reloadData()
        }
    }
    
    
    
    public var text: String? { return mainText }
    public var mainText: String?
    public var supplementaryText: String?
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: mainAmountLabel.bounds.width, height: contentHeight)
    }
    
    private var contentView: UIControl!
    private var mainAmountLabel: UILabel!
    private var supplementaryAmountLabel: UILabel!
    
    private var currencySelectorButton: UIButton!

    public var textField: UITextField!
    
    init(style: Style) {
        super.init(frame: .zero)
        
        self.style = style
        configureHierarchy()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func reloadData() {
        textField.text = dataSource?.currentInputString
        mainAmountLabel.attributedText = dataSource?.mainAmountString.attributedAmountStringWithDashSymbol(tintColor: .dw_darkTitle())
        supplementaryAmountLabel.text = dataSource?.supplementaryAmountString
    }
    
    func setActiveType(_ type: AmountType, animated: Bool, completion: (() -> Void)?) {
        guard style == .oppositeAmount else {
            completion?()
            return
        }
        
        let wasSwapped = type != .supplementary
        let bigLabel: UILabel = wasSwapped ? supplementaryAmountLabel : mainAmountLabel
        let smallLabel: UILabel = wasSwapped ? mainAmountLabel : supplementaryAmountLabel
        
        let scale = kSupplementaryAmountFontSize/kMainAmountFontSize
        
        
        bigLabel.font = .dw_regularFont(ofSize: kSupplementaryAmountFontSize)
        bigLabel.transform = CGAffineTransform(scaleX: 1.0/scale, y: 1.0/scale)
        
        smallLabel.frame = CGRect(x: 0, y: smallLabel.frame.minY, width: bounds.width, height: kMainAmountLabelHeight)
        smallLabel.font = .dw_regularFont(ofSize: kMainAmountFontSize)
        smallLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
     
        let updateAlphaAndTransform = {
            bigLabel.transform = .identity
            smallLabel.transform = .identity
            bigLabel.alpha = kSmallAmountTextAlpha
            smallLabel.alpha = kBigAmountTextAlpha
        }
        
        // Change possition
        let bigFramePosition = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
        let smallFramePosition = CGRect(x: 0, y: kMainAmountLabelHeight, width: bounds.width, height: kSupplementaryAmountLabelHeight)
        
        let changePossiton = {
            bigLabel.frame = smallFramePosition
            smallLabel.frame = bigFramePosition
        }
        
        if animated {
            UIView.animate(withDuration: 0.1, delay: 0.0, options: .curveEaseOut, animations: {
                updateAlphaAndTransform()
            }) { _ in
                UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1.0, animations: {
                    changePossiton()
                }) { _ in
                    completion?()
                }
            }
           
        }else{
            updateAlphaAndTransform()
            changePossiton()
            completion?()
        }
    }
    
    override func becomeFirstResponder() -> Bool {
        let val = textField.becomeFirstResponder()
        let endOfDocumentPosition = textField.endOfDocument
        self.textField.selectedTextRange = textField.textRange(from: endOfDocumentPosition, to: endOfDocumentPosition)
        return val
    }
    
    //MARK: Actions
    
    @objc func textFieldValueDidChange() {
        mainAmountLabel.text = textField.text
        supplementaryAmountLabel.text = textField.text
    }
    
    @objc func switchAmountCurrencyAction() {
        guard style == .oppositeAmount else { return }
        
        let nextType = amountType.toggle()
        setActiveType(nextType, animated: true, completion: nil)
        amountType = nextType
    }
}

//MARK: Layout
extension AmountInputControl {
    private func updateAppearance() {
        if style == .basic {
            mainAmountLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
            mainAmountLabel.font = .dw_regularFont(ofSize: kMainAmountFontSize)
            mainAmountLabel.alpha = 1
            supplementaryAmountLabel.isHidden = true
        }else{
            supplementaryAmountLabel.isHidden = false
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if style == .basic {
            mainAmountLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
        }else{
            let isSwapped = amountType == .supplementary
            let bigLabel: UILabel = isSwapped ? supplementaryAmountLabel : mainAmountLabel
            let smallLabel: UILabel = isSwapped ? mainAmountLabel : supplementaryAmountLabel
            
            let bigFrame = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
            let smallFrame = CGRect(x: 0, y: kMainAmountLabelHeight, width: bounds.width, height: kSupplementaryAmountLabelHeight)
            
            bigLabel.frame = bigFrame
            smallLabel.frame = smallFrame
        }
    }
}

//MARK: Private
extension AmountInputControl {
    private func configureHierarchy() {
        clipsToBounds = false
        
        let textFieldRect = CGRect(x: 0.0, y: -500.0, width: 320, height: 44)
        self.textField = UITextField(frame: textFieldRect)
        //textField.addTarget(self, action: #selector(textFieldValueDidChange), for: .editingChanged)
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
        addSubview(textField)
        
        self.contentView = UIControl()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        addSubview(contentView)
        
        self.mainAmountLabel = label(with: .dw_regularFont(ofSize: kMainAmountFontSize))
        contentView.addSubview(mainAmountLabel)
        
        self.supplementaryAmountLabel = label(with: .dw_regularFont(ofSize: kMainAmountFontSize))
        contentView.addSubview(supplementaryAmountLabel)

        mainAmountLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: kMainAmountLabelHeight)
        supplementaryAmountLabel.frame = CGRect(x: 0, y: mainAmountLabel.bounds.maxY, width: bounds.width, height: kSupplementaryAmountLabelHeight)
        
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        
        updateAppearance()
    }
}

//MARK: Utils
extension AmountInputControl {
    var contentHeight: CGFloat {
        style == .basic ? 40 : 60
    }
    
    func label(with font: UIFont) -> UILabel {
        let label = UILabel()
        label.minimumScaleFactor = 0.5
        label.adjustsFontSizeToFitWidth = true
        label.isUserInteractionEnabled = true
        label.textAlignment = .center
        label.contentMode = .redraw
        label.font = font
        label.clipsToBounds = false
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(switchAmountCurrencyAction))
        label.addGestureRecognizer(tapGesture)
        
        return label
    }
}

extension AmountInputControl: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        delegate?.updateInputField(with: string, in: range)
        
        return false
    }
    
    
}

//MARK: Text Formatting

extension AmountInputControl {
    func reloadAttributedData() {
        
    }
}
