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

import Foundation

@objc protocol NumberKeyboardDelegate: AnyObject {
    func numberKeyboardCustomButtonDidTap(_ numberKeyboard: NumberKeyboard)
}

extension NumberKeyboard {
    enum NumberKeyboardDelegateProperties {
        case textInputSupportsShouldChangeTextInRange
        case delegateSupportsTextFieldShouldChangeCharactersInRange
        case delegateSupportsTextViewShouldChangeTextInRange
    }
    
    struct NumberKeyboardDelegateOptions: OptionSet {
        let rawValue: Int
        
        static let textInputSupportsShouldChangeTextInRange   = NumberKeyboardDelegateOptions(rawValue: 1 << 0)
        static let delegateSupportsTextFieldShouldChangeCharactersInRange = NumberKeyboardDelegateOptions(rawValue: 1 << 1)
        static let delegateSupportsTextViewShouldChangeTextInRange  = NumberKeyboardDelegateOptions(rawValue: 1 << 2)
    }
}

@objc class NumberKeyboard: UIView {
    @objc weak var delegate: NumberKeyboardDelegate?
    @objc weak var textInput: UITextInput? {
        didSet {
            configureDelegateProperties()
        }
    }
    
    @objc var isEnabled: Bool = true
    
    var customButtonBackgroundColor: UIColor? {
        didSet {
            updateButtonAppearances()
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: NumberKeyboard.noIntrinsicMetric, height: Style.buttonHeight * CGFloat(Style.rowsCount) + Style.padding * CGFloat(Style.rowsCount - 1))
    }
    
    private var delegateOptions: NumberKeyboardDelegateOptions = []
    
    private var isClearButtonLongPressGestureActive: Bool = true
    
    private var allButtons: [NumberKeyboardButton]!
    private var digitButtons: [NumberKeyboardButton]!
    private var functionButton: NumberKeyboardButton!
    private var clearButton: NumberKeyboardButton!
    private var zeroButton: NumberKeyboardButton { return digitButtons.first! }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
            
        configureHierarchy()
    }
    
    @objc public func configureWithCustomFunctionButtonTitle(_ title: String) {
        functionButton.value = .custom(title)
    }
    
    @objc public func configureFunctionButtonAsHidden() {
        functionButton.isHidden = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let boundsWidth = self.bounds.width
        let horizontalPadding = Style.padding * CGFloat(Style.sectionsCount - 1)
        let buttonWidth = min(boundsWidth/CGFloat(Style.sectionsCount) - horizontalPadding, Style.buttonMaxWidth)
        let leftInitial = (boundsWidth - buttonWidth*CGFloat(Style.sectionsCount) - horizontalPadding)/2
        
        var left: CGFloat = leftInitial
        var top: CGFloat = 0
        
        // Layout digits
        for i in NumberKeyboardValue.Digit.digit1.rawValue...NumberKeyboardValue.Digit.digit9.rawValue {
            let item = digitButtons[i]
            
            item.frame = CGRect(x: left, y: top, width: buttonWidth, height: Style.buttonHeight)
            
            if i%Style.sectionsCount == 0 {
                left = leftInitial
                top += Style.buttonHeight + Style.padding
            }else{
                left += buttonWidth + Style.padding
            }
        }
        
        // Separator
        left = leftInitial
        self.functionButton?.frame = CGRect(x: left, y: top, width: buttonWidth, height: Style.buttonHeight)
        
        // Digit 0
        left += buttonWidth + Style.padding
        self.zeroButton.frame = CGRect(x: left, y: top, width: buttonWidth, height: Style.buttonHeight)
        
        // Delete button
        left += buttonWidth + Style.padding
        self.clearButton?.frame = CGRect(x: left, y: top, width: buttonWidth, height: Style.buttonHeight)
    }
}

extension NumberKeyboard {
    @objc func clearButtonLongPressGestureRecognizerAction(gestureRecognizer: UIGestureRecognizer) {
        if gestureRecognizer.state == .began {
            isClearButtonLongPressGestureActive = true
            performClearButtonLongPress(isFirstCall: true)
        }else if gestureRecognizer.state == .ended {
            isClearButtonLongPressGestureActive = false
        }
    }
    
    @objc func performClearButtonLongPress(isFirstCall: Bool) {
        guard let textInput = self.textInput else { return }
        
        if isClearButtonLongPressGestureActive {
            if textInput.hasText {
                if isFirstCall {
                    UIDevice.current.playInputClick()
                }
                
                self.performClearButtonAction(clearButton, in: textInput)
                
                self.perform(#selector(performClearButtonLongPress(isFirstCall:)), with: false, afterDelay: 0.1)
            }else{
                isClearButtonLongPressGestureActive = false
            }
        }
    }
}

//MARK: Layout
extension NumberKeyboard {
    struct Style {
        static let padding: CGFloat = 5
        static let buttonHeight: CGFloat = 50
        static let buttonMaxWidth: CGFloat = 115
        static let rowsCount: UInt = 4
        static let sectionsCount: Int = 3
    }
    
    private func configureHierarchy() {
        isExclusiveTouch = true
        isEnabled = true
        
        var buttons = Array<NumberKeyboardButton>()
        buttons.reserveCapacity(12) //We have only 12 buttons to show
        
        //Add digits
        for item in NumberKeyboardValue.Digit.allCases {
            let button = NumberKeyboardButton(value: .digit(item))
            button.customBackgroundColor = customButtonBackgroundColor
            button.delegate = self
            self.addSubview(button)
            buttons.append(button)
        }
        self.digitButtons = Array(buttons)
        
        //Add function button
        self.functionButton = NumberKeyboardButton(value: .separator)
        functionButton.customBackgroundColor = customButtonBackgroundColor
        functionButton.delegate = self
        addSubview(functionButton)
        buttons.append(functionButton)
        
        //Add clear button
        self.clearButton = NumberKeyboardButton(value: .delete)
        clearButton.customBackgroundColor = customButtonBackgroundColor
        clearButton.delegate = self
        addSubview(clearButton)
        buttons.append(clearButton)
        
        self.allButtons = buttons
        
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.clearButtonLongPressGestureRecognizerAction(gestureRecognizer:)))
        longPressGestureRecognizer.cancelsTouchesInView = false
        clearButton.addGestureRecognizer(longPressGestureRecognizer)
    }
}

//MARK: Private
extension NumberKeyboard {
    private func performButtonAction(_ button: NumberKeyboardButton) {
        guard let textInput = self.textInput else { return }
        
        if button.value == NumberKeyboardValue.delete {
            performClearButtonAction(button, in: textInput)
        }else{
            performRegularButtonAction(button, in: textInput)
        }
    }
    
    private func performClearButtonAction(_ button: NumberKeyboardButton, in textInput: UITextInput) {
        if delegateOptions.contains(.textInputSupportsShouldChangeTextInRange) {
            guard var selectedTextRange = textInput.selectedTextRange else { return }
            
            if selectedTextRange.start == selectedTextRange.end,
               let newStart = textInput.position(from: selectedTextRange.start, in: .left, offset: 1) {
                selectedTextRange = textInput.textRange(from: newStart, to: selectedTextRange.end)!
            }
            
            if textInput.shouldChangeText?(in: selectedTextRange, replacementText: "") ?? false {
                textInput.deleteBackward()
            }
        }else if delegateOptions.contains(.delegateSupportsTextFieldShouldChangeCharactersInRange) {
            guard var selectedRange = self.selectedRange(in: textInput) else { return }
            
            if selectedRange.length == 0 && selectedRange.location > 0 {
                selectedRange.location -= 1
                selectedRange.length = 1
            }
            
            if let tf = textInput as? UITextField,
               let tfDelegate = tf.delegate,
               tfDelegate.textField?(tf, shouldChangeCharactersIn: selectedRange, replacementString: "") ?? false {
                textInput.deleteBackward()
            }
        }else if delegateOptions.contains(.delegateSupportsTextViewShouldChangeTextInRange) {
            guard var selectedRange = self.selectedRange(in: textInput) else { return }
            
            if selectedRange.length == 0 && selectedRange.location > 0 {
                selectedRange.location -= 1
                selectedRange.length = 1
            }
            
            if  let tv = textInput as? UITextView,
                let tvDelegate = tv.delegate,
                tvDelegate.textView?(tv, shouldChangeTextIn: selectedRange, replacementText: "") ?? false {
                textInput.deleteBackward()
            }
        }else{
            textInput.deleteBackward()
        }
    }
    
    private func performRegularButtonAction(_ button: NumberKeyboardButton, in textInput: UITextInput) {
        if case .custom(_) = button.value {
            delegate?.numberKeyboardCustomButtonDidTap(self)
            return
        }
        
        let text: String = button.value.stringValue
        
        if delegateOptions.contains(.textInputSupportsShouldChangeTextInRange) {
            if let selectedTextRange = textInput.selectedTextRange,
                textInput.shouldChangeText?(in: selectedTextRange, replacementText: text) ?? false {
                textInput.insertText(text)
            }
        }else if delegateOptions.contains(.delegateSupportsTextFieldShouldChangeCharactersInRange) {
            if let selectedRange = self.selectedRange(in: textInput),
               let tf = textInput as? UITextField,
               let tfDelegate = tf.delegate,
               tfDelegate.textField?(tf, shouldChangeCharactersIn: selectedRange, replacementString: text) ?? false {
                textInput.insertText(text)
            }
        }else if delegateOptions.contains(.delegateSupportsTextViewShouldChangeTextInRange) {
            if let selectedRange = self.selectedRange(in: textInput),
               let tv = textInput as? UITextView,
               let tvDelegate = tv.delegate,
               tvDelegate.textView?(tv, shouldChangeTextIn: selectedRange, replacementText: text) ?? false {
                textInput.insertText(text)
            }
        }else{
            textInput.insertText(text)
        }
    }
    
    private func configureDelegateProperties() {
        guard let textInput = self.textInput else { return }
        
        delegateOptions = []
        
        if textInput.responds(to: #selector(UITextInput.shouldChangeText(in:replacementText:))) {
            delegateOptions.insert(.textInputSupportsShouldChangeTextInRange)
        }else if let tf = textInput as? UITextField, let _ = tf.delegate {
            delegateOptions.insert(.delegateSupportsTextFieldShouldChangeCharactersInRange)
        }else if let tv = textInput as? UITextView, let _ = tv.delegate {
            delegateOptions.insert(.delegateSupportsTextViewShouldChangeTextInRange)
        }
    }
    
    private func resetHighlightedButton() {
        for item in allButtons {
            item.isHighlighted = false
        }
        
        isClearButtonLongPressGestureActive = false
    }

    private func updateButtonAppearances() {
        for item in allButtons {
            item.customBackgroundColor = customButtonBackgroundColor
        }
    }
}
//MARK: NumberKeyboardButtonDelegate
extension NumberKeyboard: NumberKeyboardButtonDelegate {
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchBegan touch: UITouch) {
        guard isEnabled else { return }
        
        UIDevice.current.playInputClick()
        
        button.isHighlighted = true
        
    }
    
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchMoved touch: UITouch) {
        guard isEnabled else { return }
        
        func isHighlighted(view: UIView, touch: UITouch) -> Bool {
            let bounds = view.bounds
            let point = touch.location(in: view)
            return CGRectContainsPoint(bounds, point)
        }
        
        //Try current button first
        let isCurrentHighlighted = isHighlighted(view: button, touch: touch)

        if isCurrentHighlighted {
            button.isHighlighted = isCurrentHighlighted
        }else{
            for item in allButtons {
                item.isHighlighted = isHighlighted(view: item, touch: touch)
            }
        }
 
        if isClearButtonLongPressGestureActive {
            let bounds = self.clearButton.bounds
            let point = touch.location(in: self.clearButton)
            if !CGRectContainsPoint(bounds, point) {
                isClearButtonLongPressGestureActive = false
            }
        }
        
        
    }
    
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchEnded touch: UITouch) {
        guard isEnabled else { return }

        for item in allButtons {
            let bound = item.bounds
            let point = touch.location(in: item)
            if CGRectContainsPoint(bound, point) {
                if item != self.clearButton || !isClearButtonLongPressGestureActive {
                    self.performButtonAction(item)
                }
            }
        }
        
        resetHighlightedButton()
            
    }
    
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchCanceled touch: UITouch) {
        guard isEnabled else { return }

        resetHighlightedButton()
    }
}

//MARK: Utils
extension NumberKeyboard {
    func selectedRange(in textInput: UITextInput) -> NSRange? {
        guard let textRange = textInput.selectedTextRange else {
            return nil
        }
        
        let startOffset = textInput.offset(from: textInput.beginningOfDocument, to: textRange.start)
        let endOffset = textInput.offset(from: textInput.beginningOfDocument, to: textRange.end)
        return NSRange(location: startOffset, length: endOffset - startOffset)
        
    }
}
