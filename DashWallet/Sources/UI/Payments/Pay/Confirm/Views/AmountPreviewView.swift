//
//  Created by tkhp
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

private let kDashSymbolMainSize = CGSize(width: 35.0, height: 27.0)

// MARK: - AmountPreviewView

@objc(DWAmountPreviewView)
final class AmountPreviewView: UIView {
    @IBOutlet var contentView: UIView!
    @IBOutlet var mainAmountLabel: UILabel!
    @IBOutlet var supplementaryAmountLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        Bundle.main.loadNibNamed(String(describing: type(of: self)), owner: self, options: nil)
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: widthAnchor),
        ])

        backgroundColor = UIColor.dw_background()

        // These two labels doesn't support Dynamic Type and have same hardcoded values as in DWAmountInputControl
        mainAmountLabel.font = UIFont.dw_regularFont(ofSize: 34.0)
        supplementaryAmountLabel.font = UIFont.dw_regularFont(ofSize: 16.0)
    }

    @objc
    func setAmount(_ amount: UInt64) {
        mainAmountLabel.attributedText = mainAmountAttributedString(forAmount: amount)
        supplementaryAmountLabel.text = supplementaryAmountString(forAmount: amount)
    }

    private func mainAmountAttributedString(forAmount amount: UInt64) -> NSAttributedString {
        NSAttributedString.dashAttributedString(for: amount,
                                                tintColor: UIColor.dw_darkTitle(),
                                                symbolSize: kDashSymbolMainSize)
    }

    private func supplementaryAmountString(forAmount amount: UInt64) -> String {
        let supplementaryAmount = CurrencyExchanger.shared.fiatAmountString(for: amount.dashAmount)
        return supplementaryAmount
    }
}
