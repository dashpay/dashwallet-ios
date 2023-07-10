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

import UIKit

class TitleValueCell: TitleCell {
    private let valueLabel: UILabel
    
    override var intrinsicContentSize: CGSize {
        .init(width: TitleValueCell.noIntrinsicMetric, height: 42)
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        valueLabel = UILabel()
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(with title: String, value: String) {
        super.update(with: title)
        
        valueLabel.text = value
    }
    
    override internal func configureHierarchy() {
        super.configureHierarchy()
        
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = UIFont.dw_font(forTextStyle: .footnote)
        valueLabel.textColor = .dw_darkTitle()
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.textAlignment = .right
        
        contentView.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

extension TitleValueCell { // DWTitleDetailItem
    public func update(with item: DWTitleDetailItem) {
        titleLabel.text = item.title
        
        if let text = item.plainDetail {
            valueLabel.text = text
        }

        if let text = item.attributedDetail {
            valueLabel.attributedText = text
        }
    }
}
