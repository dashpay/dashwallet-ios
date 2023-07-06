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

import QuartzCore
import UIKit

// MARK: - DashInputField

extension DashInputField.PlaceholderState {
    var isTop: Bool {
        self == .top
    }
}

// MARK: - DashInputField

class DashInputField: UIView {
    enum PlaceholderState {
        case top
        case `default`
    }

    public var textDidChange: ((String) -> ())?

    private var borderView: UIView!
    private var backgroundView: UIView!

    internal var textView: DashTextField!

    private var placeholderLabel: UILabel!
    private var placeholderState: PlaceholderState = .default

    private var errorView: InputFieldErrorView!

    private var clearButton: UIButton!

    public var errorMessage: String? {
        didSet {
            if oldValue == errorMessage { return }

            errorView.isHidden = errorMessage == nil
            errorView.text = errorMessage

            updateBackgroundView()
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    public var hasError: Bool {
        errorMessage != nil
    }

    public var accessoryView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let view = accessoryView {
                addSubview(view)
                setNeedsLayout()
            }
        }
    }

    public var hasAccessoryView: Bool {
        accessoryView != nil
    }

    var text: String {
        set {
            textView.text = newValue
            updateLayout(animated: false)

            resetErrorMessage()
            updateBackgroundView()
            updateButtonsVisibility()

            invalidateIntrinsicContentSize()
        }
        get {
            textView.text
        }
    }

    var isEnabled: Bool {
        set {
            textView.isEditable = newValue
            updateBackgroundView()
        }
        get {
            textView.isEditable
        }
    }

    @IBInspectable var placeholder: String? {
        set {
            placeholderLabel.text = newValue
        }
        get {
            placeholderLabel.text
        }
    }

    var textInsets: UIEdgeInsets = .init(top: 10, left: 13, bottom: 0, right: 13) {
        didSet {
            textView.textInsets = textInsets
        }
    }

    private weak var outsideDelegate: UITextViewDelegate?

    var delegate: UITextViewDelegate? {
        set {
            outsideDelegate = newValue
        }
        get {
            outsideDelegate
        }
    }

    var isEditing: Bool {
        textView.isFirstResponder
    }

    var originalPlaceholderFrame: CGRect = .zero
    var originalPlaceholderPosition: CGPoint = .zero
    var originalPlaceholderTransform: CGAffineTransform = .identity

    override var intrinsicContentSize: CGSize {
        let textViewHeight = textView.contentSize.height + 25 + 10 // textView.contentSize.height + top padding + bottom padding
        let height = textViewHeight + (hasError ? 23 : 0)
        return CGSize(width: UIView.noIntrinsicMetric, height: min(120, max(58, height)))
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        textView.canBecomeFirstResponder
    }

    override var canResignFirstResponder: Bool {
        textView.canResignFirstResponder
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureLayout()
    }

    internal func configureLayout() {
        clipsToBounds = false

        textView = DashTextField()
        textView.backgroundColor = .clear
        textView.clipsToBounds = true
        textView.font = .dw_font(forTextStyle: .body)

        borderView = UIView()
        borderView.backgroundColor = .clear
        borderView.layer.cornerRadius = 12
        borderView.borderWidth = 4
        borderView.borderColor = .dw_dashBlue()
        borderView.layer.opacity = 0.2
        addSubview(borderView)

        backgroundView = UIView()
        backgroundView.backgroundColor = .clear
        backgroundView.layer.cornerRadius = 10
        backgroundView.borderWidth = 1
        addSubview(backgroundView)

        textView.isEditable = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.delegate = self
        addSubview(textView)

        var frame = CGRect(x: textInsets.left, y: 0, width: 200, height: textView.font!.lineHeight)
        frame.origin.y = ceil((intrinsicContentSize.height - frame.height)/2)

        placeholderLabel = UILabel()
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.anchorPoint = CGPoint(x: 0, y: 0)
        placeholderLabel.font = textView.font
        placeholderLabel.frame = frame
        addSubview(placeholderLabel)

        errorView = InputFieldErrorView()
        errorView.isHidden = true
        addSubview(errorView)

        clearButton = UIButton(type: .custom)
        clearButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        clearButton.tintColor = .systemGray
        clearButton.isHidden = true
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
        addSubview(clearButton)

        updateLayout(animated: false)
    }

    func updateLayout(animated: Bool = true) {
        let newPlaceholderState: PlaceholderState = (isEditing || !text.isEmpty) ? .top : .default

        guard placeholderState != newPlaceholderState else { return }
        placeholderState = newPlaceholderState

        let isTop = placeholderState.isTop
        var transform = placeholderLabel.transform

        var accessoryViewFrame = accessoryView?.frame ?? .zero

        if isTop {
            let currentPointSize: CGFloat = !isTop ? 12 : 17
            let newPointSize: CGFloat = isTop ? 12 : 17
            let scaleFactor = newPointSize/currentPointSize

            transform = transform.scaledBy(x: scaleFactor, y: scaleFactor)
                .translatedBy(x: 0, y: -15)

            accessoryViewFrame.origin.y = textView.frame.minY + (textView.frame.height - accessoryViewFrame.height)/2
        } else {
            transform = .identity
            accessoryViewFrame.origin.y = (bounds.height - accessoryViewFrame.height)/2
        }


        UIView.animate(withDuration: 0.3) { [unowned self] in
            placeholderLabel.transform = transform
            accessoryView?.frame = accessoryViewFrame
        }
    }

    private func updateBackgroundView() {
        if isEnabled {
            borderView.isHidden = !isEditing || hasError

            if hasError {
                backgroundView.borderColor = .systemRed
                backgroundView.backgroundColor = .systemRed.withAlphaComponent(0.1)
            } else {
                backgroundView.borderColor = isEditing ? .dw_dashBlue() : .darkGray.withAlphaComponent(0.5)
                backgroundView.backgroundColor = .clear
            }
        } else {
            borderView.isHidden = true
            backgroundView.borderColor = .darkGray.withAlphaComponent(0.1)
            backgroundView.backgroundColor = .clear
        }
    }

    private func updateButtonsVisibility() {
        clearButton.isHidden = text.isEmpty
        accessoryView?.isHidden = !text.isEmpty || !clearButton.isHidden
    }

    private func resetErrorMessage() {
        errorMessage = nil
    }

    @objc
    private func clearButtonTapped() {
        errorMessage = nil
        textView.text = ""
        textViewDidChange(textView)
    }

    override func layoutSubviews() {
        var bounds = bounds
        bounds.size.height -= (hasError ? 23 : 0)

        let rightPadding: CGFloat = hasAccessoryView ? accessoryView!.frame.width : 20

        var frame = bounds
        frame.origin.x = 0
        frame.origin.y = 25
        frame.size.width -= rightPadding
        frame.size.height -= 35
        textView.frame = frame

        if let accessoryView {
            var accessoryViewFrame = accessoryView.frame
            accessoryViewFrame.origin.x = bounds.width - accessoryView.bounds.width - 10
            if isEditing {
                accessoryViewFrame.origin.y = textView.frame.minY + (textView.frame.height - accessoryViewFrame.height)/2
            } else {
                accessoryViewFrame.origin.y = (self.bounds.height - accessoryViewFrame.height)/2
            }
            accessoryView.frame = accessoryViewFrame
        }

        backgroundView.frame = bounds
        borderView.frame = bounds.insetBy(dx: -3.5, dy: -3.5)
        errorView.frame = CGRect(x: 10,
                                 y: borderView.frame.maxY + 5,
                                 width: bounds.width - 10,
                                 height: 13)

        let buttonSize: CGFloat = 20
        clearButton.frame = CGRect(x: bounds.width - buttonSize - 10,
                                   y: textView.frame.minY + textView.bounds.height / 2 - buttonSize / 2,
                                   width: buttonSize,
                                   height: buttonSize)

        super.layoutSubviews()
    }
}

// MARK: UITextViewDelegate

extension DashInputField: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        outsideDelegate?.textViewDidBeginEditing?(textView)

        updateLayout(animated: true)
        updateBackgroundView()
        updateButtonsVisibility()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        outsideDelegate?.textViewDidEndEditing?(textView)

        updateLayout(animated: true)
        updateBackgroundView()
        updateButtonsVisibility()
    }

    func textViewDidChange(_ textView: UITextView) {
        textDidChange?(textView.text)
        outsideDelegate?.textViewDidChange?(textView)

        DispatchQueue.main.async {
            self.resetErrorMessage()
            self.updateButtonsVisibility()
            self.invalidateIntrinsicContentSize()
        }
    }
}


// MARK: UITextInputTraits

extension DashInputField: UITextInputTraits {
    @IBInspectable var autocapitalizationType: UITextAutocapitalizationType {
        set {
            textView.autocapitalizationType = newValue
        }
        get {
            textView.autocapitalizationType
        }
    }

    @IBInspectable var autocorrectionType: UITextAutocorrectionType {
        set {
            textView.autocorrectionType = newValue
        }
        get {
            textView.autocorrectionType
        }
    }


    @IBInspectable var spellCheckingType: UITextSpellCheckingType {
        set {
            textView.spellCheckingType = newValue
        }
        get {
            textView.spellCheckingType
        }
    }

    var smartQuotesType: UITextSmartQuotesType {
        set {
            textView.smartQuotesType = newValue
        }
        get {
            textView.smartQuotesType
        }
    }


    var smartDashesType: UITextSmartDashesType {
        set {
            textView.smartDashesType = newValue
        }
        get {
            textView.smartDashesType
        }
    }


    var smartInsertDeleteType: UITextSmartInsertDeleteType {
        set {
            textView.smartInsertDeleteType = newValue
        }
        get {
            textView.smartInsertDeleteType
        }
    }

    @IBInspectable var keyboardType: UIKeyboardType {
        set {
            textView.keyboardType = newValue
        }
        get {
            textView.keyboardType
        }
    }

    @IBInspectable var keyboardAppearance: UIKeyboardAppearance {
        set {
            textView.keyboardAppearance = newValue
        }
        get {
            textView.keyboardAppearance
        }
    }

    @IBInspectable var returnKeyType: UIReturnKeyType {
        set {
            textView.returnKeyType = newValue
        }
        get {
            textView.returnKeyType
        }
    }

    var enablesReturnKeyAutomatically: Bool {
        set {
            textView.enablesReturnKeyAutomatically = newValue
        }
        get {
            textView.enablesReturnKeyAutomatically
        }
    }

    @IBInspectable var isSecureTextEntry: Bool {
        set {
            textView.isSecureTextEntry = newValue
        }
        get {
            textView.isSecureTextEntry
        }
    }

    @IBInspectable var textContentType: UITextContentType {
        set {
            textView.textContentType = newValue
        }
        get {
            textView.textContentType
        }
    }
}

// MARK: - DashTextField

class DashTextField: UITextView {
    var textInsets: UIEdgeInsets = .init(top: 0, left: 7, bottom: 0, right: 7) {
        didSet {
            textContainerInset = textInsets
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    internal func configureLayout() {
        textContainerInset = textInsets
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }
}


// MARK: - InputFieldErrorView

class InputFieldErrorView: UIView {

    public var icon: UIImage? {
        didSet {
            iconView.image = icon
            iconView.isHidden = icon == nil
        }
    }

    private var iconView: UIImageView!
    private var errorLabel: UILabel!

    var text: String? {
        didSet {
            errorLabel.text = text
        }
    }

    override var intrinsicContentSize: CGSize {
        .init(width: -1, height: 20)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureLayout()
    }

    private func configureLayout() {
        iconView = UIImageView()
        iconView.contentMode = .center
        iconView.tintColor = .systemRed
        iconView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.isHidden = true

        errorLabel = UILabel()
        errorLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        errorLabel.textColor = .systemRed

        let stackView = UIStackView(arrangedSubviews: [errorLabel])
        stackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stackView.axis = .horizontal
        stackView.spacing = 3
        addSubview(stackView)
    }
}
