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

class ExploreMerchantItemCell: UITableViewCell {
    private var logoImageView: UIImageView!
    private var nameLabel: UILabel!
    private var subLabel: UILabel!
    private var paymentTypeIconView: UIImageView!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(with merchant: Merchant) {
        nameLabel.text = merchant.name
        
        if let urlString = merchant.logoLocation, let url = URL(string: urlString) {
            logoImageView.sd_setImage(with: url)
        }else{
            logoImageView.image = UIImage(named:"image.explore.dash.wts.item.logo.empty")
        }
        
        let isGiftCard = merchant.paymentMethod == .giftCard
        let paymentIconName = isGiftCard ? "image.explore.dash.wts.payment.gift-card" : "image.explore.dash.wts.payment.dash";
        paymentTypeIconView.image = UIImage(named: paymentIconName)
    }
}

extension ExploreMerchantItemCell {
    func configureHierarchy() {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 15
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        contentView.addSubview(stackView)
        
        logoImageView = UIImageView(image: UIImage(named: "image.explore.dash.wts.item.logo.empty"))
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.layer.cornerRadius = 8.0
        logoImageView.layer.masksToBounds = true
        stackView.addArrangedSubview(logoImageView)

        nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: 14)
        stackView.addArrangedSubview(nameLabel)
        
        stackView.addArrangedSubview(UIView())
        
        paymentTypeIconView = UIImageView(image: UIImage(named: "image.explore.dash.wts.payment.dash"))
        paymentTypeIconView.translatesAutoresizingMaskIntoConstraints = false
        paymentTypeIconView.contentMode = .center
        stackView.addArrangedSubview(paymentTypeIconView)
        
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 36),
            logoImageView.heightAnchor.constraint(equalToConstant: 36),
            
            paymentTypeIconView.widthAnchor.constraint(equalToConstant: 24),
            paymentTypeIconView.heightAnchor.constraint(equalToConstant: 24),
            
            stackView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16)
        ])
    }
}
