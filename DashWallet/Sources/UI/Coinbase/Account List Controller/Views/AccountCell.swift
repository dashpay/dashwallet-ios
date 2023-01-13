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

final class AccountCell: UITableViewCell {
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var accountNameLabel: UILabel!
    @IBOutlet var accountShortNameLabel: UILabel!
    @IBOutlet var fiatBalanceLabel: UILabel!
    @IBOutlet var balanceLabel: UILabel!

    func update(with item: CBAccount) {
        accountNameLabel.text = "· " + item.info.currency.name
        accountShortNameLabel.text = item.info.currency.code

        iconView.isHidden = false
        iconView.sd_setImage(with: item.info.iconURL, placeholderImage: nil) { [weak iconView] image, _,_,_ in
            if image == nil {
                iconView?.isHidden = true
            }
        }

        let dashStr = "\(item.info.balance.amount) \(item.info.balance.currency)"
        let fiatStr = " ≈ \("$1.23")"
        let fullStr = "\(dashStr)\(fiatStr)"
        let string = NSMutableAttributedString(string: fullStr)
        string.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.secondaryLabel],
                             range: NSMakeRange(dashStr.count, fiatStr.count))
        string.addAttribute(.font, value: UIFont.dw_font(forTextStyle: .footnote), range: NSMakeRange(0, fullStr.count - 1))

        balanceLabel.attributedText = string
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        accessoryType = selected ? .checkmark : .none
        tintColor = selected ? .dw_dashBlue() : .label
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        backgroundColor = .dw_secondaryBackground()
        contentView.backgroundColor = .dw_secondaryBackground()

        iconView.backgroundColor = .secondaryLabel
        iconView.layer.cornerRadius = 18
    }
}
