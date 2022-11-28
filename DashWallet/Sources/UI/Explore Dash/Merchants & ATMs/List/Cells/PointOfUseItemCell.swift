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
import CoreLocation

class PointOfUseItemCell: UITableViewCell {
    private var logoImageView: UIImageView!
    private var nameLabel: UILabel!
    var subLabel: UILabel!
    var mainStackView: UIStackView!
    
    override class var dw_reuseIdentifier: String { return "ExplorePointOfUseItemCell" }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(with pointOfUse: ExplorePointOfUse) {
        nameLabel.text = pointOfUse.name
        
        if let urlString = pointOfUse.logoLocation, let url = URL(string: urlString) {
            logoImageView.sd_setImage(with: url)
        }else{
            logoImageView.image = UIImage(named:"image.explore.dash.wts.item.logo.empty")
        }

    }
}

extension PointOfUseItemCell {
    @objc func configureHierarchy() {
        mainStackView = UIStackView()
        mainStackView.axis = .horizontal
        mainStackView.spacing = 15
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.alignment = .center
        contentView.addSubview(mainStackView)
        
        logoImageView = UIImageView(image: UIImage(named: "image.explore.dash.wts.item.logo.empty"))
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.layer.cornerRadius = 8.0
        logoImageView.layer.masksToBounds = true
        mainStackView.addArrangedSubview(logoImageView)
        
        let textStackView = UIStackView()
        textStackView.axis = .vertical
        textStackView.spacing = 2
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.addArrangedSubview(textStackView)
        
        nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: 14)
        textStackView.addArrangedSubview(nameLabel)
        
        subLabel = UILabel()
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.font = UIFont.systemFont(ofSize: 11)
        subLabel.textColor = .secondaryLabel
        subLabel.isHidden = true
        textStackView.addArrangedSubview(subLabel)
        
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 36),
            logoImageView.heightAnchor.constraint(equalToConstant: 36),
            
            mainStackView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16),
            mainStackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16)
        ])
    }
}
