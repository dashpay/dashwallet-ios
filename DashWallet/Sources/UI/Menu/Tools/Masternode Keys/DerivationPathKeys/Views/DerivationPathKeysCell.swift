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

import Foundation

final class DerivationPathKeysCell: UITableViewCell {
    private var nameLabel: UILabel!
    private var valueLabel: UILabel!
    private var copyButton: UIButton!

    private(set) var item: DerivationPathKeysItem!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    func update(with item: DerivationPathKeysItem) {
        self.item = item

        nameLabel.text = item.title
        valueLabel.text = item.value
    }

    private func configureHierarchy() {
        let mainStackView = UIStackView()
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.axis = .vertical
        mainStackView.spacing = 2
        contentView.addSubview(mainStackView)

        nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .dw_font(forTextStyle: .footnote)
        nameLabel.textColor = UIColor.dw_secondaryText()
        mainStackView.addArrangedSubview(nameLabel)

        valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .dw_font(forTextStyle: .subheadline)
        valueLabel.numberOfLines = 0
        valueLabel.lineBreakMode = .byWordWrapping
        valueLabel.textColor = .dw_label()
        mainStackView.addArrangedSubview(valueLabel)

        copyButton = UIButton(type: .custom)
        copyButton.setImage(UIImage(named: "icon_copy_outline"), for: .normal)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.tintColor = .dw_label()
        copyButton.isUserInteractionEnabled = false
        contentView.addSubview(copyButton)

        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            mainStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            mainStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),

            copyButton.widthAnchor.constraint(equalToConstant: 30),
            copyButton.heightAnchor.constraint(equalToConstant: 30),
            copyButton.leadingAnchor.constraint(equalTo: mainStackView.trailingAnchor, constant: 5),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            copyButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 0),
        ])
    }
}
