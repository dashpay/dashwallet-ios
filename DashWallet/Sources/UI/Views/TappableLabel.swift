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

public typealias TappableLabelAction = (String) -> ()

// MARK: - TappableLabel

final public class TappableLabel: UILabel {
    private var links: [String: (NSRange, TappableLabelAction)] = [:]

    private(set) var layoutManager = NSLayoutManager()
    private(set) var textContainer = NSTextContainer(size: CGSize.zero)
    private(set) var textStorage = NSTextStorage() {
        didSet {
            textStorage.addLayoutManager(layoutManager)
        }
    }

    public override var attributedText: NSAttributedString? {
        didSet {
            if let attributedText {
                textStorage = NSTextStorage(attributedString: attributedText)
            } else {
                textStorage = NSTextStorage()
                links = [:]
            }
        }
    }

    public override var text: String? {
        didSet {
            if let text {
                textStorage = NSTextStorage(string: text)
            } else {
                textStorage = NSTextStorage()
                links = [:]
            }
        }
    }

    public override var lineBreakMode: NSLineBreakMode {
        didSet {
            textContainer.lineBreakMode = lineBreakMode
        }
    }

    public override var numberOfLines: Int {
        didSet {
            textContainer.maximumNumberOfLines = numberOfLines
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        initialize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        initialize()
    }

    private func initialize() {
        isUserInteractionEnabled = true

        layoutManager.addTextContainer(textContainer)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = lineBreakMode
        textContainer.maximumNumberOfLines = numberOfLines
    }

    public func setAction(for text: String, action: @escaping TappableLabelAction) {
        guard let attributedText else { return }
        guard let currentText = attributedText.string as NSString? else { return }

        let range = currentText.range(of: text)

        guard range.location != NSNotFound else { return }

        links[text] = (range, action)

        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedText)
        mutableAttributedString
            .addAttributes([
                NSAttributedString.Key.font: font ?? .dw_font(forTextStyle: .body),
                NSAttributedString.Key.foregroundColor: UIColor.dw_dashBlue(),
                NSAttributedString.Key.backgroundColor: UIColor.dw_dashBlue().withAlphaComponent(0.08),
            ],
            range: range)
        self.attributedText = mutableAttributedString
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touchLocation = touches.first?.location(in: self) else { return }

        let textBoundingBox = layoutManager.usedRect(for: textContainer)
        let textContainerOffset = CGPoint(x: (bounds.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x,
                                          y: (bounds.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y)
        let locationOfTouchInTextContainer = CGPoint(x: touchLocation.x - textContainerOffset.x, y: touchLocation.y - textContainerOffset.y)
        let indexOfCharacter = layoutManager.characterIndex(for: locationOfTouchInTextContainer, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)

        for (_, value) in links.enumerated() {
            let range = value.value.0
            let action = value.value.1

            if NSLocationInRange(indexOfCharacter, range) {
                action(value.key)
                return
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        textContainer.size = bounds.size
    }
}
