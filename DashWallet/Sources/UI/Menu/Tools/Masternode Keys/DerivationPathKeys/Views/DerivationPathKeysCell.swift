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
    private var mainStackView: UIStackView!
    private var topConstraint: NSLayoutConstraint!
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!

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

    func applyMenuSpacing(isFirst: Bool, isLast: Bool, sectionPadding: CGFloat) {
        // Cell vertical padding: 12px
        // Section padding: 6px (added to first cell top and last cell bottom)
        // Inter-cell gap: 2px (added to non-first cells)
        let cellVerticalPadding: CGFloat = 12

        // Top: section padding (6px) for first cell, or cell padding + gap for others
        topConstraint.constant = isFirst ? (sectionPadding + cellVerticalPadding) : (cellVerticalPadding + kMenuVGap)

        // Bottom: section padding (6px) for last cell
        bottomConstraint.constant = isLast ? -(sectionPadding + cellVerticalPadding) : -cellVerticalPadding

        // Horizontal: section padding (6px) + cell padding (14px)
        let totalHorizontalPadding = sectionPadding + 14
        leadingConstraint.constant = totalHorizontalPadding
        trailingConstraint.constant = -totalHorizontalPadding
    }

    private func configureHierarchy() {
        backgroundColor = .dw_background()

        // Cell corner radius: 14px
        layer.cornerRadius = 14
        layer.masksToBounds = true

        mainStackView = UIStackView()
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

        // Initial cell padding (will be adjusted by applyMenuSpacing)
        let cellHorizontalPadding: CGFloat = 14
        let cellVerticalPadding: CGFloat = 12

        topConstraint = mainStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: cellVerticalPadding)
        leadingConstraint = mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: cellHorizontalPadding)
        bottomConstraint = mainStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -cellVerticalPadding)
        trailingConstraint = copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -cellHorizontalPadding)

        NSLayoutConstraint.activate([
            leadingConstraint,
            topConstraint,
            bottomConstraint,

            copyButton.widthAnchor.constraint(equalToConstant: 30),
            copyButton.heightAnchor.constraint(equalToConstant: 30),
            copyButton.leadingAnchor.constraint(equalTo: mainStackView.trailingAnchor, constant: 8),
            trailingConstraint,
            copyButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 0),
        ])
    }
}
