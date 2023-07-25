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

public typealias TappableTextViewAction = (String) -> ()

// MARK: - TappableTextView

final public class TappableTextView: UITextView {
    private var links: [String: TappableTextViewAction] = [:]

    init() {
        super.init(frame: .zero, textContainer: nil)

        initialize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        initialize()
    }

    private func initialize() {
        isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(textDidTap(recognizer:)))
        tapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(tapGesture)
    }

    public func setAction(for text: String, action: @escaping TappableLabelAction) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let attributedText else { return }
        guard let currentText = attributedText.string as NSString? else { return }

        let range = currentText.range(of: text)

        guard range.location != NSNotFound else { return }

        links[text] = action

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

    @objc
    public func textDidTap(recognizer: UITapGestureRecognizer) {
        let touchLocation = recognizer.location(in: self)

        guard let textPosition = closestPosition(to: touchLocation),
              let range = tokenizer.rangeEnclosingPosition(textPosition, with: .word, inDirection: .init(rawValue: 1)) else {
            return
        }

        guard let tappedText = text(in: range) else {
            return
        }

        guard let action = links[tappedText] else {
            return
        }

        action(tappedText)
    }
}
