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

// MARK: - CrowdNodeCell

final class CrowdNodeCell: UITableViewCell {
    @IBOutlet var title : UILabel!
    @IBOutlet var subtitle : UILabel!
    @IBOutlet var icon : UIImageView!
    @IBOutlet var iconCircle : UIView!
    @IBOutlet var additionalInfo: UIView!
    @IBOutlet var additionalInfoLabel : UILabel!
    @IBOutlet var additionalInfoIcon : UIImageView!
    @IBOutlet var verifyButton : UIButton!

    @IBOutlet var showInfoConstraint: NSLayoutConstraint!
    @IBOutlet var collapseInfoConstraint: NSLayoutConstraint!
    @IBOutlet var infoBottomAnchorConstraint: NSLayoutConstraint!

    func update(with item: CrowdNodePortalItem,
                _ crowdNodeBalance: UInt64,
                _ walletBalance: UInt64,
                _ onlineAccountState: CrowdNode.OnlineAccountState) {
        title.text = item.title(onlineState: onlineAccountState)
        subtitle.text = item.subtitle(onlineState: onlineAccountState)
        icon.image = UIImage(named: item.icon)

        if item.isDisabled(crowdNodeBalance, walletBalance, onlineAccountState.isLinkingInProgress) {
            let grayColor = UIColor(red: 176/255.0, green: 182/255.0, blue: 188/255.0, alpha: 1.0)
            iconCircle.backgroundColor = grayColor
            title.textColor = .dw_secondaryText()
            selectionStyle = .none
        } else {
            iconCircle.backgroundColor = item.iconCircleColor
            title.textColor = .label
            selectionStyle = .default
        }

        var showInfo: Bool

        switch item {
        case .deposit:
            showInfo = crowdNodeBalance < CrowdNode.minimumDeposit && !onlineAccountState.isLinkingInProgress
        case .withdraw:
            showInfo = onlineAccountState.isLinkingInProgress
        default:
            showInfo = false
        }

        additionalInfo.isHidden = !showInfo
        showInfoConstraint.isActive = showInfo
        collapseInfoConstraint.isActive = !showInfo
        infoBottomAnchorConstraint.isActive = showInfo

        if showInfo {
            additionalInfo.backgroundColor = item.infoBackgroundColor
            additionalInfoLabel.text = item.info(crowdNodeBalance, onlineAccountState)
            additionalInfoLabel.textColor = item.infoTextColor

            if !item.infoActionButton(for: onlineAccountState).isEmpty {
                additionalInfoLabel.textAlignment = .left
                additionalInfoIcon.isHidden = false
                verifyButton.isHidden = false
            } else {
                additionalInfoLabel.textAlignment = .center
                additionalInfoIcon.isHidden = true
                verifyButton.isHidden = true
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        backgroundColor = .dw_background()
    }
}
