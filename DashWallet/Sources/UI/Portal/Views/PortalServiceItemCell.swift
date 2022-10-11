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

class PortalServiceItemCell: UICollectionViewCell {
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    
    @IBOutlet var statusView: UIView!
    @IBOutlet var statusIcon: UIView!
    @IBOutlet var statusLabel: UILabel!
    
    @IBOutlet var balanceView: UIView!
    @IBOutlet var balanceLabel: UILabel!
    @IBOutlet var balanceStatusView: UIView!
    @IBOutlet var balanceStatusLabel: UILabel!
    
    func update(with item: ServiceItem, isEnabled: Bool) {
        balanceStatusView.isHidden = true
        
        iconView.image = UIImage(named: isEnabled ? item.icon : "\(item.icon).disabled" )
        titleLabel.text = item.name
        
        if item.status == .idle {
            subtitleLabel.text = NSLocalizedString("Link your account", comment: "Buy Sell Portal")
            statusView.isHidden = true
            subtitleLabel.isHidden = false
        }else if !isEnabled {
            balanceStatusView.isHidden = false
            
            statusIcon.backgroundColor = .systemRed
            
            statusLabel.text = NSLocalizedString("Disconnected", comment: "Buy Sell Portal")
            statusLabel.textColor = .systemRed
            
            if let balance = item.balanceValue {
                balanceView.isHidden = false
                
                balanceLabel.attributedText = balance
                
                balanceStatusLabel.text = NSLocalizedString("Last known balance", comment: "Buy Sell Portal")
                balanceStatusLabel.textColor = .systemRed
            }else{
                balanceView.isHidden = true
            }
            
        }else{
            statusView.isHidden = false
            subtitleLabel.isHidden = true
            statusIcon.backgroundColor = item.status.iconColor
            statusLabel.textColor = item.status.labelColor
            statusLabel.text = item.status.statusString
            balanceLabel.attributedText = item.balanceValue
            
            //balanceView.isHidden = item.status == .disconnected
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .white
        
        statusIcon.layer.cornerRadius = 3
        statusIcon.layer.masksToBounds = true
        
        backgroundColor = .clear
    }
}
