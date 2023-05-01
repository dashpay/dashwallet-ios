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

final class DerivationPathKeysHeaderView: UITableViewHeaderFooterView {
    var titleLabel: UILabel!
    var extraInfoLabel: UILabel!
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        .init(width: DerivationPathKeysHeaderView.noIntrinsicMetric, height: 30)
    }
    
    private func configureHierarchy() {
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .dw_font(forTextStyle: .callout).withWeight(UIFont.Weight.semibold.rawValue)
        titleLabel.textColor = UIColor.dw_label()
        contentView.addSubview(titleLabel)
     
        extraInfoLabel = UILabel()
        extraInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        extraInfoLabel.font = .dw_font(forTextStyle: .footnote)
        extraInfoLabel.textColor = .dw_secondaryText()
        extraInfoLabel.textAlignment = .right
        contentView.addSubview(extraInfoLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0),
            
            extraInfoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0),
            extraInfoLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            extraInfoLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0),
        ])
    }
}
