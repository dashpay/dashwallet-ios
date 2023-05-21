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

final class KeysOverviewCell: UITableViewCell {
    private var keyNameLabel: UILabel!
    private var keyCountLabel: UILabel!
    private var usedLabel: UILabel!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with keyItem: MNKey, count: Int, used: Int) {
        let keyCountText = String(format: NSLocalizedString("%d key(s)", comment: "#bc-ignore!"), count)
        let usedCountText = String(format: NSLocalizedString("%ld used(s)", comment: "#bc-ignore!"), used)

        keyNameLabel.text = keyItem.title
        keyCountLabel.text = keyCountText
        usedLabel.text = usedCountText
    }

    private func configureHierarchy() {
        backgroundColor = .dw_background()
        contentView.backgroundColor = .clear

        let mainStackView = UIStackView()
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.axis = .vertical
        mainStackView.spacing = 2
        contentView.addSubview(mainStackView)

        keyNameLabel = UILabel()
        keyNameLabel.translatesAutoresizingMaskIntoConstraints = false
        keyNameLabel.font = .dw_font(forTextStyle: .subheadline)
        mainStackView.addArrangedSubview(keyNameLabel)

        keyCountLabel = UILabel()
        keyCountLabel.translatesAutoresizingMaskIntoConstraints = false
        keyCountLabel.font = .dw_font(forTextStyle: .caption1)
        mainStackView.addArrangedSubview(keyCountLabel)

        usedLabel = UILabel()
        usedLabel.translatesAutoresizingMaskIntoConstraints = false
        usedLabel.textAlignment = .right
        usedLabel.font = .dw_font(forTextStyle: .footnote)
        contentView.addSubview(usedLabel)

        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            mainStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 0),

            usedLabel.leadingAnchor.constraint(equalTo: mainStackView.trailingAnchor, constant: 5),
            usedLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            usedLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 0),
        ])
    }
}

