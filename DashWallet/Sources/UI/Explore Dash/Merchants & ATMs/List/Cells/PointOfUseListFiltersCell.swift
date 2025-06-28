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

class PointOfUseListFiltersCell: UITableViewCell {

    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }

    var subtitle: String? {
        didSet {
            subLabel.text = subtitle
            subLabel.isHidden = subtitle == nil
        }
    }

    var titleLabel: UILabel!
    var subLabel: UILabel!
    var filterButton: UIButton!
    var filterAction: (() -> ())?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func filterButtonAction() {
        filterAction?()
    }

    func configureHierarchy() {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        contentView.addSubview(stackView)

        let txtStackView = UIStackView()
        txtStackView.axis = .vertical
        txtStackView.spacing = 1
        txtStackView.translatesAutoresizingMaskIntoConstraints = false
        txtStackView.alignment = .leading
        stackView.addArrangedSubview(txtStackView)

        var label = UILabel()
        label.adjustsFontSizeToFitWidth = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.minimumScaleFactor = 0.5
        txtStackView.addArrangedSubview(label)
        titleLabel = label

        label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_font(forTextStyle: .footnote)
        label.isHidden = true
        txtStackView.addArrangedSubview(label)
        subLabel = label

        stackView.addArrangedSubview(UIView())

        let filterButton = UIButton(type: .custom)
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.semanticContentAttribute = .forceRightToLeft
        filterButton.contentHorizontalAlignment = .leading
        filterButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)
        filterButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        filterButton.setTitleColor(.label, for: .normal)
        filterButton.setTitle(NSLocalizedString(" ", comment: ""), for: .normal)
        filterButton.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        filterButton.tintColor = .dw_label()
        filterButton.addTarget(self, action: #selector(filterButtonAction), for: .touchUpInside)
        stackView.addArrangedSubview(filterButton)
        self.filterButton = filterButton

        NSLayoutConstraint.activate([
            filterButton.widthAnchor.constraint(equalToConstant: 90),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                               constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                constant: -16),
        ])
    }
}
