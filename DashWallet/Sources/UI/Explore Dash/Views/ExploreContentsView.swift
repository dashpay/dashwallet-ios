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

class ExploreContentsView: UIView {
    
    var whereToSpendHandler: (() -> Void)?
    var atmHandler: (() -> Void)?
    var stakingHandler: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .dw_darkBlue()
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        contentView.layer.cornerRadius = 8.0
        contentView.layer.masksToBounds = true
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(contentView)
        
        let subContentView = UIView()
        subContentView.translatesAutoresizingMaskIntoConstraints = false
        subContentView.backgroundColor = .dw_background()
        subContentView.layer.cornerRadius = 8.0
        subContentView.layer.masksToBounds = true
        contentView.addSubview(subContentView)
        
        let buttonsStackView = UIStackView()
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.spacing = 8
        buttonsStackView.axis = .vertical
        buttonsStackView.distribution = .equalSpacing
        subContentView.addSubview(buttonsStackView)
        
        let merchantsItem = createItem(
            image: UIImage(named: "image.explore.dash.wheretospend"),
            title: NSLocalizedString("Where to Spend?", comment: ""),
            subtitle: NSLocalizedString("Find merchants that accept Dash payments.", comment: "")
        ) { [weak self] in
            self?.whereToSpendHandler?()
        }
        buttonsStackView.addArrangedSubview(merchantsItem)
        
        let atmItem = createItem(
            image: UIImage(named: "image.explore.dash.atm"),
            title: NSLocalizedString("ATMs", comment: ""),
            subtitle: NSLocalizedString("Find ATMs where you can buy or sell Dash.", comment: "")
        ) { [weak self] in
            self?.atmHandler?()
        }
        buttonsStackView.addArrangedSubview(atmItem)
        
        let cnItem = createItem(
            image: UIImage(named: "image.explore.dash.staking"),
            title: NSLocalizedString("Staking", comment: ""),
            subtitle: NSLocalizedString("Easily stake Dash and earn passive income with a few simple clicks.", comment: "")
        ) { [weak self] in
            self?.stakingHandler?()
        }
        cnItem.addContent(CrowdNodeAPYView(frame: .zero))
        buttonsStackView.addArrangedSubview(cnItem)
        
        let verticalPadding: CGFloat = 10
        
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            subContentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            subContentView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -35),
            subContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            subContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            
            buttonsStackView.topAnchor.constraint(equalTo: subContentView.topAnchor, constant: verticalPadding),
            buttonsStackView.bottomAnchor.constraint(equalTo: subContentView.bottomAnchor, constant: -verticalPadding),
            buttonsStackView.trailingAnchor.constraint(equalTo: subContentView.trailingAnchor),
            buttonsStackView.leadingAnchor.constraint(equalTo: subContentView.leadingAnchor)
        ])
    }
    
    private func createItem(image: UIImage?, title: String, subtitle: String, action: @escaping () -> Void) -> ExploreContentsViewCell {
        let item = ExploreContentsViewCell(frame: .zero)
        item.translatesAutoresizingMaskIntoConstraints = false
        item.image = image
        item.title = title
        item.subtitle = subtitle
        item.actionHandler = action
        return item
    }
}

// MARK: - ExploreContentsViewCell

private class ExploreContentsViewCell: UIView {
    
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let descLabel = UILabel()
    private let contentStack = UIStackView()
    
    var actionHandler: (() -> Void)?
    
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
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureHierarchy()
    }
    
    @objc private func buttonAction(_ sender: UIButton) {
        actionHandler?()
    }
    
    private func configureHierarchy() {
        backgroundColor = .dw_background()
        
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.alignment = .top
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .center
        stackView.addArrangedSubview(iconImageView)
        
        let labelsStackView = UIStackView()
        labelsStackView.translatesAutoresizingMaskIntoConstraints = false
        labelsStackView.axis = .vertical
        labelsStackView.spacing = 1
        labelsStackView.alignment = .leading
        stackView.addArrangedSubview(labelsStackView)
        contentStack.axis = .vertical
        contentStack.spacing = 1
        contentStack.alignment = .leading
        
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label
        titleLabel.font = .dw_font(forTextStyle: .body)
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 0
        labelsStackView.addArrangedSubview(titleLabel)
        
        descLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.textColor = .secondaryLabel
        descLabel.font = .dw_font(forTextStyle: .footnote)
        descLabel.textAlignment = .left
        descLabel.numberOfLines = 0
        labelsStackView.addArrangedSubview(descLabel)
        
        // Replace labelsStackView with contentStack for extensibility
        stackView.removeArrangedSubview(labelsStackView)
        stackView.addArrangedSubview(contentStack)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(descLabel)
        
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.text = ""
        button.addTarget(self, action: #selector(buttonAction(_:)), for: .touchUpInside)
        addSubview(button)
        
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 34),
            iconImageView.heightAnchor.constraint(equalToConstant: 34),
            
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    func addContent(_ view: UIView) {
        let last = contentStack.arrangedSubviews.last
        if let last = last {
            contentStack.setCustomSpacing(10, after: last)
        }
        contentStack.addArrangedSubview(view)
    }
}
