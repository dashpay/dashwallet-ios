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

// MARK: - NumberKeyboardValue

enum NumberKeyboardValue: Equatable {

    enum Digit: Int, CaseIterable {
        case digit0
        case digit1
        case digit2
        case digit3
        case digit4
        case digit5
        case digit6
        case digit7
        case digit8
        case digit9
    }

    case digit(Digit)
    case custom(String)
    case separator
    case empty
    case delete

    var stringValue: String {
        switch self {
        case .digit(let d): return String(d.rawValue)
        case .custom(let c): return c
        case .separator: return Locale.current.decimalSeparator ?? ","
        case .empty: return " "
        case .delete: return "􁂈"
        }
    }
}

// MARK: - NumberKeyboardButtonDelegate

protocol NumberKeyboardButtonDelegate: AnyObject {
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchBegan touch: UITouch)
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchMoved touch: UITouch)
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchEnded touch: UITouch)
    func numberKeyboardButton(_ button: NumberKeyboardButton, touchCanceled touch: UITouch)
}

// MARK: - NumberKeyboardButton.Styles

extension NumberKeyboardButton {
    enum Styles {
        static var textColor: UIColor { .dw_numberKeyboardText() }
        static var textHighlightedColor: UIColor { .dw_numberKeyboardHighlightedText() }
        static var backgroundColor: UIColor { .dw_secondaryBackground() }
        static var backgroundHighlightedColor: UIColor { .dw_dashBlue() }
        static var titleFont: UIFont { .dw_font(forTextStyle: .title3) }
    }
}

// MARK: - NumberKeyboardButton

class NumberKeyboardButton: UIView {
    weak var delegate: NumberKeyboardButtonDelegate?

    var value: NumberKeyboardValue {
        didSet {
            reloadTitle()
        }
    }

    var isHighlighted = false {
        didSet {
            if oldValue != isHighlighted {
                updateBackgroundView()
            }
        }
    }

    private var _customBackgroundColor: UIColor?
    var customBackgroundColor: UIColor? {
        get {
            _customBackgroundColor ?? Styles.backgroundColor
        }
        set {
            _customBackgroundColor = newValue
            if !isHighlighted {
                backgroundColor = newValue
            }
        }
    }

    private var titleLabel: UILabel!

    init(value: NumberKeyboardValue) {
        self.value = value

        super.init(frame: .zero)
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func reloadTitle() {
        #if SNAPSHOT
        if value == .separator {
            titleLabel.accessibilityIdentifier = "amount_button_separator"
        }
        #endif // SNAPSHOT

        switch value {
        case .custom(_), .digit(_), .separator, .empty:
            titleLabel.text = value.stringValue
        case .delete:

            let image: UIImage

            if #available(iOS 15.0, *) {
                image = UIImage(systemName: "delete.backward")!.withTintColor(Styles.textColor)
            } else {
                image = UIImage(systemName: "delete.left")!.withTintColor(Styles.textColor)
            }

            let textAttachment = NSTextAttachment()
            textAttachment.image = image
            textAttachment.adjustsImageSizeForAccessibilityContentSizeCategory = true
            textAttachment.bounds = CGRect(x: -3.0, y: -2.0, width: image.size.width, height: image.size.height)

            // Workaround to make UIKit correctly set text color of the attribute string:
            // Attributed string that consists only of NSTextAttachment will not change it's color
            // To solve it append any regular string at the begining (and at the end to center the image)
            let attributedText = NSMutableAttributedString()
            attributedText.beginEditing()
            attributedText.append(NSAttributedString(string: ""))
            attributedText.append(NSAttributedString(attachment: textAttachment))
            attributedText.append(NSAttributedString(string: " "))

            titleLabel.attributedText = attributedText
        }
    }

    private func updateBackgroundView() {
        UIView.animate(withDuration: 0.075,
                       delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) { [unowned self] in
            if self.isHighlighted {
                self.backgroundColor = Styles.backgroundHighlightedColor
                self.titleLabel.textColor = Styles.textHighlightedColor
            } else {
                self.backgroundColor = customBackgroundColor
                self.titleLabel.textColor = Styles.textColor
            }
        }
    }

    private func configureHierarchy() {
        isExclusiveTouch = true
        backgroundColor = Styles.backgroundColor

        layer.cornerRadius = 8
        layer.masksToBounds = true

        titleLabel = UILabel()
        titleLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        titleLabel.textAlignment = .center
        titleLabel.textColor = .dw_numberKeyboardText()
        titleLabel.font = .dw_font(forTextStyle: .title3)
        addSubview(titleLabel)

        reloadTitle()
    }
}

extension NumberKeyboardButton {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            super.touchesBegan(touches, with: event)
        }

        guard let touch = touches.first else { return }
        delegate?.numberKeyboardButton(self, touchBegan: touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            super.touchesMoved(touches, with: event)
        }

        guard let touch = touches.first else { return }
        delegate?.numberKeyboardButton(self, touchMoved: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            super.touchesEnded(touches, with: event)
        }

        guard let touch = touches.first else { return }
        delegate?.numberKeyboardButton(self, touchEnded: touch)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            super.touchesCancelled(touches, with: event)
        }

        guard let touch = touches.first else { return }
        delegate?.numberKeyboardButton(self, touchCanceled: touch)
    }
}
