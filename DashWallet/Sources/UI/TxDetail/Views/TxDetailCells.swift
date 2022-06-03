//  
//  Created by Pavel Tikhonenko
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

class TxDetailHeaderCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var dashAmountLabel: UILabel!
    @IBOutlet var fiatAmountLabel: UILabel!
    
    @IBOutlet var iconImageView: UIImageView!
    
    var model: DWTxDetailModel! {
        didSet {
            updateView()
        }
    }
        
    private func updateView() {
        var title: String!
        var iconTintColor: UIColor!
        var iconName: String!
        
        switch (self.model.direction) {
        case .moved:
            iconName = "arrow.up.circle.fill"
            title = NSLocalizedString("Moved to Address", comment: "");
            iconTintColor = UIColor.dw_iconTint()
        case .sent:
            iconName = "arrow.up.circle.fill"
            title = NSLocalizedString("Amount Sent", comment: "");
            iconTintColor = UIColor.dw_dashBlue() // Black or White (in Dark Mode)
        case .received:
            iconName = "arrow.down.circle.fill"
            title = NSLocalizedString("Amount received", comment: "");
            iconTintColor = UIColor.dw_green()
        case .notAccountFunds:
            iconName = "arrow.down.circle.fill"
            title = NSLocalizedString("Registered Masternode", comment: "");
            iconTintColor = UIColor.dw_iconTint() // Black or White (in Dark Mode)
        default:
            break
        }
        
        if (self.model.direction == .notAccountFunds) {
            self.fiatAmountLabel.text = "";
            self.dashAmountLabel.text = "";
        }
        else {
            self.fiatAmountLabel.text = self.model.fiatAmountString;
            self.dashAmountLabel.attributedText = model.dashAmountString(with: UIFont.dw_mediumFont(ofSize: 32), tintColor: .label)
        }
      
        self.titleLabel.text = title
        self.titleLabel.textColor = iconTintColor
        
        if let name = iconName
        {
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 46, weight: .medium, scale: .large)
        
            let image = UIImage(systemName: name, withConfiguration: iconConfig)
            
            iconImageView.image = image
            iconImageView.tintColor = iconTintColor
        }
    }
    
    override class var dw_reuseIdentifier: String { return "TxDetailHeaderCell" }
}

class TxDetailActionCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    
    override class var dw_reuseIdentifier: String { return "TxDetailActionCell" }
}

class TxDetailInfoCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var valueLabelsStack: UIStackView!
    
    func update(with item: TXDetailViewController.Item) {
        var title: String?
        switch item
        {
        case .sentTo(let items), .sentFrom(let items), .movedTo(let items), .movedFrom(let items), .receivedAt(let items):
            title = items.first?.title
            
            for item in items {
                let view = UILabel()
                view.lineBreakMode = .byTruncatingMiddle
                view.attributedText = item.attributedDetail
                valueLabelsStack.addArrangedSubview(view)
            }
            break
        case .date(let item), .networkFee(let item):
            title = item.title
            
            let view = UILabel()
            
            if let text = item.plainDetail {
                view.text = text
            }
            
            if let text = item.attributedDetail {
                view.attributedText = text
            }
            
            valueLabelsStack.addArrangedSubview(view)
        default:
            break
        }
        
        
        titleLabel.text = title
        
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        var views = valueLabelsStack.arrangedSubviews
        
        for view in views {
            valueLabelsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
    
    override class var dw_reuseIdentifier: String { return "TxDetailInfoCell" }
}
