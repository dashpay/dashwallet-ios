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

final class PasteboardContentView: UIView {
    public var addressHandler: ((String) -> ())?

    private var textView: TappableTextView!

    override var intrinsicContentSize: CGSize {
        let h = textView.contentSize.height + 36 + 10 + 5 // textView.contentSize.height + top padding + bottom padding
        return CGSize(width: UIView.noIntrinsicMetric, height: min(220, h))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    public func update(with string: String) {
        textView.text = string
        textView.setNeedsLayout()
        textView.layoutIfNeeded()

        let chain = DWEnvironment.sharedInstance().currentChain

        let words = string.split(separator: " ")
        for word in words {
            let word = String(word).trimmingCharacters(in: .punctuationCharacters)

            guard word.isValidDashAddress(on: chain) ||
                word.isValidDashPrivateKey(on: chain) else { continue }

            textView.setAction(for: word) { [weak self] address in
                self?.addressHandler?(address)
            }
        }

        DispatchQueue.main.async {
            self.invalidateIntrinsicContentSize()
        }
    }

    private func configureHierarchy() {
        backgroundColor = .dw_background()
        cornerRadius = 12

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 10
        addSubview(stackView)

        let pasteboardContentTitleLabel = UILabel()
        pasteboardContentTitleLabel.textColor = .dw_secondaryText()
        pasteboardContentTitleLabel.font = .dw_font(forTextStyle: .caption1)
        pasteboardContentTitleLabel.text = NSLocalizedString("Tap the address from the clipboard to paste it", comment: "Enter Address Screen")
        stackView.addArrangedSubview(pasteboardContentTitleLabel)

        textView = TappableTextView()
        textView.isEditable = false
        textView.textColor = .dw_label()
        textView.backgroundColor = .dw_background()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .dw_font(forTextStyle: .caption1)
        textView.textContainerInset = .init(top: 0, left: 0, bottom: 0, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        stackView.addArrangedSubview(textView)

        // A method in your UITextView subclass

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
}
