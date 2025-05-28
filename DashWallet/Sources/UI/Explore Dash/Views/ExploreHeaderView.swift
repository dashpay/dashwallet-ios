//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

class ExploreHeaderView: UIStackView {
    
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let descLabel = UILabel()
    
    var image: UIImage? {
        get { iconImageView.image }
        set { iconImageView.image = newValue }
    }
    
    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }
    
    var subtitle: String? {
        get { descLabel.text }
        set { descLabel.text = newValue }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .dw_darkBlue()
        spacing = 4
        axis = .vertical
        distribution = .fillProportionally
        
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        addArrangedSubview(iconImageView)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .dw_font(forTextStyle: .largeTitle)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.minimumScaleFactor = 0.4
        titleLabel.adjustsFontSizeToFitWidth = true
        addArrangedSubview(titleLabel)
        
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.textColor = .white
        descLabel.font = .dw_font(forTextStyle: .callout)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.adjustsFontSizeToFitWidth = true
        descLabel.minimumScaleFactor = 0.4
        addArrangedSubview(descLabel)
        
        iconImageView.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        descLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        
        NSLayoutConstraint.activate([
            iconImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 250.0),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15.0),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15.0)
        ])
    }
}
