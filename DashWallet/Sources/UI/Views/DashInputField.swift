//  
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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
import QuartzCore

class DashInputField: UIView
{
    enum PlaceholderState
    {
        case top
        case `default`
    }
    
    public var textDidChange: ((String) -> ())?
    
    private var backgroundView: UIView!
    
    internal var textField: DashTextField!
    
    private var placeholderLabel: UILabel!
    private var placeholderState: PlaceholderState = .default
    
    private var errorView: InputFieldErrorView!
    
    public var errorMessage: String?
    {
        didSet
        {
            if oldValue == errorMessage { return }
            
            errorView.isHidden = errorMessage == nil
            errorView.text = errorMessage
            
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }
    
    var text: String
    {
        set {
            textField.text = newValue
            updateLayout(animated: false)
        }
        get {
            textField.text ?? ""
        }
    }
    
    var isEnabled: Bool
    {
        set {
            textField.isEnabled = newValue
            updateBackgroundView()
        }
        get {
            textField.isEnabled
        }
    }
    @IBInspectable var placeholder: String?
    {
        set {
            placeholderLabel.text = newValue
        }
        get {
            placeholderLabel.text
        }
    }
    
    var textInsets: UIEdgeInsets = .init(top: 10, left: 13, bottom: 0, right: 13)
    {
        didSet
        {
            textField.textInsets = textInsets
        }
    }
    
    private weak var outsideDelegate: UITextFieldDelegate?
    
    var delegate: UITextFieldDelegate?
    {
        set {
            outsideDelegate = newValue
        }
        get {
            outsideDelegate
        }
    }
    
    var isEditing: Bool
    {
        textField.isEditing
    }
    
    var originalPlaceholderFrame: CGRect = .zero
    var originalPlaceholderPosition: CGPoint = .zero
    var originalPlaceholderTransform: CGAffineTransform = .identity
    
    override var intrinsicContentSize: CGSize
    {
        .init(width: -1, height: 58 + (errorMessage == nil ? 0 : 18))
    }
    
    @discardableResult
    override func becomeFirstResponder() -> Bool
    {
        textField.becomeFirstResponder()
    }
    
    @discardableResult
    override func resignFirstResponder() -> Bool
    {
        textField.resignFirstResponder()
    }
    
    override var canBecomeFirstResponder: Bool
    {
        textField.canBecomeFirstResponder
    }
    
    override var canResignFirstResponder: Bool
    {
        textField.canResignFirstResponder
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        configureLayout()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        configureLayout()
    }
    
    internal func configureLayout()
    {
        clipsToBounds = true
        
        textField = DashTextField()
        textField.clipsToBounds = true
        textField.layer.cornerRadius = 10
        
        backgroundView = UIView()
        backgroundView.layer.cornerRadius = 10
        backgroundView.borderWidth = isEditing ? 2 : 1
        backgroundView.borderColor = isEditing ? .label : .systemGray
        addSubview(backgroundView)
        
        textField.textInsets = textInsets
        textField.delegate = self
        textField.addAction(.editingChanged) { [weak self] (sender) in
            self?.textDidChange?(sender.text ?? "")
        }
        addSubview(textField)
        
        var frame = CGRect(x: textInsets.left, y: 0, width: bounds.width, height: textField.font!.lineHeight)
        frame.origin.y = ceil((bounds.height - frame.height)/2)
        
        placeholderLabel = UILabel()
        placeholderLabel.textColor = .systemGray
        placeholderLabel.anchorPoint = CGPoint(x: 0, y: 0)
        placeholderLabel.font = textField.font
        placeholderLabel.frame = frame
        addSubview(placeholderLabel)
        
        errorView = InputFieldErrorView()
        addSubview(errorView)
        
        updateLayout(animated: false)
    }
    
    func updateLayout(animated: Bool = true)
    {
        updateBackgroundView()
        
        let oldState = placeholderState
        placeholderState = (isEditing || !text.isEmpty) ? .top : .default
        
        if placeholderState == oldState { return }
        
        let isTop = placeholderState == .top
        
        var transform = placeholderLabel.transform
        
        if isTop
        {
            let currentPointSize: CGFloat = !isTop ? 12 : 17
            let newPointSize: CGFloat = isTop ? 12 : 17
            let scaleFactor = newPointSize/currentPointSize
            
            transform = transform.scaledBy(x: scaleFactor, y: scaleFactor)
                                     .translatedBy(x: 0, y: -15)
        }else{
            transform = .identity
        }
        
        UIView.animate(withDuration: 0.3) { [unowned self] in
            placeholderLabel.transform = transform
        }
    }
    
    private func updateBackgroundView()
    {
        if isEnabled
        {
            backgroundView.borderWidth = isEditing ? 2 : 1
            backgroundView.borderColor = isEditing ? .label : .systemGray
        }else{
            backgroundView.borderWidth = 1
            backgroundView.borderColor = .systemGray3
        }
    }
    
    override func layoutSubviews()
    {
        var frame = bounds
        if errorMessage != nil
        {
            frame.size.height = 58
        }
        textField.frame = frame.insetBy(dx: 2, dy: 2)
        backgroundView.frame = .init(x: 0, y: 0, width: bounds.width, height: frame.height)
        
        errorView.frame = CGRect(x: 0, y: 63, width: bounds.width, height: 13)
        
        super.layoutSubviews()
    }
}

extension DashInputField: UITextInputTraits
{
    @IBInspectable var autocapitalizationType: UITextAutocapitalizationType
    {
        set {
            textField.autocapitalizationType = newValue
        }
        get {
            textField.autocapitalizationType
        }
    }
    
    @IBInspectable var autocorrectionType: UITextAutocorrectionType
    {
        set {
            textField.autocorrectionType = newValue
        }
        get {
            textField.autocorrectionType
        }
    }
    
    
    @IBInspectable var spellCheckingType: UITextSpellCheckingType
    {
        set {
            textField.spellCheckingType = newValue
        }
        get {
            textField.spellCheckingType
        }
    }
    
    var smartQuotesType: UITextSmartQuotesType
    {
        set {
            textField.smartQuotesType = newValue
        }
        get {
            textField.smartQuotesType
        }
    }
    
    
    var smartDashesType: UITextSmartDashesType
    {
        set {
            textField.smartDashesType = newValue
        }
        get {
            textField.smartDashesType
        }
    }
    
    
    var smartInsertDeleteType: UITextSmartInsertDeleteType
    {
        set {
            textField.smartInsertDeleteType = newValue
        }
        get {
            textField.smartInsertDeleteType
        }
    }
    
    @IBInspectable var keyboardType: UIKeyboardType
    {
        set {
            textField.keyboardType = newValue
        }
        get {
            textField.keyboardType
        }
    }
    
    @IBInspectable var keyboardAppearance: UIKeyboardAppearance
    {
        set {
            textField.keyboardAppearance = newValue
        }
        get {
            textField.keyboardAppearance
        }
    }
    
    @IBInspectable var returnKeyType: UIReturnKeyType
    {
        set {
            textField.returnKeyType = newValue
        }
        get {
            textField.returnKeyType
        }
    }
    
    var enablesReturnKeyAutomatically: Bool
    {
        set {
            textField.enablesReturnKeyAutomatically = newValue
        }
        get {
            textField.enablesReturnKeyAutomatically
        }
    }
    
    @IBInspectable var isSecureTextEntry: Bool
    {
        set {
            textField.isSecureTextEntry = newValue
        }
        get {
            textField.isSecureTextEntry
        }
    }
    
    @IBInspectable var textContentType: UITextContentType
    {
        set {
            textField.textContentType = newValue
        }
        get {
            textField.textContentType
        }
    }
}

class DashTextField: UITextField
{
    var textInsets: UIEdgeInsets = .init(top: 0, left: 10, bottom: 0, right: 10) {
        didSet {
            setNeedsLayout()
        }
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        configureLayout()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        configureLayout()
    }
    
    override func textRect(forBounds bounds: CGRect) -> CGRect
    {
        return CGRect(
            x: bounds.origin.x + textInsets.left,
            y: bounds.origin.y + textInsets.top,
            width: bounds.size.width - (textInsets.left + textInsets.right),
            height: bounds.size.height - (textInsets.top + textInsets.bottom)
        )
    }
    
    override func editingRect(forBounds bounds: CGRect) -> CGRect
    {
        return self.textRect(forBounds: bounds)
    }
    
    internal func configureLayout()
    {
        borderStyle = .none
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
    }
}

extension DashInputField: UITextFieldDelegate
{
    func textFieldDidEndEditing(_ textField: UITextField)
    {
        updateLayout()
        
        outsideDelegate?.textFieldDidEndEditing?(textField)
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField)
    {
        updateLayout()
        
        outsideDelegate?.textFieldDidBeginEditing?(textField)
    }
    
    func textFieldDidChangeSelection(_ textField: UITextField)
    {
        outsideDelegate?.textFieldDidChangeSelection?(textField)
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool
    {
        return outsideDelegate?.textFieldShouldBeginEditing?(textField) ?? true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool
    {
        return outsideDelegate?.textFieldShouldEndEditing?(textField) ?? true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
    {
        return outsideDelegate?.textField?(textField, shouldChangeCharactersIn: range, replacementString: string) ?? true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool
    {
        outsideDelegate?.textFieldShouldClear?(textField) ?? true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        outsideDelegate?.textFieldShouldReturn?(textField) ?? true
    }
}

class InputFieldErrorView: UIView
{
    private var iconView: UIImageView!
    private var errorLabel: UILabel!
    
    var text: String?
    {
        didSet {
            errorLabel.text = text
        }
    }
    
    override var intrinsicContentSize: CGSize
    {
        .init(width: -1, height: 20)
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        configureLayout()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        configureLayout()
    }
    
    private func configureLayout()
    {
        iconView = UIImageView(image: UIImage(systemName: "xmark.octagon", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium, scale: .default)))
        iconView.contentMode = .center
        iconView.tintColor = .dw_red()
        iconView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        errorLabel = UILabel()
        errorLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        errorLabel.textColor = .dw_red()
        
        let stackView = UIStackView(arrangedSubviews: [iconView, errorLabel])
        stackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stackView.axis = .horizontal
        stackView.spacing = 3
        addSubview(stackView)
    }
}
